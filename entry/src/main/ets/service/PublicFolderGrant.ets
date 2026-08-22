import { fileIo, picker, fileUri, fileShare, Environment } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/Logger';
import { RestApi } from '../network/RestApi';
import { Folder } from '../model/Index';
import { Constants } from './Constants';
import { PreferencesManager } from '../data/PreferencesManager';

const TAG = 'PublicFolderGrant';

/**
 * Result of a FOLDER-picker selection: the `uri` is used for
 * `fileShare.persistPermission` (persistent grant on commercial devices), the
 * `path` is the real POSIX path returned by `FileUri(uri).path`.
 */
export interface FolderChoice {
  uri: string;
  path: string;
}

/**
 * Public-directory sync helper (A2, 2026-08-18).
 *
 * Device classes:
 * - Tablet / PC/2in1 / API26+ (`FolderObtain` syscap present):
 *   the unified container lives at `<Download>/Syncthing` and is reached via
 *   `Environment.getUserDownloadDir()` (user_grant READ_WRITE_DOWNLOAD_DIRECTORY,
 *   persistent). No picker needed.
 * - Phone-class devices (e.g. HarmonyOS NEXT phones, API24): the
 *   `FileManagement.File.Environment.FolderObtain` syscap is NOT available
 *   (official docs: `Environment.getUserDownloadDir()` on non-2in1/Tablet
 *   returns error 801 since API26). The only supported way to reach the public
 *   Download dir there is the FOLDER-picker. We fall back to it once: the user
 *   selects the Download (or any) directory, and we keep the SAME container
 *   model `<picked>/Syncthing/<folderId>`.
 * - `fileShare.persistPermission` is attempted for the picked URI (best
 *   effort): on the OpenHarmony generic image it is rejected (13900001,
 *   session-only) and the MainPage dead-folder banner offers a single-tap
 *   re-grant; on commercial HarmonyOS NEXT it may succeed and make re-picking
 *   unnecessary. `fallbackRoot` is re-established from preferences on launch.
 */
export class PublicFolderGrant {
  private static readonly SANDBOX_PREFIX: string = '/data/storage/';

  /**
   * Unified container root on devices without FolderObtain (phone-class).
   * Process-lifetime cache; re-established from Preferences on launch when the
   * persisted grant still holds (see restoreFallbackFromPrefs).
   */
  private static fallbackRoot: string = '';

  static isPublicPath(path: string): boolean {
    if (path === undefined || path === null) {
      return false;
    }
    const p = path.trim();
    if (p.length === 0 || p.indexOf('://') >= 0) {
      return false;
    }
    return !p.startsWith(PublicFolderGrant.SANDBOX_PREFIX);
  }

  static isPathAccessible(path: string): boolean {
    try {
      const entries: string[] = fileIo.listFileSync(path);
      return entries !== undefined && entries !== null;
    } catch (err) {
      return false;
    }
  }

  /**
   * Folders whose configured path is a public (non-sandbox) POSIX path that
   * is no longer readable by this process (grant lost after restart).
   */
  static async findDeadPublicFolders(api: RestApi): Promise<Folder[]> {
    const dead: Folder[] = [];
    if (api === undefined || api === null) {
      return dead;
    }
    const result = await api.getFolders();
    if (!result.success || result.data === undefined) {
      Logger.w(TAG, `findDeadPublicFolders: getFolders failed ${result.error}`);
      return dead;
    }
    const folders: Folder[] = result.data;
    for (let i = 0; i < folders.length; i++) {
      const folder = folders[i];
      if (!PublicFolderGrant.isPublicPath(folder.path)) {
        continue;
      }
      if (!PublicFolderGrant.isPathAccessible(folder.path)) {
        dead.push(folder);
      }
    }
    if (dead.length > 0) {
      Logger.i(TAG, `dead public folders: ${dead.map((f) => `${f.id}@${f.path}`).join(', ')}`);
    }
    return dead;
  }

  /**
   * Select a public directory via the FOLDER picker; returns its real POSIX
   * path plus the uri ('' '' when cancelled / unsupported).
   */
  static async chooseFolder(): Promise<FolderChoice> {
    try {
      if (!canIUse('SystemCapability.FileManagement.UserFileService.FolderSelection')) {
        Logger.w(TAG, 'FolderSelection syscap unavailable');
        return { uri: '', path: '' };
      }
      const docPicker = new picker.DocumentViewPicker();
      const opts = new picker.DocumentSelectOptions();
      opts.selectMode = picker.DocumentSelectMode.FOLDER;
      const uris: string[] = await docPicker.select(opts);
      if (uris === undefined || uris === null || uris.length === 0) {
        return { uri: '', path: '' };
      }
      const uri: string = uris[0];
      const path: string = new fileUri.FileUri(uri).path;
      Logger.i(TAG, `chooseFolder uri=${uri} path=${path}`);
      return { uri: uri, path: path };
    } catch (err) {
      Logger.w(TAG, `chooseFolder failed: ${JSON.stringify(err)}`);
      return { uri: '', path: '' };
    }
  }

