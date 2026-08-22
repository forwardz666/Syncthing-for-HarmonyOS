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
  isLocal?: boolean;
  primary?: PrimaryConnection;
}

export interface PrimaryConnection {
  address: string;
  at: string;
  crypto: string;
  inBytesTotal: number;
  isLocal: boolean;
  outBytesTotal: number;
  startedAt: string;
  type: string;
}

export interface Connections {
  connections: Record<string, Connection>;
  total: TotalConnectionStats;
}

export interface TotalConnectionStats {
  at: string;
  inBytesTotal: number;
  outBytesTotal: number;
  numConnections?: number;
  paused?: boolean;
}
