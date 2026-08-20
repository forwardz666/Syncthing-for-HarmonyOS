import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { RestApi } from '../network/RestApi';
import { PublicFolderGrant } from '../service/PublicFolderGrant';
import { Folder, FolderStatus } from '../model/Index';
import { L10n } from '../common/L10n';

const TAG = 'FolderListPage';

@Component
export struct FolderListPage {
  @State folders: Folder[] = [];
  @State folderStatuses: Map<string, FolderStatus> = new Map();
  @State isLoading: boolean = true;
  @State showEmpty: boolean = false;
  @State isCreatingUnified: boolean = false;
  // A2 (2026-08-18): bumped by FolderDetailPage after save/delete so the list
  // refreshes immediately (no app restart needed).
  @StorageLink('folderListRefreshTick') @Watch('onFolderListRefresh') folderRefreshTick: number = 0;

  onWheelSwitch?: (direction: number) => void = undefined;
  private restApi: RestApi | null = null;
  private cleanedLegacyRoot: boolean = false;
  private listScroller: Scroller = new Scroller();

  onFolderListRefresh(): void {
    Logger.i(TAG, `folder list refresh tick -> ${this.folderRefreshTick}`);
    this.loadFolders();
  }

  aboutToAppear(): void {
    Logger.i(TAG, 'FolderListPage appearing');
    this.loadFolders();
  }

  async loadFolders(): Promise<void> {
    try {
      this.isLoading = true;
      const api = ServiceLocator.get<RestApi>(SERVICE_NAMES.REST_API);
      if (api) {
        this.restApi = api;
        // A2 (2026-08-18): one-time cleanup of the legacy root-folder
        // registration (old "统一同步文件夹", path = Download/Syncthing root).
        // The container dir itself is kept; only the folder config is removed.
        if (!this.cleanedLegacyRoot) {
          this.cleanedLegacyRoot = true;
          await this.ensureUnifiedContainer(api);
        }
        const result = await api.getFolders();
        if (result.success && result.data) {
          this.folders = result.data;
          this.showEmpty = this.folders.length === 0;
          await this.loadFolderStatuses(api, this.folders);
        }
      }
    } catch (err) {
      Logger.e(TAG, `Error loading folders: ${JSON.stringify(err)}`);
    } finally {
      this.isLoading = false;
    }
  }

  private async ensureUnifiedContainer(api: RestApi): Promise<void> {
    try {
      await PublicFolderGrant.ensureUnifiedRoot(api);
    } catch (err) {
      Logger.w(TAG, `ensureUnifiedContainer failed: ${JSON.stringify(err)}`);
    }
  }

  private async loadFolderStatuses(api: RestApi, folders: Folder[]): Promise<void> {
    const statuses: Map<string, FolderStatus> = new Map();
    for (let i = 0; i < folders.length; i++) {
      const folder = folders[i];
      const statusResult = await api.getFolderStatus(folder.id);
      if (statusResult.success && statusResult.data !== undefined) {
        statuses.set(folder.id, statusResult.data);
      }
    }
    this.folderStatuses = statuses;
  }

  getCompletionText(folder: Folder): string {
    const status = this.folderStatuses.get(folder.id);
    if (status) {
      if (status.state.length > 0 && status.state !== 'idle') {
        return L10n.folderState(status.state);
      }
      if (status.globalBytes === 0) {
        return L10n.t('app.string.folder_empty');
      }
      const completed = status.globalBytes - status.needBytes;
      const percent = status.globalBytes > 0
        ? Math.round((completed / status.globalBytes) * 100)
        : 0;
      return L10n.fmt('app.string.percent_synced', percent);
    }
    return folder.type;
  }

  getStatusColor(folder: Folder): string {
    const status = this.folderStatuses.get(folder.id);
    if (status) {
      const percent = status.globalBytes > 0
        ? Math.round(((status.globalBytes - status.needBytes) / status.globalBytes) * 100)
        : 100;
      if (status.errors > 0 || status.pullErrors > 0 || status.invalid.length > 0 || status.watchError.length > 0) {
        return '#FF3B30';
      }
      if (percent >= 100) {
        return '#34C759';
      }
      if (percent >= 50) {
        return '#007AFF';
      }
      return '#FF9500';
    }
    return '#999';
  }