  /**
   * Best-effort persistence. Returns true when the grant survived (so the
   * path keeps working after restart without a re-pick). Returns false on
   * this device class (13900001 → session-only).
   */
  static async persistGrant(uri: string, path: string): Promise<boolean> {
    const preferences: PreferencesManager = PreferencesManager.getInstance();
    try {
      const mode = fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
        | fileShare.OperationMode.CREATE_MODE | fileShare.OperationMode.DELETE_MODE
        | fileShare.OperationMode.RENAME_MODE;
      await fileShare.persistPermission([{ uri: uri, operationMode: mode } as fileShare.PolicyInfo]);
      await preferences.putString(Constants.PREF_WORK_FOLDER_URI, uri);
      await preferences.putString(Constants.PREF_WORK_FOLDER_PATH, path);
      Logger.i(TAG, `grant persisted: ${uri}`);
      return true;
    } catch (err) {
      const be = err as BusinessError;
      Logger.w(TAG, `persistPermission failed code=${be.code} msg=${be.message} (session-only)`);
      return false;
    }
  }

  /**
   * Point every dead public folder at a freshly authorized path and rescan.
   * Returns the number of folders recovered.
   */
  static async restoreFolders(api: RestApi, dead: Folder[], newPath: string): Promise<number> {
    let recovered = 0;
    for (let i = 0; i < dead.length; i++) {
      const folder = dead[i];
      folder.path = newPath;
      const put = await api.putFolder(folder.id, folder);
      if (put.success) {
        await api.scanFolder(folder.id).catch(() => undefined);
        Logger.i(TAG, `restored folder ${folder.id} -> ${newPath}`);
        recovered++;
      } else {
        Logger.w(TAG, `restore folder ${folder.id} failed: ${put.statusCode} ${JSON.stringify(put.error)}`);
      }
    }
    return recovered;
  }

  /**
   * Unified sync container root. On devices with FolderObtain (Tablet/PC,
   * API26+) it is `<Download>/Syncthing` via `Environment.getUserDownloadDir()`.
   * On phone-class devices it is the FOLDER-picker fallback root
   * `<picked>/Syncthing` ('' until the user picks once).
   * Returns '' when neither is available.
   */
  static getUnifiedSyncPath(): string {
    const envRoot = PublicFolderGrant.getEnvironmentRoot();
    if (envRoot.length > 0) {
      return envRoot;
    }
    return PublicFolderGrant.fallbackRoot;
  }

  /**
   * True when the Environment-based (Download) root is available on this
   * device — i.e. Unified-sync needs no picker here.
   */
  static isEnvironmentRootAvailable(): boolean {
    return PublicFolderGrant.getEnvironmentRoot().length > 0;
  }

  private static getEnvironmentRoot(): string {
    try {
      if (!canIUse('SystemCapability.FileManagement.File.Environment.FolderObtain')) {
        return '';
      }
      const downloadPath: string = Environment.getUserDownloadDir();
      if (downloadPath === undefined || downloadPath === null || downloadPath.length === 0) {
        return '';
      }
      return `${downloadPath}/${Constants.UNIFIED_SYNC_SUBDIR}`;
    } catch (err) {
      Logger.w(TAG, `getEnvironmentRoot failed: ${JSON.stringify(err)}`);
      return '';
    }
  }

  /**
   * Path for a specific sync folder inside the unified container.
   */
  static getUnifiedFolderPath(folderId: string): string {
    const root = PublicFolderGrant.getUnifiedSyncPath();
    if (root.length === 0) {
      return '';
    }
    return `${root}/${folderId}`;
  }

  /**
   * Whether the Download-dir permission is currently granted (and the unified
   * container is usable without picker).
   */
  static isUnifiedSyncAvailable(): boolean {
    const path = PublicFolderGrant.getUnifiedSyncPath();
    return path.length > 0;
  }

  /**
   * Re-establish the picker fallback root from a previously persisted grant
   * (Preferences). Returns the root ('' when none / no longer accessible).
   * Only meaningful on devices without FolderObtain.
   */
  static async restoreFallbackFromPrefs(): Promise<string> {
    if (PublicFolderGrant.fallbackRoot.length > 0) {
      return PublicFolderGrant.fallbackRoot;
    }
    if (PublicFolderGrant.isEnvironmentRootAvailable()) {
      return '';
    }
    try {
      const prefs = PreferencesManager.getInstance();
      const pickedPath = await prefs.getString(Constants.PREF_WORK_FOLDER_PATH);
      if (pickedPath.length === 0) {
        return '';
      }
      const root = `${pickedPath}/${Constants.UNIFIED_SYNC_SUBDIR}`;
      if (!PublicFolderGrant.isPathAccessible(root)) {
        Logger.w(TAG, `stored fallback root not accessible: ${root}`);
        return '';
      }
      PublicFolderGrant.fallbackRoot = root;
      Logger.i(TAG, `restored fallback root from prefs: ${root}`);
      return root;
    } catch (err) {
      Logger.w(TAG, `restoreFallbackFromPrefs failed: ${JSON.stringify(err)}`);
      return '';
    }
  }

