import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Logger } from '../common/Logger';
import { BackgroundDiagnostics } from './BackgroundDiagnostics';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { RestApi } from '../network/RestApi';
import { RunConditionMonitor, RunDecision } from './RunConditionMonitor';
import { NotificationManager } from './NotificationManager';
import { PreferencesManager } from '../data/PreferencesManager';
import { Constants } from './Constants';
import { Utils } from '../common/Utils';
import { L10n } from '../common/L10n';
import { WorkSchedulerManager } from './WorkSchedulerManager';

const TAG = 'BackgroundSyncManager';
const BACKGROUND_TASK_SYSCAP = 'SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask';

function resolveBackgroundModes(): string[] {
  if (deviceInfo.deviceType === '2in1') {
    return ['taskKeeping'];
  }
  return ['dataTransfer'];
}

/**
 * Wraps HarmonyOS continuous background tasks for Syncthing's long-running sync.
 *
 * The manager intentionally uses only the system-provided bgmode notification.
 * It also keeps a lightweight heartbeat and system-task reconciliation log so
 * background task cancellation can be diagnosed from hilog.
 */
export class BackgroundSyncManager {
  private readonly bgModes: string[] = resolveBackgroundModes();
  private continuousTaskId: number = -1;
  private continuousNotificationId: number = -1;
  private enabled: boolean = false;
  private desired: boolean = false;
  private lastError: string = '';
  private context: common.UIAbilityContext | null = null;
  private heartbeatTimer: number = -1;
  private progressTimer: number = -1;
  private progressInProgress: boolean = false;
  private callbacksRegistered: boolean = false;
  private reenableInProgress: boolean = false;
  private suspendedBySystem: boolean = false;
  private lastSuspendReason: number = -1;
  private lastSuspendMessage: string = '';
  private readonly heartbeatIntervalMs: number = 30000;
  private readonly progressIntervalMs: number = 10000;

  /**
   * Stores the UIAbility context required by BackgroundTasksKit and callbacks.
   */
  initialize(context: common.UIAbilityContext): void {
    this.context = context;
    this.registerContinuousTaskCallbacks();
  }

  /**
   * Requests a continuous task and records the returned task/notification IDs.
   */
  async enable(notifyStart: boolean = true): Promise<boolean> {
    this.desired = true;
    if (!this.isContinuousTaskSupported()) {
      this.enabled = false;
      this.lastError = 'Continuous background task capability is not available on this device profile';
      Logger.w(TAG, this.lastError);
      BackgroundDiagnostics.record('background.enable.unsupported', this.lastError);
      return false;
    }
    if (this.enabled) {
      this.startHeartbeat();
      this.startProgressUpdater();
      await this.logSystemTaskSnapshot('enable-already-enabled');
      WorkSchedulerManager.register();
      await this.publishInitialProgress();
      return true;
    }

    try {
      const uiContext = this.requireContext();
      BackgroundDiagnostics.record('background.enable.request', `modes=${this.bgModes.join(',')}`);
      await this.ensureNotificationEnabled(uiContext);
      const agent = await this.createWantAgent();
      if (!canIUse('SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask')) {
        throw new Error('Continuous background task capability is not available');
      }
      const result = await backgroundTaskManager.startBackgroundRunning(uiContext, this.bgModes, agent);
      this.enabled = true;
      this.lastError = '';
      this.continuousNotificationId = result.notificationId;
      this.continuousTaskId = result.continuousTaskId === undefined ? -1 : result.continuousTaskId;

      Logger.i(TAG, `Background sync enabled notificationId=${this.continuousNotificationId}, continuousTaskId=${this.continuousTaskId}`);
      BackgroundDiagnostics.record('background.enable.success', `notificationId=${this.continuousNotificationId}, continuousTaskId=${this.continuousTaskId}`);
      await this.logSystemTaskSnapshot('enable-success');
      this.startHeartbeat();
      this.startProgressUpdater();
      WorkSchedulerManager.register();
      await this.publishInitialProgress();
      if (notifyStart) {
        await this.notifySyncStarted();
      }
      return true;
    } catch (err) {
      this.enabled = false;
      this.lastError = JSON.stringify(err);
      Logger.e(TAG, `Failed to enable background sync: ${this.lastError}`);
      BackgroundDiagnostics.record('background.enable.failed', this.lastError);
      return false;
    }
  }

