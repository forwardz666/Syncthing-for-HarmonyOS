import { ConfigurationConstant } from '@kit.AbilityKit';
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
            .fillColor($r('app.color.text_primary'))
        }
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.background_secondary'))
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
            .color($r('app.color.primary'))
          Text(L10n.t('app.string.loading_settings'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ListItemGroup({ header: this.sectionHeader(L10n.t('app.string.syncthing_connections')) }) {
            ListItem() {
              Column({ space: 0 }) {
                this.textItem(L10n.t('app.string.listen_addresses'), L10n.t('app.string.listen_addresses_desc'), this.listenAddressesText, (value: string) => {
                  this.listenAddressesText = value;
                }, () => this.saveOptions())
                this.groupDivider()
                this.textItem(L10n.t('app.string.max_receive_kbps'), L10n.t('app.string.max_receive_unlimited'), this.maxRecvKbpsText, (value: string) => {
                  this.maxRecvKbpsText = this.normalizeNumber(value);
                }, () => this.saveOptions())
                this.groupDivider()
                this.textItem(L10n.t('app.string.max_send_kbps'), L10n.t('app.string.max_receive_unlimited'), this.maxSendKbpsText, (value: string) => {
                  this.maxSendKbpsText = this.normalizeNumber(value);
                }, () => this.saveOptions())
                this.groupDivider()
                this.toggleItem(L10n.t('app.string.limit_bandwidth_lan'), L10n.t('app.string.limit_bandwidth_lan_desc'), this.limitBandwidthInLan, (value) => {
                  this.limitBandwidthInLan = value;
                  this.saveOptions();
                })
              }
              .width('100%')
              .borderRadius(12)
              .backgroundColor($r('app.color.card_background'))
              .clip(true)
            }
          }
          .width('100%')

          ListItemGroup({ header: this.sectionHeader(L10n.t('app.string.discovery_relay')) }) {
            ListItem() {
              Column({ space: 0 }) {
                this.toggleItem(L10n.t('app.string.nat_traversal'), L10n.t('app.string.nat_traversal_desc'), this.natEnabled, (value) => {
                  this.natEnabled = value;
                  this.saveOptions();
                })
                this.groupDivider()
                this.toggleItem(L10n.t('app.string.local_discovery'), L10n.t('app.string.local_discovery_desc'), this.localDiscovery, (value) => {
                  this.localDiscovery = value;
                  this.saveOptions();
                })
                this.groupDivider()
                this.toggleItem(L10n.t('app.string.global_discovery'), L10n.t('app.string.global_discovery_desc'), this.globalDiscovery, (value) => {
                  this.globalDiscovery = value;
                  this.saveOptions();
                })
                this.groupDivider()
                this.toggleItem(L10n.t('app.string.relays_enabled'), L10n.t('app.string.relays_enabled_desc'), this.relaysEnabled, (value) => {
                  this.relaysEnabled = value;
                  this.saveOptions();
                })
                this.groupDivider()
                this.textItem(L10n.t('app.string.global_announce_servers'), L10n.t('app.string.listen_addresses_desc'), this.globalServersText, (value: string) => {
                  this.globalServersText = value;
                }, () => this.saveOptions())
              }
              .width('100%')
              .borderRadius(12)
              .backgroundColor($r('app.color.card_background'))
              .clip(true)
            }
          }
          .width('100%')

          ListItemGroup({ header: this.sectionHeader(L10n.t('app.string.run_conditions')) }) {
            ListItem() {
              Column({ space: 0 }) {
                this.navActionItem(L10n.t('app.string.sync_conditions'), L10n.t('app.string.sync_conditions_summary'), 'pages/SyncConditionsPage')
                this.groupDivider()
                this.toggleItem(L10n.t('app.string.run_on_wifi'), L10n.t('app.string.run_on_wifi_desc'), this.runOnWifi, (value) => {
                  this.runOnWifi = value;
                  this.saveLocalBoolean(Constants.PREF_RUN_ON_WIFI, value, L10n.t('app.string.run_on_wifi_saved'));
                })
                this.groupDivider()
                this.toggleItem(L10n.t('app.string.run_on_mobile_data'), L10n.t('app.string.run_on_mobile_data_desc'), this.runOnMobileData, (value) => {
                  this.runOnMobileData = value;
                  this.saveLocalBoolean(Constants.PREF_RUN_ON_MOBILE_DATA, value, L10n.t('app.string.run_on_mobile_data_saved'));
                })
              }
              .width('100%')
              .borderRadius(12)
              .backgroundColor($r('app.color.card_background'))
              .clip(true)
            }
          }
          .width('100%')

          ListItemGroup({ header: this.sectionHeader(L10n.t('app.string.debug')) }) {
            ListItem() {
              Column({ space: 0 }) {
                this.toggleItem(L10n.t('app.string.verbose_logging'), L10n.t('app.string.verbose_logging_desc'), this.verboseLog, (value) => {
                  this.verboseLog = value;
                  Logger.setVerboseLog(value);
                  this.saveLocalBoolean(Constants.PREF_VERBOSE_LOG, value, L10n.t('app.string.verbose_logging_saved'));
                })
              }
              .width('100%')
              .borderRadius(12)
              .backgroundColor($r('app.color.card_background'))
              .clip(true)
            }
          }
          .width('100%')

          ListItemGroup({ header: this.sectionHeader(L10n.t('app.string.app')) }) {
            ListItem() {
              Column({ space: 0 }) {
                this.themeItem()
                this.groupDivider()
                this.languageItem()
                this.groupDivider()
                this.exitItem()
              }
              .width('100%')
              .borderRadius(12)
              .backgroundColor($r('app.color.card_background'))
              .clip(true)
            }
          }
          .width('100%')

          if (this.statusText.length > 0) {
            ListItem() {
              Text(this.statusText)
                .fontSize(13)
                .fontColor(this.isSuccessStatus(this.statusText) ? $r('app.color.success') : $r('app.color.text_secondary'))
                .width('100%')
                .padding(12)
                .borderRadius(8)
                .backgroundColor($r('app.color.card_background'))
            }
          }

          ListItemGroup({ header: this.sectionHeader(L10n.t('app.string.about')) }) {
            ListItem() {
              Column({ space: 0 }) {
                this.infoItem(L10n.t('app.string.app_version'), '2.0.2')
                this.groupDivider()
                this.infoItem(L10n.t('app.string.syncthing_core'), this.syncthingCoreVersion.length > 0 ? this.syncthingCoreVersion : '-')
              }
              .width('100%')
              .borderRadius(12)
              .backgroundColor($r('app.color.card_background'))
              .clip(true)
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
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  sectionHeader(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
      .fontWeight(FontWeight.Bold)
      .margin({ left: 8, top: 16, bottom: 4 })
  }

  @Builder
  groupDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('app.color.background_neutral'))
      .margin({ left: 16, right: 16 })
  }

  @Builder
  toggleItem(title: string, subtitle: string, value: boolean, onChange: (value: boolean) => void) {
    Row() {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))

        Text(subtitle)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
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
  }

  @Builder
  pendingToggleItem(title: string, subtitle: string, value: boolean) {
    Row() {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(16)
          .fontColor($r('app.color.text_tertiary'))
          .decoration({ type: TextDecorationType.LineThrough })

        Text(subtitle)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: value })
        .enabled(false)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
  }

  @Builder
  textItem(title: string, subtitle: string, value: string, onChange: (value: string) => void, onSubmit: () => void) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
      Text(subtitle)
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
      TextInput({ text: value })
        .height(40)
        .enabled(!this.isSaving)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor($r('app.color.background_secondary'))
        .borderRadius(8)
        .onChange(onChange)
        .onSubmit(() => onSubmit())
      Button(this.isSaving ? L10n.t('app.string.saving') : L10n.t('app.string.save'))
        .height(32)
        .enabled(!this.isSaving)
        .backgroundColor($r('app.color.button_secondary_background'))
        .fontColor($r('app.color.primary'))
        .onClick(onSubmit)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
  }

  @Builder
  navItem(title: string, value: string) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      Row({ space: 4 }) {
        Text(value)
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
      }
    }
    .width('100%')
    .padding({ top: 14, bottom: 14, left: 16, right: 16 })
  }

  @Builder
  navActionItem(title: string, value: string, url: string) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      Text(value)
        .fontSize(14)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 14, bottom: 14, left: 16, right: 16 })
    .onClick(() => {
      this.getUIContext().getRouter().pushUrl({ url });
    })
  }

  @Builder
  infoItem(title: string, value: string) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      Text(value)
        .fontSize(14)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .padding({ top: 14, bottom: 14, left: 16, right: 16 })
  }

  @Builder
  themeItem() {
    Row() {
      Column({ space: 2 }) {
        Text(L10n.t('app.string.theme'))
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
        Text(L10n.t('app.string.theme_desc'))
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(this.getThemeDisplay())
        .fontSize(14)
        .fontColor($r('app.color.primary'))
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .onClick(() => this.changeTheme())
  }

  @Builder
  languageItem() {
    Row() {
      Column({ space: 2 }) {
        Text(L10n.t('app.string.language'))
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
        Text(L10n.t('app.string.language_desc'))
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(this.getLanguageDisplay())
        .fontSize(14)
        .fontColor($r('app.color.primary'))
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .onClick(() => this.changeLanguage())
  }

  private getThemeDisplay(): string {
    if (this.appTheme === 'light') {
      return L10n.t('app.string.theme_light');
    }
    if (this.appTheme === 'dark') {
      return L10n.t('app.string.theme_dark');
    }
    return L10n.t('app.string.theme_follow_system');
  }

  private async changeTheme(): Promise<void> {
    const ctx = this.getUIContext();
    try {
      const result = await ctx.getPromptAction().showActionMenu({
        title: L10n.t('app.string.theme'),
        buttons: [
          { text: L10n.t('app.string.theme_follow_system'), color: $r('app.color.primary') },
          { text: L10n.t('app.string.theme_light'), color: $r('app.color.primary') },
          { text: L10n.t('app.string.theme_dark'), color: $r('app.color.primary') }
        ]
      });
      if (result === undefined || result.index === undefined) {
        return;
      }
      const theme = ['system', 'light', 'dark'][result.index] || 'system';
      this.appTheme = theme;
      await this.preferencesManager.putString(Constants.PREF_APP_THEME, theme);
      this.applyAppTheme(theme);
      this.statusText = L10n.t('app.string.theme_saved');
      this.showToast(this.statusText);
    } catch (err) {
      Logger.w(TAG, `changeTheme: ${JSON.stringify(err)}`);
    }
  }

  private applyAppTheme(theme: string): void {
    try {
      const host = this.getUIContext().getHostContext();
      if (host === undefined) {
        return;
      }
      const appContext = host.getApplicationContext();
      if (appContext === undefined) {
        return;
      }
      if (theme === 'light') {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else if (theme === 'dark') {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
    } catch (err) {
      Logger.w(TAG, `applyAppTheme: ${JSON.stringify(err)}`);
    }
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
          { text: L10n.t('app.string.language_follow_system'), color: $r('app.color.primary') },
          { text: 'English', color: $r('app.color.primary') },
          { text: '中文', color: $r('app.color.primary') }
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
          .fontColor($r('app.color.danger'))

        Text(L10n.t('app.string.exit_app_desc'))
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(this.isExiting ? L10n.t('app.string.exiting') : L10n.t('app.string.exit'))
        .height(32)
        .enabled(!this.isExiting)
        .backgroundColor($r('app.color.danger_background'))
        .fontColor($r('app.color.danger'))
        .onClick(() => this.exitApplication())
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
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
      || text === L10n.t('app.string.theme_saved')
      || text === L10n.t('app.string.run_on_wifi_saved')
      || text === L10n.t('app.string.run_on_mobile_data_saved')
      || text === L10n.t('app.string.verbose_logging_saved');
  }

  private async loadLocalPreferences(): Promise<void> {
    this.appTheme = await this.preferencesManager.getAppTheme();
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
