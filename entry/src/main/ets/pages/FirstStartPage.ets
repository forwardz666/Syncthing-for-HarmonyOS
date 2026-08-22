import { common } from '@kit.AbilityKit';
import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { PreferencesManager } from '../data/PreferencesManager';
import { Constants } from '../service/Constants';
import { SyncthingService } from '../service/SyncthingService';
import { FolderPermission } from '../service/FolderPermission';
import { SystemStatus } from '../model/Index';
import { L10n } from '../common/L10n';

const TAG = 'FirstStartPage';

@Entry
@Component
struct FirstStartPage {
  @State currentStep: number = 1;
  @State totalSteps: number = 4;
  @State generatingKey: boolean = false;
  @State deviceId: string = '';
  @State acceptTerms: boolean = false;

  private preferencesManager: PreferencesManager = PreferencesManager.getInstance();

  aboutToAppear(): void {
    Logger.i(TAG, 'FirstStartPage appearing');
    this.generateDeviceId();
  }

  build() {
    Column() {
      Row() {
        Text(L10n.t('app.string.first_start_title'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .height(60)
      .justifyContent(FlexAlign.Center)
      .margin({ top: 40 })

      Progress({ value: this.currentStep, total: this.totalSteps, type: ProgressType.Linear })
        .width('80%')
        .height(4)
        .margin({ top: 20, bottom: 20 })

      if (this.currentStep === 1) {
        this.buildStep1()
      } else if (this.currentStep === 2) {
        this.buildStep2()
      } else if (this.currentStep === 3) {
        this.buildStep3()
      } else if (this.currentStep === 4) {
        this.buildStep4()
      }

      Blank()

      Row({ space: 16 }) {
        if (this.currentStep > 1) {
          Button(L10n.t('app.string.previous'))
            .onClick(() => {
              this.currentStep--;
            })
        }

        if (this.currentStep < this.totalSteps) {
          Button(L10n.t('app.string.next'))
            .type(ButtonType.Capsule)
            .backgroundColor($r('app.color.primary'))
            .fontColor(Color.White)
            .onClick(() => {
              this.currentStep++;
            })
        } else {
          Button(L10n.t('app.string.first_start_ready_desc'))
            .type(ButtonType.Capsule)
            .backgroundColor($r('app.color.success'))
            .fontColor(Color.White)
            .onClick(() => {
              this.finishFirstStart();
            })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 40 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  buildStep1() {
    Column({ space: 20 }) {
      Text(L10n.t('app.string.first_start_desc1'))
        .fontSize(16)
        .textAlign(TextAlign.Center)
        .width('85%')
        .padding(20)
        .borderRadius(12)
        .backgroundColor($r('app.color.background_alternate'))

      Text(L10n.t('app.string.first_start_desc2'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .width('85%')
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildStep2() {
    Column({ space: 20 }) {
      Text(L10n.t('app.string.first_start_privacy'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)

      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Text(L10n.t('app.string.first_start_encryption'))
            .fontSize(14)
        }

        Row({ space: 8 }) {
          Text(L10n.t('app.string.first_start_local'))
            .fontSize(14)
        }

        Row({ space: 8 }) {
          Text(L10n.t('app.string.first_start_no_track'))
            .fontSize(14)
        }
      }
      .width('85%')
      .padding(16)
      .borderRadius(12)
      .backgroundColor($r('app.color.info_background'))

      Row({ space: 8 }) {
        Checkbox()
          .select(this.acceptTerms)
          .onChange((value: boolean) => {
            this.acceptTerms = value;
          })
        Text(L10n.t('app.string.first_start_agree'))
          .fontSize(14)
      }
      .margin({ top: 10 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildStep3() {
    Column({ space: 20 }) {
      Text(L10n.t('app.string.first_start_identity'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)

      Text(L10n.t('app.string.first_start_identity_desc'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .width('85%')

      if (this.generatingKey) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color($r('app.color.primary'))
      } else if (this.deviceId.length > 0) {
        Column({ space: 8 }) {
          Text(L10n.t('app.string.first_start_your_id'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))

          Text(this.deviceId)
            .fontSize(12)
            .fontFamily('monospace')
            .fontColor($r('app.color.text_primary'))
            .width('85%')
            .padding(12)
            .borderRadius(8)
            .backgroundColor($r('app.color.background_secondary'))
            .textAlign(TextAlign.Center)
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildStep4() {
    Column({ space: 20 }) {
      Text(L10n.t('app.string.first_start_ready'))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.success'))

      Text(L10n.t('app.string.first_start_next_steps_desc'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .width('85%')

      Column({ space: 12 }) {
        Text(L10n.t('app.string.first_start_next_steps'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)

        Text(L10n.t('app.string.first_start_step1'))
          .fontSize(14)
        Text(L10n.t('app.string.first_start_step2'))
          .fontSize(14)
        Text(L10n.t('app.string.first_start_step3'))
          .fontSize(14)
      }
      .width('85%')
      .padding(16)
      .borderRadius(12)
      .backgroundColor($r('app.color.background_alternate'))
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  async generateDeviceId(): Promise<void> {
    if (this.generatingKey || this.deviceId.length > 0) {
      return;
    }
    Logger.i(TAG, 'Generating device identity from Syncthing core');
    this.generatingKey = true;

    try {
      const service = await this.ensureSyncthingService();
      if (service.getState() !== 'active') {
        await service.startService();
      }

      const statusResult = await service.getRestApi().getSystemStatus();
      const coreDeviceId = statusResult.data !== undefined ? this.getSystemDeviceId(statusResult.data) : '';
      if (!statusResult.success || coreDeviceId.length === 0) {
        throw new Error(statusResult.error || 'Syncthing did not return a device ID');
      }

      this.deviceId = coreDeviceId;
      await this.preferencesManager.setLocalDeviceId(this.deviceId);
      Logger.i(TAG, `Device ID loaded from core: ${this.deviceId}`);
    } catch (err) {
      Logger.e(TAG, `Failed to generate device ID: ${JSON.stringify(err)}`);
    } finally {
      this.generatingKey = false;
    }
  }

  async finishFirstStart(): Promise<void> {
    Logger.i(TAG, 'Finishing first start setup');
    try {
      const service = await this.ensureSyncthingService();
      if (service.getState() !== 'active') {
        await service.startService();
      }
      if (this.deviceId.length === 0) {
        const statusResult = await service.getRestApi().getSystemStatus();
        if (statusResult.success && statusResult.data !== undefined) {
          this.deviceId = this.getSystemDeviceId(statusResult.data);
          await this.preferencesManager.setLocalDeviceId(this.deviceId);
        }
      }
      await this.preferencesManager.putBoolean(Constants.PREF_START_SERVICE_ON_BOOT, false);
      // Ask for the public Download/Documents dir permissions right after the
      // onboarding completes (requested by the user): the unified sync
      // container lives in the Download dir and needs a persistent user_grant,
      // otherwise the app falls back to a per-launch folder re-auth flow.
      await this.requestFolderPermissions();
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/MainPage' });
    } catch (err) {
      Logger.e(TAG, `Error finishing first start: ${JSON.stringify(err)}`);
    }
  }

  private async requestFolderPermissions(): Promise<void> {
    try {
      const context = ServiceLocator.get<common.UIAbilityContext>(SERVICE_NAMES.UI_ABILITY_CONTEXT);
      if (context === undefined || context === null) {
        Logger.w(TAG, 'requestFolderPermissions: ability context unavailable');
        return;
      }
      const granted = await FolderPermission.requestDirPermissions(context);
      Logger.i(TAG, `requestFolderPermissions: granted=${granted}`);
    } catch (err) {
      Logger.w(TAG, `requestFolderPermissions failed: ${JSON.stringify(err)}`);
    }
  }

  private async ensureSyncthingService(): Promise<SyncthingService> {
    const existing = ServiceLocator.get<SyncthingService>(SERVICE_NAMES.SYNCTHING_SERVICE);
    if (existing !== undefined) {
      return existing;
    }

    const service = new SyncthingService();
    await service.initialize();
    ServiceLocator.registerSingleton(SERVICE_NAMES.SYNCTHING_SERVICE, service);
    return service;
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
}
