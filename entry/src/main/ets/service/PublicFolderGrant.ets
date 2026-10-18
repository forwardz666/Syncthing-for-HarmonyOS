import { fileIo, picker, fileUri, fileShare, Environment } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
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
 * Public-directory sync helper.
 *
 * Tablet / PC / 2-in-1 devices use `<Download>/Syncthing` through
 * `Environment.getUserDownloadDir()`. Phones use the system DOWNLOAD mode,
 * which creates `<Download>/<package>` with a persistent grant; every
 * Syncthing folder then lives at `<base>/<folderId>`. The FOLDER picker is
 * kept as a fallback when DOWNLOAD mode is unavailable.
 */
export class PublicFolderGrant {
  private static readonly SANDBOX_PREFIX: string = '/data/storage/';

  /**
   * Process-lifetime public root used when `FolderObtain` is unavailable:
   * either the DOWNLOAD-mode base `<Download>/<package>` or a picked
   * `<picked>/Syncthing`. Re-established from Preferences on launch.
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
  static async chooseFolder(context: common.UIAbilityContext): Promise<FolderChoice> {
    try {
      if (!canIUse('SystemCapability.FileManagement.UserFileService.FolderSelection')) {
        Logger.w(TAG, 'FolderSelection syscap unavailable');
        return { uri: '', path: '' };
      }
      const docPicker = new picker.DocumentViewPicker(context);
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
   * Obtains `<Download>/<package>` with a persistent grant through the system
   * DOWNLOAD mode. No permission dialog and no folder picker are involved.
   */
  static async ensureDownloadModeRoot(context: common.UIAbilityContext): Promise<string> {
    try {
      const opts = new picker.DocumentSaveOptions();
      opts.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      const docPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await docPicker.save(opts);
      if (uris === undefined || uris === null || uris.length === 0) {
        return '';
      }
      const uri: string = uris[0];
      const path: string = new fileUri.FileUri(uri).path;
      if (path.length === 0) {
        return '';
      }
      const preferences: PreferencesManager = PreferencesManager.getInstance();
      await preferences.putString(Constants.PREF_WORK_FOLDER_URI, uri);
      await preferences.putString(Constants.PREF_WORK_FOLDER_PATH, path);
      await preferences.putString(Constants.PREF_PUBLIC_ROOT_MODE, Constants.PUBLIC_ROOT_MODE_DOWNLOAD);
      PublicFolderGrant.fallbackRoot = path;
      Logger.i(TAG, `DOWNLOAD-mode root ready: ${path}`);
      return path;
    } catch (err) {
      Logger.w(TAG, `ensureDownloadModeRoot failed: ${JSON.stringify(err)}`);
      return '';
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
   * Re-points every dead public folder at `<root>/<folderId>` and rescans it.
   * Returns the number of folders recovered.
   */
  static async restoreFolders(api: RestApi, dead: Folder[], root: string): Promise<number> {
    let recovered = 0;
    for (let i = 0; i < dead.length; i++) {
      const folder = dead[i];
      const folderPath = `${root}/${PublicFolderGrant.sanitizeFolderId(folder.id)}`;
      try {
        if (!PublicFolderGrant.isPathAccessible(folderPath)) {
          fileIo.mkdir(folderPath, true);
        }
      } catch (err) {
        Logger.w(TAG, `restore mkdir failed for ${folderPath}: ${JSON.stringify(err)}`);
      }
      folder.path = folderPath;
      const put = await api.putFolder(folder.id, folder);
      if (put.success) {
        await api.scanFolder(folder.id).catch(() => undefined);
        Logger.i(TAG, `restored folder ${folder.id} -> ${folderPath}`);
        recovered++;
      } else {
        Logger.w(TAG, `restore folder ${folder.id} failed: ${put.statusCode} ${JSON.stringify(put.error)}`);
      }
    }
    return recovered;
  }

  private static sanitizeFolderId(folderId: string): string {
    const safe = folderId.replace(/[^A-Za-z0-9._-]/g, '_');
    return safe.length > 0 ? safe : 'folder';
  }

  /**
   * Unified sync root. Tablet / PC / 2-in-1 use `<Download>/Syncthing` via
   * `Environment.getUserDownloadDir()`. Phones use the DOWNLOAD-mode base
   * `<Download>/<package>` (or, as a fallback, `<picked>/Syncthing`).
   * Returns '' when no root is available.
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
    return `${root}/${PublicFolderGrant.sanitizeFolderId(folderId)}`;
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
   * Re-establishes the persisted public root (DOWNLOAD-mode base or picked
   * directory). Returns '' when none is stored or it is no longer accessible.
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
      const storedPath = await prefs.getString(Constants.PREF_WORK_FOLDER_PATH);
      if (storedPath.length === 0) {
        return '';
      }
      const mode = await prefs.getString(
        Constants.PREF_PUBLIC_ROOT_MODE, Constants.PUBLIC_ROOT_MODE_PICKER);
      const root = mode === Constants.PUBLIC_ROOT_MODE_DOWNLOAD
        ? storedPath
        : `${storedPath}/${Constants.UNIFIED_SYNC_SUBDIR}`;
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
    await PreferencesManager.getInstance().putString(
      Constants.PREF_PUBLIC_ROOT_MODE, Constants.PUBLIC_ROOT_MODE_PICKER);
    PublicFolderGrant.fallbackRoot = `${pickedPath}/${Constants.UNIFIED_SYNC_SUBDIR}`;
    Logger.i(TAG, `picker fallback set: root=${PublicFolderGrant.fallbackRoot}`);
  }

  /**
   * Ensures a public sync root exists. Resolution order:
   *   1) `<Download>/Syncthing` on FolderObtain devices.
   *   2) A persisted DOWNLOAD-mode base or FOLDER-picker root.
   *   3) `DocumentPickerMode.DOWNLOAD` -> `<Download>/<package>`.
   *   4) FOLDER picker -> `<picked>/Syncthing` (API 26+ phones).
   * The root is a plain directory, not a Syncthing folder.
   */
  static async ensureUnifiedRoot(api: RestApi, context?: common.UIAbilityContext): Promise<string> {
    if (PublicFolderGrant.isEnvironmentRootAvailable()) {
      const envPath = PublicFolderGrant.getUnifiedSyncPath();
      PublicFolderGrant.fallbackRoot = envPath;
      return await PublicFolderGrant.prepareRoot(api, envPath);
    }
    const restored = await PublicFolderGrant.restoreFallbackFromPrefs();
    if (restored.length > 0) {
      const prepared = await PublicFolderGrant.prepareRoot(api, restored);
      if (prepared.length > 0) {
        return prepared;
      }
    }
    if (context === undefined) {
      Logger.w(TAG, 'unified root unavailable: no UIAbilityContext');
      return '';
    }
    const downloadRoot = await PublicFolderGrant.ensureDownloadModeRoot(context);
    if (downloadRoot.length > 0) {
      const prepared = await PublicFolderGrant.prepareRoot(api, downloadRoot);
      if (prepared.length > 0) {
        return prepared;
      }
    }
    const choice = await PublicFolderGrant.chooseFolder(context);
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
    if (!PublicFolderGrant.isPathAccessible(path)) {
      try {
        fileIo.mkdir(path, true);
      } catch (err) {
        Logger.w(TAG, `mkdir unified container failed: ${JSON.stringify(err)}`);
      }
      if (!PublicFolderGrant.isPathAccessible(path)) {
        Logger.w(TAG, `unified container still inaccessible: ${path}`);
        return '';
      }
      Logger.i(TAG, `mkdir unified container ${path} ok`);
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
