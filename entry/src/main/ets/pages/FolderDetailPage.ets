import { fileIo } from '@kit.CoreFileKit';
import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { RestApi } from '../network/RestApi';
import { Constants } from '../service/Constants';
import { PublicFolderGrant } from '../service/PublicFolderGrant';
import { Device, Folder, FolderDevice, FolderStatus, Versioning } from '../model/Index';
import { L10n } from '../common/L10n';
import { AppTextInput } from '../components/AppTextInput';

const TAG = 'FolderDetailPage';

class DeviceShareState {
  deviceId: string = '';
  name: string = '';
  shared: boolean = false;
  encryptionPassword: string = '';
}

/**
 * Folder create/edit screen backed by app-sandbox storage.
 */
@Entry
@Component
struct FolderDetailPage {
  @State isCreateMode: boolean = true;
  @State isLoading: boolean = true;
  @State isSaving: boolean = false;
  @State isScanning: boolean = false;
  @State isDeleting: boolean = false;
  @State folderId: string = '';
  @State label: string = '';
  @State labelCustomized: boolean = false;
  @State labelEditorOpen: boolean = false;
  @State path: string = '';
  @State folderType: string = 'sendreceive';
  @State pullOrder: string = 'random';
  @State versioningType: string = 'none';
  @State versionKeep: string = '5';
  @State versionCleanoutDays: string = '0';
  @State versionMaxAgeDays: string = '0';
  @State versionCommand: string = '';
  @State paused: boolean = false;
  @State ignorePerms: boolean = false;
  @State fsWatcherEnabled: boolean = true;
  @State rescanIntervalS: number = 3600;
  @State deviceShares: DeviceShareState[] = [];
  @State statusText: string = '';
  @State folderStateText: string = '';
  @State folderStatsText: string = '';

  private restApi: RestApi | null = null;
  private currentFolder: Folder | null = null;
  private devices: Device[] = [];
  private pendingDeviceId: string = '';
  private localDeviceId: string = '';
  private deleteArmed: boolean = false;

