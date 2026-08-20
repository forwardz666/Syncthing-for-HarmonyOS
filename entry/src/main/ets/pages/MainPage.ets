import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { common } from '@kit.AbilityKit';
import { RestApi } from '../network/RestApi';
import { DeviceListPage } from './DeviceListPage';
import { FolderListPage } from './FolderListPage';
import { StatusPage } from './StatusPage';
import { PublicFolderGrant } from '../service/PublicFolderGrant';
import { FolderPermission } from '../service/FolderPermission';
import { Folder } from '../model/Index';
import { L10n } from '../common/L10n';

const TAG = 'MainPage';

/**
 * Home tabs (Devices / Folders / Status) plus a banner that restores
 * public-directory sync grants after an app restart.
 *
 * A2 (2026-08-18): on OpenHarmony generic images the FOLDER-picker grant is
 * session-scoped (persistPermission rejected, 13900001), so after a restart
 * any public-dir folder loses access. When that happens we show a one-tap
 * banner: tapping re-runs the FOLDER picker and points every dead public
 * folder at the freshly authorized path.
 */
@Entry
@Component
struct MainPage {
  @State currentTabIndex: number = 0;
  @State serviceState: string = 'unknown';
  @State deadPublicCount: number = 0;
  @State reauthInProgress: boolean = false;
  private deadPublicFolders: Folder[] = [];
  private lastWheelSwitchAt: number = 0;
  private tabTitles: string[] = [L10n.t('app.string.nav_devices'), L10n.t('app.string.nav_folders'), L10n.t('app.string.nav_status')];

  aboutToAppear(): void {
    Logger.i(TAG, 'MainPage appearing');
    this.scheduleDeadPublicCheck();
  }

