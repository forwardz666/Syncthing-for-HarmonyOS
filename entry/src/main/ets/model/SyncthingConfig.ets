import { Device, PendingDevice, RemoteIgnoredDevice } from './Device';
import { GuiConfig } from './GuiConfig';
import { Options } from './Options';

export interface SyncthingConfig {
  version: number;
  folders: Folder[];
  devices: Device[];
  gui: GuiConfig;
  options: Options;
  ldap?: LdapConfig;
  defaults?: Defaults;
  pendingDevices?: PendingDevice[];
  remoteIgnoredDevices?: RemoteIgnoredDevice[];
}

export interface Folder {
  id: string;
  label: string;
  filesystemType?: string;
  path: string;
  type: string;
  devices: FolderDevice[];
  group?: string;
  rescanIntervalS: number;
  fsWatcherEnabled: boolean;
  fsWatcherDelayS: number;
  fsWatcherTimeoutS?: number;
  ignorePerms: boolean;
  autoNormalize: boolean;
  minDiskFree?: MinDiskFree;
  minDiskFreePct: number;
  versioning: Versioning;
  copiers: number;
  pullerMaxPendingKiB?: number;
  pullers: number;
  hashers: number;
  order: string;
  ignoreDelete: boolean;
  scanProgressIntervalS: number;
  pullerPauseS: number;
  pullerDelayS?: number;
  maxConflicts: number;
  maxConcurrentWrites: number;
  disableSparseFiles: boolean;
  disableTempIndexes: boolean;
  disableFsync?: boolean;
  pinned: boolean;
  markerName: string;
  copyOwnershipFromParent: boolean;
  copyRangeMethod: string;
  modTimeWindowS: number;
  paused?: boolean;
  blockPullOrder?: string;
  caseSensitiveFS?: boolean;
  junctionsAsDirs?: boolean;
  syncOwnership?: boolean;
  sendOwnership?: boolean;
  syncXattrs?: boolean;
  sendXattrs?: boolean;
  xattrFilter?: XattrFilter;
}

export interface FolderDevice {
  deviceID?: string;
  deviceId: string;
  introducedBy: string;
  encryptionPassword: string;
}

export interface Versioning {
  type: string;
  params: Record<string, string>;
  cleanupIntervalS?: number;
  fsPath: string;
  fsType: string;
}

export interface MinDiskFree {
  value: number;
  unit: string;
}

export interface XattrFilter {
  entries: string[];
  maxSingleEntrySize: number;
  maxTotalSize: number;
}

export interface Defaults {
  folder: Folder;
  device: Device;
  ignores: IgnoreDefaults;
}

export interface IgnoreDefaults {
  lines: string[];
}

export interface LdapConfig {
  address: string;
  bindDn: string;
  transport: string;
  insecureSkipVerify: boolean;
  searchBaseDn: string;
  searchFilter: string;
}
