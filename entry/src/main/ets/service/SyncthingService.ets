import { common } from '@kit.AbilityKit';
import { Logger } from '../common/Logger';
import { EventBus, SyncthingEvents } from '../common/EventBus';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { PreferencesManager } from '../data/PreferencesManager';
import { RestApi } from '../network/RestApi';
import { Constants } from './Constants';
import { ServiceState } from '../types/index';
import { Event } from '../model/Event';
import { EventProcessor } from './EventProcessor';
import { RunConditionMonitor, RunConditionResult, RunDecision } from './RunConditionMonitor';
import { SyncthingProcessManager } from './SyncthingProcessManager';
import { BackgroundSyncManager } from './BackgroundSyncManager';
import { NotificationManager } from './NotificationManager';
import { BackgroundDiagnostics } from './BackgroundDiagnostics';

const TAG = 'SyncthingService';

/**
 * Coordinates the embedded Syncthing runtime and the app-facing services around it.
 *
 * This is the lifecycle owner for the NAPI-backed Go core, REST polling, event
 * processing, run-condition monitoring, and HarmonyOS continuous background task
 * integration.
 */
export class SyncthingService {
  private state: ServiceState = 'stopped';
  private restApi: RestApi;
  private eventProcessor: EventProcessor | null = null;
  private runConditionMonitor: RunConditionMonitor | null = null;
  private backgroundSyncManager: BackgroundSyncManager | null = null;
  private preferencesManager: PreferencesManager;
  private processManager: SyncthingProcessManager | null = null;
  private updateTimer: number | null = null;
  private runConditionTimer: number | null = null;
  private syncPausedByRunConditions: boolean = false;
  private pollInterval: number = Constants.REST_UPDATE_INTERVAL_MS;
  private runConditionIntervalMs: number = 30000;
  private coreRestProbeLogged: boolean = false;

  constructor() {
    this.restApi = new RestApi();
    this.preferencesManager = PreferencesManager.getInstance();
  }

  /**
   * Registers app singletons and prepares the embedded core without starting it.
   */
  async initialize(): Promise<void> {
    Logger.i(TAG, 'SyncthingService initializing');
    ServiceLocator.registerSingleton(SERVICE_NAMES.REST_API, this.restApi);

    const appContext = ServiceLocator.getOrThrow<Context>(SERVICE_NAMES.APPLICATION_CONTEXT);
    const uiContext = ServiceLocator.getOrThrow<common.UIAbilityContext>(SERVICE_NAMES.UI_ABILITY_CONTEXT);
    this.processManager = new SyncthingProcessManager();
    await this.processManager.initialize('', appContext.filesDir);
    ServiceLocator.registerSingleton(SERVICE_NAMES.SYNCTHING_PROCESS_MANAGER, this.processManager);
    ServiceLocator.registerSingleton(SERVICE_NAMES.NOTIFICATION_MANAGER, NotificationManager.getInstance());

    try {
      await this.restApi.initialize();
    } catch (err) {
      Logger.w(TAG, `RestApi initialization deferred: ${JSON.stringify(err)}`);
    }

    this.eventProcessor = new EventProcessor(this.restApi);
    ServiceLocator.registerSingleton(SERVICE_NAMES.EVENT_PROCESSOR, this.eventProcessor);

    this.runConditionMonitor = new RunConditionMonitor(this.preferencesManager);
    ServiceLocator.registerSingleton(SERVICE_NAMES.RUN_CONDITION_MONITOR, this.runConditionMonitor);

    this.backgroundSyncManager = new BackgroundSyncManager();
    this.backgroundSyncManager.initialize(uiContext);
    ServiceLocator.registerSingleton(SERVICE_NAMES.BACKGROUND_SYNC_MANAGER, this.backgroundSyncManager);

    Logger.i(TAG, 'SyncthingService initialized');
  }

  getState(): ServiceState {
    return this.state;
  }

  getRestApi(): RestApi {
    return this.restApi;
  }

  getEventProcessor(): EventProcessor | null {
    return this.eventProcessor;
  }

