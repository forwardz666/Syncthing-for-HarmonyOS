import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { RestApi } from '../network/RestApi';
import { Device, DiscoveredDevice } from '../model/Device';
import { Folder, FolderDevice } from '../model/SyncthingConfig';
import { L10n } from '../common/L10n';
import { AppTextInput } from '../components/AppTextInput';

const TAG = 'DeviceDetailPage';
const SCAN_BARCODE_SYSCAP = 'SystemCapability.Multimedia.Scan.ScanBarcode';

class FolderShareState {
  folderId: string = '';
  label: string = '';
  shared: boolean = false;
  encryptionPassword: string = '';
}

/**
 * Device create/edit screen with Android-compatible config persistence and
 * QR-code pairing support.
 */
@Entry
@Component
struct DeviceDetailPage {
  @State isCreateMode: boolean = true;
  @State isLoading: boolean = true;
  @State isSaving: boolean = false;
  @State showDeleteConfirm: boolean = false;
  @State deviceId: string = '';
  @State name: string = '';
  @State addresses: string = 'dynamic';
  @State compression: string = 'metadata';
  @State introducer: boolean = false;
  @State autoAcceptFolders: boolean = false;
  @State paused: boolean = false;
  @State untrusted: boolean = false;
  @State currentAddress: string = '';
  @State syncthingVersion: string = '';
  @State connectionStatus: string = '';
  @State folderShareStatus: string = '';
  @State scanSupported: boolean = false;
  @State folders: Folder[] = [];
  @State folderShares: FolderShareState[] = [];
  @State discoveredDeviceIds: string[] = [];
  @State discoveredDevices: Record<string, DiscoveredDevice> = {};

  private restApi: RestApi | null = null;

  aboutToAppear(): void {
    Logger.i(TAG, 'DeviceDetailPage appearing');
    this.scanSupported = canIUse(SCAN_BARCODE_SYSCAP);
    this.loadDevice();
  }

