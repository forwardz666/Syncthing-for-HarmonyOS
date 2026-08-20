import * as syncthingNative from 'libsyncthing_napi.so';
import type { SyncthingNativeModule } from 'libsyncthing_napi.so';

export { SyncthingNativeModule };

/**
 * ArkTS wrapper around the Harmony NAPI module that embeds Syncthing's Go core.
 */
export class SyncthingNative {
  static loadLibrary(libPath: string = ''): boolean {
    return syncthingNative.loadLibrary(libPath);
  }

  static unloadLibrary(): boolean {
    return syncthingNative.unloadLibrary();
  }

  static startSyncthing(homeDir: string, logFile: string, guiAddress: string, apiKey: string): number {
    return syncthingNative.startSyncthing(homeDir, logFile, guiAddress, apiKey);
  }

  static stopSyncthing(): number {
    return syncthingNative.stopSyncthing();
  }

  static isRunning(): boolean {
    return syncthingNative.isRunning();
  }

  static getVersion(): string {
    return syncthingNative.getVersion();
  }

  static getLastError(): string {
    return syncthingNative.getLastError();
  }

  static startSyncthingProcess(executablePath: string, homeDir: string, logFile: string, guiAddress: string, apiKey: string): number {
    return syncthingNative.startSyncthingProcess(executablePath, homeDir, logFile, guiAddress, apiKey);
  }

  static stopSyncthingProcess(): number {
    return syncthingNative.stopSyncthingProcess();
  }
}
