declare module 'libsyncthing_napi.so' {
  export interface SyncthingNativeModule {
    loadLibrary(libPath: string): boolean;
    unloadLibrary(): boolean;
    startSyncthing(homeDir: string, logFile: string, guiAddress: string, apiKey: string): number;
    stopSyncthing(): number;
    isRunning(): boolean;
    getVersion(): string;
    getLastError(): string;
    startSyncthingProcess(executablePath: string, homeDir: string, logFile: string, guiAddress: string, apiKey: string): number;
    stopSyncthingProcess(): number;
  }

  const syncthingNative: SyncthingNativeModule;
  export default syncthingNative;
}
