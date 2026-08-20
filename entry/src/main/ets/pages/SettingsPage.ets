import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { PreferencesManager } from '../data/PreferencesManager';
import { RestApi } from '../network/RestApi';
import { Constants } from '../service/Constants';
import { SyncthingService } from '../service/SyncthingService';
import { Options, SystemVersion } from '../model/Index';
import { L10n } from '../common/L10n';

const TAG = 'SettingsPage';

/**
 * Application and Syncthing settings page backed by the local REST config API.
 */
@Entry
@Component
struct SettingsPage {
  @State appTheme: string = 'system';
  @State runOnWifi: boolean = true;
  @State runOnMobileData: boolean = false;
  @State verboseLog: boolean = false;
  @State isLoading: boolean = true;
  @State isSaving: boolean = false;
  @State listenAddressesText: string = 'default';
  @State globalServersText: string = 'default';
  @State maxRecvKbpsText: string = '0';
  @State maxSendKbpsText: string = '0';
  @State natEnabled: boolean = true;
  @State localDiscovery: boolean = true;
  @State globalDiscovery: boolean = true;
  @State relaysEnabled: boolean = true;
  @State limitBandwidthInLan: boolean = false;
  @State currentLanguageDisplay: string = '';
  @State lastLanguagePref: string = Constants.PREF_APP_LANGUAGE_SYSTEM;
  @State statusText: string = '';
  @State isExiting: boolean = false;
  @State syncthingCoreVersion: string = '';

  private restApi: RestApi | null = null;
  private options: Options | null = null;
  private preferencesManager: PreferencesManager = PreferencesManager.getInstance();

  aboutToAppear(): void {
    Logger.i(TAG, 'SettingsPage appearing');
    this.loadSettings();
  }

  async loadSettings(): Promise<void> {
    Logger.d(TAG, 'Loading settings');
    this.isLoading = true;
    try {
      const api = ServiceLocator.get<RestApi>(SERVICE_NAMES.REST_API);
      if (api === undefined) {
        this.statusText = L10n.t('app.string.syncthing_not_ready');
        return;
      }
      this.restApi = api;
      await this.loadLocalPreferences();
      this.lastLanguagePref = await this.preferencesManager.getString(Constants.PREF_APP_LANGUAGE, Constants.PREF_APP_LANGUAGE_SYSTEM);
      const optionsResult = await api.getOptions();
      if (optionsResult.success && optionsResult.data !== undefined) {
        this.applyOptions(optionsResult.data);
      } else {
        this.statusText = optionsResult.error || L10n.t('app.string.options_load_failed');
      }
      const versionResult = await api.getVersion();
      if (versionResult.success && versionResult.data !== undefined) {
        this.syncthingCoreVersion = this.getDisplayCoreVersion(versionResult.data);
      } else {
        this.syncthingCoreVersion = Constants.SYNCTHING_CORE_FALLBACK_VERSION;
      }
    } catch (err) {
      Logger.e(TAG, `Failed to load settings: ${JSON.stringify(err)}`);
      this.syncthingCoreVersion = Constants.SYNCTHING_CORE_FALLBACK_VERSION;
      this.statusText = L10n.t('app.string.settings_load_failed');
    } finally {
      this.isLoading = false;
    }
  }

  private getDisplayCoreVersion(version: SystemVersion): string {
    const realVersion = version.version !== undefined && version.version.length > 0
      && version.version !== 'unknown-dev' && version.version.indexOf('unknown-dev') < 0
      ? version.version
      : '';
    const realLongVersion = version.longVersion !== undefined && version.longVersion.length > 0
      && version.longVersion.indexOf('unknown-dev') < 0
      ? version.longVersion
      : '';
    return realVersion.length > 0 ? realVersion : (realLongVersion.length > 0 ? realLongVersion : Constants.SYNCTHING_CORE_FALLBACK_VERSION);
  }

