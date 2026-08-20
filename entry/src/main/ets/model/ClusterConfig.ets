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

export interface ClusterPendingDevice {
  time: string;
  name: string;
  address: string;
}

export interface ClusterPendingFolderOffer {
  time: string;
  label: string;
  receiveEncrypted: boolean;
  remoteEncrypted: boolean;
}

export interface ClusterPendingFolder {
  offeredBy: Record<string, ClusterPendingFolderOffer>;
}