  /**
   * Starts the Go core, waits for REST availability, and enables polling workers.
   */
  async startService(): Promise<void> {
    if (this.state === 'active' || this.state === 'starting') {
      Logger.w(TAG, `Service already in state: ${this.state}`);
      return;
    }

    Logger.i(TAG, 'Starting SyncthingService');
    BackgroundDiagnostics.record('service.start.request', `state=${this.state}`);
    this.setState('starting');

    try {
      if (this.processManager === null) {
        throw new Error('SyncthingProcessManager is not initialized');
      }
      const nativeStarted = await this.processManager.startNativeBinary();
      if (!nativeStarted) {
        throw new Error('Native Syncthing core failed to start');
      }

      await this.restApi.initialize();
      this.setState('active');

      if (this.eventProcessor) {
        this.eventProcessor.start();
      }
      this.startRunConditionEnforcement();
      if (this.backgroundSyncManager && await this.preferencesManager.getBoolean(Constants.PREF_START_SERVICE_ON_BOOT, false)) {
        await this.backgroundSyncManager.enable();
      }

      this.startPolling();

      EventBus.emit(SyncthingEvents.SERVICE_STATE_CHANGED, this.state);

      Logger.i(TAG, 'SyncthingService started successfully');
      BackgroundDiagnostics.record('service.start.success');
    } catch (err) {
      Logger.e(TAG, `Failed to start service: ${JSON.stringify(err)}`);
      BackgroundDiagnostics.record('service.start.failed', JSON.stringify(err));
      this.setState('error');
      EventBus.emit(SyncthingEvents.SERVICE_ERROR, JSON.stringify(err));
    }
  }

  /**
   * Stops foreground polling and the embedded core when the user explicitly stops sync.
   */
  async stopService(): Promise<void> {
    if (this.state === 'stopped') {
      return;
    }

    Logger.i(TAG, 'Stopping SyncthingService');
    BackgroundDiagnostics.record('service.stop.request');
    this.setState('stopped');

    this.stopPolling();

    if (this.eventProcessor) {
      this.eventProcessor.stop();
    }
    if (this.runConditionMonitor) {
      this.runConditionMonitor.stopMonitoring();
    }
    this.stopRunConditionEnforcement();

    if (this.processManager !== null) {
      await this.processManager.stopNativeBinary();
    }

    EventBus.emit(SyncthingEvents.SERVICE_STATE_CHANGED, this.state);

    Logger.i(TAG, 'SyncthingService stopped');
    BackgroundDiagnostics.record('service.stop.success');
  }

  /**
   * Implements Android-style Exit: stop sync, stop background running, clear
   * notifications, and close the foreground ability without changing the user's
   * background-sync preference for the next launch.
   */
  async exitApplication(): Promise<void> {
    Logger.i(TAG, 'Exiting application by user request');
    BackgroundDiagnostics.record('service.exit.request');
    await this.preferencesManager.putBoolean(Constants.PREF_EXIT_REQUESTED, true);

    if (this.backgroundSyncManager !== null) {
      await this.backgroundSyncManager.disable();
    }

    await this.stopService();
    await NotificationManager.getInstance().cancelAll();

    const uiContext = ServiceLocator.get<common.UIAbilityContext>(SERVICE_NAMES.UI_ABILITY_CONTEXT);
    if (uiContext === undefined) {
      Logger.w(TAG, 'UIAbilityContext unavailable during exit');
      BackgroundDiagnostics.record('service.exit.noUiContext');
      return;
    }

    try {
      await uiContext.terminateSelf();
      BackgroundDiagnostics.record('service.exit.terminateSelf.success');
    } catch (err) {
      Logger.e(TAG, `Failed to terminate ability during exit: ${JSON.stringify(err)}`);
      BackgroundDiagnostics.record('service.exit.terminateSelf.failed', JSON.stringify(err));
      await this.preferencesManager.remove(Constants.PREF_EXIT_REQUESTED);
      throw new Error(JSON.stringify(err));
    }
  }

  private setState(newState: ServiceState): void {
    this.state = newState;
    Logger.d(TAG, `Service state changed to: ${newState}`);
  }

  private startPolling(): void {
    if (this.updateTimer !== null) {
      return;
    }
    this.pollStatus();
  }

  private stopPolling(): void {
    if (this.updateTimer !== null) {
      clearTimeout(this.updateTimer);
      this.updateTimer = null;
    }
  }

  private startRunConditionEnforcement(): void {
    if (this.runConditionTimer !== null) {
      return;
    }
    this.enforceRunConditions();
  }

  async enforceRunConditionsNow(): Promise<void> {
    if (this.runConditionTimer !== null) {
      clearTimeout(this.runConditionTimer);
      this.runConditionTimer = null;
    }
    await this.enforceRunConditions();
  }

  private stopRunConditionEnforcement(): void {
    if (this.runConditionTimer !== null) {
      clearTimeout(this.runConditionTimer);
      this.runConditionTimer = null;
    }
    this.syncPausedByRunConditions = false;
  }

