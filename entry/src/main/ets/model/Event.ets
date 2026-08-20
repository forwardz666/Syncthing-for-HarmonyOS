export interface Event {
  id: number;
  globalId: number;
  time: string;
  type: string;
  data: Record<string, Object>;
}

export interface DiskEvent {
  id: number;
  time: string;
  type: string;
  data: Record<string, Object>;
}

export type EventData = Record<string, Object>;
