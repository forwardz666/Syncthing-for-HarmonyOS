import { webview } from '@kit.ArkWeb';
import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { Constants } from '../service/Constants';
import { SyncthingService } from '../service/SyncthingService';
import { L10n } from '../common/L10n';

const TAG = 'WebGuiPage';

@Entry
@Component
struct WebGuiPage {
  controller: WebviewController = new webview.WebviewController();
  @State isLoading: boolean = true;
  @State statusText: string = L10n.t('app.string.webgui_loading');
  @State currentUrl: string = Constants.SYNCTHING_BASE_URL;

  aboutToAppear(): void {
    Logger.i(TAG, 'WebGuiPage appearing');
    this.ensureServiceRunning();
  }

  build() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle }) {
          Image($r('sys.media.ohos_ic_public_arrow_left'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_primary'))
        }
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.background_secondary'))
        .onClick(() => this.getUIContext().getRouter().back())

        Text(L10n.t('app.string.web_gui_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 })
          .layoutWeight(1)

        Button(L10n.t('app.string.back'))
          .height(36)
          .backgroundColor($r('app.color.button_secondary_background'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => this.goWebBack())

        Button(L10n.t('app.string.forward'))
          .height(36)
          .backgroundColor($r('app.color.button_secondary_background'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => this.goWebForward())

        Button(L10n.t('app.string.reload'))
          .height(36)
          .backgroundColor($r('app.color.button_secondary_background'))
          .fontColor($r('app.color.primary'))
          .onClick(() => this.reloadWebGui())
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })

      if (this.isLoading || this.statusText.length > 0) {
        Row({ space: 8 }) {
          if (this.isLoading) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color($r('app.color.primary'))
          }
          Text(this.statusText)
            .fontSize(12)
            .fontColor(this.statusText.indexOf('failed') >= 0 || this.statusText.indexOf('error') >= 0 ? $r('app.color.danger') : $r('app.color.text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.background_secondary'))
      }

      Web({ src: `${Constants.SYNCTHING_BASE_URL}`, controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .onErrorReceive((event) => {
          Logger.e(TAG, `WebView error: ${JSON.stringify(event)}`);
          this.isLoading = false;
          this.statusText = L10n.t('app.string.webgui_load_failed');
        })
        .onPageBegin((event) => {
          Logger.d(TAG, `WebView page begin: ${event?.url}`);
          this.isLoading = true;
          this.currentUrl = event?.url === undefined ? Constants.SYNCTHING_BASE_URL : event.url;
          this.statusText = L10n.t('app.string.webgui_loading');
        })
        .onPageEnd((event) => {
          Logger.d(TAG, `WebView page end: ${event?.url}`);
          this.isLoading = false;
          this.currentUrl = event?.url === undefined ? this.currentUrl : event.url;
          this.statusText = '';
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  private async ensureServiceRunning(): Promise<void> {
    const service = ServiceLocator.get<SyncthingService>(SERVICE_NAMES.SYNCTHING_SERVICE);
    if (service === undefined) {
      this.statusText = L10n.t('app.string.syncthing_not_ready_yet');
      return;
    }
    if (service.getState() !== 'active') {
      this.statusText = L10n.t('app.string.starting_syncthing_service');
      await service.startService();
    }
    this.statusText = L10n.t('app.string.webgui_loading');
  }

  private reloadWebGui(): void {
    try {
      this.isLoading = true;
      this.statusText = L10n.t('app.string.webgui_loading');
      this.controller.loadUrl(Constants.SYNCTHING_BASE_URL);
      this.controller.refresh();
    } catch (err) {
      Logger.e(TAG, `Failed to reload Web GUI: ${JSON.stringify(err)}`);
      this.isLoading = false;
      this.statusText = L10n.t('app.string.webgui_reload_failed');
    }
  }

  private goWebBack(): void {
    try {
      if (this.controller.accessBackward()) {
        this.controller.backward();
      } else {
        this.getUIContext().getRouter().back();
      }
    } catch (err) {
      Logger.e(TAG, `Failed to go back in Web GUI: ${JSON.stringify(err)}`);
      this.getUIContext().getRouter().back();
    }
  }

  private goWebForward(): void {
    try {
      if (this.controller.accessForward()) {
        this.controller.forward();
      }
    } catch (err) {
      Logger.e(TAG, `Failed to go forward in Web GUI: ${JSON.stringify(err)}`);
    }
  }
}
