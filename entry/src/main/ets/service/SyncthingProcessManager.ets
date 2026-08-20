import { fileIo } from '@kit.CoreFileKit';
import { bundleManager } from '@kit.AbilityKit';
import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { RestApi } from '../network/RestApi';
import { Constants } from './Constants';
import { PreferencesManager } from '../data/PreferencesManager';
import { SyncthingNative } from '../native/SyncthingNative';
import { BackgroundDiagnostics } from './BackgroundDiagnostics';

const TAG = 'SyncthingProcessManager';

export interface ProcessState {
  isRunning: boolean;
  pid: number;
  startTime: number;
}

/**
 * Owns the native bridge boundary to the patched Syncthing Go core.
 *
 * HarmonyOS Next cannot reuse the Android libsyncthingnative.so directly, so
 * this manager copies the bundled core artifact into app storage, prepares the
 * sandboxed home directory and API key, then invokes the NAPI wrapper.
 */
export class SyncthingProcessManager {
  private processState: ProcessState = {
    isRunning: false,
    pid: 0,
    startTime: 0,
  };

  private restApi: RestApi;
  private preferencesManager: PreferencesManager;
  private nativeLibraryDir: string = '';
  private appFilesDir: string = '';
  private apiKey: string = '';

  constructor() {
    this.restApi = new RestApi();
    this.preferencesManager = PreferencesManager.getInstance();
  }

  /**
   * Captures app paths and ensures the local Web GUI API key is available.
   */
  async initialize(nativeLibraryDir: string, appFilesDir: string): Promise<void> {
    const registeredRestApi = ServiceLocator.get<RestApi>(SERVICE_NAMES.REST_API);
    if (registeredRestApi !== undefined) {
      this.restApi = registeredRestApi;
    }
    this.nativeLibraryDir = nativeLibraryDir;
    this.appFilesDir = appFilesDir;
    this.apiKey = await this.ensureApiKey();
    this.restApi.setApiKey(this.apiKey);
    Logger.i(TAG, 'SyncthingProcessManager initialized');
    Logger.d(TAG, `Native lib dir: ${nativeLibraryDir}`);
    Logger.d(TAG, `App files dir: ${appFilesDir}`);
  }

  getSyncthingBinaryPath(): string {
    return Constants.getSyncthingBinaryPath(this.nativeLibraryDir);
  }

  getConfigFilePath(): string {
    return Constants.getConfigFilePath(this.appFilesDir);
  }

  getHttpsCertPath(): string {
    return Constants.getHttpsCertFilePath(this.appFilesDir);
  }

  getHttpsKeyPath(): string {
    return Constants.getHttpsKeyFilePath(this.appFilesDir);
  }

  async startNativeBinary(): Promise<boolean> {
    if (this.processState.isRunning) {
      Logger.w(TAG, 'Native binary already running');
      return true;
    }

    Logger.i(TAG, 'Starting native Syncthing binary');
    BackgroundDiagnostics.record('core.start.request', `home=${this.appFilesDir}`);

    try {
      const logPath = Constants.getSyncthingLogFilePath(this.appFilesDir);
      Logger.i(TAG, `Calling linked Syncthing core home=${this.appFilesDir}, gui=${Constants.SYNCTHING_BASE_URL}`);
      const startResult = SyncthingNative.startSyncthing(
        this.appFilesDir,
        logPath,
        Constants.SYNCTHING_BASE_URL,
        this.apiKey
      );

      if (startResult !== 0 && startResult !== 1) {
        Logger.e(TAG, `Native Syncthing start failed: ${startResult}, ${SyncthingNative.getLastError()}`);
        return false;
      }

      const apiReady = await this.waitForApi(30000);
      if (!apiReady) {
        Logger.e(TAG, `Syncthing REST API did not become available: ${SyncthingNative.getLastError()}`);
        Logger.e(TAG, this.readProcessLogTail());
        return false;
      }

      this.processState.isRunning = true;
      this.processState.pid = 0;
      this.processState.startTime = Date.now();
      Logger.i(TAG, `Native Syncthing started: ${SyncthingNative.getVersion()}`);
      BackgroundDiagnostics.record('core.start.success', `version=${SyncthingNative.getVersion()}`);
      return true;
    } catch (err) {
      Logger.e(TAG, `Failed to start native binary: ${this.formatError(err)}`);
      BackgroundDiagnostics.record('core.start.failed', this.formatError(err));
      return false;
    }
  }