  async disable(): Promise<boolean> {
    try {
      this.desired = false;
      this.stopHeartbeat();
      this.stopProgressUpdater();
      WorkSchedulerManager.unregister();
      await NotificationManager.getInstance().dismissPersistentNotification();
      if (!this.isContinuousTaskSupported()) {
        this.enabled = false;
        this.continuousTaskId = -1;
        this.continuousNotificationId = -1;
        BackgroundDiagnostics.record('background.disable.unsupported');
        return true;
      }
      const uiContext = this.requireContext();
      BackgroundDiagnostics.record('background.disable.request', `notificationId=${this.continuousNotificationId}, continuousTaskId=${this.continuousTaskId}`);
      if (!canIUse('SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask')) {
        BackgroundDiagnostics.record('background.disable.unsupported.inline');
      } else if (!this.enabled && this.continuousTaskId <= 0 && this.continuousNotificationId <= 0) {
        BackgroundDiagnostics.record('background.disable.noTask');
      } else if (this.continuousTaskId > 0) {
        await backgroundTaskManager.stopBackgroundRunning(uiContext, this.continuousTaskId);
      } else {
        await backgroundTaskManager.stopBackgroundRunning(uiContext);
      }
      this.enabled = false;
      this.continuousTaskId = -1;
      this.continuousNotificationId = -1;
      this.lastError = '';
      Logger.i(TAG, 'Background sync disabled');
      BackgroundDiagnostics.record('background.disable.success');
      await this.notifySyncStopped();
      return true;
    } catch (err) {
      this.lastError = JSON.stringify(err);
      Logger.e(TAG, `Failed to disable background sync: ${this.lastError}`);
      BackgroundDiagnostics.record('background.disable.failed', this.lastError);
      return false;
    }
  }

  async refreshNotification(): Promise<void> {
    await this.ensureRunning('refreshNotification');
  }

  async ensureRunning(source: string): Promise<boolean> {
    if (!this.desired) {
      BackgroundDiagnostics.record('background.ensure.skip', `source=${source}, desired=false, enabled=${this.enabled}`);
      return false;
    }

    const snapshot = await this.logSystemTaskSnapshot(`ensure-${source}`);
    if (this.enabled && this.continuousTaskId > 0 && snapshot.indexOf(`continuousTaskId=${this.continuousTaskId}`) >= 0) {
      return true;
    }

    BackgroundDiagnostics.record('background.ensure.restart', `source=${source}, previousTaskId=${this.continuousTaskId}, snapshot=${snapshot}`);
    this.enabled = false;
    return await this.reenable(source);
  }

  isEnabled(): boolean {
    return this.enabled;
  }

  getLastError(): string {
    return this.lastError;
  }

  getContinuousTaskId(): number {
    return this.continuousTaskId;
  }

  getNotificationId(): number {
    return this.continuousNotificationId;
  }

  private requireContext(): common.UIAbilityContext {
    if (this.context === null) {
      throw new Error('UIAbilityContext is not available for background sync');
    }
    return this.context;
  }

  private async ensureNotificationEnabled(context: common.UIAbilityContext): Promise<void> {
    try {
      const enabled = await notificationManager.isNotificationEnabled();
      BackgroundDiagnostics.record('background.notification.permission', `enabled=${enabled}`);
      if (!enabled) {
        await notificationManager.requestEnableNotification(context);
        BackgroundDiagnostics.record('background.notification.permission.requested');
      }
    } catch (err) {
      BackgroundDiagnostics.record('background.notification.permission.failed', JSON.stringify(err));
      throw new Error(JSON.stringify(err));
    }
  }

