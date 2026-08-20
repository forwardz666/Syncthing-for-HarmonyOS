import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { PreferencesManager } from '../data/PreferencesManager';
import { Constants } from '../service/Constants';
import { BackgroundSyncManager } from '../service/BackgroundSyncManager';
import { SyncthingService } from '../service/SyncthingService';
import { RunCondition } from '../types/index';
import { L10n } from '../common/L10n';

const TAG = 'SyncConditionsPage';

/**
 * User-facing controls for sync run conditions and continuous background sync.
 */
@Entry
@Component
struct SyncConditionsPage {
  @State isLoading: boolean = true;
  @State statusText: string = '';
  @State alwaysRunInBackground: boolean = false;
  @State runOnWifi: boolean = true;
  @State runOnMeteredWifi: boolean = true;
  @State runOnMobileData: boolean = false;
  @State runOnRoaming: boolean = false;
  @State useWifiSsidWhitelist: boolean = false;
  @State wifiSsidWhitelist: string = '';
  @State powerSource: string = Constants.POWER_SOURCE_CHARGER_BATTERY;
  @State respectBatterySaving: boolean = true;
  @State respectMasterSync: boolean = true;
  @State runInFlightMode: boolean = false;
  @State runOnTimeSchedule: boolean = false;
  @State syncDurationMinutesText: string = '0';
  @State sleepIntervalMinutesText: string = '0';

  private preferencesManager: PreferencesManager = PreferencesManager.getInstance();

