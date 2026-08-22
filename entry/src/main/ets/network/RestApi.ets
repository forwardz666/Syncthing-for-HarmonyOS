import { ApiRequest, ApiResponse } from './ApiRequest';
import { Logger } from '../common/Logger';
import { PreferencesManager } from '../data/PreferencesManager';
import { Constants } from '../service/Constants';
import {
  SyncthingConfig, Folder, Device, Options, GuiConfig,
  SystemStatus, Connections, Event, DiskEvent, FolderStatus, CompletionInfo,
  PendingDevice, PendingFolder, DeviceStat, FolderCompletion, DiscoveredDevice,
  SystemVersion, SystemLog, ClusterPendingDevice, ClusterPendingFolder
} from '../model/Index';

const TAG = 'RestApi';

interface EventsEnvelope {
  value?: Event[];
  events?: Event[];
}

/**
 * Typed facade over Syncthing's local REST API exposed by the embedded core.
 *
 * The app talks to Syncthing through 127.0.0.1:8384 after the NAPI bridge starts
 * the Go runtime. This class owns model normalization for v1/v2 payload
 * differences and keeps lightweight caches for UI rendering.
 */
export class RestApi {
  private apiKey: string = '';
  private preferencesManager: PreferencesManager = PreferencesManager.getInstance();
  private config: SyncthingConfig | null = null;
  private systemStatus: SystemStatus | null = null;
  private connections: Connections | null = null;
  private folderStatusCache: Map<string, FolderStatus> = new Map();
  private pendingDevices: PendingDevice[] = [];
  private pendingFolders: PendingFolder[] = [];
  private debugFacilitiesAvailable: string[] = [];
  private isAvailable: boolean = false;

  async initialize(): Promise<void> {
    Logger.i(TAG, 'RestApi initializing');
    ApiRequest.setBaseUrl(Constants.SYNCTHING_BASE_URL);
    this.apiKey = await this.preferencesManager.getString(Constants.PREF_WEBUI_API_KEY, '');
    const version = await this.getVersion();
    this.isAvailable = version.success;
  }

  setApiKey(apiKey: string): void {
    this.apiKey = apiKey;
  }

  setIsAvailable(available: boolean): void {
    this.isAvailable = available;
  }

  getIsAvailable(): boolean {
    return this.isAvailable;
  }

  async updateConfig(config: SyncthingConfig): Promise<void> {
    this.config = config;
  }

  getConfig(): SyncthingConfig | null {
    return this.config;
  }

  async ping(): Promise<ApiResponse<Object>> {
    return ApiRequest.get<Object>('/rest/noauth/health');
  }

  async getConfigFull(): Promise<ApiResponse<SyncthingConfig>> {
    const result = await ApiRequest.get<SyncthingConfig>('/rest/config', this.apiKey);
    if (result.success && result.data !== undefined) {
      this.config = result.data;
    }
    return result;
  }

  async putConfigFull(config: SyncthingConfig): Promise<ApiResponse<Object>> {
    const result = await ApiRequest.put<Object>('/rest/config', config, this.apiKey);
    if (result.success) {
      this.config = config;
    }
    return result;
  }

  async getFolders(): Promise<ApiResponse<Folder[]>> {
    return ApiRequest.get<Folder[]>('/rest/config/folders', this.apiKey);
  }

  async getDevices(): Promise<ApiResponse<Device[]>> {
    return ApiRequest.get<Device[]>('/rest/config/devices', this.apiKey);
  }

  async getSystemStatus(): Promise<ApiResponse<SystemStatus>> {
    const result = await ApiRequest.get<SystemStatus>('/rest/system/status', this.apiKey);
    if (result.success && result.data !== undefined) {
      this.systemStatus = result.data;
    }
    return result;
  }

  async getVersion(): Promise<ApiResponse<SystemVersion>> {
    return ApiRequest.get<SystemVersion>('/rest/system/version', this.apiKey);
  }

  async shutdown(): Promise<ApiResponse<Object>> {
    return ApiRequest.post<Object>('/rest/system/shutdown', '', this.apiKey, 5000);
  }

