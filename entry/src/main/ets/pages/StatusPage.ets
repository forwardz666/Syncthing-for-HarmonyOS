import { pasteboard } from '@kit.BasicServicesKit';
import { Logger } from '../common/Logger';
import { L10n } from '../common/L10n';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { Utils } from '../common/Utils';
import { PreferencesManager } from '../data/PreferencesManager';
import { RestApi } from '../network/RestApi';
import { Constants } from '../service/Constants';
import { BackgroundSyncManager } from '../service/BackgroundSyncManager';
import { SyncthingService } from '../service/SyncthingService';
import { SyncthingNative } from '../native/SyncthingNative';
import {
  ClusterPendingDevice,
  ClusterPendingFolder,
  Connections,
  Device,
  SystemLog,
  SystemLogEntry,
  SystemStatus,
  SystemVersion
} from '../model/Index';
import { EventBus, SyncthingEvents } from '../common/EventBus';

const TAG = 'StatusPage';

class ConnectionRow {
  deviceId: string = '';
  name: string = '';
  connected: boolean = false;
  address: string = '';
  type: string = '';
  clientVersion: string = '';
}

class PendingDeviceRow {
  deviceId: string = '';
  name: string = '';
  address: string = '';
  time: string = '';
}

class PendingFolderRow {
  folderId: string = '';
  deviceId: string = '';
  label: string = '';
  time: string = '';
}

class LogRow {
  when: string = '';
  message: string = '';
}

/**
 * Runtime dashboard for the embedded core, peer connections, pending requests,
 * discovery state, and recent Syncthing log entries.
 */
@Component
export struct StatusPage {
  @State serviceState: string = 'stopped';
  @State forceMode: number = Constants.BTNSTATE_NO_FORCE_START_STOP;
  @State isLoading: boolean = false;
  @State uptime: string = '';
  @State ramUsage: string = '';
  @State deviceId: string = '';
  @State guiAddress: string = '';
  @State coreVersion: string = '';
  @State restApiState: string = 'unknown';
  @State lastError: string = '';
  @State connectedDevices: number = 0;
  @State nativeRunning: boolean = false;
  @State nativeVersion: string = '';
  @State nativeLastError: string = '';
  @State configDeviceCount: number = 0;
  @State configuredDeviceRows: ConnectionRow[] = [];
  @State pendingDeviceRows: PendingDeviceRow[] = [];
  @State pendingFolderRows: PendingFolderRow[] = [];
  @State recentLogRows: LogRow[] = [];
  @State discoveryErrorText: string = '';
  @State lastRefreshText: string = '';
  @State backgroundTaskSupported: boolean = false;
  @State backgroundSyncEnabled: boolean = false;
  @State backgroundSyncTaskText: string = L10n.t('app.string.background_off');

  onWheelSwitch?: (direction: number) => void = undefined;
  private restApi: RestApi | null = null;
  private scrollController: Scroller = new Scroller();
  private preferencesManager: PreferencesManager = PreferencesManager.getInstance();
  private updateTimer: number | null = null;

  aboutToAppear(): void {
    Logger.i(TAG, 'StatusPage appearing');
    const api = ServiceLocator.get<RestApi>(SERVICE_NAMES.REST_API);
    if (api !== undefined) {
      this.restApi = api;
    }
    this.backgroundTaskSupported = canIUse('SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask');
    this.loadForceMode();
    this.refresh();
    this.startTimer();
  }

  aboutToDisappear(): void {
    this.stopTimer();
  }