  async loadDevice(): Promise<void> {
    this.isLoading = true;
    try {
      const api = ServiceLocator.get<RestApi>(SERVICE_NAMES.REST_API);
      if (api === undefined) {
        this.showToast(L10n.t('app.string.syncthing_not_ready'));
        return;
      }
      this.restApi = api;

      // Guard getParams(): some router/API versions return undefined when no
      // params were passed. Treat undefined/null as an empty object (create mode).
      const rawParams = this.getUIContext().getRouter().getParams();
      const params: Record<string, string> = (rawParams === undefined || rawParams === null) ? {} : (rawParams as Record<string, string>);
      const mode = params['mode'];
      const routeDeviceId = params['deviceId'];
      this.isCreateMode = mode === 'create' || routeDeviceId === undefined || routeDeviceId.length === 0;

      const foldersResult = await api.getFolders();
      if (foldersResult.success && foldersResult.data !== undefined) {
        this.folders = foldersResult.data;
      }

      if (this.isCreateMode) {
        this.applyDevice(this.createDefaultDevice(routeDeviceId));
        await this.loadDiscoveredDevices();
      } else {
        const deviceResult = await api.getDevice(routeDeviceId);
        if (deviceResult.success && deviceResult.data !== undefined) {
          this.applyDevice(deviceResult.data);
        } else {
          const devicesResult = await api.getDevices();
          if (devicesResult.success && devicesResult.data !== undefined) {
            const device = this.findDevice(devicesResult.data, routeDeviceId);
            if (device !== null) {
              this.applyDevice(device);
            } else {
              this.showToast(L10n.t('app.string.device_not_found'));
            }
          }
        }
      }

      this.buildFolderShares();
    } catch (err) {
      const e = err as Error;
      const detail = (e !== undefined && e !== null && e.message !== undefined && e.message.length > 0)
        ? `${e.name}: ${e.message}` : JSON.stringify(err);
      Logger.e(TAG, `Failed to load device: ${detail}`);
      this.showToast(L10n.t('app.string.device_load_failed'));
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    Column() {
      this.header()

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color($r('app.color.primary'))
          Text(L10n.t('app.string.loading_device'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 10 }) {
            if (this.isCreateMode) {
              this.deviceIdField()

              this.discoveredDevicesSection()
            } else {
              this.readOnlyField(L10n.t('app.string.device_id'), this.deviceId)
            }

            this.textField(L10n.t('app.string.device_name'), this.name, L10n.t('app.string.remote_device_name'), (value: string) => {
              this.name = value;
            })

            this.textField(L10n.t('app.string.addresses'), this.addresses, L10n.t('app.string.dynamic'), (value: string) => {
              this.addresses = value;
            })

            this.folderSection()
            if (this.folderShareStatus.length > 0) {
              this.infoSection(this.folderShareStatus)
            }
            this.compressionSection()
            this.switchRow(L10n.t('app.string.introducer'), this.introducer, (value: boolean) => {
              this.introducer = value;
            }, L10n.t('app.string.introducer_desc'))
            this.switchRow(L10n.t('app.string.auto_accept_folders'), this.autoAcceptFolders, (value: boolean) => {
              this.autoAcceptFolders = value;
            }, L10n.t('app.string.auto_accept_folders_desc'))
            this.switchRow(L10n.t('app.string.pause_device'), this.paused, (value: boolean) => {
              this.paused = value;
            }, L10n.t('app.string.pause_device_desc'))
            this.switchRow(L10n.t('app.string.untrusted_device'), this.untrusted, (value: boolean) => {
              this.untrusted = value;
            }, L10n.t('app.string.untrusted_device_desc'))

            if (this.currentAddress.length > 0) {
              this.readOnlyField(L10n.t('app.string.current_address'), this.currentAddress)
            }
            if (this.syncthingVersion.length > 0) {
              this.readOnlyField(L10n.t('app.string.syncthing_version'), this.syncthingVersion)
            }
            if (this.connectionStatus.length > 0) {
              this.connectionStatusSection()
            }

            if (!this.isCreateMode) {
              this.deleteSection()
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 24 })
        }
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  header() {
    Row({ space: 10 }) {
      Button(L10n.t('app.string.back'))
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.button_secondary_background'))
        .fontColor($r('app.color.text_primary'))
        .onClick(() => this.getUIContext().getRouter().back())

      Text(this.isCreateMode ? L10n.t('app.string.add_device') : L10n.t('app.string.edit_device'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)

      Button(this.isSaving ? L10n.t('app.string.saving') : (this.isCreateMode ? L10n.t('app.string.create') : L10n.t('app.string.save')))
        .height(38)
        .enabled(!this.isSaving)
        .backgroundColor($r('app.color.primary'))
        .fontColor(Color.White)
        .onClick(() => {
          this.saveDevice();
        })
    }
    .width('100%')
    .height(58)
    .padding({ left: 12, right: 12 })
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  deviceIdField() {
    Column({ space: 6 }) {
      Text(L10n.t('app.string.device_id'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Row({ space: 8 }) {
        AppTextInput({
          text: this.deviceId,
          placeholder: L10n.t('app.string.enter_remote_device_id'),
          onChange: (value: string) => {
            this.deviceId = value.trim();
          }
        })
          .layoutWeight(1)

        Button() {
          Image($r('app.media.bootstrap_qr_code_scan_512_1'))
            .width(26)
            .height(26)
            .objectFit(ImageFit.Contain)
        }
          .width(64)
          .height(44)
          .enabled(this.scanSupported)
          .backgroundColor(this.scanSupported ? $r('app.color.primary') : $r('app.color.background_disabled'))
          .onClick(() => {
            this.scanDeviceId();
          })
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  textField(label: string, value: string, placeholder: string, onChange: (value: string) => void) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      AppTextInput({
        text: value,
        placeholder: placeholder,
        onChange: onChange
      })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  readOnlyField(label: string, value: string) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Text(value)
        .fontSize(14)
        .fontFamily('monospace')
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding(12)
        .borderRadius(8)
        .backgroundColor($r('app.color.card_background'))
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  switchRow(title: string, value: boolean, onChange: (value: boolean) => void, caption: string = '') {
    Column() {
      Row() {
        Text(title)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: value })
          .onChange(onChange)
      }
      .width('100%')

      if (caption.length > 0) {
        Text(caption)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(8)
    .backgroundColor($r('app.color.card_background'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  compressionSection() {
    Column({ space: 8 }) {
      Text(L10n.t('app.string.compression'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Row({ space: 8 }) {
        this.compressionChip('metadata', L10n.t('app.string.compression_metadata'))
        this.compressionChip('always', L10n.t('app.string.compression_always'))
        this.compressionChip('never', L10n.t('app.string.compression_never'))
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  compressionChip(value: string, label: string) {
    Button(label)
      .height(34)
      .layoutWeight(1)
      .backgroundColor(this.compression === value ? $r('app.color.primary') : $r('app.color.card_background'))
      .fontColor(this.compression === value ? Color.White : $r('app.color.text_primary'))
      .onClick(() => {
        this.compression = value;
      })
  }

  @Builder
  discoveredDevicesSection() {
    if (this.discoveredDeviceIds.length > 0 && this.deviceId.length === 0) {
      Column({ space: 8 }) {
        Text(L10n.t('app.string.discovered_devices'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
        ForEach(this.discoveredDeviceIds, (id: string) => {
          Row() {
            Column({ space: 3 }) {
              Text(id)
                .fontSize(12)
                .fontFamily('monospace')
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.getDiscoveredAddress(id))
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
          }
          .width('100%')
          .padding(12)
          .borderRadius(8)
          .backgroundColor($r('app.color.card_background'))
          .onClick(() => {
            this.deviceId = id;
            const address = this.getDiscoveredAddress(id);
            if (address.length > 0) {
              this.addresses = address;
            }
          })
        }, (id: string) => id)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  folderSection() {
    Column({ space: 8 }) {
      Row() {
        Text(L10n.fmt('app.string.folders_count', this.selectedFolderShareCount(), this.folderShares.length))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        if (this.folderShares.length > 0) {
          Button(L10n.t('app.string.all'))
            .height(28)
            .fontSize(12)
            .backgroundColor($r('app.color.button_secondary_background'))
            .fontColor($r('app.color.primary'))
            .onClick(() => {
              this.setAllFolderShares(true);
            })
          Button(L10n.t('app.string.none'))
            .height(28)
            .fontSize(12)
            .backgroundColor($r('app.color.button_secondary_background'))
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 8 })
            .onClick(() => {
              this.setAllFolderShares(false);
            })
        }
      }
      .width('100%')

      if (this.folderShares.length === 0) {
        Text(L10n.t('app.string.no_folders'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding(14)
          .borderRadius(8)
          .backgroundColor($r('app.color.card_background'))
      } else {
        ForEach(this.folderShares, (share: FolderShareState) => {
          Column({ space: 8 }) {
            Row() {
              Text(share.label.length > 0 ? share.label : share.folderId)
                .fontSize(15)
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: share.shared })
                .onChange((value: boolean) => {
                  this.updateFolderShare(share.folderId, value, share.encryptionPassword);
                })
            }
            .width('100%')

            if (share.shared && this.untrusted) {
              AppTextInput({
                text: share.encryptionPassword,
                placeholder: L10n.t('app.string.encryption_password'),
                inputHeight: 40,
                onChange: (value: string) => {
                  this.updateFolderShare(share.folderId, share.shared, value);
                }
              })
            }
          }
          .width('100%')
          .padding(14)
          .borderRadius(8)
          .backgroundColor($r('app.color.card_background'))
        }, (share: FolderShareState) => share.folderId)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  deleteSection() {
    Column({ space: 8 }) {
      if (this.showDeleteConfirm) {
        Text(L10n.t('app.string.delete_device_confirm'))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
        Row({ space: 10 }) {
          Button(L10n.t('app.string.cancel'))
            .layoutWeight(1)
            .backgroundColor($r('app.color.button_secondary_background'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => {
              this.showDeleteConfirm = false;
            })
          Button(L10n.t('app.string.delete'))
            .layoutWeight(1)
            .backgroundColor($r('app.color.danger'))
            .fontColor(Color.White)
            .onClick(() => {
              this.deleteDevice();
            })
        }
      } else {
        Button(L10n.t('app.string.delete_device'))
          .width('100%')
          .backgroundColor($r('app.color.danger'))
          .fontColor(Color.White)
          .onClick(() => {
            this.showDeleteConfirm = true;
          })
      }
    }
    .width('100%')
    .padding({ top: 8 })
  }

  @Builder
  connectionStatusSection() {
    this.infoSection(this.connectionStatus)
  }

  @Builder
  infoSection(message: string) {
    Text(message)
      .fontSize(13)
      .fontColor(message.indexOf(L10n.t('app.string.folder_sharing_updated')) >= 0 ? $r('app.color.success') : $r('app.color.text_secondary'))
      .width('100%')
      .padding(12)
      .borderRadius(8)
      .backgroundColor($r('app.color.card_background'))
  }

  private async saveDevice(): Promise<void> {
    if (this.restApi === null) {
      this.showToast(L10n.t('app.string.syncthing_not_ready'));
      return;
    }
    if (!this.validateDevice()) {
      return;
    }
    this.deviceId = this.extractDeviceId(this.deviceId);

    this.isSaving = true;
    try {
      const device = this.buildDevicePayload();
      const deviceResult = await this.restApi.upsertDevice(device);
      if (!deviceResult.success) {
        this.showToast(deviceResult.error || L10n.t('app.string.device_save_failed'));
        return;
      }

      const verified = await this.verifyDeviceSaved(this.deviceId);
      if (!verified) {
        this.showToast(L10n.t('app.string.device_save_not_confirmed'));
        return;
      }

      if (this.hasFolderShareChanges()) {
        const foldersSaved = await this.persistFolderShares();
        if (!foldersSaved) {
          this.showToast(L10n.t('app.string.device_share_folders_failed'));
          return;
        }
      }

      const connected = await this.waitForConnection(this.deviceId, 12000);
      if (connected) {
        this.connectionStatus = L10n.t('app.string.connected_to_remote_device');
        this.showToast(this.isCreateMode ? L10n.t('app.string.device_added_connected') : L10n.t('app.string.device_saved_connected'));
      } else {
        this.connectionStatus = L10n.t('app.string.saved_await_remote');
        this.showToast(this.isCreateMode ? L10n.t('app.string.device_added_waiting') : L10n.t('app.string.device_saved_waiting'));
      }
      this.getUIContext().getRouter().back();
    } catch (err) {
      Logger.e(TAG, `Failed to save device: ${JSON.stringify(err)}`);
      this.showToast(L10n.t('app.string.device_save_failed'));
    } finally {
      this.isSaving = false;
    }
  }

  private async deleteDevice(): Promise<void> {
    if (this.restApi === null) {
      return;
    }
    const result = await this.restApi.deleteDevice(this.deviceId);
    if (result.success) {
      this.showToast(L10n.t('app.string.device_deleted'));
      this.getUIContext().getRouter().back();
    } else {
      this.showToast(result.error || L10n.t('app.string.device_delete_failed'));
    }
  }

  private async verifyDeviceSaved(deviceId: string): Promise<boolean> {
    if (this.restApi === null) {
      return false;
    }
    const result = await this.restApi.getDevices();
    if (!result.success || result.data === undefined) {
      Logger.e(TAG, `Device verification failed: ${result.error}`);
      return false;
    }
    for (let i = 0; i < result.data.length; i++) {
      if (this.getDeviceId(result.data[i]) === deviceId) {
        Logger.i(TAG, `Device save verified by Syncthing config: ${deviceId}`);
        return true;
      }
    }
    Logger.e(TAG, `Device not found after save: ${deviceId}`);
    return false;
  }

  private async waitForConnection(deviceId: string, timeoutMs: number): Promise<boolean> {
    if (this.restApi === null) {
      return false;
    }
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      const result = await this.restApi.getConnections();
      if (result.success && result.data !== undefined) {
        const connection = result.data.connections[deviceId];
        if (connection !== undefined && connection.connected) {
          Logger.i(TAG, `Device connected after save: ${deviceId}`);
          return true;
        }
      }
      await new Promise<void>(resolve => setTimeout(resolve, 1000));
    }
    Logger.i(TAG, `Device saved but not connected yet: ${deviceId}`);
    return false;
  }

  private async loadDiscoveredDevices(): Promise<void> {
    if (this.restApi === null) {
      return;
    }
    const result = await this.restApi.getDiscoveredDevices();
    if (result.success && result.data !== undefined) {
      this.discoveredDevices = result.data;
      this.discoveredDeviceIds = Object.keys(result.data);
    }
  }

  private async scanDeviceId(): Promise<void> {
    if (!canIUse('SystemCapability.Multimedia.Scan.ScanBarcode')) {
      this.showToast(L10n.t('app.string.qr_unsupported'));
      return;
    }
    try {
      const context = this.resolveContext();
      if (context === null) {
        this.showToast(L10n.t('app.string.unable_open_scanner'));
        return;
      }

      const result = await scanBarcode.startScanForResult(context, {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableAlbum: true,
        enableMultiMode: false
      });

      const scannedValue = this.normalizeScannedDeviceId(result.originalValue);
      if (scannedValue.length === 0) {
        this.showToast(L10n.t('app.string.no_qr_id'));
        return;
      }
      this.deviceId = scannedValue;
      this.showToast(L10n.t('app.string.device_id_scanned'));
    } catch (err) {
      const businessErr = err as BusinessError;
      if (businessErr.code !== 1000500002) {
        Logger.e(TAG, `QR scan failed: ${JSON.stringify(err)}`);
        this.showToast(L10n.t('app.string.qr_scan_failed'));
      }
    }
  }

  private buildFolderShares(): void {
    const shares: FolderShareState[] = [];
    for (let i = 0; i < this.folders.length; i++) {
      const folder = this.folders[i];
      const share = new FolderShareState();
      share.folderId = folder.id;
      share.label = folder.label;
      for (let j = 0; j < folder.devices.length; j++) {
        const folderDevice = folder.devices[j];
        if (this.getFolderDeviceId(folderDevice) === this.deviceId) {
          share.shared = true;
          share.encryptionPassword = folderDevice.encryptionPassword;
          break;
        }
      }
      shares.push(share);
    }
    this.folderShares = shares;
  }

  private updateFolderShare(folderId: string, shared: boolean, encryptionPassword: string): void {
    const updated: FolderShareState[] = [];
    for (let i = 0; i < this.folderShares.length; i++) {
      const current = this.folderShares[i];
      if (current.folderId === folderId) {
        const next = new FolderShareState();
        next.folderId = current.folderId;
        next.label = current.label;
        next.shared = shared;
        next.encryptionPassword = encryptionPassword;
        updated.push(next);
      } else {
        updated.push(current);
      }
    }
    this.folderShares = updated;
  }

  private setAllFolderShares(shared: boolean): void {
    const updated: FolderShareState[] = [];
    for (let i = 0; i < this.folderShares.length; i++) {
      const current = this.folderShares[i];
      const next = new FolderShareState();
      next.folderId = current.folderId;
      next.label = current.label;
      next.shared = shared;
      next.encryptionPassword = current.encryptionPassword;
      updated.push(next);
    }
    this.folderShares = updated;
  }

  private async persistFolderShares(): Promise<boolean> {
    if (this.restApi === null) {
      return false;
    }

    for (let i = 0; i < this.folders.length; i++) {
      const folder = this.folders[i];
      const share = this.findFolderShare(folder.id);
      if (share === null) {
        continue;
      }

      const devices: FolderDevice[] = [];
      for (let j = 0; j < folder.devices.length; j++) {
        const folderDevice = folder.devices[j];
        if (this.getFolderDeviceId(folderDevice) !== this.deviceId) {
          devices.push(folderDevice);
        }
      }

      if (share.shared) {
        devices.push({
          deviceId: this.deviceId,
          deviceID: this.deviceId,
          introducedBy: '',
          encryptionPassword: share.encryptionPassword
        });
      }

      folder.devices = devices;
      const result = await this.restApi.putFolder(folder.id, folder);
      if (!result.success) {
        Logger.e(TAG, `Failed to update folder share: ${folder.id} ${result.error}`);
        this.folderShareStatus = result.error || L10n.fmt('app.string.folder_update_failed', folder.id);
        return false;
      }
    }

    const verified = await this.verifyFolderShares();
    this.folderShareStatus = verified ? L10n.t('app.string.folder_sharing_updated') : L10n.t('app.string.folder_sharing_not_confirmed');
    return verified;
  }

  private validateDevice(): boolean {
    if (this.deviceId.length === 0) {
      this.showToast(L10n.t('app.string.device_id_required'));
      return false;
    }
    if (!this.isLikelyDeviceId(this.deviceId)) {
      this.showToast(L10n.t('app.string.device_id_invalid'));
      return false;
    }
    if (this.parseAddresses(this.addresses).length === 0) {
      this.showToast(L10n.t('app.string.device_addresses_invalid'));
      return false;
    }
    return true;
  }

  private buildDevicePayload(): Device {
    return {
      deviceId: this.deviceId,
      deviceID: this.deviceId,
      name: this.name,
      addresses: this.parseAddresses(this.addresses),
      compression: this.compression,
      certName: '',
      introducer: this.introducer,
      skipIntroductionRemovals: false,
      introducedBy: '',
      paused: this.paused,
      allowedNetworks: [],
      autoAcceptFolders: this.autoAcceptFolders,
      maxSendKbps: 0,
      maxRecvKbps: 0,
      ignoredFolders: [],
      maxRequestKiB: 0,
      maxRequestKib: 0,
      numConnections: 0,
      untrusted: this.untrusted,
      remoteGUIPort: 0,
      remoteGuiPort: 0
    };
  }

  private createDefaultDevice(deviceId: string | undefined): Device {
    const id = deviceId === undefined ? '' : deviceId;
    return {
      deviceId: id,
      deviceID: id,
      name: '',
      addresses: ['dynamic'],
      compression: 'metadata',
      certName: '',
      introducer: false,
      skipIntroductionRemovals: false,
      introducedBy: '',
      paused: false,
      allowedNetworks: [],
      autoAcceptFolders: false,
      maxSendKbps: 0,
      maxRecvKbps: 0,
      ignoredFolders: [],
      maxRequestKiB: 0,
      maxRequestKib: 0,
      numConnections: 0,
      untrusted: false,
      remoteGUIPort: 0,
      remoteGuiPort: 0
    };
  }

  private applyDevice(device: Device): void {
    this.deviceId = this.getDeviceId(device);
    this.name = device.name;
    this.addresses = this.formatAddresses(device.addresses);
    this.compression = device.compression || 'metadata';
    this.introducer = device.introducer;
    this.autoAcceptFolders = device.autoAcceptFolders;
    this.paused = device.paused;
    this.untrusted = device.untrusted;
  }

  private findDevice(devices: Device[], deviceId: string): Device | null {
    for (let i = 0; i < devices.length; i++) {
      if (this.getDeviceId(devices[i]) === deviceId) {
        return devices[i];
      }
    }
    return null;
  }

  private findFolderShare(folderId: string): FolderShareState | null {
    for (let i = 0; i < this.folderShares.length; i++) {
      if (this.folderShares[i].folderId === folderId) {
        return this.folderShares[i];
      }
    }
    return null;
  }

  private getDeviceId(device: Device): string {
    if (device.deviceId !== undefined && device.deviceId.length > 0) {
      return device.deviceId;
    }
    if (device.deviceID !== undefined) {
      return device.deviceID;
    }
    return '';
  }

  private getFolderDeviceId(device: FolderDevice): string {
    if (device.deviceId !== undefined && device.deviceId.length > 0) {
      return device.deviceId;
    }
    if (device.deviceID !== undefined) {
      return device.deviceID;
    }
    return '';
  }

  private formatAddresses(addresses: string[]): string {
    if (addresses.length === 0) {
      return 'dynamic';
    }
    return addresses.join(', ');
  }

  private parseAddresses(value: string): string[] {
    const normalized = value.replace(/[,;]+/g, ' ').replace(/\s+/g, ' ').trim();
    if (normalized.length === 0) {
      return ['dynamic'];
    }
    return normalized.split(' ');
  }

  private isLikelyDeviceId(value: string): boolean {
    return this.extractDeviceId(value).length > 0;
  }

  private normalizeScannedDeviceId(value: string): string {
    return this.extractDeviceId(value);
  }

  private extractDeviceId(value: string): string {
    const normalized = value.trim().toUpperCase();
    const groupedMatch = normalized.match(/[A-Z2-7]{7}(-[A-Z2-7]{7}){7}/);
    if (groupedMatch !== null && groupedMatch.length > 0) {
      return groupedMatch[0];
    }

    const compact = normalized.replace(/[^A-Z2-7]/g, '');
    if (compact.length === 56) {
      const groups: string[] = [];
      for (let i = 0; i < compact.length; i += 7) {
        groups.push(compact.substring(i, i + 7));
      }
      return groups.join('-');
    }
    return '';
  }

  private hasFolderShareChanges(): boolean {
    for (let i = 0; i < this.folderShares.length; i++) {
      const share = this.folderShares[i];
      const folder = this.findFolderById(share.folderId);
      if (folder === null) {
        continue;
      }
      const currentlyShared = this.isFolderSharedWithDevice(folder, this.deviceId);
      if (share.shared !== currentlyShared) {
        return true;
      }
      if (share.shared && this.untrusted && this.getFolderEncryptionPassword(folder, this.deviceId) !== share.encryptionPassword) {
        return true;
      }
    }
    return false;
  }

  private async verifyFolderShares(): Promise<boolean> {
    if (this.restApi === null) {
      return false;
    }
    const result = await this.restApi.getFolders();
    if (!result.success || result.data === undefined) {
      Logger.e(TAG, `Folder share verification failed: ${result.error}`);
      return false;
    }

    this.folders = result.data;
    for (let i = 0; i < this.folderShares.length; i++) {
      const share = this.folderShares[i];
      const folder = this.findFolderById(share.folderId);
      if (folder === null) {
        continue;
      }
      const shared = this.isFolderSharedWithDevice(folder, this.deviceId);
      if (shared !== share.shared) {
        Logger.e(TAG, `Folder share mismatch folder=${share.folderId} expected=${share.shared} actual=${shared}`);
        return false;
      }
    }
    return true;
  }

  private selectedFolderShareCount(): number {
    let count = 0;
    for (let i = 0; i < this.folderShares.length; i++) {
      if (this.folderShares[i].shared) {
        count++;
      }
    }
    return count;
  }

  private findFolderById(folderId: string): Folder | null {
    for (let i = 0; i < this.folders.length; i++) {
      if (this.folders[i].id === folderId) {
        return this.folders[i];
      }
    }
    return null;
  }

  private isFolderSharedWithDevice(folder: Folder, deviceId: string): boolean {
    for (let i = 0; i < folder.devices.length; i++) {
      if (this.getFolderDeviceId(folder.devices[i]) === deviceId) {
        return true;
      }
    }
    return false;
  }

  private getFolderEncryptionPassword(folder: Folder, deviceId: string): string {
    for (let i = 0; i < folder.devices.length; i++) {
      const folderDevice = folder.devices[i];
      if (this.getFolderDeviceId(folderDevice) === deviceId) {
        return folderDevice.encryptionPassword;
      }
    }
    return '';
  }

  private resolveContext(): common.Context | null {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext !== undefined) {
      return hostContext as common.Context;
    }

    const registeredContext = ServiceLocator.get<common.Context>(SERVICE_NAMES.UI_ABILITY_CONTEXT);
    if (registeredContext !== undefined) {
      return registeredContext;
    }
    return null;
  }

  private getDiscoveredAddress(deviceId: string): string {
    const discovered = this.discoveredDevices[deviceId];
    if (discovered === undefined || discovered.addresses === undefined || discovered.addresses.length === 0) {
      return '';
    }
    return discovered.addresses.join(', ');
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (err) {
      Logger.w(TAG, `Failed to show toast: ${JSON.stringify(err)}`);
    }
  }
}
