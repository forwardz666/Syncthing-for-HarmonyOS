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
  myId?: string;
  myID?: string;
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
