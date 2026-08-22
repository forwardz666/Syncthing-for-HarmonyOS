import { workScheduler, WorkSchedulerExtensionAbility } from '@kit.BackgroundTasksKit';
import { Logger } from '../common/Logger';
import { L10n } from '../common/L10n';
import { PreferencesManager } from '../data/PreferencesManager';
import { RestApi } from '../network/RestApi';
import { NotificationManager } from '../service/NotificationManager';
import { BackgroundDiagnostics } from '../service/BackgroundDiagnostics';

const TAG = 'SyncWatchExt';

/**
 * WorkScheduler fallback (route C) for the background-keepalive plan.
 *
 * WorkSchedulerExtensionAbility must not call backgroundTaskManager (explicitly
 * forbidden by the platform). It only probes the local REST endpoint and shows
 * an honest info notification when the Syncthing core is absent.
 */
export default class SyncWatchExt extends WorkSchedulerExtensionAbility {
  onWorkStart(work: workScheduler.WorkInfo): void {
    Logger.i(TAG, `onWorkStart workId=${work.workId}, bundleName=${work.bundleName}, abilityName=${work.abilityName}`);
    BackgroundDiagnostics.record('workScheduler.onWorkStart', `workId=${work.workId}`);
    this.probe().catch((err: Error) => {
      Logger.e(TAG, `SyncWatch probe failed: ${JSON.stringify(err)}`);
      BackgroundDiagnostics.record('workScheduler.probe.failed', JSON.stringify(err));
    });
  }

  onWorkStop(work: workScheduler.WorkInfo): void {
    Logger.i(TAG, `onWorkStop workId=${work.workId}`);
    BackgroundDiagnostics.record('workScheduler.onWorkStop', `workId=${work.workId}`);
  }

  private async probe(): Promise<void> {
    try {
      const context = this.context;
      const preferencesManager = PreferencesManager.getInstance();
      await preferencesManager.initialize(context);
      const restApi = new RestApi();
      await restApi.initialize();
      const ping = await restApi.ping();
      if (ping.success) {
        Logger.i(TAG, 'Core REST ping succeeded; Syncthing core is reachable');
        BackgroundDiagnostics.record('workScheduler.probe.corePresent', 'ping=ok');
        return;
      }
      Logger.w(TAG, `Core REST ping failed: ${ping.error || 'unknown'}`);
      BackgroundDiagnostics.record('workScheduler.probe.coreAbsent', ping.error || 'unknown');
      await NotificationManager.getInstance().showInfoNotification(
        L10n.t('app.string.work_scheduler_watch_title'),
        L10n.t('app.string.work_scheduler_watch_text'),
        context
      );
    } catch (err) {
      Logger.e(TAG, `SyncWatch probe exception: ${JSON.stringify(err)}`);
      BackgroundDiagnostics.record('workScheduler.probe.exception', JSON.stringify(err));
    }
  }
}
