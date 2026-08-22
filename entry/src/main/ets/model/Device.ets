export interface Device {
  deviceID?: string;
  deviceId: string;
  name: string;
  addresses: string[];
  compression: string;
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
  maxRequestKiB?: number;
  maxRequestKib: number;
  numConnections: number;
  untrusted: boolean;
  remoteGUIPort?: number;
  remoteGuiPort: number;
}

export interface IgnoredFolder {
  id: string;
  label: string;
  time: string;
}

export interface SharedWithDevice {
  folders: SharedFolder[];
  deviceId: string;
  deviceName: string;
}

export interface SharedFolder {
  id: string;
  label: string;
  sharedWith: SharedWithDevice[];
}

export interface PendingDevice {
  deviceID?: string;
  deviceId: string;
  name: string;
  address: string;
}

export interface RemoteIgnoredDevice {
  deviceID?: string;
  deviceId: string;
  name: string;
  address: string;
  time: string;
}

export interface DiscoveredDevice {
  addresses: string[];
  relays: string[];
}