  aboutToAppear(): void {
    Logger.i(TAG, 'FolderDetailPage appearing');
    this.loadFolder();
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
          Text(L10n.t('app.string.loading_folder'))
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
            this.textField(L10n.t('app.string.folder_id'), this.folderId, L10n.t('app.string.folder_id_placeholder'), (value: string) => {
              if (this.isCreateMode) {
                this.folderId = this.normalizeFolderId(value);
                // Label display follows folderId live (see Label block below).
              }
            }, !this.isCreateMode)

            // Label. Until customized it is a read-only Text that always shows
            // the live folderId (guaranteed to follow input). Tapping "自定义"
            // switches to a real input for a custom label. (ArkUI TextInput is
            // not fully re-controlled by state, so we avoid driving its text
            // from folderId changes.)
            Column({ space: 6 }) {
              Row() {
                Text(L10n.t('app.string.label'))
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                  .layoutWeight(1)
                if (!this.labelEditorOpen) {
                  Button(L10n.t('app.string.custom'))
                    .height(28)
                    .fontSize(12)
                    .backgroundColor($r('app.color.button_secondary_background'))
                    .fontColor($r('app.color.primary'))
                    .onClick(() => {
                      this.labelEditorOpen = true;
                      this.labelCustomized = true;
                      // Seed the editor with the current effective label.
                      if (this.label.length === 0) {
                        this.label = this.folderId;
                      }
                    })
                }
              }
              .width('100%')

              if (this.labelEditorOpen && this.labelCustomized) {
                AppTextInput({
                  text: this.label,
                  placeholder: L10n.t('app.string.custom_label'),
                  onChange: (value: string) => {
                    this.label = value;
                  }
                })
              } else {
                // Read-only live display of the current effective label.
                Text(this.isCreateMode ? this.folderId : this.label)
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                  .width('100%')
                  .padding(12)
                  .borderRadius(8)
                  .backgroundColor($r('app.color.card_background'))
                  .textAlign(TextAlign.Start)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            // A2 (2026-08-18): all sync folders live under the unified
            // container <Download>/Syncthing/<folderId>. Path is fixed and
            // read-only; sandbox/picker selection removed.
            this.syncPathSection()

            this.syncScenarioSection()
            this.folderTypeSection()
            this.pullOrderSection()
            this.versioningSection()
            this.deviceShareSection()
            if (!this.isCreateMode) {
              this.statusSection()
              this.actionsSection()
            }

            this.switchRow(L10n.t('app.string.watch_for_changes'), this.fsWatcherEnabled, (value: boolean) => {
              this.fsWatcherEnabled = value;
            })
            this.switchRow(L10n.t('app.string.ignore_permissions'), this.ignorePerms, (value: boolean) => {
              this.ignorePerms = value;
            })
            this.switchRow(L10n.t('app.string.pause_folder'), this.paused, (value: boolean) => {
              this.paused = value;
            })

            if (this.statusText.length > 0) {
              Text(this.statusText)
                .fontSize(13)
                .fontColor(this.statusText === L10n.t('app.string.folder_saved') || this.statusText === L10n.t('app.string.folder_scan_requested') ? $r('app.color.success') : $r('app.color.text_secondary'))
                .width('100%')
                .padding(12)
                .borderRadius(8)
                .backgroundColor($r('app.color.card_background'))
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
  syncScenarioSection() {
    Column({ space: 8 }) {
      Text(L10n.t('app.string.sync_scenario'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Row({ space: 8 }) {
        Button(L10n.t('app.string.pc_to_phone'))
          .height(36)
          .layoutWeight(1)
          .backgroundColor(this.folderType === 'receiveonly' ? $r('app.color.primary') : $r('app.color.card_background'))
          .fontColor(this.folderType === 'receiveonly' ? Color.White : $r('app.color.text_primary'))
          .onClick(() => {
            this.folderType = 'receiveonly';
          })
        Button(L10n.t('app.string.phone_to_pc'))
          .height(36)
          .layoutWeight(1)
          .backgroundColor(this.folderType === 'sendonly' ? $r('app.color.primary') : $r('app.color.card_background'))
          .fontColor(this.folderType === 'sendonly' ? Color.White : $r('app.color.text_primary'))
          .onClick(() => {
            this.folderType = 'sendonly';
          })
      }
      .width('100%')
      Row({ space: 8 }) {
        Button(L10n.t('app.string.two_way'))
          .height(36)
          .layoutWeight(1)
          .backgroundColor(this.folderType === 'sendreceive' ? $r('app.color.primary') : $r('app.color.card_background'))
          .fontColor(this.folderType === 'sendreceive' ? Color.White : $r('app.color.text_primary'))
          .onClick(() => {
            this.folderType = 'sendreceive';
          })
      }
      .width('100%')
      Text(this.getScenarioHint())
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .borderRadius(8)
        .backgroundColor($r('app.color.card_background'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  statusSection() {
    Column({ space: 6 }) {
      Text(L10n.t('app.string.nav_status'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Row() {
        Text(this.folderStateText.length > 0 ? this.folderStateText : L10n.t('app.string.unknown'))
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(this.folderStatsText)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .padding(14)
      .borderRadius(8)
      .backgroundColor($r('app.color.card_background'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  actionsSection() {
    Column({ space: 8 }) {
      Text(L10n.t('app.string.folder_actions'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Row({ space: 8 }) {
        Button(this.isScanning ? L10n.t('app.string.scanning') : L10n.t('app.string.rescan'))
          .height(38)
          .layoutWeight(1)
          .enabled(!this.isSaving && !this.isDeleting && !this.isScanning)
          .backgroundColor($r('app.color.button_secondary_background'))
          .fontColor($r('app.color.primary'))
          .onClick(() => this.scanFolder())
        Button(this.isDeleting ? L10n.t('app.string.deleting') : (this.deleteArmed ? L10n.t('app.string.confirm_delete') : L10n.t('app.string.delete')))
          .height(38)
          .layoutWeight(1)
          .enabled(!this.isSaving && !this.isDeleting && !this.isScanning)
          .backgroundColor(this.deleteArmed ? $r('app.color.danger') : $r('app.color.danger_background'))
          .fontColor(this.deleteArmed ? Color.White : $r('app.color.danger'))
          .onClick(() => this.deleteFolder())
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
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

      Text(this.isCreateMode ? L10n.t('app.string.add_folder') : L10n.t('app.string.edit_folder'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)

      Button(this.isSaving ? L10n.t('app.string.saving') : (this.isCreateMode ? L10n.t('app.string.create') : L10n.t('app.string.save')))
        .height(38)
        .enabled(!this.isSaving)
        .backgroundColor($r('app.color.primary'))
        .fontColor(Color.White)
        .onClick(() => {
          this.saveFolder();
        })
    }
    .width('100%')
    .height(58)
    .padding({ left: 12, right: 12 })
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  textField(label: string, value: string, placeholder: string, onChange: (value: string) => void, readOnly: boolean = false) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      AppTextInput({
        text: value,
        placeholder: placeholder,
        readOnly: readOnly,
        onChange: onChange
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  folderTypeSection() {
    Column({ space: 8 }) {
      Text(L10n.t('app.string.folder_type'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Row({ space: 8 }) {
        this.typeChip('sendreceive', L10n.t('app.string.send_receive'))
        this.typeChip('sendonly', L10n.t('app.string.send_only'))
      }
      .width('100%')
      Row({ space: 8 }) {
        this.typeChip('receiveonly', L10n.t('app.string.receive_only'))
        this.typeChip('receiveencrypted', L10n.t('app.string.encrypted'))
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  typeChip(value: string, label: string) {
    Button(label)
      .height(34)
      .layoutWeight(1)
      .backgroundColor(this.folderType === value ? $r('app.color.primary') : $r('app.color.card_background'))
      .fontColor(this.folderType === value ? Color.White : $r('app.color.text_primary'))
      .onClick(() => {
        this.folderType = value;
      })
  }

  @Builder
  pullOrderSection() {
    Column({ space: 8 }) {
      Text(L10n.t('app.string.pull_order'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Row({ space: 8 }) {
        this.pullOrderChip('random', L10n.t('app.string.random'))
        this.pullOrderChip('alphabetic', L10n.t('app.string.alphabetic'))
      }
      .width('100%')
      Row({ space: 8 }) {
        this.pullOrderChip('smallestFirst', L10n.t('app.string.smallest'))
        this.pullOrderChip('largestFirst', L10n.t('app.string.largest'))
      }
      .width('100%')
      Row({ space: 8 }) {
        this.pullOrderChip('oldestFirst', L10n.t('app.string.oldest'))
        this.pullOrderChip('newestFirst', L10n.t('app.string.newest'))
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  pullOrderChip(value: string, label: string) {
    Button(label)
      .height(34)
      .layoutWeight(1)
      .backgroundColor(this.pullOrder === value ? $r('app.color.primary') : $r('app.color.card_background'))
      .fontColor(this.pullOrder === value ? Color.White : $r('app.color.text_primary'))
      .onClick(() => {
        this.pullOrder = value;
      })
  }

  @Builder
  versioningSection() {
    Column({ space: 8 }) {
      Text(L10n.t('app.string.file_versioning'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Row({ space: 8 }) {
        this.versioningChip('none', L10n.t('app.string.none'))
        this.versioningChip('trashcan', L10n.t('app.string.versioning_trashcan'))
      }
      .width('100%')
      Row({ space: 8 }) {
        this.versioningChip('simple', L10n.t('app.string.versioning_simple'))
        this.versioningChip('staggered', L10n.t('app.string.versioning_staggered'))
      }
      .width('100%')
      Row({ space: 8 }) {
        this.versioningChip('external', L10n.t('app.string.versioning_external'))
      }
      .width('100%')

      if (this.versioningType === 'trashcan' || this.versioningType === 'simple') {
        this.textField(L10n.t('app.string.cleanout_days'), this.versionCleanoutDays, '0', (value: string) => {
          this.versionCleanoutDays = this.normalizeNumber(value);
        })
      }
      if (this.versioningType === 'simple') {
        this.textField(L10n.t('app.string.keep_versions'), this.versionKeep, '5', (value: string) => {
          this.versionKeep = this.normalizeNumber(value);
        })
      }
      if (this.versioningType === 'staggered') {
        this.textField(L10n.t('app.string.max_age_days'), this.versionMaxAgeDays, '0', (value: string) => {
          this.versionMaxAgeDays = this.normalizeNumber(value);
        })
      }
      if (this.versioningType === 'external') {
        this.textField(L10n.t('app.string.version_command'), this.versionCommand, L10n.t('app.string.version_command_placeholder'), (value: string) => {
          this.versionCommand = value.trim();
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  versioningChip(value: string, label: string) {
    Button(label)
      .height(34)
      .layoutWeight(1)
      .backgroundColor(this.versioningType === value ? $r('app.color.primary') : $r('app.color.card_background'))
      .fontColor(this.versioningType === value ? Color.White : $r('app.color.text_primary'))
      .onClick(() => {
        this.versioningType = value;
        this.ensureVersioningDefaults(value);
      })
  }

  @Builder
  deviceShareSection() {
    Column({ space: 8 }) {
      Row() {
        Text(L10n.fmt('app.string.share_with_devices', this.selectedDeviceShareCount(), this.deviceShares.length))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        if (this.deviceShares.length > 0) {
          Button(L10n.t('app.string.all'))
            .height(28)
            .fontSize(12)
            .backgroundColor($r('app.color.button_secondary_background'))
            .fontColor($r('app.color.primary'))
            .onClick(() => this.setAllDeviceShares(true))
          Button(L10n.t('app.string.none'))
            .height(28)
            .fontSize(12)
            .backgroundColor($r('app.color.button_secondary_background'))
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 8 })
            .onClick(() => this.setAllDeviceShares(false))
        }
      }
      .width('100%')

      if (this.deviceShares.length === 0) {
        Text(L10n.t('app.string.no_remote_devices'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding(14)
          .borderRadius(8)
          .backgroundColor($r('app.color.card_background'))
      } else {
        ForEach(this.deviceShares, (share: DeviceShareState) => {
          Column({ space: 8 }) {
            Row() {
              Text(share.name.length > 0 ? share.name : share.deviceId.substring(0, 8))
                .fontSize(15)
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: share.shared })
                .onChange((value: boolean) => {
                  this.updateDeviceShare(share.deviceId, value, share.encryptionPassword);
                })
            }
            .width('100%')
            Text(share.deviceId)
              .fontSize(11)
              .fontFamily('monospace')
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (share.shared && this.folderType === 'receiveencrypted') {
              AppTextInput({
                text: share.encryptionPassword,
                placeholder: L10n.t('app.string.encryption_password'),
                inputHeight: 40,
                onChange: (value: string) => {
                  this.updateDeviceShare(share.deviceId, share.shared, value);
                }
              })
            }
          }
          .width('100%')
          .padding(14)
          .borderRadius(8)
          .backgroundColor($r('app.color.card_background'))
        }, (share: DeviceShareState) => share.deviceId)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  switchRow(title: string, value: boolean, onChange: (value: boolean) => void) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .onChange(onChange)
    }
    .width('100%')
    .padding(14)
    .borderRadius(8)
    .backgroundColor($r('app.color.card_background'))
  }

  private async loadFolder(): Promise<void> {
    this.isLoading = true;
    try {
      const api = ServiceLocator.get<RestApi>(SERVICE_NAMES.REST_API);
      if (api === undefined) {
        this.showToast(L10n.t('app.string.syncthing_not_ready'));
        return;
      }
      this.restApi = api;

      // Guard getParams(): some router/API versions return undefined when no
      // params were passed (e.g. route pushed without params), which used to
      // throw here and surface as "Failed to load folder" on non-tablet
      // devices. Treat undefined/null as an empty object (create mode).
      const rawParams = this.getUIContext().getRouter().getParams();
      const params: Record<string, string> = (rawParams === undefined || rawParams === null) ? {} : (rawParams as Record<string, string>);
      const mode = params['mode'];
      const routeFolderId = params['folderId'];
      this.pendingDeviceId = params['deviceId'] === undefined ? '' : params['deviceId'];
      this.isCreateMode = mode === 'create' || routeFolderId === undefined || routeFolderId.length === 0;

      const devicesResult = await api.getDevices();
      if (devicesResult.success && devicesResult.data !== undefined) {
        this.devices = devicesResult.data;
      }
      const statusResult = await api.getSystemStatus();
      if (statusResult.success && statusResult.data !== undefined) {
        if (statusResult.data.myID !== undefined && statusResult.data.myID.length > 0) {
          this.localDeviceId = statusResult.data.myID;
        } else if (statusResult.data.myId !== undefined && statusResult.data.myId.length > 0) {
          this.localDeviceId = statusResult.data.myId;
        }
      }

      if (this.isCreateMode) {
        const defaultResult = await api.getDefaultFolder();
        if (defaultResult.success && defaultResult.data !== undefined) {
          this.applyFolder(defaultResult.data);
        } else {
          this.applyFolder(this.createFallbackFolder());
        }
        // Core's /rest/config/defaults/folder template has ignorePerms=false,
        // but all app folders live in HarmonyOS public dirs (Download, FUSE)
        // which deny chmod -> syncing would never finish. Force it ON for
        // every new folder; user can still toggle it off per folder.
        this.ignorePerms = true;
        this.folderId = routeFolderId !== undefined && routeFolderId.length > 0 ? this.normalizeFolderId(routeFolderId) : this.suggestFolderId();
        // Label follows the folder ID live until the user edits it.
        this.label = params['label'] !== undefined && params['label'].length > 0 ? params['label'] : this.folderId;
        this.labelCustomized = params['label'] !== undefined && params['label'].length > 0;
        // All sync folders live under <Download>/Syncthing/<folderId>.
        this.path = this.getUnifiedPath(this.folderId);
      } else {
        const folderResult = await api.getFolder(routeFolderId);
        if (folderResult.success && folderResult.data !== undefined) {
          this.applyFolder(folderResult.data);
          await this.loadFolderStatus(routeFolderId);
        } else {
          this.showToast(folderResult.error || L10n.t('app.string.folder_not_found'));
        }
      }
      this.buildDeviceShares();
    } catch (err) {
      const e = err as Error;
      const detail = (e !== undefined && e !== null && e.message !== undefined && e.message.length > 0)
        ? `${e.name}: ${e.message}` : JSON.stringify(err);
      Logger.e(TAG, `Failed to load folder: ${detail}`);
      this.showToast(L10n.t('app.string.folder_load_failed'));
    } finally {
      this.isLoading = false;
    }
  }

  private async loadFolderStatus(folderId: string): Promise<void> {
    if (this.restApi === null || folderId.length === 0) {
      return;
    }
    const statusResult = await this.restApi.getFolderStatus(folderId);
    if (statusResult.success && statusResult.data !== undefined) {
      this.applyFolderStatus(statusResult.data);
    }
  }

  private async saveFolder(): Promise<void> {
    if (this.restApi === null) {
      this.showToast(L10n.t('app.string.syncthing_not_ready'));
      return;
    }
    if (!this.validateFolder()) {
      return;
    }

    this.isSaving = true;
    try {
      const folder = this.buildFolderPayload();
      const prepared = await this.ensureSyncthingFolder(folder.path);
      if (!prepared) {
        this.showToast(L10n.t('app.string.folder_storage_not_ready'));
        return;
      }
      const result = await this.restApi.putFolder(folder.id, folder);
      if (!result.success) {
        this.showToast(result.error || L10n.t('app.string.folder_save_failed'));
        return;
      }

      const verified = await this.verifyFolderSaved(folder.id);
      if (!verified) {
        this.showToast(L10n.t('app.string.folder_save_not_confirmed'));
        return;
      }
      this.statusText = L10n.t('app.string.folder_saved');
      this.showToast(this.isCreateMode ? L10n.t('app.string.folder_created') : L10n.t('app.string.folder_saved'));
      this.notifyFolderListChanged();
      this.getUIContext().getRouter().back();
    } catch (err) {
      Logger.e(TAG, `Failed to save folder: ${JSON.stringify(err)}`);
      this.showToast(L10n.t('app.string.folder_save_failed'));
    } finally {
      this.isSaving = false;
    }
  }

  private async scanFolder(): Promise<void> {
    if (this.restApi === null) {
      this.showToast(L10n.t('app.string.syncthing_not_ready'));
      return;
    }
    this.isScanning = true;
    this.deleteArmed = false;
    try {
      const result = await this.restApi.scanFolder(this.folderId);
      if (!result.success) {
        this.showToast(result.error || L10n.t('app.string.folder_scan_failed'));
        return;
      }
      this.statusText = L10n.t('app.string.folder_scan_requested');
      this.showToast(L10n.t('app.string.folder_scan_requested'));
      await this.loadFolderStatus(this.folderId);
    } catch (err) {
      Logger.e(TAG, `Failed to scan folder: ${JSON.stringify(err)}`);
      this.showToast(L10n.t('app.string.folder_scan_failed'));
    } finally {
      this.isScanning = false;
    }
  }

  private async deleteFolder(): Promise<void> {
    if (!this.deleteArmed) {
      this.deleteArmed = true;
      this.statusText = L10n.t('app.string.tap_delete_confirm');
      return;
    }
    if (this.restApi === null) {
      this.showToast(L10n.t('app.string.syncthing_not_ready'));
      return;
    }
    this.isDeleting = true;
    try {
      const result = await this.restApi.deleteFolder(this.folderId);
      if (!result.success) {
        this.showToast(result.error || L10n.t('app.string.folder_delete_failed'));
        return;
      }
      this.showToast(L10n.t('app.string.folder_deleted'));
      this.notifyFolderListChanged();
      this.getUIContext().getRouter().back();
    } catch (err) {
      Logger.e(TAG, `Failed to delete folder: ${JSON.stringify(err)}`);
      this.showToast(L10n.t('app.string.folder_delete_failed'));
    } finally {
      this.isDeleting = false;
      this.deleteArmed = false;
    }
  }

  private applyFolder(folder: Folder): void {
    this.currentFolder = folder;
    // Defensive: REST config may omit optional fields on some cores/devices.
    // Treat missing strings as '' and missing booleans as their defaults.
    this.folderId = folder.id === undefined ? '' : folder.id;
    this.label = folder.label === undefined ? '' : folder.label;
    this.labelCustomized = folder.label !== undefined && folder.label.length > 0;
    this.path = folder.path === undefined ? '' : folder.path;
    this.folderType = folder.type !== undefined && folder.type.length > 0 ? folder.type : 'sendreceive';
    this.pullOrder = folder.order !== undefined && folder.order.length > 0 ? folder.order : 'random';
    this.applyVersioning(folder.versioning);
    this.paused = folder.paused === true;
    this.ignorePerms = folder.ignorePerms === true;
    this.fsWatcherEnabled = folder.fsWatcherEnabled !== false;
    this.rescanIntervalS = folder.rescanIntervalS !== undefined ? folder.rescanIntervalS : 3600;
  }

  // A2 (2026-08-18): unified sync folder. Path is always
  // <Download>/Syncthing/<folderId>, read-only (no sandbox / picker).
  private getUnifiedPath(id: string): string {
    return PublicFolderGrant.getUnifiedFolderPath(id);
  }

  @Builder
  syncPathSection() {
    Column({ space: 6 }) {
      Text(L10n.t('app.string.sync_path_readonly'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Text(this.isCreateMode ? this.getUnifiedPath(this.folderId) : this.path)
        .fontSize(13)
        .fontColor($r('app.color.primary'))
        .width('100%')
        .padding(12)
        .borderRadius(8)
        .backgroundColor($r('app.color.info_background'))
        .textAlign(TextAlign.Start)
      Text(L10n.t('app.string.sync_path_hint'))
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private getScenarioHint(): string {
    if (this.folderType === 'receiveonly') {
      return L10n.t('app.string.pc_to_phone_hint');
    }
    if (this.folderType === 'sendonly') {
      return L10n.t('app.string.phone_to_pc_hint');
    }
    return L10n.t('app.string.two_way_hint');
  }

  private async ensureSyncthingFolder(path: string): Promise<boolean> {
    if (path.length === 0 || path.indexOf('://') >= 0) {
      return false;
    }
    try {
      if (!this.pathExists(path)) {
        await fileIo.mkdir(path, true);
      }
      const markerPath = `${path}/${Constants.FILENAME_STFOLDER}`;
      if (!this.pathExists(markerPath)) {
        await fileIo.mkdir(markerPath, true);
      }
      return true;
    } catch (err) {
      Logger.e(TAG, `Failed to prepare Syncthing folder path '${path}': ${JSON.stringify(err)}`);
      return false;
    }
  }

  private pathExists(path: string): boolean {
    try {
      return fileIo.accessSync(path);
    } catch (err) {
      return false;
    }
  }

  private applyFolderStatus(status: FolderStatus): void {
    this.folderStateText = status.state !== undefined && status.state.length > 0 ? L10n.folderState(status.state) : L10n.t('app.string.idle');
    if (status.globalBytes === 0) {
      this.folderStatsText = L10n.fmt('app.string.local_items', status.localTotalItems === undefined ? 0 : status.localTotalItems);
      return;
    }
    const completed = status.globalBytes - status.needBytes;
    const percent = Math.round((completed / status.globalBytes) * 100);
    this.folderStatsText = L10n.fmt('app.string.percent_synced', percent);
  }

  private buildDeviceShares(): void {
    const shares: DeviceShareState[] = [];
    for (let i = 0; i < this.devices.length; i++) {
      const device = this.devices[i];
      const id = this.getDeviceId(device);
      if (id.length === 0 || id === this.getLocalDeviceId()) {
        continue;
      }
      const share = new DeviceShareState();
      share.deviceId = id;
      share.name = device.name;
      if (this.currentFolder !== null) {
        const folderDevices = this.currentFolder.devices === undefined ? [] : this.currentFolder.devices;
        for (let j = 0; j < folderDevices.length; j++) {
          const folderDevice = folderDevices[j];
          if (this.getFolderDeviceId(folderDevice) === id) {
            share.shared = true;
            share.encryptionPassword = folderDevice.encryptionPassword;
            break;
          }
        }
      }
      if (this.pendingDeviceId.length > 0 && id === this.pendingDeviceId) {
        share.shared = true;
      }
      shares.push(share);
    }
    this.deviceShares = shares;
  }

  private buildFolderPayload(): Folder {
    let folder = this.currentFolder;
    if (folder === null) {
      folder = this.createFallbackFolder();
    }
    folder.id = this.folderId;
    // Label: if the user customized it, use theirs; otherwise default to the
    // final folder ID (so it always matches what was entered).
    folder.label = this.labelCustomized && this.label.length > 0 ? this.label : folder.id;
    // A2 (2026-08-18): create-mode path is always bound to the unified
    // container (<Download>/Syncthing/<id>), even if the id changed after load.
    folder.path = this.isCreateMode ? this.getUnifiedPath(folder.id) : this.path;
    folder.type = this.folderType;
    folder.order = this.pullOrder;
    folder.versioning = this.buildVersioning();
    folder.paused = this.paused;
    folder.ignorePerms = this.ignorePerms;
    folder.fsWatcherEnabled = this.fsWatcherEnabled;
    folder.rescanIntervalS = this.rescanIntervalS;

    const devices: FolderDevice[] = [];
    const localId = this.getLocalDeviceId();
    if (localId.length > 0) {
      devices.push({
        deviceId: localId,
        deviceID: localId,
        introducedBy: '',
        encryptionPassword: ''
      });
    }
    for (let i = 0; i < this.deviceShares.length; i++) {
      const share = this.deviceShares[i];
      if (share.shared) {
        devices.push({
          deviceId: share.deviceId,
          deviceID: share.deviceId,
          introducedBy: '',
          encryptionPassword: share.encryptionPassword
        });
      }
    }
    folder.devices = devices;
    return folder;
  }

  private applyVersioning(versioning: Versioning): void {
    if (versioning === undefined || versioning === null) {
      this.versioningType = 'none';
      this.versionCleanoutDays = '0';
      this.versionKeep = '5';
      this.versionMaxAgeDays = '0';
      this.versionCommand = '';
      return;
    }
    this.versioningType = versioning.type !== undefined && versioning.type.length > 0 ? versioning.type : 'none';
    this.versionCleanoutDays = this.getVersioningParam(versioning, 'cleanoutDays', '0');
    this.versionKeep = this.getVersioningParam(versioning, 'keep', '5');
    const maxAgeSeconds = this.parsePositiveInt(this.getVersioningParam(versioning, 'maxAge', '0'), 0);
    this.versionMaxAgeDays = Math.floor(maxAgeSeconds / 86400).toString();
    this.versionCommand = this.getVersioningParam(versioning, 'command', '');
  }

  private buildVersioning(): Versioning {
    const params: Record<string, string> = {};
    if (this.versioningType === 'trashcan') {
      params['cleanoutDays'] = this.normalizeNumber(this.versionCleanoutDays);
    } else if (this.versioningType === 'simple') {
      params['keep'] = this.normalizeNumber(this.versionKeep);
      params['cleanoutDays'] = this.normalizeNumber(this.versionCleanoutDays);
    } else if (this.versioningType === 'staggered') {
      const days = this.parsePositiveInt(this.versionMaxAgeDays, 0);
      params['maxAge'] = (days * 86400).toString();
    } else if (this.versioningType === 'external') {
      params['command'] = this.versionCommand;
    }

    return {
      type: this.versioningType === 'none' ? '' : this.versioningType,
      params,
      cleanupIntervalS: this.currentFolder !== null && this.currentFolder.versioning !== undefined && this.currentFolder.versioning.cleanupIntervalS !== undefined
        ? this.currentFolder.versioning.cleanupIntervalS
        : 3600,
      fsPath: this.currentFolder !== null && this.currentFolder.versioning !== undefined ? this.currentFolder.versioning.fsPath : '',
      fsType: this.currentFolder !== null && this.currentFolder.versioning !== undefined ? this.currentFolder.versioning.fsType : 'basic'
    };
  }

  private getVersioningParam(versioning: Versioning, key: string, fallback: string): string {
    if (versioning.params === undefined || versioning.params === null) {
      return fallback;
    }
    const value = versioning.params[key];
    return value === undefined ? fallback : value;
  }

  private normalizeNumber(value: string): string {
    const sanitized = value.trim().replace(/[^0-9]/g, '');
    return sanitized.length === 0 ? '0' : sanitized;
  }

  private parsePositiveInt(value: string, fallback: number): number {
    const parsed = Number.parseInt(value, 10);
    if (Number.isNaN(parsed) || parsed < 0) {
      return fallback;
    }
    return parsed;
  }

  private ensureVersioningDefaults(type: string): void {
    if (type === 'simple' && this.versionKeep.length === 0) {
      this.versionKeep = '5';
    }
    if ((type === 'simple' || type === 'trashcan') && this.versionCleanoutDays.length === 0) {
      this.versionCleanoutDays = '0';
    }
    if (type === 'staggered' && this.versionMaxAgeDays.length === 0) {
      this.versionMaxAgeDays = '0';
    }
  }

  private createFallbackFolder(): Folder {
    const versioning: Versioning = {
      type: '',
      params: {},
      fsPath: '',
      fsType: 'basic'
    };
    return {
      id: '',
      label: '',
      filesystemType: 'basic',
      path: '',
      type: 'sendreceive',
      devices: [],
      rescanIntervalS: 3600,
      fsWatcherEnabled: true,
      fsWatcherDelayS: 10,
      // HarmonyOS public dir (Download, FUSE-backed) denies chmod: syncthing's
      // finish step would fail on every file ("operation not permitted") and the
      // folder could never complete. ignorePerms must be the default here.
      ignorePerms: true,
      autoNormalize: true,
      minDiskFreePct: 1,
      minDiskFree: { value: 1, unit: '%' },
      versioning,
      copiers: 0,
      pullers: 0,
      hashers: 0,
      order: 'random',
      ignoreDelete: false,
      scanProgressIntervalS: 0,
      pullerPauseS: 0,
      maxConflicts: 10,
      maxConcurrentWrites: 16,
      disableSparseFiles: false,
      disableTempIndexes: false,
      pinned: false,
      markerName: '.stfolder',
      copyOwnershipFromParent: false,
      copyRangeMethod: 'standard',
      modTimeWindowS: 0,
      paused: false
    };
  }

  private validateFolder(): boolean {
    if (this.folderId.length === 0) {
      this.showToast(L10n.t('app.string.folder_id_required'));
      return false;
    }
    if (this.path.length === 0) {
      this.showToast(L10n.t('app.string.folder_path_required'));
      return false;
    }
    return true;
  }

  private async verifyFolderSaved(folderId: string): Promise<boolean> {
    if (this.restApi === null) {
      return false;
    }
    const result = await this.restApi.getFolder(folderId);
    if (result.success && result.data !== undefined) {
      Logger.i(TAG, `Folder save verified: ${folderId}`);
      return true;
    }
    Logger.e(TAG, `Folder verification failed: ${result.error}`);
    return false;
  }

  private updateDeviceShare(deviceId: string, shared: boolean, encryptionPassword: string): void {
    const updated: DeviceShareState[] = [];
    for (let i = 0; i < this.deviceShares.length; i++) {
      const current = this.deviceShares[i];
      const next = new DeviceShareState();
      next.deviceId = current.deviceId;
      next.name = current.name;
      next.shared = current.deviceId === deviceId ? shared : current.shared;
      next.encryptionPassword = current.deviceId === deviceId ? encryptionPassword : current.encryptionPassword;
      updated.push(next);
    }
    this.deviceShares = updated;
  }

  private setAllDeviceShares(shared: boolean): void {
    const updated: DeviceShareState[] = [];
    for (let i = 0; i < this.deviceShares.length; i++) {
      const current = this.deviceShares[i];
      const next = new DeviceShareState();
      next.deviceId = current.deviceId;
      next.name = current.name;
      next.shared = shared;
      next.encryptionPassword = current.encryptionPassword;
      updated.push(next);
    }
    this.deviceShares = updated;
  }

  private selectedDeviceShareCount(): number {
    let count = 0;
    for (let i = 0; i < this.deviceShares.length; i++) {
      if (this.deviceShares[i].shared) {
        count++;
      }
    }
    return count;
  }

  private getLocalDeviceId(): string {
    if (this.localDeviceId.length > 0) {
      return this.localDeviceId;
    }
    if (this.currentFolder !== null && this.currentFolder.devices.length > 0) {
      return this.getFolderDeviceId(this.currentFolder.devices[0]);
    }
    return '';
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

  private getFolderDeviceId(device: FolderDevice): string {
    if (device.deviceID !== undefined && device.deviceID.length > 0) {
      return device.deviceID;
    }
    if (device.deviceId !== undefined && device.deviceId.length > 0) {
      return device.deviceId;
    }
    return '';
  }

  private normalizeFolderId(value: string): string {
    return value.trim().toLowerCase().replace(/[^a-z0-9._-]/g, '-');
  }

  private suggestFolderId(): string {
    return `sync-${Date.now().toString(36)}`;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (err) {
      Logger.w(TAG, `Failed to show toast: ${JSON.stringify(err)}`);
    }
  }

  // A2 (2026-08-18): after save/delete, bump an AppStorage counter that
  // FolderListPage watches, so the list refreshes immediately (no restart).
  private notifyFolderListChanged(): void {
    try {
      const current: number = (AppStorage.get<number>('folderListRefreshTick') ?? 0) as number;
      AppStorage.setOrCreate<number>('folderListRefreshTick', current + 1);
    } catch (err) {
      Logger.w(TAG, `notifyFolderListChanged failed: ${JSON.stringify(err)}`);
    }
  }
}
