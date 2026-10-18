import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Logger } from '../common/Logger';
import { PreferencesManager } from '../data/PreferencesManager';
import { Constants } from './Constants';

const TAG = 'FolderPermission';

/**
 * Runtime (user_grant) permission handling for the public Download/Documents
 * directories used by Tablet / PC / 2-in-1 devices.
 *
 * Phones cannot obtain `READ_WRITE_DOWNLOAD_DIRECTORY`; they use the
 * DocumentPickerMode.DOWNLOAD path instead, so requests are skipped there.
 * The user is prompted at most once automatically (prefs flag).
 */
export class FolderPermission {
  /** Order matters: Download first (it is the sync container). */
  static readonly DIR_PERMISSIONS: Permissions[] = [
    'ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY',
    'ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY',
  ];

  static isGranted(context: common.UIAbilityContext, permission: Permissions): boolean {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const tokenId: number = context.applicationInfo.accessTokenId;
      return atManager.checkAccessTokenSync(tokenId, permission) ===
        abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (err) {
      Logger.w(TAG, `checkAccessTokenSync(${permission}) failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  static allDirPermissionsGranted(context: common.UIAbilityContext): boolean {
    for (let i = 0; i < FolderPermission.DIR_PERMISSIONS.length; i++) {
      if (!FolderPermission.isGranted(context, FolderPermission.DIR_PERMISSIONS[i])) {
        return false;
      }
    }
    return true;
  }

  static isSupportedOnThisDevice(): boolean {
    return deviceInfo.deviceType !== 'phone' &&
      canIUse('SystemCapability.FileManagement.File.Environment.FolderObtain');
  }

  /**
   * Ask the user for the public-dir permissions. Idempotent per lifecycle:
   * already-granted permissions are skipped by the system silently. On
   * success (dialog shown, or all already granted) records the one-time
   * 'asked' flag so the app never re-prompts on its own. Returns the number
   * of permissions granted.
   */
  static async requestDirPermissions(context: common.UIAbilityContext): Promise<number> {
    if (!FolderPermission.isSupportedOnThisDevice()) {
      await PreferencesManager.getInstance().putBoolean(Constants.PREF_HAS_REQUESTED_DOWNLOAD_PERM, true);
      Logger.i(TAG, 'public-dir permissions skipped on this device');
      return 0;
    }
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(context, FolderPermission.DIR_PERMISSIONS);
      await PreferencesManager.getInstance().putBoolean(Constants.PREF_HAS_REQUESTED_DOWNLOAD_PERM, true);
      let granted = 0;
      if (result.authResults !== undefined) {
        for (let i = 0; i < result.authResults.length; i++) {
          if (result.authResults[i] === 0) {
            granted++;
          }
        }
      }
      Logger.i(TAG, `dir permissions requested: granted=${granted}/${FolderPermission.DIR_PERMISSIONS.length}`);
      return granted;
    } catch (err) {
      // e.g. called while the ability is not visible / window not focused —
      // flag stays false so a later invocation can still prompt.
      Logger.w(TAG, `requestDirPermissions failed: ${JSON.stringify(err)}`);
      return 0;
    }
  }
}