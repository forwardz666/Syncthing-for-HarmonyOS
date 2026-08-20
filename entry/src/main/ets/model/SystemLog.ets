export interface SystemLog {
  messages: SystemLogEntry[];
}

export interface SystemLogEntry {
  when: string;
  level?: string;
  message: string;
}