  build() {
    Column() {
      this.header()

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color('#007AFF')
          Text(L10n.t('app.string.loading_folders'))
            .fontSize(14)
            .fontColor('#888')
            .margin({ top: 12 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.showEmpty || this.folders.length === 0) {
        Column({ space: 16 }) {
          Text(L10n.t('app.string.no_folders'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)

          Text(L10n.t('app.string.add_folder_prompt'))
            .fontSize(14)
            .fontColor('#888')
            .textAlign(TextAlign.Center)
            .width('80%')

          Button(this.isCreatingUnified ? '…' : L10n.t('app.string.add_folder'))
            .type(ButtonType.Capsule)
            .backgroundColor('#007AFF')
            .fontColor(Color.White)
            .enabled(!this.isCreatingUnified)
            .onClick(() => {
              this.addUnifiedFolder();
            })
            .margin({ top: 10 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 4, scroller: this.listScroller }) {
          ForEach(this.folders, (folder: Folder) => {
            ListItem() {
              this.folderItem(folder)
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 8 })
        .onAxisEvent((event: AxisEvent) => {
          this.handleWheel(event);
        })
      }
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
      const offset = this.listScroller.currentOffset();
      return offset === undefined || offset.yOffset === undefined || offset.yOffset <= 1;
    } catch (err) {
      return true;
    }
  }

  @Builder
  header() {
    Row() {
      Text(L10n.t('app.string.nav_folders'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)

      Button(this.isCreatingUnified ? '…' : L10n.t('app.string.add'))
        .height(36)
        .backgroundColor('#007AFF')
        .fontColor(Color.White)
        .enabled(!this.isCreatingUnified)
        .onClick(() => this.addUnifiedFolder())
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  folderItem(folder: Folder) {
    Row() {
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(folder.label || folder.id)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#333')
        }

        Text(folder.path)
          .fontSize(12)
          .fontColor('#999')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 8 }) {
          Text(this.getCompletionText(folder))
            .fontSize(11)
            .fontColor('#FFF')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor(this.getStatusColor(folder))

          Text(this.getFolderTypeLabel(folder.type))
            .fontSize(11)
            .fontColor('#666')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor('#EEEEEE')
        }
        .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Image($r('sys.media.ohos_ic_public_arrow_right'))
        .width(20)
        .height(20)
        .fillColor('#CCC')
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
    .onClick(() => {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/FolderDetailPage',
        params: { folderId: folder.id }
      });
    })
  }

  getFolderTypeLabel(type: string): string {
    switch (type) {
      case 'sendreceive': return L10n.t('app.string.send_receive');
      case 'sendonly': return L10n.t('app.string.send_only');
      case 'receiveonly': return L10n.t('app.string.receive_only');
      case 'receiveencrypted': return L10n.t('app.string.receive_encrypted');
      default: return type;
    }
  }

  /**
   * Add a sync folder — always inside the unified container
   * (<Download>/Syncthing/<folderId>). Ensures the container exists (and
   * legacy root-folder config is cleaned), then opens FolderDetailPage in
   * create mode where the path is automatically bound to the container.
   */
  private async addUnifiedFolder(): Promise<void> {
    if (this.isCreatingUnified) {
      return;
    }
    this.isCreatingUnified = true;
    try {
      const api = ServiceLocator.get<RestApi>(SERVICE_NAMES.REST_API);
      if (api === undefined) {
        this.showToast(L10n.t('app.string.syncthing_not_ready'));
        return;
      }
      const root = await PublicFolderGrant.ensureUnifiedRoot(api);
      if (root.length === 0) {
        this.showToast(PublicFolderGrant.isEnvironmentRootAvailable()
          ? L10n.t('app.string.grant_download_permission')
          : L10n.t('app.string.picker_choose_dir'));
        return;
      }
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/FolderDetailPage',
        params: { mode: 'create' }
      });
    } catch (err) {
      Logger.e(TAG, `addUnifiedFolder failed: ${JSON.stringify(err)}`);
      this.showToast(L10n.t('app.string.create_failed'));
    } finally {
      this.isCreatingUnified = false;
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (err) {
      Logger.w(TAG, `showToast failed: ${JSON.stringify(err)}`);
    }
  }
}
