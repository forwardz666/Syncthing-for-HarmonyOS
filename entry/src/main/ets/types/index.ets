export interface SyncthingConfig {
  version: number;
  folders: FolderConfiguration[];
  devices: DeviceConfiguration[];
  gui: GuiConfiguration;
  options: OptionsConfiguration;
  ldap?: LdapConfiguration;
}

export interface FolderConfiguration {
  id: string;
  label: string;
  path: string;
  type: FolderType;
  devices: FolderDeviceConfiguration[];
  rescanIntervalS: number;
  fsWatcherEnabled: boolean;
  fsWatcherDelayS: number;
  ignorePerms: boolean;
  autoNormalize: boolean;
  minDiskFreePct: number;
  versioning: VersioningConfiguration;
  copiers: number;
  pullers: number;
  hashers: number;
  order: PullOrder;
  ignoreDelete: boolean;
  scanProgressIntervalS: number;
  pullerPauseS: number;
  maxConflicts: number;
  maxConcurrentWrites: number;
  disableSparseFiles: boolean;
  disableTempIndexes: boolean;
  pinned: boolean;
  markerName: string;
  copyOwnershipFromParent: boolean;
  copyRangeMethod: CopyRangeMethod;
  modTimeWindowS: number;
}

export type FolderType = 'sendreceive' | 'sendonly' | 'receiveonly' | 'receiveencrypted';

export type PullOrder = 'random' | 'alphabetic' | 'smallestFirst' | 'largestFirst' | 'oldestFirst' | 'newestFirst';

export type CopyRangeMethod = 'standard' | 'ioctl' | 'copyfile';

export interface FolderDeviceConfiguration {
  deviceId: string;
  introducedBy: string;
  encryptionPassword: string;
}

export interface VersioningConfiguration {
  type: string;
  params: Record<string, string>;
  fsPath: string;
  fsType: string;
}

export interface DeviceConfiguration {
  deviceId: string;
  name: string;
  addresses: string[];
  compression: CompressionType;
  certName: string;
  introducer: boolean;
  skipIntroductionRemovals: boolean;
  introducedBy: string;
  paused: boolean;
  allowedNetworks: string[];
  autoAcceptFolders: boolean;
  maxSendKbps: number;
  maxRecvKbps: number;
  ignoredFolders: IgnoredFolder[];
  maxRequestKib: number;
  numConnections: number;
  untrusted: boolean;
  remoteGuiPort: number;
}

export type CompressionType = 'metadata' | 'always' | 'never';

export interface IgnoredFolder {
  id: string;
  label: string;
  time: string;
}

export interface GuiConfiguration {
  enabled: boolean;
  address: string;
  user: string;
  password: string;
  authMode: string;
  useTLS: boolean;
  apiKey: string;
  theme: string;
  debugging: boolean;
  insecureSkipHostcheck: boolean;
  insecureAdminAccess: boolean;
  rawUnixSocketPermissions: string;
}

export interface OptionsConfiguration {
  listenAddresses: string[];
  globalAnnounceServers: string[];
  globalAnnounceEnabled: boolean;
  localAnnounceEnabled: boolean;
  localAnnouncePort: number;
  localAnnounceMCAddr: string;
  maxSendKbps: number;
  maxRecvKbps: number;
  reconnectionIntervalS: number;
  relaysEnabled: boolean;
  relayReconnectIntervalM: number;
  startBrowser: boolean;
  natEnabled: boolean;
  natLeaseMinutes: number;
  natRenewalMinutes: number;
  natTimeoutSeconds: number;
  urAccepted: number;
  urSeen: number;
  urUniqueId: string;
  urPostInsecurely: boolean;
  urInitialDelayS: number;
  autoUpgradeIntervalH: number;
  upgradeToPreReleases: boolean;
  keepTemporariesH: number;
  cacheIgnoredFiles: boolean;
  progressUpdateIntervalS: number;
  limitBandwidthInLan: boolean;
  minHomeDiskFree: number;
  releasesUrl: string;
  overwriteRemoteDeviceNamesOnConnect: boolean;
  tempIndexMinBlocks: number;
  trafficClass: number;
  setLowPriority: boolean;
  maxConcurrentScans: number;
  maxConcurrentIncomingRequestKib: number;
  sendFullIndexOnUpgrade: boolean;
  featureFlags: string[];
  connectionLimitEnough: number;
  connectionLimitMax: number;
  insecureAllowOldTlsVersions: boolean;
}

export interface LdapConfiguration {
  address: string;
  bindDn: string;
  transport: string;
  insecureSkipVerify: boolean;
  searchBaseDn: string;
  searchFilter: string;
}