  build() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle }) {
          Image($r('sys.media.ohos_ic_public_arrow_left'))
            .width(24)
            .height(24)
            .fillColor('#333')
        }
        .width(40)
        .height(40)
        .backgroundColor('#F0F0F0')
        .onClick(() => {
          this.getUIContext().getRouter().back();
        })

        Text(L10n.t('app.string.settings'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 })
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color('#007AFF')
          Text(L10n.t('app.string.loading_settings'))
            .fontSize(14)
            .fontColor('#777')
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ListItemGroup({ header: this.sectionHeader(L10n.t('app.string.syncthing_connections')) }) {
            ListItem() {
              this.textItem(L10n.t('app.string.listen_addresses'), L10n.t('app.string.listen_addresses_desc'), this.listenAddressesText, (value: string) => {
                this.listenAddressesText = value;
              }, () => this.saveOptions())
            }

            ListItem() {
              this.textItem(L10n.t('app.string.max_receive_kbps'), L10n.t('app.string.max_receive_unlimited'), this.maxRecvKbpsText, (value: string) => {
                this.maxRecvKbpsText = this.normalizeNumber(value);
              }, () => this.saveOptions())
            }

            ListItem() {
              this.textItem(L10n.t('app.string.max_send_kbps'), L10n.t('app.string.max_receive_unlimited'), this.maxSendKbpsText, (value: string) => {
                this.maxSendKbpsText = this.normalizeNumber(value);
              }, () => this.saveOptions())
            }

            ListItem() {
              this.toggleItem(L10n.t('app.string.limit_bandwidth_lan'), L10n.t('app.string.limit_bandwidth_lan_desc'), this.limitBandwidthInLan, (value) => {
                this.limitBandwidthInLan = value;
                this.saveOptions();
              })
            }
          }
          .width('100%')

          ListItemGroup({ header: this.sectionHeader(L10n.t('app.string.discovery_relay')) }) {
            ListItem() {
              this.toggleItem(L10n.t('app.string.nat_traversal'), L10n.t('app.string.nat_traversal_desc'), this.natEnabled, (value) => {
                this.natEnabled = value;
                this.saveOptions();
              })
            }

            ListItem() {
              this.toggleItem(L10n.t('app.string.local_discovery'), L10n.t('app.string.local_discovery_desc'), this.localDiscovery, (value) => {
                this.localDiscovery = value;
                this.saveOptions();
              })
            }

            ListItem() {
              this.toggleItem(L10n.t('app.string.global_discovery'), L10n.t('app.string.global_discovery_desc'), this.globalDiscovery, (value) => {
                this.globalDiscovery = value;
                this.saveOptions();
              })
            }

            ListItem() {
              this.toggleItem(L10n.t('app.string.relays_enabled'), L10n.t('app.string.relays_enabled_desc'), this.relaysEnabled, (value) => {
                this.relaysEnabled = value;
                this.saveOptions();
              })
            }

            ListItem() {
              this.textItem(L10n.t('app.string.global_announce_servers'), L10n.t('app.string.listen_addresses_desc'), this.globalServersText, (value: string) => {
                this.globalServersText = value;
              }, () => this.saveOptions())
            }
          }
          .width('100%')

          ListItemGroup({ header: this.sectionHeader(L10n.t('app.string.run_conditions')) }) {
            ListItem() {
              this.navActionItem(L10n.t('app.string.sync_conditions'), L10n.t('app.string.sync_conditions_summary'), 'pages/SyncConditionsPage')
            }

            ListItem() {
              this.toggleItem(L10n.t('app.string.run_on_wifi'), L10n.t('app.string.run_on_wifi_desc'), this.runOnWifi, (value) => {
                this.runOnWifi = value;
                this.saveLocalBoolean(Constants.PREF_RUN_ON_WIFI, value, L10n.t('app.string.run_on_wifi_saved'));
              })
            }

            ListItem() {
              this.toggleItem(L10n.t('app.string.run_on_mobile_data'), L10n.t('app.string.run_on_mobile_data_desc'), this.runOnMobileData, (value) => {
                this.runOnMobileData = value;
                this.saveLocalBoolean(Constants.PREF_RUN_ON_MOBILE_DATA, value, L10n.t('app.string.run_on_mobile_data_saved'));
              })
            }
          }
          .width('100%')

          ListItemGroup({ header: this.sectionHeader(L10n.t('app.string.debug')) }) {
            ListItem() {
              this.toggleItem(L10n.t('app.string.verbose_logging'), L10n.t('app.string.verbose_logging_desc'), this.verboseLog, (value) => {
                this.verboseLog = value;
                Logger.setVerboseLog(value);
                this.saveLocalBoolean(Constants.PREF_VERBOSE_LOG, value, L10n.t('app.string.verbose_logging_saved'));
              })
            }
          }
          .width('100%')

          ListItemGroup({ header: this.sectionHeader(L10n.t('app.string.app')) }) {
            ListItem() {
              this.languageItem()
            }
            ListItem() {
              this.exitItem()
            }
          }
          .width('100%')

          if (this.statusText.length > 0) {
            ListItem() {
              Text(this.statusText)
                .fontSize(13)
                .fontColor(this.isSuccessStatus(this.statusText) ? '#34C759' : '#777')
                .width('100%')
                .padding(12)
                .borderRadius(8)
                .backgroundColor('#FFFFFF')
            }
          }

          ListItemGroup({ header: this.sectionHeader(L10n.t('app.string.about')) }) {
            ListItem() {
              this.infoItem(L10n.t('app.string.app_version'), '2.0.0')
            }

            ListItem() {
              this.infoItem(L10n.t('app.string.syncthing_core'), this.syncthingCoreVersion.length > 0 ? this.syncthingCoreVersion : '-')
            }
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
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
        .enabled(!this.isSaving)
        .onChange((isOn: boolean) => {
          onChange(isOn);
        })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .borderRadius(12)
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
    .borderRadius(12)
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
        .enabled(!this.isSaving)
        .fontSize(14)
        .backgroundColor('#F5F7FA')
        .borderRadius(8)
        .onChange(onChange)
        .onSubmit(() => onSubmit())
      Button(this.isSaving ? L10n.t('app.string.saving') : L10n.t('app.string.save'))
        .height(32)
        .enabled(!this.isSaving)
        .backgroundColor('#E9EEF5')
        .fontColor('#007AFF')
        .onClick(onSubmit)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
  }

  @Builder
  navItem(title: string, value: string) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontColor('#333')
        .layoutWeight(1)

      Row({ space: 4 }) {
        Text(value)
          .fontSize(14)
          .fontColor('#999')
      }
    }
    .width('100%')
    .padding({ top: 14, bottom: 14, left: 16, right: 16 })
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
  }

  @Builder
  navActionItem(title: string, value: string, url: string) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontColor('#333')
        .layoutWeight(1)

      Text(value)
        .fontSize(14)
        .fontColor('#999')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 14, bottom: 14, left: 16, right: 16 })
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
    .onClick(() => {
      this.getUIContext().getRouter().pushUrl({ url });
    })
  }

  @Builder
  infoItem(title: string, value: string) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontColor('#333')
        .layoutWeight(1)

      Text(value)
        .fontSize(14)
        .fontColor('#999')
    }
    .width('100%')
    .padding({ top: 14, bottom: 14, left: 16, right: 16 })
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
  }

  @Builder
  languageItem() {
    Row() {
      Column({ space: 2 }) {
        Text(L10n.t('app.string.language'))
          .fontSize(16)
          .fontColor('#333')
        Text(L10n.t('app.string.language_desc'))
          .fontSize(12)
          .fontColor('#999')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(this.currentLanguageDisplay)
        .fontSize(14)
        .fontColor('#007AFF')
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
    .onClick(() => this.changeLanguage())
  }

  private getLanguageDisplay(): string {
    const pref = this.lastLanguagePref;
    if (pref === 'zh-CN') return '中文';
    if (pref === 'en-US') return 'English';
    return L10n.t('app.string.language_follow_system');
  }

  private async changeLanguage(): Promise<void> {
    const ctx = this.getUIContext();
    try {
      const result = await ctx.getPromptAction().showActionMenu({
        title: L10n.t('app.string.language'),
        buttons: [
          { text: L10n.t('app.string.language_follow_system'), color: '#007AFF' },
          { text: 'English', color: '#007AFF' },
          { text: '中文', color: '#007AFF' }
        ]
      });
      if (result === undefined || result.index === undefined) {
        return;
      }
      // Order: 0=跟随系统, 1=English, 2=中文
      const pref = ['system', 'en-US', 'zh-CN'][result.index] || 'system';
      await this.preferencesManager.putString(Constants.PREF_APP_LANGUAGE, pref);
      this.lastLanguagePref = pref;
      L10n.setLocale(pref);
      // Reload the whole app so ALL pages (not just Settings) re-render.
      ctx.getRouter().clear();
      ctx.getRouter().pushUrl({ url: 'pages/MainPage' });
      Logger.i(TAG, `Language changed to: ${pref}`);
    } catch (err) {
      Logger.w(TAG, `changeLanguage: ${JSON.stringify(err)}`);
    }
  }

  @Builder
  exitItem() {
    Row() {
      Column({ space: 2 }) {
        Text(L10n.t('app.string.exit'))
          .fontSize(16)
          .fontColor('#FF3B30')

        Text(L10n.t('app.string.exit_app_desc'))
          .fontSize(12)
          .fontColor('#999')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(this.isExiting ? L10n.t('app.string.exiting') : L10n.t('app.string.exit'))
        .height(32)
        .enabled(!this.isExiting)
        .backgroundColor('#FFF1F0')
        .fontColor('#FF3B30')
        .onClick(() => this.exitApplication())
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
  }

  private applyOptions(options: Options): void {
    this.options = options;
    this.listenAddressesText = this.joinValues(options.listenAddresses);
    this.globalServersText = this.joinValues(options.globalAnnounceServers);
    this.maxRecvKbpsText = options.maxRecvKbps.toString();
    this.maxSendKbpsText = options.maxSendKbps.toString();
    this.natEnabled = options.natEnabled;
    this.localDiscovery = options.localAnnounceEnabled;
    this.globalDiscovery = options.globalAnnounceEnabled;
    this.relaysEnabled = options.relaysEnabled;
    this.limitBandwidthInLan = options.limitBandwidthInLan;
  }

  private isSuccessStatus(text: string): boolean {
    return text === L10n.t('app.string.options_saved')
      || text === L10n.t('app.string.settings_saved')
      || text === L10n.t('app.string.run_on_wifi_saved')
      || text === L10n.t('app.string.run_on_mobile_data_saved')
      || text === L10n.t('app.string.verbose_logging_saved');
  }

  private async loadLocalPreferences(): Promise<void> {
    this.runOnWifi = await this.preferencesManager.getBoolean(Constants.PREF_RUN_ON_WIFI, true);
    this.runOnMobileData = await this.preferencesManager.getBoolean(Constants.PREF_RUN_ON_MOBILE_DATA, false);
    this.verboseLog = await this.preferencesManager.getBoolean(Constants.PREF_VERBOSE_LOG, false);
  }

  private async saveLocalBoolean(key: string, value: boolean, message: string): Promise<void> {
    await this.preferencesManager.putBoolean(key, value);
    this.statusText = message;
  }

  private async saveOptions(): Promise<void> {
    if (this.restApi === null || this.options === null) {
      this.statusText = L10n.t('app.string.syncthing_not_ready');
      return;
    }
    this.isSaving = true;
    try {
      const next = this.options;
      next.listenAddresses = this.splitValues(this.listenAddressesText, 'default');
      next.globalAnnounceServers = this.splitValues(this.globalServersText, 'default');
      next.maxRecvKbps = this.parsePositiveInt(this.maxRecvKbpsText);
      next.maxSendKbps = this.parsePositiveInt(this.maxSendKbpsText);
      next.natEnabled = this.natEnabled;
      next.localAnnounceEnabled = this.localDiscovery;
      next.globalAnnounceEnabled = this.globalDiscovery;
      next.relaysEnabled = this.relaysEnabled;
      next.limitBandwidthInLan = this.limitBandwidthInLan;

      const result = await this.restApi.putOptions(next);
      if (!result.success) {
        this.statusText = result.error || L10n.t('app.string.options_save_failed');
        this.showToast(this.statusText);
        return;
      }
      const verify = await this.restApi.getOptions();
      if (verify.success && verify.data !== undefined) {
        this.applyOptions(verify.data);
        this.statusText = L10n.t('app.string.options_saved');
        this.showToast(L10n.t('app.string.settings_saved'));
      } else {
        this.statusText = L10n.t('app.string.options_saved_verify_failed');
      }
    } catch (err) {
      Logger.e(TAG, `Failed to save options: ${JSON.stringify(err)}`);
      this.statusText = L10n.t('app.string.options_save_failed');
      this.showToast(this.statusText);
    } finally {
      this.isSaving = false;
    }
  }

  private async exitApplication(): Promise<void> {
    if (this.isExiting) {
      return;
    }
    this.isExiting = true;
    this.statusText = L10n.t('app.string.exiting');
    try {
      const service = ServiceLocator.get<SyncthingService>(SERVICE_NAMES.SYNCTHING_SERVICE);
      if (service === undefined) {
        this.statusText = L10n.t('app.string.syncthing_not_ready');
        this.isExiting = false;
        return;
      }
      await service.exitApplication();
    } catch (err) {
      Logger.e(TAG, `Failed to exit application: ${JSON.stringify(err)}`);
      this.statusText = L10n.t('app.string.exit_failed');
      this.showToast(this.statusText);
      this.isExiting = false;
    }
  }

  private joinValues(values: string[]): string {
    if (values.length === 0) {
      return 'default';
    }
    return values.join(', ');
  }

  private splitValues(value: string, fallback: string): string[] {
    const pieces = value.split(',');
    const result: string[] = [];
    for (let i = 0; i < pieces.length; i++) {
      const item = pieces[i].trim();
      if (item.length > 0) {
        result.push(item);
      }
    }
    if (result.length === 0) {
      result.push(fallback);
    }
    return result;
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

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (err) {
      Logger.w(TAG, `Failed to show toast: ${JSON.stringify(err)}`);
    }
  }
}
