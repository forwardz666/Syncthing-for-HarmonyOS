import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { PreferencesManager } from '../data/PreferencesManager';
import { SyncthingService } from '../service/SyncthingService';
import { Constants } from '../service/Constants';
import { L10n } from '../common/L10n';

const TAG = 'Index';

@Entry
@Component
struct Index {
  @State loadingMessage: string = 'Syncthing';
  @State loadingProgress: number = 0;
  @State showError: boolean = false;
  @State errorMessage: string = '';

  private syncthingService: SyncthingService | null = null;
  private preferencesManager: PreferencesManager = PreferencesManager.getInstance();

  async aboutToAppear(): Promise<void> {
    Logger.i(TAG, 'Index page appearing');
    await this.initializeApp();
  }

  async initializeApp(): Promise<void> {
    try {
      this.loadingMessage = L10n.t('app.string.loading_init');
      this.loadingProgress = 10;

      const firstRun = await this.isFirstRun();

      this.loadingMessage = L10n.t('app.string.loading_start_services');
      this.loadingProgress = 50;

      this.syncthingService = new SyncthingService();
      await this.syncthingService.initialize();
      ServiceLocator.registerSingleton(SERVICE_NAMES.SYNCTHING_SERVICE, this.syncthingService);

      this.loadingProgress = 80;

      if (firstRun) {
        if (this.syncthingService.getState() !== 'active') {
          await this.syncthingService.startService();
        }
        this.loadingMessage = L10n.t('app.string.welcome_syncthing');
        this.loadingProgress = 100;
        this.getUIContext().getRouter().replaceUrl({ url: 'pages/FirstStartPage' });
      } else {
        if (this.syncthingService.getState() !== 'active') {
          await this.syncthingService.startService();
        }
        this.loadingMessage = L10n.t('app.string.ready');
        this.loadingProgress = 100;
        this.getUIContext().getRouter().replaceUrl({ url: 'pages/MainPage' });
      }
    } catch (err) {
      Logger.e(TAG, `Initialization failed: ${JSON.stringify(err)}`);
      this.showError = true;
      this.errorMessage = L10n.fmt('app.string.init_failed', JSON.stringify(err));
    }
  }

  async isFirstRun(): Promise<boolean> {
    try {
      const hasPreferences = await this.preferencesManager.has(Constants.PREF_LOCAL_DEVICE_ID);
      return !hasPreferences;
    } catch (err) {
      Logger.w(TAG, `Could not determine if first run: ${JSON.stringify(err)}`);
      return true;
    }
  }

  build() {
    Column() {
      if (this.showError) {
        Column({ space: 20 }) {
          Image($r('app.media.startIcon'))
            .width(80)
            .height(80)
            .opacity(0.6)

          Text(this.errorMessage)
            .fontSize(16)
            .fontColor('#FF4444')
            .textAlign(TextAlign.Center)
            .width('80%')

          Button(L10n.t('app.string.retry'))
            .onClick(() => {
              this.showError = false;
              this.initializeApp();
            })
            .margin({ top: 20 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Column({ space: 30 }) {
          Image($r('app.media.startIcon'))
            .width(80)
            .height(80)

          Text(this.loadingMessage)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)

          Progress({ value: this.loadingProgress, total: 100, type: ProgressType.Linear })
            .width('60%')
            .height(4)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
  }
}