  async getConnections(): Promise<ApiResponse<Connections>> {
    const result = await ApiRequest.get<Connections>('/rest/system/connections', this.apiKey);
    if (result.success && result.data !== undefined) {
      this.connections = result.data;
    }
    return result;
  }

  async getFolderStatus(folderId: string): Promise<ApiResponse<FolderStatus>> {
    return ApiRequest.get<FolderStatus>(`/rest/db/status?folder=${encodeURIComponent(folderId)}`, this.apiKey);
  }

  async getEvents(since?: number, limit?: number, timeout?: number): Promise<ApiResponse<Event[]>> {
    let url = '/rest/events';
    const params: string[] = [];
    if (since !== undefined) {
      params.push(`since=${since}`);
    }
    if (limit !== undefined) {
      params.push(`limit=${limit}`);
    }
    if (timeout !== undefined) {
      params.push(`timeout=${timeout}`);
    }
    if (params.length > 0) {
      url += '?' + params.join('&');
    }
    const timeoutMs = timeout !== undefined ? (timeout + 5) * 1000 : undefined;
    const result = await ApiRequest.get<EventsEnvelope | Event[]>(url, this.apiKey, timeoutMs);
    if (!result.success || result.data === undefined) {
      return {
        success: false,
        error: result.error,
        statusCode: result.statusCode
      };
    }
    if (Array.isArray(result.data)) {
      return {
        success: true,
        data: result.data as Event[],
        statusCode: result.statusCode
      };
    }
    const envelope = result.data as EventsEnvelope;
    if (envelope.value !== undefined) {
      return {
        success: true,
        data: envelope.value,
        statusCode: result.statusCode
      };
    }
    if (envelope.events !== undefined) {
      return {
        success: true,
        data: envelope.events,
        statusCode: result.statusCode
      };
    }
    return {
      success: true,
      data: [],
      statusCode: result.statusCode
    };
  }

  async getConnectedDevices(): Promise<Device[]> {
    if (this.config === null) {
      return [];
    }
    return this.config.devices;
  }

  async getCachedFolderStatus(folderId: string): Promise<FolderStatus | undefined> {
    return this.folderStatusCache.get(folderId);
  }

  async updateDebugFacilitiesCache(): Promise<void> {
    this.debugFacilitiesAvailable = [];
  }

  isInactiveDevice(deviceId: string): boolean {
    return false;
  }

  isFolderSharedToDevice(folder: Folder, deviceId: string): boolean {
    return false;
  }

