import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { Logger } from '../common/Logger';
import { L10n } from '../common/L10n';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { PreferencesManager } from '../data/PreferencesManager';
import { Constants } from '../service/Constants';
import { FolderPermission } from '../service/FolderPermission';
import { BackgroundSyncManager } from '../service/BackgroundSyncManager';
import { SyncthingService } from '../service/SyncthingService';
import { BackgroundDiagnostics } from '../service/BackgroundDiagnostics';

const TAG = 'EntryAbility';

/**
 * Application ability entry point.
 *
 * It registers long-lived services, loads preferences, and avoids stopping the
 * Syncthing core during normal foreground/background transitions.
 */
export default class EntryAbility extends UIAbility {
  private preferencesManager: PreferencesManager = PreferencesManager.getInstance();

  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    Logger.i(TAG, 'EntryAbility onCreate');

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      Logger.e(TAG, `Failed to set colorMode: ${JSON.stringify(err)}`);
    }

    const appContext = this.context.getApplicationContext();
    ServiceLocator.registerSingleton(SERVICE_NAMES.APPLICATION_CONTEXT, appContext);
    ServiceLocator.registerSingleton(SERVICE_NAMES.UI_ABILITY_CONTEXT, this.context);

    try {
      await this.preferencesManager.initialize(appContext);
      ServiceLocator.registerSingleton(SERVICE_NAMES.PREFERENCES_MANAGER, this.preferencesManager);

      const verboseLog = await this.preferencesManager.isVerboseLogEnabled();
      Logger.setVerboseLog(verboseLog);
      await this.preferencesManager.remove(Constants.PREF_EXIT_REQUESTED);
      // Reset any persisted 'Force Stop' button state from a previous run so the
      // embedded core is not blocked from starting on next launch.
      await this.preferencesManager.putNumber(Constants.PREF_BTNSTATE_FORCE_START_STOP,
        Constants.BTNSTATE_NO_FORCE_START_STOP);

    } catch (err) {
      Logger.e(TAG, `Failed to initialize preferences: ${JSON.stringify(err)}`);
    }

    // i18n: init L10n with saved language preference (default zh-CN).
    try {
      const langPref = await this.preferencesManager.getString(Constants.PREF_APP_LANGUAGE, 'zh-CN');
      L10n.setLocale(langPref);
      Logger.i(TAG, `App language: ${L10n.getCurrentLocale()}`);
    } catch (err) {
      L10n.setLocale('zh-CN');
      Logger.w(TAG, `Language init failed, default zh-CN: ${JSON.stringify(err)}`);
    }

    Logger.i(TAG, 'EntryAbility initialized successfully');
  }

  onDestroy(): void {
    Logger.i(TAG, 'EntryAbility onDestroy');
    BackgroundDiagnostics.record('ability.onDestroy');
    this.destroySafely();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    Logger.i(TAG, 'EntryAbility onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        Logger.e(TAG, `Failed to load content: ${JSON.stringify(err)}`);
        return;
      }
      Logger.i(TAG, 'Content loaded successfully');
    });

    // The Download-dir user_grant permission is requested right after the
    // first-start wizard finishes (FirstStartPage.finishFirstStart). For
    // already-onboarded installs that were never asked (e.g. upgraded from a
    // pre-permission build) we prompt once here. Granting gives direct,
    // persistent access to the public Download dir — a unified sync folder
    // there needs no picker and survives app restarts.
    this.requestFolderPermissionOnce();
  }

  private async requestFolderPermissionOnce(): Promise<void> {
    try {
      const alreadyAsked = await this.preferencesManager.getBoolean(Constants.PREF_HAS_REQUESTED_DOWNLOAD_PERM, false);
      if (alreadyAsked) {
        return;
      }
      // Fresh installs: the wizard prompts right after onboarding; never
      // double-ask here.
      if (await this.isFirstRun()) {
        return;
      }
      const granted = await FolderPermission.requestDirPermissions(this.context);
      Logger.i(TAG, `Folder permissions auto-requested for returning user: granted=${granted}`);
    } catch (err) {
      Logger.w(TAG, `requestFolderPermissionOnce failed: ${JSON.stringify(err)}`);
    }
  }

  private async isFirstRun(): Promise<boolean> {
    try {
      return !(await this.preferencesManager.has(Constants.PREF_LOCAL_DEVICE_ID));
    } catch (err) {
      Logger.w(TAG, `isFirstRun check failed: ${JSON.stringify(err)}`);
      return true;
    }
  }

  onWindowStageDestroy(): void {
    Logger.i(TAG, 'EntryAbility onWindowStageDestroy');
    BackgroundDiagnostics.record('ability.onWindowStageDestroy');
  }

  onForeground(): void {
    Logger.i(TAG, 'EntryAbility onForeground');
    BackgroundDiagnostics.record('ability.onForeground');
    this.keepBackgroundSessionAlive('onForeground');
  }

  onBackground(): void {
    Logger.i(TAG, 'EntryAbility onBackground');
    BackgroundDiagnostics.record('ability.onBackground');
    this.keepBackgroundSessionAlive('onBackground');
  }

  private destroySafely(): void {
    this.isExitRequested()
      .then((exitRequested: boolean) => {
        if (exitRequested) {
          Logger.i(TAG, 'User exit requested; stopping service and skipping background keepalive');
          BackgroundDiagnostics.record('ability.destroy.exitRequested');
          return this.stopForUserExit();
        }
        return this.destroyByBackgroundPolicy();
      })
      .catch((err: Error) => {
        Logger.e(TAG, `Failed to evaluate destroy policy: ${JSON.stringify(err)}`);
        BackgroundDiagnostics.record('ability.destroy.policyFailed', JSON.stringify(err));
        ServiceLocator.clear();
      });
  }

  private async isExitRequested(): Promise<boolean> {
    return await this.preferencesManager.getBoolean(Constants.PREF_EXIT_REQUESTED, false);
  }

  private async stopForUserExit(): Promise<void> {
    await this.preferencesManager.remove(Constants.PREF_EXIT_REQUESTED);
    const manager = ServiceLocator.get<BackgroundSyncManager>(SERVICE_NAMES.BACKGROUND_SYNC_MANAGER);
    if (manager !== undefined) {
      await manager.disable();
    }
    const service = ServiceLocator.get<SyncthingService>(SERVICE_NAMES.SYNCTHING_SERVICE);
    if (service !== undefined) {
      await service.stopService();
    }
    ServiceLocator.clear();
  }

  private destroyByBackgroundPolicy(): Promise<void> {
    return this.shouldKeepBackgroundRunning()
      .then((keepRunning: boolean) => {
        if (keepRunning) {
          Logger.i(TAG, 'Background sync is enabled; keeping service registry for continuous task');
          BackgroundDiagnostics.record('ability.destroy.keepBackground');
          this.keepBackgroundSessionAlive('onDestroy');
          return;
        }
        BackgroundDiagnostics.record('ability.destroy.stopAndClear');
        const service = ServiceLocator.get<SyncthingService>(SERVICE_NAMES.SYNCTHING_SERVICE);
        if (service !== undefined) {
          service.destroy();
        }
        ServiceLocator.clear();
      })
      .catch((err: Error) => {
        Logger.e(TAG, `Failed to evaluate destroy policy: ${JSON.stringify(err)}`);
        BackgroundDiagnostics.record('ability.destroy.policyFailed', JSON.stringify(err));
        ServiceLocator.clear();
      });
  }

  private async shouldKeepBackgroundRunning(): Promise<boolean> {
    return await this.preferencesManager.getBoolean(Constants.PREF_START_SERVICE_ON_BOOT, false);
  }

  private keepBackgroundSessionAlive(source: string): void {
    this.ensureBackgroundSession(source).catch((err: Error) => {
      Logger.e(TAG, `Failed to keep background session alive from ${source}: ${JSON.stringify(err)}`);
    });
  }

  private async ensureBackgroundSession(source: string): Promise<void> {
    if (await this.isExitRequested()) {
      BackgroundDiagnostics.record('ability.ensure.skipExitRequested', `source=${source}`);
      return;
    }

    const enabled = await this.shouldKeepBackgroundRunning();
    if (!enabled) {
      return;
    }

    const service = ServiceLocator.get<SyncthingService>(SERVICE_NAMES.SYNCTHING_SERVICE);
    if (service !== undefined && service.getState() !== 'active') {
      Logger.i(TAG, `Restarting SyncthingService for background sync from ${source}`);
      BackgroundDiagnostics.record('ability.ensure.restartService', `source=${source}, state=${service.getState()}`);
      await service.startService();
    }

    const manager = ServiceLocator.get<BackgroundSyncManager>(SERVICE_NAMES.BACKGROUND_SYNC_MANAGER);
    if (manager !== undefined && !manager.isEnabled()) {
      Logger.i(TAG, `Re-enabling continuous background task from ${source}`);
      BackgroundDiagnostics.record('ability.ensure.enableBackground', `source=${source}`);
      await manager.enable();
    } else if (manager !== undefined) {
      await manager.ensureRunning(source);
    }
  }
}