export interface SystemStatus {
  alloc: number;
  connectionServiceStatus: Record<string, ConnectionServiceStatus>;
  cpuPercent: number;
  discoveryEnabled: boolean;
  discoveryErrors: Record<string, string>;
  discoveryMethods: number;
  discoveryStatus: string;
  goroutines: number;
  guiAddressOverridden: boolean;
  guiAddressUsed: string;
  lastDialStatus: Record<string, string>;
  myId: string;
  pathSeparator: string;
  startTime: string;
  uptime: number;
  urVersion: number;
  version: string;
}

export interface ConnectionServiceStatus {
  error: string;
  lanAddresses: string[];
  wanAddresses: string[];
}

export interface SystemVersion {
  arch: string;
  longVersion: string;
  os: string;
  version: string;
}

export interface Connection {
  address: string;
  at: string;
  clientVersion: string;
  connected: boolean;
  crypto: string;
  deviceId: string;
  inBytesTotal: number;
  outBytesTotal: number;
  paused: boolean;
  primaryAddress: string;
  type: string;
  startedAt: string;
  establishedAt: string;
}

export interface Connections {
  connections: Record<string, Connection>;
  total: TotalConnectionStats;
}

export interface TotalConnectionStats {
  at: string;
  inBytesTotal: number;
  outBytesTotal: number;
  numConnections: number;
  paused: boolean;
}

export interface FolderStatus {
  errors: number;
  globalBytes: number;
  globalDeleted: number;
  globalDirectories: number;
  globalFiles: number;
  globalSymlinks: number;
  globalTotalItems: number;
  ignorePatterns: boolean;
  inSyncBytes: number;
  inSyncFiles: number;
  invalid: string;
  localBytes: number;
  localDeleted: number;
  localDirectories: number;
  localFiles: number;
  localSymlinks: number;
  localTotalItems: number;
  needBytes: number;
  needDeletes: number;
  needDirectories: number;
  needFiles: number;
  needSymlinks: number;
  needTotalItems: number;
  pullErrors: number;
  receiveOnlyChangedBytes: number;
  receiveOnlyChangedDeletes: number;
  receiveOnlyChangedDirectories: number;
  receiveOnlyChangedFiles: number;
  receiveOnlyChangedSymlinks: number;
  receiveOnlyTotalItems: number;
  sequence: number;
  state: string;
  stateChanged: string;
  version: number;
  watchError: string;
}

export interface CompletionInfo {
  completion: number;
}

export interface Event {
  id: number;
  globalId: number;
  time: string;
  type: EventType;
  data: EventData;
}

export type EventType =
  | 'RemoteIndexUpdated'
  | 'LocalIndexUpdated'
  | 'ItemStarted'
  | 'ItemFinished'
  | 'StateChanged'
  | 'StartupCompleted'
  | 'DeviceConnected'
  | 'DeviceDisconnected'
  | 'DeviceRejected'
  | 'DevicePaused'
  | 'DeviceResumed'
  | 'DownloadProgress'
  | 'FolderSummary'
  | 'FolderCompletion'
  | 'FolderErrors'
  | 'FolderScanProgress'
  | 'FolderPaused'
  | 'FolderResumed'
  | 'ListenAddressesChanged'
  | 'LoginAttempt'
  | 'ConfigSaved'
  | 'PendingDevicesChanged'
  | 'PendingFoldersChanged'
  | 'RemoteDownloadProgress'
  | 'LocalChangeDetected'
  | 'RemoteChangeDetected'
  | 'Failure'
  | 'NewConnRejected';

export type EventData = Object;

export interface DiskEvent {
  id: number;
  time: string;
  type: string;
  data: Record<string, Object>;
}

export interface PendingDevice {
  deviceId: string;
  name: string;
  address: string;
}

export interface PendingFolder {
  deviceId: string;
  folderId: string;
  folderLabel: string;
}

export interface DeviceStat {
  lastConnectionDurationS: number;
  lastSeen: string;
}

export interface FolderCompletion {
  completion: number;
  globalBytes: number;
  needBytes: number;
  needDeletes: number;
  needItems: number;
  remoteState: string;
}

export interface RunCondition {
  runOnMobileData: boolean;
  runOnRoaming: boolean;
  runOnWifi: boolean;
  runOnMeteredWifi: boolean;
  useWifiSsidWhitelist: boolean;
  wifiSsidWhitelist: string;
  powerSource: string;
  respectBatterySaving: boolean;
  respectMasterSync: boolean;
  runInFlightMode: boolean;
  runOnTimeSchedule: boolean;
  syncDurationMinutes: number;
  sleepIntervalMinutes: number;
  alwaysRunInBackground: boolean;
}

export type PreferenceValue = string | number | boolean | null;

export class SharedPreferenceEntry {
  key: string = '';
  value: PreferenceValue = null;
}

export type SharedPreferencesData = Array<SharedPreferenceEntry>;

export type ServiceState = 'stopped' | 'starting' | 'active' | 'error';
