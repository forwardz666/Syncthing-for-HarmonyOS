import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { common } from '@kit.AbilityKit';
import { LengthMetrics } from '@kit.ArkUI';
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
  @State indicatorLeftMargin: number = 0;
  @State indicatorWidth: number = 0;
  @State serviceState: string = 'unknown';
  @State deadPublicCount: number = 0;
  @State reauthInProgress: boolean = false;
  private deadPublicFolders: Folder[] = [];
  private lastWheelSwitchAt: number = 0;
  private tabsController: TabsController = new TabsController();
  private tabsWidth: number = 0;
  private textInfos: [number, number][] = [];
  private isStartAnimateTo: boolean = false;
  private animationDuration: number = 300;
  private tabTitles: string[] = [L10n.t('app.string.nav_devices'), L10n.t('app.string.nav_folders'), L10n.t('app.string.nav_status')];

  aboutToAppear(): void {
    Logger.i(TAG, 'MainPage appearing');
    for (let i = 0; i < 3; i++) {
      this.textInfos.push([0, 0]);
    }
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
            .fontColor($r('app.color.text_primary'))
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

      Stack({ alignContent: Alignment.TopStart }) {
        Tabs({ controller: this.tabsController }) {
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
        .barBackgroundColor($r('app.color.card_background'))
        .animationDuration(this.animationDuration)
        // Wheel switching is handled per-tab; Tabs remains scrollable so touch
        // swipe can also switch tabs. The no-op onAxisEvent below prevents the
        // built-in wheel handler from double-switching alongside the per-tab one.
        .scrollable(true)
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_background'))
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.tabsWidth = newValue.width as number;
          if (!this.isStartAnimateTo && this.currentTabIndex >= 0 && this.currentTabIndex < this.textInfos.length) {
            this.setIndicatorAttr(this.textInfos[this.currentTabIndex][0], this.textInfos[this.currentTabIndex][1]);
          }
        })
        .onAxisEvent((event: AxisEvent) => {
          if (event.getVerticalAxisValue() !== 0) {
            // The per-tab handlers decide whether to consume the wheel event;
            // Tabs itself must not perform any wheel-based switching.
          }
        })
        .onAnimationStart((index: number, targetIndex: number, event: TabsAnimationEvent) => {
          if (index !== targetIndex) {
            this.currentTabIndex = targetIndex;
            this.startAnimateTo(this.animationDuration, this.textInfos[targetIndex][0], this.textInfos[targetIndex][1]);
          }
        })
        .onAnimationEnd((index: number, event: TabsAnimationEvent) => {
          const info = this.getCurrentIndicatorInfo(index, event);
          this.startAnimateTo(0, info.left, info.width);
        })
        .onGestureSwipe((index: number, event: TabsAnimationEvent) => {
          const info = this.getCurrentIndicatorInfo(index, event);
          this.currentTabIndex = info.index;
          this.setIndicatorAttr(info.left, info.width);
        })
        .onChange((index: number) => {
          this.currentTabIndex = index;
        })

        Column()
          .height(3)
          .width(this.indicatorWidth)
          .margin({ start: LengthMetrics.vp(this.indicatorLeftMargin), top: LengthMetrics.vp(44) })
          .borderRadius(1.5)
          .backgroundColor($r('app.color.primary'))
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
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
      this.tabsController.changeIndex(next);
    }
  }

  @Builder
  tabBarBuilder(title: string, index: number) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontWeight(index === this.currentTabIndex ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(index === this.currentTabIndex ? $r('app.color.primary') : $r('app.color.text_tertiary'))
        .id(index.toString())
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.textInfos[index] = [newValue.globalPosition.x as number, newValue.width as number];
          if (!this.isStartAnimateTo && this.currentTabIndex === index && this.tabsWidth > 0) {
            this.setIndicatorAttr(this.textInfos[this.currentTabIndex][0], this.textInfos[this.currentTabIndex][1]);
          }
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 4, bottom: 4 })
  }

  private getCurrentIndicatorInfo(index: number, event: TabsAnimationEvent): Record<string, number> {
    let nextIndex = index;
    if (index > 0 && event.currentOffset > 0) {
      nextIndex--;
    } else if (index < this.textInfos.length - 1 && event.currentOffset < 0) {
      nextIndex++;
    }
    const indexInfo = this.textInfos[index];
    const nextIndexInfo = this.textInfos[nextIndex];
    const swipeRatio = this.tabsWidth > 0 ? Math.abs(event.currentOffset / this.tabsWidth) : 0;
    const currentIndex = swipeRatio > 0.5 ? nextIndex : index;
    const currentLeft = indexInfo[0] + (nextIndexInfo[0] - indexInfo[0]) * swipeRatio;
    const currentWidth = indexInfo[1] + (nextIndexInfo[1] - indexInfo[1]) * swipeRatio;
    return { 'index': currentIndex, 'left': currentLeft, 'width': currentWidth };
  }

  private startAnimateTo(duration: number, leftMargin: number, width: number): void {
    this.isStartAnimateTo = true;
    this.getUIContext()?.animateTo({
      duration: duration,
      curve: Curve.Linear,
      iterations: 1,
      playMode: PlayMode.Normal,
      onFinish: () => {
        this.isStartAnimateTo = false;
      }
    }, () => {
      this.setIndicatorAttr(leftMargin, width);
    });
  }

  private setIndicatorAttr(leftMargin: number, width: number): void {
    this.indicatorWidth = width;
    this.indicatorLeftMargin = leftMargin;
  }

  @Builder
  reauthBanner() {
    Row() {
      Column({ space: 2 }) {
        Text(this.reauthInProgress ? L10n.t('app.string.reauth_in_progress') : L10n.fmt('app.string.reauth_dead_folders', this.deadPublicCount))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.warning_text'))
        Text(L10n.t('app.string.grant_reauth_path'))
          .fontSize(12)
          .fontColor($r('app.color.warning_subtext'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (!this.reauthInProgress) {
        Button(L10n.t('app.string.restore'))
          .height(30)
          .fontSize(12)
          .backgroundColor($r('app.color.warning_text'))
          .fontColor(Color.White)
          .onClick(() => this.reauthPublicFolders())
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .borderRadius(10)
    .backgroundColor($r('app.color.warning_background'))
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
      const context = ServiceLocator.get<common.UIAbilityContext>(SERVICE_NAMES.UI_ABILITY_CONTEXT);
      if (context === undefined) {
        return;
      }
      if (!PublicFolderGrant.isEnvironmentRootAvailable()) {
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
      const root = await PublicFolderGrant.ensureUnifiedRoot(api, context);
      if (root.length === 0) {
        return;
      }
      const recovered = await PublicFolderGrant.restoreFolders(api, this.deadPublicFolders, root);
      Logger.i(TAG, `reauth: recovered ${recovered}/${this.deadPublicFolders.length}`);
      if (recovered > 0) {
        this.showToast(L10n.fmt('app.string.recovered_n_folders', recovered));
      }
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
