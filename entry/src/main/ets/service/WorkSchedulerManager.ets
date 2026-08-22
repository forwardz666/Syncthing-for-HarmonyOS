import { workScheduler } from '@kit.BackgroundTasksKit';
import { Logger } from '../common/Logger';
import { BackgroundDiagnostics } from './BackgroundDiagnostics';

const TAG = 'WorkSchedulerManager';
const WATCH_WORK_ID = 2;
const WATCH_BUNDLE_NAME = 'com.syncthing.syncthingharmonyosnext';
const WATCH_ABILITY_NAME = 'SyncWatchExt';
const WATCH_REPEAT_CYCLE_MS = 30 * 60 * 1000;

/**
 * Registers the delayed-task fallback (route C) for Syncthing keepalive.
 *
 * When the app/process is killed, WorkScheduler can still wake SyncWatchExt to
 * probe whether the embedded core is alive and surface an info notification if
 * it is not. The task is intentionally a real delayed task, never a fake
 * keepalive or ClashBox-style simulation.
 */
export class WorkSchedulerManager {
  static register(): void {
    try {
      workScheduler.stopAndClearWorks();
      const workInfo: workScheduler.WorkInfo = {
        workId: WATCH_WORK_ID,
        bundleName: WATCH_BUNDLE_NAME,
        abilityName: WATCH_ABILITY_NAME,
        networkType: workScheduler.NetworkType.NETWORK_TYPE_ANY,
        isRepeat: true,
        repeatCycleTime: WATCH_REPEAT_CYCLE_MS,
        isPersisted: true,
      };
      workScheduler.startWork(workInfo);
      Logger.i(TAG, `Registered SyncWatch workId=${WATCH_WORK_ID}`);
      BackgroundDiagnostics.record('workScheduler.register.success', `workId=${WATCH_WORK_ID}, repeatCycleMs=${WATCH_REPEAT_CYCLE_MS}`);
    } catch (err) {
      Logger.e(TAG, `Failed to register SyncWatch work: ${JSON.stringify(err)}`);
      BackgroundDiagnostics.record('workScheduler.register.failed', JSON.stringify(err));
    }
  }

  static unregister(): void {
    try {
      workScheduler.stopAndClearWorks();
      Logger.i(TAG, 'Cleared SyncWatch works');
      BackgroundDiagnostics.record('workScheduler.unregister.success');
    } catch (err) {
      Logger.e(TAG, `Failed to clear SyncWatch works: ${JSON.stringify(err)}`);
      BackgroundDiagnostics.record('workScheduler.unregister.failed', JSON.stringify(err));
    }
  }
}
