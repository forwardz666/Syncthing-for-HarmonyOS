export interface FolderCompletion {
  completion: number;
  globalBytes: number;
  needBytes: number;
  needDeletes: number;
  needItems: number;
  remoteState: string;
}