  async stopNativeBinary(): Promise<boolean> {
    if (!this.processState.isRunning) {
      Logger.w(TAG, 'Native binary not running');
      return true;
    }

    Logger.i(TAG, 'Stopping native Syncthing binary');
    BackgroundDiagnostics.record('core.stop.request');
    try {
      await this.restApi.shutdown();
    } catch (err) {
      Logger.w(TAG, `REST shutdown failed: ${JSON.stringify(err)}`);
    }
    SyncthingNative.stopSyncthing();

      this.processState.isRunning = false;
      this.processState.pid = 0;
      BackgroundDiagnostics.record('core.stop.success');
      return true;
  }

  isRunning(): boolean {
    return this.processState.isRunning;
  }

  getProcessState(): ProcessState {
    return this.processState;
  }

  async restartNativeBinary(): Promise<boolean> {
    Logger.i(TAG, 'Restarting native Syncthing binary');
    await this.stopNativeBinary();
    return await this.startNativeBinary();
  }

  async isApiAvailable(): Promise<boolean> {
    try {
      const result = await this.restApi.ping();
      return result.success;
    } catch (err) {
      return false;
    }
  }

  async waitForApi(timeoutMs: number = 30000): Promise<boolean> {
    const startTime = Date.now();
    const interval = 500;

    while (Date.now() - startTime < timeoutMs) {
      const available = await this.isApiAvailable();
      if (available) {
        return true;
      }
      await new Promise<void>(resolve => setTimeout(resolve, interval));
    }
    return false;
  }

  private async ensureApiKey(): Promise<string> {
    const key = Constants.DEFAULT_WEBUI_API_KEY;
    await this.preferencesManager.putString(Constants.PREF_WEBUI_API_KEY, key);
    return key;
  }

  private async ensureSyncthingExecutable(): Promise<string> {
    const bundledPath = await this.getBundledExecutablePath();
    if (bundledPath.length > 0) {
      return bundledPath;
    }

    const executablePath = `${this.appFilesDir}/syncthing_core`;
    try {
      const stat = fileIo.statSync(executablePath);
      if (stat.size > 0) {
        return executablePath;
      }
    } catch (err) {
    }

    const context = ServiceLocator.getOrThrow<Context>(SERVICE_NAMES.APPLICATION_CONTEXT);
    let content: Uint8Array;
    try {
      content = await context.resourceManager.getRawFileContent('syncthing_core');
    } catch (err) {
      throw new Error(`Unable to read bundled Syncthing core: ${JSON.stringify(err)}`);
    }

    let file: fileIo.File;
    try {
      file = await fileIo.open(
        executablePath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
    } catch (err) {
      throw new Error(`Unable to create Syncthing executable: ${JSON.stringify(err)}`);
    }

    try {
      try {
        await fileIo.write(file.fd, content.buffer);
      } catch (err) {
        throw new Error(`Unable to write Syncthing executable: ${JSON.stringify(err)}`);
      }
      Logger.i(TAG, `Syncthing executable installed: ${executablePath}`);
    } finally {
      try {
        await fileIo.close(file);
      } catch (err) {
        Logger.w(TAG, `Failed to close Syncthing executable: ${JSON.stringify(err)}`);
      }
    }
    return executablePath;
  }

  private async getBundledExecutablePath(): Promise<string> {
    try {
      const bundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
      );
      const nativeLibraryPath = bundleInfo.appInfo.nativeLibraryPath;
      if (nativeLibraryPath.length === 0) {
        return '';
      }
      const executablePath = `${nativeLibraryPath}/libsyncthing_core.so`;
      const stat = fileIo.statSync(executablePath);
      if (stat.size > 0) {
        Logger.i(TAG, `Using bundled Syncthing executable: ${executablePath}`);
        return executablePath;
      }
    } catch (err) {
      Logger.w(TAG, `Bundled Syncthing executable unavailable: ${JSON.stringify(err)}`);
    }
    return '';
  }

  private readProcessLogTail(): string {
    const logPath = `${this.appFilesDir}/syncthing-process.log`;
    try {
      const content = fileIo.readTextSync(logPath);
      if (content.length <= 3000) {
        return content;
      }
      return content.substring(content.length - 3000);
    } catch (err) {
      return `No process log available at ${logPath}: ${JSON.stringify(err)}`;
    }
  }

  private formatError(err: Error | Object): string {
    if (err instanceof Error) {
      return `${err.name}: ${err.message}`;
    }
    return `${err}`;
  }
}