  async getFolder(folderId: string): Promise<ApiResponse<Folder>> { return ApiRequest.get<Folder>(`/rest/config/folders/${folderId}`, this.apiKey); }
  async getDefaultFolder(): Promise<ApiResponse<Folder>> { return ApiRequest.get<Folder>('/rest/config/defaults/folder', this.apiKey); }
  async putFolder(folderId: string, folder: Folder): Promise<ApiResponse<Object>> { return ApiRequest.put<Object>(`/rest/config/folders/${folderId}`, folder, this.apiKey); }
  async deleteFolder(folderId: string): Promise<ApiResponse<Object>> { return ApiRequest.delete<Object>(`/rest/config/folders/${folderId}`, this.apiKey); }
  async scanFolder(folderId: string): Promise<ApiResponse<Object>> { return ApiRequest.post<Object>(`/rest/db/scan?folder=${encodeURIComponent(folderId)}`, '', this.apiKey); }
  async getDevice(deviceId: string): Promise<ApiResponse<Device>> { return ApiRequest.get<Device>(`/rest/config/devices/${deviceId}`, this.apiKey); }
  async putDevice(deviceId: string, device: Device): Promise<ApiResponse<Object>> { return ApiRequest.put<Object>(`/rest/config/devices/${deviceId}`, device, this.apiKey); }
  async upsertDevice(device: Device): Promise<ApiResponse<Object>> {
    const deviceId = this.getDeviceId(device);
    if (deviceId.length === 0) {
      return { success: false, error: 'Device ID is required', statusCode: 0 };
    }

    const configResult = await this.getConfigFull();
    if (!configResult.success || configResult.data === undefined) {
      return {
        success: false,
        error: configResult.error || 'Failed to read Syncthing config',
        statusCode: configResult.statusCode
      };
    }

    const config = configResult.data;
    const devices: Device[] = [];
    for (let i = 0; i < config.devices.length; i++) {
      const current = config.devices[i];
      if (this.getDeviceId(current) !== deviceId) {
        devices.push(current);
      }
    }
    devices.push(device);
    config.devices = devices;

    return this.putConfigFull(config);
  }
  async deleteDevice(deviceId: string): Promise<ApiResponse<Object>> { return ApiRequest.delete<Object>(`/rest/config/devices/${deviceId}`, this.apiKey); }
  async getDiscoveredDevices(): Promise<ApiResponse<Record<string, DiscoveredDevice>>> { return ApiRequest.get<Record<string, DiscoveredDevice>>('/rest/system/discovery', this.apiKey); }
  async getSystemLog(): Promise<ApiResponse<SystemLog>> { return ApiRequest.get<SystemLog>('/rest/system/log', this.apiKey); }
  async getSystemLogText(): Promise<ApiResponse<string>> { return ApiRequest.get<string>('/rest/system/log.txt', this.apiKey); }
  async getOptions(): Promise<ApiResponse<Options>> { return ApiRequest.get<Options>('/rest/config/options', this.apiKey); }
  async putOptions(options: Options): Promise<ApiResponse<Object>> { return ApiRequest.put<Object>('/rest/config/options', options, this.apiKey); }
  async pauseAll(): Promise<ApiResponse<Object>> { return ApiRequest.post<Object>('/rest/system/pause', '', this.apiKey); }
  async resumeAll(): Promise<ApiResponse<Object>> { return ApiRequest.post<Object>('/rest/system/resume', '', this.apiKey); }
  async getGuiConfig(): Promise<ApiResponse<GuiConfig>> { return ApiRequest.get<GuiConfig>('/rest/config/gui', this.apiKey); }
  async putGuiConfig(guiConfig: GuiConfig): Promise<ApiResponse<Object>> { return ApiRequest.put<Object>('/rest/config/gui', guiConfig, this.apiKey); }
  async getCompletion(deviceId: string, folderId: string): Promise<ApiResponse<CompletionInfo>> { return ApiRequest.get<CompletionInfo>('/rest/db/completion', this.apiKey); }
  async getDiskEvents(since?: number, limit?: number): Promise<ApiResponse<DiskEvent[]>> { return ApiRequest.get<DiskEvent[]>('/rest/events/disk', this.apiKey); }
  async getDeviceStats(): Promise<ApiResponse<Object>> { return ApiRequest.get<Object>('/rest/stats/device', this.apiKey); }
  async getFolderStats(): Promise<ApiResponse<Object>> { return ApiRequest.get<Object>('/rest/stats/folder', this.apiKey); }
  async getPendingDevices(): Promise<ApiResponse<Record<string, ClusterPendingDevice>>> { return ApiRequest.get<Record<string, ClusterPendingDevice>>('/rest/cluster/pending/devices', this.apiKey); }
  async getPendingFolders(): Promise<ApiResponse<Record<string, ClusterPendingFolder>>> { return ApiRequest.get<Record<string, ClusterPendingFolder>>('/rest/cluster/pending/folders', this.apiKey); }
  async deletePendingDevice(deviceId: string): Promise<ApiResponse<Object>> { return ApiRequest.delete<Object>(`/rest/cluster/pending/devices?device=${encodeURIComponent(deviceId)}`, this.apiKey); }
  async deletePendingFolder(folderId: string, deviceId?: string): Promise<ApiResponse<Object>> {
    let path = `/rest/cluster/pending/folders?folder=${encodeURIComponent(folderId)}`;
    if (deviceId !== undefined && deviceId.length > 0) {
      path += `&device=${encodeURIComponent(deviceId)}`;
    }
    return ApiRequest.delete<Object>(path, this.apiKey);
  }
  async getFolderCompletion(folderId: string): Promise<ApiResponse<FolderCompletion>> { return ApiRequest.get<FolderCompletion>('/rest/db/completion', this.apiKey); }

  private getDeviceId(device: Device): string {
    if (device.deviceID !== undefined && device.deviceID.length > 0) {
      return device.deviceID;
    }
    if (device.deviceId.length > 0) {
      return device.deviceId;
    }
    return '';
  }
}