  aboutToAppear(): void {
    Logger.i(TAG, 'SyncConditionsPage appearing');
    this.loadConditions();
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
          Text(L10n.t('app.string.loading_sync_conditions'))
            .fontSize(14)
            .fontColor('#777')
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ListItemGroup({ header: this.sectionHeader(L10n.t('app.string.background')) }) {
            ListItem() {
              this.toggleItem(L10n.t('app.string.background_sync'), L10n.t('app.string.background_sync_desc'), this.alwaysRunInBackground, (value: boolean) => {
                this.setBackgroundSync(value);
              })
            }
          }

          ListItemGroup({ header: this.sectionHeader(L10n.t('app.string.network')) }) {
            ListItem() {
              this.toggleItem(L10n.t('app.string.run_on_wifi'), L10n.t('app.string.run_on_wifi_desc'), this.runOnWifi, (value: boolean) => {
                this.runOnWifi = value;
                this.saveBoolean(Constants.PREF_RUN_ON_WIFI, value);
              })
            }
            ListItem() {
              this.toggleItem(L10n.t('app.string.run_on_metered_wifi'), L10n.t('app.string.run_on_metered_wifi_desc'), this.runOnMeteredWifi, (value: boolean) => {
                this.runOnMeteredWifi = value;
                this.saveBoolean(Constants.PREF_RUN_ON_METERED_WIFI, value);
              })
            }
            ListItem() {
              this.toggleItem(L10n.t('app.string.run_on_mobile_data'), L10n.t('app.string.run_on_mobile_data_desc'), this.runOnMobileData, (value: boolean) => {
                this.runOnMobileData = value;
                this.saveBoolean(Constants.PREF_RUN_ON_MOBILE_DATA, value);
              })
            }
            ListItem() {
              this.pendingToggleItem(L10n.t('app.string.run_while_roaming'), L10n.t('app.string.run_while_roaming_desc'), this.runOnRoaming)
            }
            ListItem() {
              this.pendingToggleItem(L10n.t('app.string.wifi_ssid_list'), L10n.t('app.string.wifi_ssid_list_desc'), this.useWifiSsidWhitelist)
            }
            ListItem() {
              this.pendingTextItem(L10n.t('app.string.allowed_ssids'), L10n.t('app.string.wifi_ssid_list_desc'), this.wifiSsidWhitelist)
            }
          }

          ListItemGroup({ header: this.sectionHeader(L10n.t('app.string.power')) }) {
            ListItem() {
              this.powerSourceItem()
            }
            ListItem() {
              this.toggleItem(L10n.t('app.string.respect_battery_saver'), L10n.t('app.string.respect_battery_saver_desc'), this.respectBatterySaving, (value: boolean) => {
                this.respectBatterySaving = value;
                this.saveBoolean(Constants.PREF_RESPECT_BATTERY_SAVING, value);
              })
            }
            ListItem() {
              this.pendingToggleItem(L10n.t('app.string.respect_master_sync'), L10n.t('app.string.respect_master_sync_desc'), this.respectMasterSync)
            }
            ListItem() {
              this.pendingToggleItem(L10n.t('app.string.run_in_flight_mode'), L10n.t('app.string.run_in_flight_mode_desc'), this.runInFlightMode)
            }
          }

          ListItemGroup({ header: this.sectionHeader(L10n.t('app.string.schedule')) }) {
            ListItem() {
              this.toggleItem(L10n.t('app.string.timed_schedule'), L10n.t('app.string.timed_schedule_desc'), this.runOnTimeSchedule, (value: boolean) => {
                this.runOnTimeSchedule = value;
                this.saveBoolean(Constants.PREF_RUN_ON_TIME_SCHEDULE, value);
              })
            }
            if (this.runOnTimeSchedule) {
              ListItem() {
                this.textItem(L10n.t('app.string.sync_duration_minutes'), L10n.t('app.string.sync_duration_minutes_desc'), this.syncDurationMinutesText, (value: string) => {
                  this.syncDurationMinutesText = this.normalizeNumber(value);
                }, () => this.saveNumber(Constants.PREF_SYNC_DURATION_MINUTES, this.parsePositiveInt(this.syncDurationMinutesText)))
              }
              ListItem() {
                this.textItem(L10n.t('app.string.sleep_interval_minutes'), L10n.t('app.string.sleep_interval_minutes_desc'), this.sleepIntervalMinutesText, (value: string) => {
                  this.sleepIntervalMinutesText = this.normalizeNumber(value);
                }, () => this.saveNumber(Constants.PREF_SLEEP_INTERVAL_MINUTES, this.parsePositiveInt(this.sleepIntervalMinutesText)))
              }
            }
          }

          if (this.statusText.length > 0) {
            ListItem() {
              Text(this.statusText)
                .fontSize(13)
                .fontColor('#34C759')
                .width('100%')
                .padding(12)
                .borderRadius(8)
                .backgroundColor('#FFFFFF')
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 20 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  header() {
    Row({ space: 10 }) {
      Button(L10n.t('app.string.back'))
        .width(40)
        .height(40)
        .backgroundColor('#E9EEF5')
        .fontColor('#222')
        .onClick(() => this.getUIContext().getRouter().back())
      Text(L10n.t('app.string.sync_conditions'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)
      Button(L10n.t('app.string.reload'))
        .height(36)
        .backgroundColor('#E9EEF5')
        .fontColor('#007AFF')
        .onClick(() => this.loadConditions())
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  sectionHeader(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor('#888')
      .fontWeight(FontWeight.Bold)
      .margin({ left: 8, top: 16, bottom: 4 })
      .textCase(TextCase.UpperCase)
  }

  @Builder
  toggleItem(title: string, subtitle: string, value: boolean, onChange: (value: boolean) => void) {
    Row() {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(16)
          .fontColor('#333')
        Text(subtitle)
          .fontSize(12)
          .fontColor('#999')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: value })
        .onChange(onChange)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
  }

  @Builder
  pendingToggleItem(title: string, subtitle: string, value: boolean) {
    Row() {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(16)
          .fontColor('#999')
          .decoration({ type: TextDecorationType.LineThrough })
        Text(subtitle)
          .fontSize(12)
          .fontColor('#999')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: value })
        .enabled(false)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
  }

  @Builder
  textItem(title: string, subtitle: string, value: string, onChange: (value: string) => void, onSubmit: () => void) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(16)
        .fontColor('#333')
      Text(subtitle)
        .fontSize(12)
        .fontColor('#999')
      TextInput({ text: value })
        .height(40)
        .fontSize(14)
        .backgroundColor('#F5F7FA')
        .borderRadius(8)
        .onChange(onChange)
        .onSubmit(() => onSubmit())
      Button(L10n.t('app.string.save'))
        .height(32)
        .backgroundColor('#E9EEF5')
        .fontColor('#007AFF')
        .onClick(onSubmit)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
  }

  @Builder
  pendingTextItem(title: string, subtitle: string, value: string) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(16)
        .fontColor('#999')
        .decoration({ type: TextDecorationType.LineThrough })
      Text(subtitle)
        .fontSize(12)
        .fontColor('#999')
      TextInput({ text: value })
        .height(40)
        .enabled(false)
        .fontSize(14)
        .backgroundColor('#F5F7FA')
        .borderRadius(8)
      Button(L10n.t('app.string.save'))
        .height(32)
        .enabled(false)
        .backgroundColor('#E8E8E8')
        .fontColor('#999')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
  }

  @Builder
  powerSourceItem() {
    Column({ space: 8 }) {
      Text(L10n.t('app.string.power_source'))
        .fontSize(16)
        .fontColor('#333')
      Row({ space: 8 }) {
        this.powerChip(Constants.POWER_SOURCE_CHARGER_BATTERY, L10n.t('app.string.power_any'))
        this.powerChip(Constants.POWER_SOURCE_CHARGER, L10n.t('app.string.power_charging'))
        this.powerChip(Constants.POWER_SOURCE_BATTERY, L10n.t('app.string.power_battery'))
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
  }

  @Builder
  pendingPowerSourceItem() {
    Column({ space: 8 }) {
      Text(L10n.t('app.string.power_source'))
        .fontSize(16)
        .fontColor('#999')
        .decoration({ type: TextDecorationType.LineThrough })
      Text(L10n.t('app.string.pending_charging'))
        .fontSize(12)
        .fontColor('#999')
      Row({ space: 8 }) {
        this.pendingPowerChip(L10n.t('app.string.power_any'))
        this.pendingPowerChip(L10n.t('app.string.power_charging'))
        this.pendingPowerChip(L10n.t('app.string.power_battery'))
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
  }

  @Builder
  pendingPowerChip(label: string) {
    Button(label)
      .height(34)
      .layoutWeight(1)
      .enabled(false)
      .backgroundColor('#E8E8E8')
      .fontColor('#999')
  }

  @Builder
  powerChip(value: string, label: string) {
    Button(label)
      .height(34)
      .layoutWeight(1)
      .backgroundColor(this.powerSource === value ? '#007AFF' : '#F5F7FA')
      .fontColor(this.powerSource === value ? Color.White : '#333')
      .onClick(() => {
        this.powerSource = value;
        this.saveString(Constants.PREF_POWER_SOURCE, value);
      })
  }

  private async loadConditions(): Promise<void> {
    this.isLoading = true;
    try {
      const conditions: RunCondition = await this.preferencesManager.getRunConditions();
      this.alwaysRunInBackground = conditions.alwaysRunInBackground;
      this.runOnWifi = conditions.runOnWifi;
      this.runOnMeteredWifi = conditions.runOnMeteredWifi;
      this.runOnMobileData = conditions.runOnMobileData;
      this.runOnRoaming = conditions.runOnRoaming;
      this.useWifiSsidWhitelist = conditions.useWifiSsidWhitelist;
      this.wifiSsidWhitelist = conditions.wifiSsidWhitelist;
      this.powerSource = conditions.powerSource;
      this.respectBatterySaving = conditions.respectBatterySaving;
      this.respectMasterSync = conditions.respectMasterSync;
      this.runInFlightMode = conditions.runInFlightMode;
      this.runOnTimeSchedule = conditions.runOnTimeSchedule;
      this.syncDurationMinutesText = conditions.syncDurationMinutes.toString();
      this.sleepIntervalMinutesText = conditions.sleepIntervalMinutes.toString();
      this.statusText = '';
    } catch (err) {
      Logger.e(TAG, `Failed to load sync conditions: ${JSON.stringify(err)}`);
      this.statusText = L10n.t('app.string.conditions_load_failed');
    } finally {
      this.isLoading = false;
    }
  }

  private async saveBoolean(key: string, value: boolean): Promise<void> {
    await this.preferencesManager.putBoolean(key, value);
    this.showSaved();
  }

  private async setBackgroundSync(value: boolean): Promise<void> {
    const previous = this.alwaysRunInBackground;
    this.alwaysRunInBackground = value;
    this.statusText = value ? L10n.t('app.string.starting_background_sync') : L10n.t('app.string.stopping_background_sync');

    try {
      await this.preferencesManager.putBoolean(Constants.PREF_START_SERVICE_ON_BOOT, value);
      const manager = ServiceLocator.get<BackgroundSyncManager>(SERVICE_NAMES.BACKGROUND_SYNC_MANAGER);
      if (manager === undefined) {
        throw new Error('Background sync manager is not ready');
      }

      if (value) {
        const service = ServiceLocator.get<SyncthingService>(SERVICE_NAMES.SYNCTHING_SERVICE);
        if (service !== undefined && service.getState() !== 'active') {
          await service.startService();
        }
        const ok = await manager.enable();
        if (!ok) {
          throw new Error(manager.getLastError());
        }
        this.statusText = L10n.t('app.string.background_sync_saved');
      } else {
        const ok = await manager.disable();
        if (!ok) {
          throw new Error(manager.getLastError());
        }
        this.statusText = L10n.t('app.string.background_sync_stopped');
      }
    } catch (err) {
      this.alwaysRunInBackground = previous;
      await this.preferencesManager.putBoolean(Constants.PREF_START_SERVICE_ON_BOOT, previous);
      Logger.e(TAG, `Failed to change background sync: ${JSON.stringify(err)}`);
      this.statusText = L10n.fmt('app.string.background_sync_failed', JSON.stringify(err));
    }
  }

  private async saveString(key: string, value: string): Promise<void> {
    await this.preferencesManager.putString(key, value.trim());
    this.showSaved();
  }

  private async saveNumber(key: string, value: number): Promise<void> {
    await this.preferencesManager.putNumber(key, value);
    this.showSaved();
  }

  private showSaved(): void {
    this.statusText = L10n.t('app.string.sync_condition_saved');
    this.showToast(L10n.t('app.string.saved'));
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (err) {
      Logger.w(TAG, `Failed to show toast: ${JSON.stringify(err)}`);
    }
  }

  private normalizeNumber(value: string): string {
    const sanitized = value.trim().replace(/[^0-9]/g, '');
    return sanitized.length === 0 ? '0' : sanitized;
  }

  private parsePositiveInt(value: string): number {
    const parsed = Number.parseInt(this.normalizeNumber(value), 10);
    if (Number.isNaN(parsed) || parsed < 0) {
      return 0;
    }
    return parsed;
  }
}