  private async enforceRunConditions(): Promise<void> {
    if (this.state !== 'active') {
      this.stopRunConditionEnforcement();
      return;
    }

    try {
      if (this.runConditionMonitor !== null) {
        const result = await this.runConditionMonitor.checkConditions();
        await this.applyRunConditionResult(result);
      }
    } catch (err) {
      Logger.w(TAG, `Run condition enforcement failed: ${JSON.stringify(err)}`);
      BackgroundDiagnostics.record('runConditions.enforce.failed', JSON.stringify(err));
    }

    this.runConditionTimer = setTimeout(() => {
      this.runConditionTimer = null;
      this.enforceRunConditions();
    }, this.runConditionIntervalMs);
  }

  private async applyRunConditionResult(result: RunConditionResult): Promise<void> {
    if (result.decision === RunDecision.SHOULD_NOT_RUN || result.decision === RunDecision.FORCE_STOP) {
      if (this.syncPausedByRunConditions) {
        return;
      }
      const pauseResult = await this.restApi.pauseAll();
      if (pauseResult.success) {
        this.syncPausedByRunConditions = true;
        Logger.i(TAG, `Syncthing paused by run conditions: ${result.reason}`);
        BackgroundDiagnostics.record('runConditions.pause.success', result.reason);
      } else {
        Logger.w(TAG, `Failed to pause Syncthing by run conditions: ${pauseResult.error}`);
        BackgroundDiagnostics.record('runConditions.pause.failed', pauseResult.error || 'unknown');
      }
      return;
    }

    if (result.decision === RunDecision.SHOULD_RUN || result.decision === RunDecision.FORCE_START) {
      if (!this.syncPausedByRunConditions && result.decision !== RunDecision.FORCE_START) {
        return;
      }
      const resumeResult = await this.restApi.resumeAll();
      if (resumeResult.success) {
        this.syncPausedByRunConditions = false;
        Logger.i(TAG, `Syncthing resumed by run conditions: ${result.reason}`);
        BackgroundDiagnostics.record('runConditions.resume.success', result.reason);
      } else {
        Logger.w(TAG, `Failed to resume Syncthing by run conditions: ${resumeResult.error}`);
        BackgroundDiagnostics.record('runConditions.resume.failed', resumeResult.error || 'unknown');
      }
    }
  }

  private async pollStatus(): Promise<void> {
    if (this.state !== 'active') {
      this.stopPolling();
      return;
    }

    try {
      const statusResult = await this.restApi.getSystemStatus();
      if (statusResult.success) {
        EventBus.emit(SyncthingEvents.EVENT_DATA_UPDATED, 'systemStatus');
      }

      const connResult = await this.restApi.getConnections();
      if (connResult.success) {
        EventBus.emit(SyncthingEvents.EVENT_DATA_UPDATED, 'connections');
      }

      const configResult = await this.restApi.getConfigFull();
      if (configResult.success) {
        EventBus.emit(SyncthingEvents.EVENT_DATA_UPDATED, 'config');
      }

      if (!this.coreRestProbeLogged) {
        let myId = '';
        if (statusResult.data !== undefined) {
          if (statusResult.data.myID !== undefined && statusResult.data.myID.length > 0) {
            myId = statusResult.data.myID;
          } else if (statusResult.data.myId !== undefined && statusResult.data.myId.length > 0) {
            myId = statusResult.data.myId;
          }
        }
        Logger.i(TAG, `Core REST probe status=${statusResult.success}, connections=${connResult.success}, config=${configResult.success}, myID=${myId}`);
        BackgroundDiagnostics.record('service.rest.probe', `status=${statusResult.success}, connections=${connResult.success}, config=${configResult.success}, myID=${myId}`);
        this.coreRestProbeLogged = true;
      }
    } catch (err) {
      Logger.d(TAG, `Poll error: ${JSON.stringify(err)}`);
      BackgroundDiagnostics.record('service.poll.error', JSON.stringify(err));
    }

    this.updateTimer = setTimeout(() => {
      this.updateTimer = null;
      this.pollStatus();
    }, this.pollInterval);
  }

  destroy(): void {
    Logger.i(TAG, 'SyncthingService destroying');
    BackgroundDiagnostics.record('service.destroy');
    this.destroySafely();
    this.restApi.setIsAvailable(false);
  }

  private async destroySafely(): Promise<void> {
    const keepBackgroundRunning = await this.preferencesManager.getBoolean(Constants.PREF_START_SERVICE_ON_BOOT, false);
    if (keepBackgroundRunning) {
      Logger.i(TAG, 'Background sync preference is enabled; keeping continuous task alive during destroy');
      BackgroundDiagnostics.record('service.destroy.keepBackground');
      return;
    }
    BackgroundDiagnostics.record('service.destroy.stop');
    await this.stopService();
  }
}