  private async createWantAgent(): Promise<WantAgent> {
    const info: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: 'com.syncthing.syncthingharmonyosnext',
          abilityName: 'EntryAbility'
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 1001,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    try {
      return await wantAgent.getWantAgent(info);
    } catch (err) {
      BackgroundDiagnostics.record('background.wantAgent.failed', JSON.stringify(err));
      throw new Error(JSON.stringify(err));
    }
  }

  private startHeartbeat(): void {
    if (this.heartbeatTimer >= 0) {
      return;
    }
    this.heartbeatTimer = setInterval(() => {
      this.runHeartbeat().catch((err: Error) => {
        BackgroundDiagnostics.record('background.heartbeat.failed', JSON.stringify(err));
      });
    }, this.heartbeatIntervalMs);
    BackgroundDiagnostics.record('background.heartbeat.started', `intervalMs=${this.heartbeatIntervalMs}`);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer < 0) {
      return;
    }
    clearInterval(this.heartbeatTimer);
    this.heartbeatTimer = -1;
    BackgroundDiagnostics.record('background.heartbeat.stopped');
  }

  private async runHeartbeat(): Promise<void> {
    await this.ensureRunning('heartbeat');
  }

  private startProgressUpdater(): void {
    if (this.progressTimer >= 0) {
      return;
    }
    this.progressTimer = setInterval(() => {
      this.runProgressUpdate().catch((err: Error) => {
        BackgroundDiagnostics.record('background.progress.failed', JSON.stringify(err));
      });
    }, this.progressIntervalMs);
    BackgroundDiagnostics.record('background.progress.started', `intervalMs=${this.progressIntervalMs}`);
  }

  private stopProgressUpdater(): void {
    if (this.progressTimer < 0) {
      return;
    }
    clearInterval(this.progressTimer);
    this.progressTimer = -1;
    BackgroundDiagnostics.record('background.progress.stopped');
  }

  private async runProgressUpdate(): Promise<void> {
    if (!this.enabled || !this.desired || this.progressInProgress) {
      return;
    }
    this.progressInProgress = true;
    try {
      const restApi = ServiceLocator.get<RestApi>(SERVICE_NAMES.REST_API);
      if (restApi === undefined) {
        BackgroundDiagnostics.record('background.progress.skip', 'restApi=undefined');
        return;
      }
      const result = await restApi.getConnections();
      if (!result.success || result.data === undefined) {
        BackgroundDiagnostics.record('background.progress.restFailed', result.error || 'no data');
        return;
      }
      const total = result.data.total;
      const inBytes = total.inBytesTotal === undefined ? 0 : total.inBytesTotal;
      const outBytes = total.outBytesTotal === undefined ? 0 : total.outBytesTotal;
      let connectedCount = 0;
      if (result.data.connections !== undefined) {
        const keys = Object.keys(result.data.connections);
        for (let i = 0; i < keys.length; i++) {
          const conn = result.data.connections[keys[i]];
          if (conn.connected === true && conn.paused !== true) {
            connectedCount++;
          }
        }
      } else if (total.numConnections !== undefined) {
        connectedCount = total.numConnections;
      }

      let paused = this.suspendedBySystem;
      const runMonitor = ServiceLocator.get<RunConditionMonitor>(SERVICE_NAMES.RUN_CONDITION_MONITOR);
      if (runMonitor !== undefined) {
        const last = runMonitor.getLastResult();
        if (last.decision === RunDecision.SHOULD_NOT_RUN || last.decision === RunDecision.FORCE_STOP) {
          paused = true;
        }
      }

      const title = L10n.t('app.string.notification_title');
      let text = '';
      if (paused) {
        text = L10n.fmt('app.string.notification_paused', Utils.formatBytes(inBytes), Utils.formatBytes(outBytes));
      } else if (connectedCount <= 0) {
        text = L10n.fmt('app.string.notification_idle', Utils.formatBytes(inBytes), Utils.formatBytes(outBytes));
      } else {
        text = L10n.fmt('app.string.notification_active', Utils.formatBytes(inBytes), Utils.formatBytes(outBytes), connectedCount);
      }
      const progress = await this.computeSyncProgress();
      if (this.usesDataTransferMode()) {
        await this.publishPersistentNotification(title, text, Math.min(progress, 99));
      }
      BackgroundDiagnostics.record('background.progress.success', `in=${inBytes},out=${outBytes},connected=${connectedCount},paused=${paused},progress=${progress},notificationId=${this.continuousNotificationId}`);
    } finally {
      this.progressInProgress = false;
    }
  }

  private async computeSyncProgress(): Promise<number> {
    try {
      const restApi = ServiceLocator.get<RestApi>(SERVICE_NAMES.REST_API);
      if (restApi === undefined) {
        return 100;
      }
      const folders = await restApi.getFolders();
      if (!folders.success || folders.data === undefined || folders.data.length === 0) {
        return 100;
      }
      let globalBytes = 0;
      let needBytes = 0;
      for (let i = 0; i < folders.data.length; i++) {
        const folder = folders.data[i];
        if (folder.paused === true) {
          continue;
        }
        const status = await restApi.getFolderStatus(folder.id);
        if (status.success && status.data !== undefined) {
          globalBytes += status.data.globalBytes;
          needBytes += status.data.needBytes;
        }
      }
      if (globalBytes <= 0) {
        return 100;
      }
      const completed = globalBytes - needBytes;
      const progress = Math.round(completed / globalBytes * 100);
      return Math.max(0, Math.min(100, progress));
    } catch (err) {
      BackgroundDiagnostics.record('background.progress.computeFailed', JSON.stringify(err));
      return 100;
    }
  }

  private async notifySyncStarted(): Promise<void> {
    if (this.usesDataTransferMode() || this.context === null) {
      return;
    }
    await NotificationManager.getInstance().showInfoNotification(
      L10n.t('app.string.notification_start_title'),
      L10n.t('app.string.notification_start_text'),
      this.context
    );
  }

  private async notifySyncStopped(): Promise<void> {
    if (this.usesDataTransferMode() || this.context === null) {
      return;
    }
    await NotificationManager.getInstance().showInfoNotification(
      L10n.t('app.string.notification_end_title'),
      L10n.t('app.string.notification_end_text'),
      this.context
    );
  }

  private async publishInitialProgress(): Promise<void> {
    if (!this.usesDataTransferMode()) {
      return;
    }
    await this.publishPersistentNotification(
      L10n.t('app.string.notification_title'),
      L10n.t('app.string.notification_idle', '0 B', '0 B'),
      0
    );
  }

  private async publishPersistentNotification(title: string, text: string, progressValue?: number): Promise<void> {
    const manager = NotificationManager.getInstance();
    if (this.continuousNotificationId < 0) {
      BackgroundDiagnostics.record('background.notification.publish.skip', 'notificationId<0');
      return;
    }
    if (this.bgModes.indexOf('dataTransfer') >= 0) {
      await manager.showDataTransferProgressNotification(
        title,
        text,
        this.continuousNotificationId,
        progressValue === undefined ? 0 : progressValue,
        text
      );
      return;
    }
    if (!manager.isPersistentNotificationShowing()) {
      if (this.context === null) {
        BackgroundDiagnostics.record('background.notification.publish.skip', 'context=null');
        return;
      }
      await manager.showPersistentNotification(title, text, this.context, this.continuousNotificationId);
    } else {
      await manager.updatePersistentNotification(title, text);
    }
  }

  private async reenable(source: string): Promise<boolean> {
    if (this.reenableInProgress) {
      BackgroundDiagnostics.record('background.reenable.skip', `source=${source}, reason=inProgress`);
      return false;
    }
    this.reenableInProgress = true;
    try {
      BackgroundDiagnostics.record('background.reenable.request', `source=${source}`);
      const result = await this.enable(false);
      BackgroundDiagnostics.record('background.reenable.result', `source=${source}, result=${result}`);
      return result;
    } finally {
      this.reenableInProgress = false;
    }
  }

  private async logSystemTaskSnapshot(source: string): Promise<string> {
    if (!this.isContinuousTaskSupported()) {
      const snapshot = 'unsupported';
      BackgroundDiagnostics.record('background.tasks.snapshot', `source=${source}, tasks=${snapshot}`);
      return snapshot;
    }
    try {
      if (!canIUse('SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask')) {
        return 'unsupported';
      }
      const tasks = await backgroundTaskManager.getAllContinuousTasks(this.requireContext(), true);
      const parts: string[] = [];
      for (let i = 0; i < tasks.length; i++) {
        const task = tasks[i];
        if (task.abilityName === 'EntryAbility' && this.hasManagedMode(task.backgroundModes)) {
          if (task.notificationId > 0) {
            this.continuousNotificationId = task.notificationId;
          }
          if (task.continuousTaskId > 0) {
            this.continuousTaskId = task.continuousTaskId;
          }
          this.enabled = true;
        }
        parts.push(`ability=${task.abilityName},pid=${task.pid},notificationId=${task.notificationId},continuousTaskId=${task.continuousTaskId},suspend=${task.suspendState},modes=${task.backgroundModes.join('|')}`);
      }
      const snapshot = parts.length > 0 ? parts.join(';') : 'none';
      BackgroundDiagnostics.record('background.tasks.snapshot', `source=${source}, managerEnabled=${this.enabled}, notificationId=${this.continuousNotificationId}, continuousTaskId=${this.continuousTaskId}, tasks=${snapshot}`);
      return snapshot;
    } catch (err) {
      const message = JSON.stringify(err);
      BackgroundDiagnostics.record('background.tasks.snapshot.failed', `source=${source}, error=${message}`);
      return `error=${message}`;
    }
  }

  private hasManagedMode(modes: string[]): boolean {
    for (let i = 0; i < modes.length; i++) {
      if (this.bgModes.indexOf(modes[i]) >= 0) {
        return true;
      }
    }
    return false;
  }

  private usesDataTransferMode(): boolean {
    return this.bgModes.indexOf('dataTransfer') >= 0;
  }

  private registerContinuousTaskCallbacks(): void {
    if (this.callbacksRegistered) {
      return;
    }
    if (!this.isContinuousTaskSupported()) {
      BackgroundDiagnostics.record('background.callbacks.unsupported');
      return;
    }
    try {
      if (!canIUse('SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask')) {
        BackgroundDiagnostics.record('background.callbacks.unsupported.inline');
        return;
      }
      backgroundTaskManager.on('continuousTaskCancel', (info) => {
        const cancelInfo = JSON.parse(JSON.stringify(info)) as Record<string, Object>;
        const detailedRaw = cancelInfo['detailedReason'];
        const detailedReason = typeof detailedRaw === 'number' ? detailedRaw : -1;
        BackgroundDiagnostics.record('background.callback.cancel',
          `id=${info.id}, reason=${info.reason}, detailedReason=${detailedReason >= 0 ? String(detailedReason) : ''}`);
        if (info.id !== this.continuousTaskId && this.continuousTaskId > 0) {
          BackgroundDiagnostics.record('background.callback.cancel.ignore', `id=${info.id}, current=${this.continuousTaskId}`);
          return;
        }
        const userRemoved = this.isUserRemovedCancel(info.reason, detailedReason);
        BackgroundDiagnostics.record('background.callback.cancel.decision', `id=${info.id}, reason=${info.reason}, detailedReason=${detailedReason >= 0 ? String(detailedReason) : ''}, userRemoved=${userRemoved}`);
        if (userRemoved) {
          this.handleUserRemovedNotification().catch((err: Error) => {
            BackgroundDiagnostics.record('background.callback.cancel.userRemovedFailed', JSON.stringify(err));
          });
        } else {
          this.handleSystemCancel().catch((err: Error) => {
            BackgroundDiagnostics.record('background.callback.cancel.systemCancelFailed', JSON.stringify(err));
          });
        }
      });
      backgroundTaskManager.on('continuousTaskSuspend', (info) => {
        this.suspendedBySystem = info.suspendState;
        this.lastSuspendReason = info.suspendReason;
        // suspendMessage is only available from API 26; access dynamically so the
        // API 20 build still compiles while API 26 runtimes can persist it.
        const suspendInfo = JSON.parse(JSON.stringify(info)) as Record<string, Object>;
        const suspendMessage = suspendInfo['suspendMessage'];
        this.lastSuspendMessage = suspendMessage === undefined ? '' : JSON.stringify(suspendMessage);
        BackgroundDiagnostics.record('background.callback.suspend', `continuousTaskId=${info.continuousTaskId}, suspendState=${info.suspendState}, reason=${this.lastSuspendReason}, message=${this.lastSuspendMessage}`);
        PreferencesManager.getInstance().putString(Constants.PREF_BACKGROUND_SUSPEND_REASON, String(this.lastSuspendReason)).catch((err: Error) => {
          BackgroundDiagnostics.record('background.suspend.persistFailed', JSON.stringify(err));
        });
        if (this.lastSuspendMessage.length > 0) {
          PreferencesManager.getInstance().putString(Constants.PREF_BACKGROUND_SUSPEND_MESSAGE, this.lastSuspendMessage).catch((err: Error) => {
            BackgroundDiagnostics.record('background.suspend.persistMessageFailed', JSON.stringify(err));
          });
        }
      });
      backgroundTaskManager.on('continuousTaskActive', (info) => {
        this.suspendedBySystem = false;
        BackgroundDiagnostics.record('background.callback.active', `id=${info.id}`);
      });
      this.callbacksRegistered = true;
      BackgroundDiagnostics.record('background.callbacks.registered');
    } catch (err) {
      BackgroundDiagnostics.record('background.callbacks.failed', JSON.stringify(err));
    }
  }

  /**
   * Decides whether a continuous-task cancel was caused by the user removing
   * the persistent notification.
   *
   * On API 26 the detailed reason is authoritative: only 3
   * (USER_CANCEL_REMOVE_NOTIFICATION) is a user removal; all other detailed
   * reasons (4/6/7/8/9/10/11/12/13/14) are system cancels and must auto-heal.
   * On older API levels detailedReason is absent, so fall back to the coarse
   * reason values (1=USER_CANCEL, 3=USER_CANCEL_REMOVE_NOTIFICATION).
   */
  private isUserRemovedCancel(reason: number, detailedReason: number): boolean {
    if (detailedReason >= 0) {
      return detailedReason === 3;
    }
    return reason === backgroundTaskManager.ContinuousTaskCancelReason.USER_CANCEL ||
      reason === backgroundTaskManager.ContinuousTaskCancelReason.USER_CANCEL_REMOVE_NOTIFICATION;
  }

  private async handleSystemCancel(): Promise<void> {
    this.enabled = false;
    this.continuousTaskId = -1;
    this.continuousNotificationId = -1;
    await NotificationManager.getInstance().dismissPersistentNotification();
    if (this.desired) {
      this.startHeartbeat();
      this.startProgressUpdater();
      await this.reenable('continuousTaskCancel');
    } else {
      this.stopHeartbeat();
      this.stopProgressUpdater();
    }
  }

  private async handleUserRemovedNotification(): Promise<void> {
    BackgroundDiagnostics.record('background.callback.cancel.userRemoved', `id=${this.continuousTaskId}, desired=${this.desired}`);
    this.enabled = false;
    this.desired = false;
    this.continuousTaskId = -1;
    this.continuousNotificationId = -1;
    this.stopHeartbeat();
    this.stopProgressUpdater();
    WorkSchedulerManager.unregister();
    await NotificationManager.getInstance().dismissPersistentNotification();
    BackgroundDiagnostics.record('background.callback.cancel.userRemoved.keepPreference');
    if (this.context !== null) {
      await NotificationManager.getInstance().showInfoNotification(
        L10n.t('app.string.notification_deleted_title'),
        L10n.t('app.string.notification_deleted_text'),
        this.context
      );
    }
  }

  private isContinuousTaskSupported(): boolean {
    return canIUse(BACKGROUND_TASK_SYSCAP);
  }
}