  build() {
    Scroll(this.scrollController) {
      Column({ space: 12 }) {
        this.forceControl()
        this.serviceCard()
        this.statusGrid()
        this.coreDebugCard()
        this.deviceConnectionCard()
        this.pendingCard()
        this.logCard()
        this.toolsCard()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
    .onAxisEvent((event: AxisEvent) => {
      this.handleWheel(event);
    })
  }

  private handleWheel(event: AxisEvent): void {
    if (!event.hasAxis(AxisType.VERTICAL_AXIS)) {
      return;
    }
    const delta = event.getVerticalAxisValue();
    if (delta === undefined || delta === 0) {
      return;
    }
    if (!this.isScrollAtTop()) {
      return;
    }
    const direction = delta > 0 ? 1 : -1;
    if (this.onWheelSwitch !== undefined) {
      this.onWheelSwitch(direction);
    }
  }

  private isScrollAtTop(): boolean {
    try {
      const offset = this.scrollController.currentOffset();
      return offset === undefined || offset.yOffset === undefined || offset.yOffset <= 1;
    } catch (err) {
      return true;
    }
  }

  @Builder
  forceControl() {
    Column({ space: 8 }) {
      Text(L10n.t('app.string.run_mode'))
        .fontSize(13)
        .fontColor('#666')
        .width('100%')

      Row({ space: 8 }) {
        this.modeButton(L10n.t('app.string.follow'), Constants.BTNSTATE_NO_FORCE_START_STOP)
        this.modeButton(L10n.t('app.string.force_start'), Constants.BTNSTATE_FORCE_START)
        this.modeButton(L10n.t('app.string.force_stop'), Constants.BTNSTATE_FORCE_STOP)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  modeButton(label: string, value: number) {
    Button(label)
      .height(38)
      .layoutWeight(1)
      .backgroundColor(this.forceMode === value ? '#007AFF' : '#FFFFFF')
      .fontColor(this.forceMode === value ? Color.White : '#333')
      .onClick(() => {
        this.setForceMode(value);
      })
  }

  @Builder
  serviceCard() {
    Column({ space: 8 }) {
      Row() {
        Text(this.statusTitle())
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.statusColor())
          .layoutWeight(1)
        if (this.isLoading) {
          LoadingProgress()
            .width(22)
            .height(22)
            .color('#007AFF')
        }
      }
      .width('100%')

      Text(this.statusReason())
        .fontSize(13)
        .fontColor('#666')
        .width('100%')

      if (this.deviceId.length > 0) {
        Row({ space: 8 }) {
          Text(L10n.fmt('app.string.device_id_label', this.deviceId))
            .fontSize(12)
            .fontFamily('monospace')
            .fontColor('#777')
            .maxLines(2)
            .layoutWeight(1)

          Button(L10n.t('app.string.copy'))
            .height(30)
            .fontSize(12)
            .backgroundColor('#E9EEF5')
            .fontColor('#007AFF')
            .onClick(() => {
              this.copyDeviceId();
            })
        }
        .width('100%')
      }

      if (this.guiAddress.length > 0) {
        Text(L10n.fmt('app.string.gui_label', this.guiAddress))
          .fontSize(12)
          .fontColor('#777')
      }

      if (this.lastRefreshText.length > 0) {
        Text(L10n.fmt('app.string.updated_label', this.lastRefreshText))
          .fontSize(12)
          .fontColor('#999')
      }

      if (this.coreVersion.length > 0) {
        Text(L10n.fmt('app.string.core_label', this.coreVersion))
          .fontSize(12)
          .fontColor('#777')
      }

      if (this.lastError.length > 0) {
        Text(this.lastError)
          .fontSize(12)
          .fontColor('#FF3B30')
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  statusGrid() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Column({ space: 6 }) {
          Text(L10n.t('app.string.run_state'))
            .fontSize(12)
            .fontColor('#777')
          Text(this.shortStatus())
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#222')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .height(76)
        .padding(12)
        .borderRadius(8)
        .backgroundColor('#FFFFFF')
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)

        Column({ space: 6 }) {
          Text(L10n.t('app.string.uptime'))
            .fontSize(12)
            .fontColor('#777')
          Text(this.uptime.length > 0 ? this.uptime : '-')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#222')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .height(76)
        .padding(12)
        .borderRadius(8)
        .backgroundColor('#FFFFFF')
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')

      Row({ space: 8 }) {
        Column({ space: 6 }) {
          Text(L10n.t('app.string.memory_usage'))
            .fontSize(12)
            .fontColor('#777')
          Text(this.ramUsage.length > 0 ? this.ramUsage : '-')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#222')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .height(76)
        .padding(12)
        .borderRadius(8)
        .backgroundColor('#FFFFFF')
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)

        Column({ space: 6 }) {
          Text(L10n.t('app.string.syncthing_version'))
            .fontSize(12)
            .fontColor('#777')
          Text(this.coreVersion.length > 0 ? this.coreVersion : '-')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#222')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .height(76)
        .padding(12)
        .borderRadius(8)
        .backgroundColor('#FFFFFF')
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  coreDebugCard() {
    Column({ space: 8 }) {
      Row() {
        Text(L10n.t('app.string.core_debug'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        Button(L10n.t('app.string.refresh'))
          .height(30)
          .fontSize(12)
          .backgroundColor('#E9EEF5')
          .fontColor('#007AFF')
          .onClick(() => {
            this.refresh();
          })
      }
      .width('100%')

      Row() {
        Text(L10n.t('app.string.native_running'))
          .fontSize(12)
          .fontColor('#777')
          .width(110)
        Text(this.nativeRunning ? L10n.t('app.string.yes') : L10n.t('app.string.no'))
          .fontSize(12)
          .fontColor('#222')
          .layoutWeight(1)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      Row() {
        Text(L10n.t('app.string.native_version'))
          .fontSize(12)
          .fontColor('#777')
          .width(110)
        Text(this.nativeVersion.length > 0 ? this.nativeVersion : '-')
          .fontSize(12)
          .fontColor('#222')
          .layoutWeight(1)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      Row() {
        Text(L10n.t('app.string.rest'))
          .fontSize(12)
          .fontColor('#777')
          .width(110)
        Text(this.restApiState)
          .fontSize(12)
          .fontColor('#222')
          .layoutWeight(1)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      Row() {
        Text(L10n.t('app.string.config_devices'))
          .fontSize(12)
          .fontColor('#777')
          .width(110)
        Text(`${this.configDeviceCount}`)
          .fontSize(12)
          .fontColor('#222')
          .layoutWeight(1)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      Row() {
        Text(L10n.t('app.string.gui_address'))
          .fontSize(12)
          .fontColor('#777')
          .width(110)
        Text(this.guiAddress.length > 0 ? this.guiAddress : '-')
          .fontSize(12)
          .fontColor('#222')
          .layoutWeight(1)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      Row() {
        Text(L10n.t('app.string.discovery_errors'))
          .fontSize(12)
          .fontColor('#777')
          .width(110)
        Text(this.discoveryErrorText.length > 0 ? this.discoveryErrorText : '-')
          .fontSize(12)
          .fontColor('#222')
          .layoutWeight(1)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      if (this.nativeLastError.length > 0) {
        Text(this.nativeLastError)
          .fontSize(12)
          .fontColor('#FF3B30')
          .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  deviceConnectionCard() {
    Column({ space: 8 }) {
      Text(L10n.t('app.string.device_connections'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      Text(this.connectedDevices > 0 ? L10n.fmt('app.string.device_connected_count', this.connectedDevices) : L10n.t('app.string.no_active_connections'))
        .fontSize(12)
        .fontColor(this.connectedDevices > 0 ? '#34C759' : '#777')
        .width('100%')

      if (this.configuredDeviceRows.length === 0) {
        Text(L10n.t('app.string.no_remote_devices_configured'))
          .fontSize(12)
          .fontColor('#777')
      } else {
        ForEach(this.configuredDeviceRows, (row: ConnectionRow) => {
          Column({ space: 4 }) {
            Row() {
              Text(row.name.length > 0 ? row.name : row.deviceId.substring(0, 8))
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .layoutWeight(1)
              Text(row.connected ? L10n.t('app.string.connected') : L10n.t('app.string.feature_waiting'))
                .fontSize(11)
                .fontColor(row.connected ? '#34C759' : '#8E8E93')
            }
            .width('100%')
            Text(row.deviceId)
              .fontSize(11)
              .fontFamily('monospace')
              .fontColor('#777')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (row.address.length > 0 || row.clientVersion.length > 0 || row.type.length > 0) {
              Text(this.formatConnectionDetail(row))
                .fontSize(11)
                .fontColor('#777')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .width('100%')
          .padding(10)
          .borderRadius(6)
          .backgroundColor('#F7F8FA')
        }, (row: ConnectionRow) => row.deviceId)
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  pendingCard() {
    Column({ space: 8 }) {
      Text(L10n.t('app.string.pending_pairing'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      if (this.pendingDeviceRows.length === 0 && this.pendingFolderRows.length === 0) {
        Text(L10n.t('app.string.no_pending'))
          .fontSize(12)
          .fontColor('#777')
      }

      ForEach(this.pendingDeviceRows, (row: PendingDeviceRow) => {
        Column({ space: 6 }) {
          Text(row.name.length > 0 ? row.name : row.deviceId.substring(0, 8))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
          Text(row.deviceId)
            .fontSize(11)
            .fontFamily('monospace')
            .fontColor('#777')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(row.address)
            .fontSize(11)
            .fontColor('#777')
          Row({ space: 8 }) {
            Button(L10n.t('app.string.add'))
              .height(30)
              .fontSize(12)
              .backgroundColor('#007AFF')
              .fontColor(Color.White)
              .onClick(() => {
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/DeviceDetailPage',
                  params: { mode: 'create', deviceId: row.deviceId }
                });
              })
            Button(L10n.t('app.string.ignore'))
              .height(30)
              .fontSize(12)
              .backgroundColor('#E9EEF5')
              .fontColor('#666')
              .onClick(() => {
                this.ignorePendingDevice(row.deviceId);
              })
          }
        }
        .width('100%')
        .padding(10)
        .borderRadius(6)
        .backgroundColor('#FFF8E8')
        .alignItems(HorizontalAlign.Start)
      }, (row: PendingDeviceRow) => row.deviceId)

      ForEach(this.pendingFolderRows, (row: PendingFolderRow) => {
        Column({ space: 6 }) {
          Text(row.label.length > 0 ? row.label : row.folderId)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
          Text(L10n.fmt('app.string.pending_folder_offer', row.folderId, row.deviceId.substring(0, 8)))
            .fontSize(11)
            .fontColor('#777')
          Row({ space: 8 }) {
            Button(L10n.t('app.string.add'))
              .height(30)
              .fontSize(12)
              .backgroundColor('#007AFF')
              .fontColor(Color.White)
              .onClick(() => {
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/FolderDetailPage',
                  params: {
                    mode: 'create',
                    folderId: row.folderId,
                    label: row.label,
                    deviceId: row.deviceId
                  }
                });
              })
            Button(L10n.t('app.string.ignore'))
              .height(30)
              .fontSize(12)
              .backgroundColor('#E9EEF5')
              .fontColor('#666')
              .onClick(() => {
                this.ignorePendingFolder(row.folderId, row.deviceId);
              })
          }
        }
          .width('100%')
          .padding(10)
          .borderRadius(6)
          .backgroundColor('#F7F8FA')
      }, (row: PendingFolderRow) => `${row.folderId}-${row.deviceId}`)
    }
    .width('100%')
    .padding(16)
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  logCard() {
    Column({ space: 8 }) {
      Text(L10n.t('app.string.recent_core_log'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      if (this.recentLogRows.length === 0) {
        Text(L10n.t('app.string.no_log_entries'))
          .fontSize(12)
          .fontColor('#777')
      } else {
        ForEach(this.recentLogRows, (row: LogRow) => {
          Column({ space: 3 }) {
            Text(row.when)
              .fontSize(10)
              .fontColor('#999')
            Text(row.message)
              .fontSize(11)
              .fontColor('#333')
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .padding(8)
          .borderRadius(6)
          .backgroundColor('#F7F8FA')
          .alignItems(HorizontalAlign.Start)
        }, (row: LogRow) => `${row.when}-${row.message}`)
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  toolsCard() {
    Column({ space: 8 }) {
      Text(L10n.t('app.string.tools'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      Row({ space: 8 }) {
        this.toolButton(L10n.t('app.string.logs'), 'pages/LogPage')
        this.toolButton(L10n.t('app.string.recent_changes'), 'pages/RecentChangesPage')
      }
      .width('100%')

      Row({ space: 8 }) {
        this.toolButton(L10n.t('app.string.web_gui'), 'pages/WebGuiPage')
        this.toolButton(L10n.t('app.string.settings'), 'pages/SettingsPage')
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  toolButton(label: string, url: string) {
    Button(label)
      .height(38)
      .layoutWeight(1)
      .backgroundColor('#E9EEF5')
      .fontColor('#007AFF')
      .onClick(() => {
        this.getUIContext().getRouter().pushUrl({ url });
      })
  }

  private async refresh(): Promise<void> {
    this.updateServiceState();
    this.updateNativeDebug();
    if (this.restApi === null) {
      const api = ServiceLocator.get<RestApi>(SERVICE_NAMES.REST_API);
      if (api !== undefined) {
        this.restApi = api;
      }
    }
    if (this.restApi === null) {
      this.restApiState = 'missing';
      this.lastError = L10n.t('app.string.rest_missing');
      return;
    }

    this.isLoading = true;
    try {
      const pingResult = await this.restApi.ping();
      if (!pingResult.success) {
        this.restApiState = 'unavailable';
        this.lastError = pingResult.error || L10n.t('app.string.rest_unreachable');
        return;
      }
      this.restApiState = 'available';
      this.lastError = '';

      const versionResult = await this.restApi.getVersion();
      if (versionResult.success && versionResult.data !== undefined) {
        this.applyVersion(versionResult.data);
      }

      const statusResult = await this.restApi.getSystemStatus();
      if (statusResult.success && statusResult.data !== undefined) {
        this.applyStatus(statusResult.data);
      } else if (!statusResult.success) {
        this.lastError = statusResult.error || L10n.t('app.string.status_requires_key');
      }

      await this.refreshConfigDebug();

      const connectionsResult = await this.restApi.getConnections();
      if (connectionsResult.success && connectionsResult.data !== undefined) {
        this.applyConnections(connectionsResult.data);
      }

      await this.refreshPending();
      await this.refreshCoreLog();
      await this.refreshBackgroundSyncState();
      this.lastRefreshText = new Date().toLocaleTimeString();
    } catch (err) {
      Logger.d(TAG, `Status refresh failed: ${JSON.stringify(err)}`);
    } finally {
      this.isLoading = false;
    }
  }

  private applyStatus(status: SystemStatus): void {
    this.uptime = Utils.formatUptime(status.uptime === undefined ? 0 : status.uptime);
    this.ramUsage = Utils.formatBytes(status.alloc === undefined ? 0 : status.alloc);
    this.deviceId = this.getSystemDeviceId(status);
    this.guiAddress = status.guiAddressUsed === undefined ? '' : status.guiAddressUsed;
    this.discoveryErrorText = this.formatDiscoveryErrors(status);
    if (this.coreVersion.length === 0) {
      this.coreVersion = this.isRealCoreVersion(status.version)
        ? status.version
        : Constants.SYNCTHING_CORE_FALLBACK_VERSION;
    }
  }

  private isRealCoreVersion(value: string): boolean {
    return value !== undefined && value.length > 0 && value !== 'unknown-dev' && value.indexOf('unknown-dev') < 0;
  }

  private applyVersion(version: SystemVersion): void {
    if (this.isRealCoreVersion(version.version)) {
      const platform = version.os !== undefined && version.arch !== undefined && version.os.length > 0 && version.arch.length > 0
        ? ` (${version.os}-${version.arch})`
        : '';
      this.coreVersion = `${version.version}${platform}`;
    } else if (this.isRealCoreVersion(version.longVersion)) {
      this.coreVersion = version.longVersion;
    } else {
      this.coreVersion = Constants.SYNCTHING_CORE_FALLBACK_VERSION;
    }
  }

  private applyConnections(connections: Connections): void {
    const keys = Object.keys(connections.connections);
    let connected = 0;
    for (let i = 0; i < keys.length; i++) {
      const connection = connections.connections[keys[i]];
      if (connection.connected) {
        connected++;
      }
    }
    this.connectedDevices = connected;
    this.updateConnectionRows(connections);
  }

  private updateNativeDebug(): void {
    try {
      this.nativeRunning = SyncthingNative.isRunning();
      this.nativeVersion = SyncthingNative.getVersion();
      this.nativeLastError = SyncthingNative.getLastError();
    } catch (err) {
      this.nativeRunning = false;
      this.nativeLastError = L10n.fmt('app.string.native_debug_unavailable', JSON.stringify(err));
    }
  }

  private async refreshConfigDebug(): Promise<void> {
    if (this.restApi === null) {
      return;
    }
    const configResult = await this.restApi.getConfigFull();
    if (!configResult.success || configResult.data === undefined) {
      return;
    }
    this.configDeviceCount = configResult.data.devices.length;
    this.updateConfiguredDeviceRows(configResult.data.devices);
  }

  private updateConfiguredDeviceRows(devices: Device[]): void {
    const existing: ConnectionRow[] = this.configuredDeviceRows;
    const rows: ConnectionRow[] = [];
    for (let i = 0; i < devices.length; i++) {
      const device = devices[i];
      const deviceId = this.getDeviceId(device);
      if (deviceId.length === 0 || deviceId === this.deviceId) {
        continue;
      }
      const row = new ConnectionRow();
      row.deviceId = deviceId;
      row.name = device.name;
      for (let j = 0; j < existing.length; j++) {
        if (existing[j].deviceId === deviceId) {
          row.connected = existing[j].connected;
          row.address = existing[j].address;
          row.type = existing[j].type;
          row.clientVersion = existing[j].clientVersion;
          break;
        }
      }
      rows.push(row);
    }
    this.configuredDeviceRows = rows;
  }

  private updateConnectionRows(connections: Connections): void {
    const currentRows: ConnectionRow[] = [];
    for (let i = 0; i < this.configuredDeviceRows.length; i++) {
      const current = this.configuredDeviceRows[i];
      const row = new ConnectionRow();
      row.deviceId = current.deviceId;
      row.name = current.name;
      row.connected = false;

      const connection = connections.connections[current.deviceId];
      if (connection !== undefined) {
        row.connected = connection.connected;
        row.address = connection.address.length > 0 ? connection.address : connection.primaryAddress;
        row.type = connection.type;
        row.clientVersion = connection.clientVersion;
      }
      currentRows.push(row);
    }
    this.configuredDeviceRows = currentRows;
  }

  private async refreshPending(): Promise<void> {
    if (this.restApi === null) {
      return;
    }

    const deviceResult = await this.restApi.getPendingDevices();
    if (deviceResult.success && deviceResult.data !== undefined) {
      const ids = Object.keys(deviceResult.data);
      const rows: PendingDeviceRow[] = [];
      for (let i = 0; i < ids.length; i++) {
        const id = ids[i];
        const pending: ClusterPendingDevice = deviceResult.data[id];
        const row = new PendingDeviceRow();
        row.deviceId = id;
        row.name = pending.name;
        row.address = pending.address;
        row.time = pending.time;
        rows.push(row);
      }
      this.pendingDeviceRows = rows;
    }

    const folderResult = await this.restApi.getPendingFolders();
    if (folderResult.success && folderResult.data !== undefined) {
      this.pendingFolderRows = this.flattenPendingFolders(folderResult.data);
    }
  }

  private flattenPendingFolders(folders: Record<string, ClusterPendingFolder>): PendingFolderRow[] {
    const rows: PendingFolderRow[] = [];
    const folderIds = Object.keys(folders);
    for (let i = 0; i < folderIds.length; i++) {
      const folderId = folderIds[i];
      const folder = folders[folderId];
      const deviceIds = Object.keys(folder.offeredBy);
      for (let j = 0; j < deviceIds.length; j++) {
        const deviceId = deviceIds[j];
        const offer = folder.offeredBy[deviceId];
        const row = new PendingFolderRow();
        row.folderId = folderId;
        row.deviceId = deviceId;
        row.label = offer.label;
        row.time = offer.time;
        rows.push(row);
      }
    }
    return rows;
  }

  private async refreshCoreLog(): Promise<void> {
    if (this.restApi === null) {
      return;
    }
    const logResult = await this.restApi.getSystemLog();
    if (logResult.success && logResult.data !== undefined) {
      this.recentLogRows = this.toRecentLogRows(logResult.data);
    }
  }

  private toRecentLogRows(systemLog: SystemLog): LogRow[] {
    const rows: LogRow[] = [];
    const messages: SystemLogEntry[] = systemLog.messages;
    const start = messages.length > 8 ? messages.length - 8 : 0;
    for (let i = start; i < messages.length; i++) {
      const entry = messages[i];
      const row = new LogRow();
      row.when = entry.when;
      row.message = entry.message;
      rows.push(row);
    }
    return rows;
  }

  private async ignorePendingDevice(deviceId: string): Promise<void> {
    if (this.restApi === null) {
      return;
    }
    const result = await this.restApi.deletePendingDevice(deviceId);
    if (result.success) {
      this.showToast(L10n.t('app.string.pending_device_ignored'));
      await this.refreshPending();
    } else {
      this.showToast(result.error || L10n.t('app.string.ignore_failed'));
    }
  }

  private async ignorePendingFolder(folderId: string, deviceId: string): Promise<void> {
    if (this.restApi === null) {
      return;
    }
    const result = await this.restApi.deletePendingFolder(folderId, deviceId);
    if (result.success) {
      this.showToast(L10n.t('app.string.pending_folder_ignored'));
      await this.refreshPending();
    } else {
      this.showToast(result.error || L10n.t('app.string.ignore_failed'));
    }
  }

  private formatDiscoveryErrors(status: SystemStatus): string {
    const keys = Object.keys(status.discoveryErrors);
    if (keys.length === 0) {
      return '';
    }
    const parts: string[] = [];
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      parts.push(`${key}: ${status.discoveryErrors[key]}`);
    }
    return parts.join('; ');
  }

  private getDeviceId(device: Device): string {
    if (device.deviceID !== undefined && device.deviceID.length > 0) {
      return device.deviceID;
    }
    if (device.deviceId !== undefined && device.deviceId.length > 0) {
      return device.deviceId;
    }
    return '';
  }

  private getSystemDeviceId(status: SystemStatus): string {
    if (status.myID !== undefined && status.myID.length > 0) {
      return status.myID;
    }
    if (status.myId !== undefined && status.myId.length > 0) {
      return status.myId;
    }
    return '';
  }

  private formatConnectionDetail(row: ConnectionRow): string {
    const parts: string[] = [];
    if (row.address.length > 0) {
      parts.push(row.address);
    }
    if (row.type.length > 0) {
      parts.push(row.type);
    }
    if (row.clientVersion.length > 0) {
      parts.push(row.clientVersion);
    }
    return parts.join(' ');
  }

  private updateServiceState(): void {
    const service = ServiceLocator.get<SyncthingService>(SERVICE_NAMES.SYNCTHING_SERVICE);
    if (service !== undefined) {
      this.serviceState = service.getState();
    }
  }

  private async loadForceMode(): Promise<void> {
    this.forceMode = await this.preferencesManager.getNumber(
      Constants.PREF_BTNSTATE_FORCE_START_STOP,
      Constants.BTNSTATE_NO_FORCE_START_STOP
    );
  }

  private async refreshBackgroundSyncState(): Promise<void> {
    this.backgroundSyncEnabled = await this.preferencesManager.getBoolean(Constants.PREF_START_SERVICE_ON_BOOT, false);
    const manager = ServiceLocator.get<BackgroundSyncManager>(SERVICE_NAMES.BACKGROUND_SYNC_MANAGER);
    if (!this.backgroundSyncEnabled) {
      this.backgroundSyncTaskText = L10n.t('app.string.background_off');
      return;
    }
    if (manager !== undefined && manager.isEnabled()) {
      const taskId = manager.getContinuousTaskId();
      this.backgroundSyncTaskText = taskId > 0 ? L10n.fmt('app.string.background_running', taskId) : L10n.t('app.string.background_running_plain');
      return;
    }
    this.backgroundSyncTaskText = L10n.t('app.string.background_waiting_task');
  }

  private async setForceMode(mode: number): Promise<void> {
    this.forceMode = mode;
    await this.preferencesManager.putNumber(Constants.PREF_BTNSTATE_FORCE_START_STOP, mode);
    const service = ServiceLocator.get<SyncthingService>(SERVICE_NAMES.SYNCTHING_SERVICE);
    if (service !== undefined) {
      await service.enforceRunConditionsNow();
    }
  }

  private shortStatus(): string {
    if (this.serviceState === 'active') {
      return L10n.t('app.string.run_state_running');
    }
    if (this.serviceState === 'starting') {
      return L10n.t('app.string.run_state_starting');
    }
    if (this.serviceState === 'error') {
      return L10n.t('app.string.run_state_error');
    }
    return L10n.t('app.string.run_state_stopped');
  }

  private statusTitle(): string {
    if (this.serviceState === 'active') {
      return L10n.t('app.string.status_running');
    }
    if (this.restApiState === 'available') {
      return L10n.t('app.string.status_rest_available');
    }
    if (this.serviceState === 'starting') {
      return L10n.t('app.string.status_starting');
    }
    if (this.serviceState === 'error') {
      return L10n.t('app.string.status_crashed');
    }
    return L10n.t('app.string.status_not_running');
  }

  private statusReason(): string {
    if (this.forceMode === Constants.BTNSTATE_FORCE_START) {
      return L10n.t('app.string.reason_forced_start');
    }
    if (this.forceMode === Constants.BTNSTATE_FORCE_STOP) {
      return L10n.t('app.string.reason_forced_stop');
    }
    if (this.restApiState === 'available') {
      return L10n.t('app.string.reason_rest_live');
    }
    if (this.restApiState === 'unavailable') {
      return L10n.t('app.string.reason_waiting_rest');
    }
    return L10n.t('app.string.reason_following_conditions');
  }

  private statusColor(): string {
    if (this.serviceState === 'active') {
      return '#34C759';
    }
    if (this.restApiState === 'available') {
      return '#34C759';
    }
    if (this.serviceState === 'starting') {
      return '#007AFF';
    }
    if (this.serviceState === 'error') {
      return '#FF3B30';
    }
    return '#8E8E93';
  }

  private startTimer(): void {
    this.stopTimer();
    this.updateTimer = setInterval(() => {
      this.refresh();
    }, Constants.REST_UPDATE_INTERVAL_MS);
  }

  private stopTimer(): void {
    if (this.updateTimer !== null) {
      clearInterval(this.updateTimer);
      this.updateTimer = null;
    }
  }

  private async copyDeviceId(): Promise<void> {
    if (this.deviceId.length === 0) {
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.deviceId);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(data);
      this.showToast(L10n.t('app.string.device_id_copied'));
    } catch (err) {
      Logger.e(TAG, `Failed to copy device ID: ${JSON.stringify(err)}`);
      this.showToast(L10n.t('app.string.copy_failed'));
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (err) {
      Logger.w(TAG, `Failed to show toast: ${JSON.stringify(err)}`);
    }
  }
}