  /**
   * Install a freshly FOLDER-picker-granted directory as the unified fallback
   * root: best-effort persist the URI, then keep `<picked>/Syncthing` for this
   * process. Used by the phone-class create flow and by the MainPage re-auth
   * banner.
   */
  static async setPickerFallback(uri: string, pickedPath: string): Promise<void> {
    if (pickedPath === undefined || pickedPath === null || pickedPath.length === 0) {
      return;
    }
    await PublicFolderGrant.persistGrant(uri, pickedPath);
    PublicFolderGrant.fallbackRoot = `${pickedPath}/${Constants.UNIFIED_SYNC_SUBDIR}`;
    Logger.i(TAG, `picker fallback set: root=${PublicFolderGrant.fallbackRoot}`);
  }

  /**
   * Ensure the unified container exists and is registered-ready. Resolution
   * order:
   *   1) Environment (Download) root — tablet/PC/API26+ (no picker).
   *   2) Previously persisted picker grant — reused when still accessible.
   *   3) FOLDER-picker — phone-class devices; user picks a public directory
   *      once, then the same container model `<picked>/Syncthing/<folderId>`
   *      applies.
   * Keeps the container as a PLAIN directory (NOT a syncthing folder) and
   * removes the legacy root-folder registration (sync-public-download) so
   * per-subfolder sync folders don't nest inside it.
   * Returns the root path ('' on failure / user cancelled).
   */
  static async ensureUnifiedRoot(api: RestApi): Promise<string> {
    // 1) Environment (Download) — no picker needed.
    if (PublicFolderGrant.isEnvironmentRootAvailable()) {
      const envPath = PublicFolderGrant.getUnifiedSyncPath();
      PublicFolderGrant.fallbackRoot = envPath;
      return await PublicFolderGrant.prepareRoot(api, envPath);
    }
    // 2) Previously persisted picker grant (commercial HarmonyOS).
    const restored = await PublicFolderGrant.restoreFallbackFromPrefs();
    if (restored.length > 0) {
      return await PublicFolderGrant.prepareRoot(api, restored);
    }
    // 3) Fresh FOLDER-picker (phone-class devices).
    const choice = await PublicFolderGrant.chooseFolder();
    if (choice.path.length === 0) {
      Logger.w(TAG, 'unified root unavailable: picker cancelled/unsupported');
      return '';
    }
    await PublicFolderGrant.setPickerFallback(choice.uri, choice.path);
    return await PublicFolderGrant.prepareRoot(api, PublicFolderGrant.fallbackRoot);
  }

  /**
   * mkdir the container (plain dir) + drop the legacy root-folder config, so
   * subfolders stay siblings inside it. Returns the path ('' on failure).
   */
  private static async prepareRoot(api: RestApi, path: string): Promise<string> {
    try {
      if (!PublicFolderGrant.isPathAccessible(path)) {
        fileIo.mkdir(path, true);
        Logger.i(TAG, `mkdir unified container ${path} ok`);
      }
    } catch (err) {
      Logger.w(TAG, `mkdir unified container failed: ${JSON.stringify(err)}`);
      return '';
    }
    // Remove the legacy root-folder registration (old "统一同步文件夹" pointed at
    // this same path) so it doesn't conflict with subfolders. The directory stays.
    try {
      const existing = await api.getFolder(Constants.UNIFIED_SYNC_FOLDER_ID);
      if (existing.success && existing.data !== undefined) {
        await api.deleteFolder(Constants.UNIFIED_SYNC_FOLDER_ID);
        Logger.i(TAG, `removed legacy root-folder registration ${Constants.UNIFIED_SYNC_FOLDER_ID}`);
      }
    } catch (err) {
      Logger.w(TAG, `legacy root cleanup skipped: ${JSON.stringify(err)}`);
    }
    return path;
  }

  /**
   * Ensure a specific subfolder path <Download>/Syncthing/<folderId> exists.
   * Returns the full path ('' on failure).
   */
  static async ensureUnifiedSubdir(folderId: string): Promise<string> {
    const path = PublicFolderGrant.getUnifiedFolderPath(folderId);
    if (path.length === 0) {
      return '';
    }
    try {
      if (!PublicFolderGrant.isPathAccessible(path)) {
        fileIo.mkdir(path, true);
        Logger.i(TAG, `mkdir unified subdir ${path} ok`);
      }
    } catch (err) {
      Logger.w(TAG, `mkdir unified subdir failed: ${JSON.stringify(err)}`);
      return '';
    }
    return path;
  }
}