  build() {
    Column() {
      Row() {
        Text(L10n.t('app.string.app_name'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 16 })
          .layoutWeight(1)

        Row({ space: 8 }) {
          Text(L10n.t('app.string.settings'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#333')
          Image($r('app.media.syncthing'))
            .width(24)
            .height(24)
        }
        .margin({ right: 16 })
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/SettingsPage' });
        })
      }
      .width('100%')
      .height(56)
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)

      if (this.deadPublicCount > 0) {
        this.reauthBanner()
      }

      Tabs({ index: this.currentTabIndex }) {
        TabContent() {
          DeviceListPage({ onWheelSwitch: (direction: number) => this.handleWheelSwitch(direction) })
        }
        .tabBar(this.tabBarBuilder(L10n.t('app.string.nav_devices'), 0))

        TabContent() {
          FolderListPage({ onWheelSwitch: (direction: number) => this.handleWheelSwitch(direction) })
        }
        .tabBar(this.tabBarBuilder(L10n.t('app.string.nav_folders'), 1))

        TabContent() {
          StatusPage({ onWheelSwitch: (direction: number) => this.handleWheelSwitch(direction) })
        }
        .tabBar(this.tabBarBuilder(L10n.t('app.string.nav_status'), 2))
      }
      .barMode(BarMode.Fixed)
      .barWidth('100%')
      .barHeight(48)
      // Wheel switching is handled per-tab; disable Tabs' built-in wheel/scroll switching to avoid conflicts.
      .scrollable(false)
      .width('100%')
      .layoutWeight(1)
      .onAxisEvent((event: AxisEvent) => {
        if (event.hasAxis(AxisType.VERTICAL_AXIS) && event.getVerticalAxisValue() !== 0) {
          // The per-tab handlers decide whether to consume the wheel event;
          // Tabs itself must not perform any wheel-based switching.
        }
      })
      .onChange((index: number) => {
        this.currentTabIndex = index;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  private handleWheelSwitch(direction: number): void {
    const now = Date.now();
    if (now - this.lastWheelSwitchAt < 300) {
      return;
    }
    const next = this.currentTabIndex + direction;
    if (next >= 0 && next < 3) {
      this.lastWheelSwitchAt = now;
      this.currentTabIndex = next;
    }
  }

  @Builder
  tabBarBuilder(title: string, index: number) {
    Row() {
      Text(title)
        .fontSize(14)
        .fontWeight(index === this.currentTabIndex ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(index === this.currentTabIndex ? '#007AFF' : '#999')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  reauthBanner() {
    Row() {
      Column({ space: 2 }) {
        Text(this.reauthInProgress ? L10n.t('app.string.reauth_in_progress') : L10n.fmt('app.string.reauth_dead_folders', this.deadPublicCount))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#7A4A00')
        Text(L10n.t('app.string.grant_reauth_path'))
          .fontSize(12)
          .fontColor('#9A6A20')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (!this.reauthInProgress) {
        Button(L10n.t('app.string.restore'))
          .height(30)
          .fontSize(12)
          .backgroundColor('#7A4A00')
          .fontColor(Color.White)
          .onClick(() => this.reauthPublicFolders())
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .borderRadius(10)
    .backgroundColor('#FFF3D6')
    .margin({ left: 12, right: 12, top: 4, bottom: 4 })
    .onClick(() => this.reauthPublicFolders())
  }

  private scheduleDeadPublicCheck(): void {
    // Core/RestApi may not be ready yet on cold start; poll briefly.
    let attempts = 0;
    const interval = setInterval(() => {
      attempts++;
      const api = ServiceLocator.get<RestApi>(SERVICE_NAMES.REST_API);
      if (api !== undefined) {
        clearInterval(interval);
        this.checkDeadPublicFolders(api);
      } else if (attempts >= 20) {
        clearInterval(interval);
      }
    }, 500);
  }

  private async checkDeadPublicFolders(api: RestApi): Promise<void> {
    try {
      const dead = await PublicFolderGrant.findDeadPublicFolders(api);
      this.deadPublicFolders = dead;
      this.deadPublicCount = dead.length;
      if (dead.length > 0) {
        Logger.i(TAG, `detected ${dead.length} public folder(s) needing re-auth`);
      }
    } catch (err) {
      Logger.w(TAG, `checkDeadPublicFolders failed: ${JSON.stringify(err)}`);
    }
  }

  private async reauthPublicFolders(): Promise<void> {
    if (this.reauthInProgress) {
      return;
    }
    const api = ServiceLocator.get<RestApi>(SERVICE_NAMES.REST_API);
    if (api === undefined) {
      return;
    }
    this.reauthInProgress = true;
    try {
      // On FolderObtain devices the public folders live under the Download
      // env root; granting READ_WRITE_DOWNLOAD/DOCUMENTS_DIRECTORY once makes
      // them readable again — no picker, no per-launch re-auth. Try that first.
      const context = ServiceLocator.get<common.UIAbilityContext>(SERVICE_NAMES.UI_ABILITY_CONTEXT);
      if (!PublicFolderGrant.isEnvironmentRootAvailable() && context !== undefined) {
        await FolderPermission.requestDirPermissions(context);
        if (PublicFolderGrant.isEnvironmentRootAvailable()) {
          await this.checkDeadPublicFolders(api);
          if (this.deadPublicCount === 0) {
            this.showToast(L10n.t('app.string.folder_permission_granted'));
            Logger.i(TAG, 'reauth: env root revived by folder permission grant');
          }
          return;
        }
      }
      const choice = await PublicFolderGrant.chooseFolder();
      if (choice.path.length === 0) {
        // cancelled / unsupported
        return;
      }
      // Best-effort persist + install the picked dir as the fallback container
      // root (phone-class devices; no-op on the Environment path).
      await PublicFolderGrant.setPickerFallback(choice.uri, choice.path);
      const recovered = await PublicFolderGrant.restoreFolders(api, this.deadPublicFolders, choice.path);
      Logger.i(TAG, `reauth: recovered ${recovered}/${this.deadPublicFolders.length}`);
      if (recovered > 0) {
        this.showToast(L10n.fmt('app.string.recovered_n_folders', recovered));
      }
      // refresh visibility
      await this.checkDeadPublicFolders(api);
    } catch (err) {
      Logger.w(TAG, `reauthPublicFolders failed: ${JSON.stringify(err)}`);
    } finally {
      this.reauthInProgress = false;
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
