export class Constants {
  static readonly FILENAME_SYNCTHING_BINARY: string = 'libsyncthingnative.so';
  static readonly FILENAME_STIGNORE: string = '.stignore';
  static readonly FILENAME_STFOLDER: string = '.stfolder';
  static readonly FOLDER_NAME_STVERSIONS: string = '.stversions';

  static readonly PREF_RUN_ON_MOBILE_DATA: string = 'run_on_mobile_data';
  static readonly PREF_RUN_ON_ROAMING: string = 'run_on_roaming';
  static readonly PREF_RUN_ON_WIFI: string = 'run_on_wifi';
  static readonly PREF_RUN_ON_METERED_WIFI: string = 'run_on_metered_wifi';
  static readonly PREF_USE_WIFI_SSID_WHITELIST: string = 'use_wifi_whitelist';
  static readonly PREF_WIFI_SSID_WHITELIST: string = 'wifi_ssid_whitelist';
  static readonly PREF_POWER_SOURCE: string = 'power_source';

  static readonly POWER_SOURCE_CHARGER_BATTERY: string = 'ac_and_battery_power';
  static readonly POWER_SOURCE_CHARGER: string = 'ac_power';
  static readonly POWER_SOURCE_BATTERY: string = 'battery_power';

  static readonly PREF_RESPECT_BATTERY_SAVING: string = 'respect_battery_saving';
  static readonly PREF_RESPECT_MASTER_SYNC: string = 'respect_master_sync';
  static readonly PREF_RUN_IN_FLIGHT_MODE: string = 'run_in_flight_mode';
  static readonly PREF_RUN_ON_TIME_SCHEDULE: string = 'run_on_time_schedule';
  static readonly PREF_SYNC_DURATION_MINUTES: string = 'sync_duration_minutes';
  static readonly PREF_SLEEP_INTERVAL_MINUTES: string = 'sleep_interval_minutes';

  static readonly PREF_APP_THEME: string = 'app_theme';
  static readonly PREF_EXPERT_MODE: string = 'expert_mode';
  static readonly PREF_START_INTO_WEB_GUI: string = 'start_into_web_gui';

  static readonly PREF_START_SERVICE_ON_BOOT: string = 'always_run_in_background';
  static readonly PREF_EXIT_REQUESTED: string = 'exit_requested';
  static readonly PREF_BROADCAST_SERVICE_CONTROL: string = 'broadcast_service_control';
  static readonly PREF_ALLOW_OVERWRITE_FILES: string = 'allow_overwrite_files';
  // A-3 (2026-08-20): persist latest system suspend reason/message for diagnostics.
  static readonly PREF_BACKGROUND_SUSPEND_REASON: string = 'background_suspend_reason';
  static readonly PREF_BACKGROUND_SUSPEND_MESSAGE: string = 'background_suspend_message';

  static readonly PREF_WEBUI_USERNAME: string = 'webui_username';
  static readonly PREF_WEBUI_PASSWORD: string = 'webui_password';
  static readonly PREF_WEBUI_API_KEY: string = 'webui_api_key';
  static readonly DEFAULT_WEBUI_API_KEY: string = 'syncthing-harmony-local-api-key';

  static readonly PREF_BACKUP_REL_PATH_TO_ZIP: string = 'backup_rel_path_to_zip';
  static readonly PREF_BACKUP_PASSWORD: string = 'backup_password';

  static readonly PREF_VERBOSE_LOG: string = 'verbose_log';
  static readonly PREF_ENVIRONMENT_VARIABLES: string = 'environment_variables';
  static readonly PREF_DEBUG_FACILITIES_ENABLED: string = 'debug_facilities_enabled';
  // i18n (2026-08-19): app language preference ('system' | 'zh-CN' | 'en-US').
  static readonly PREF_APP_LANGUAGE: string = 'app_language';
  static readonly PREF_APP_LANGUAGE_SYSTEM: string = 'system';
  // A2 (2026-08-18): persisted FOLDER-picker grant (public-directory sync).
  static readonly PREF_WORK_FOLDER_URI: string = 'work_folder_uri';
  static readonly PREF_WORK_FOLDER_PATH: string = 'work_folder_path';
  // A2 (2026-08-18): unified sync folder in Download dir (user_grant permission).
  static readonly PREF_HAS_REQUESTED_DOWNLOAD_PERM: string = 'has_requested_download_perm';
  static readonly UNIFIED_SYNC_SUBDIR: string = 'Syncthing';
  static readonly UNIFIED_SYNC_FOLDER_ID: string = 'sync-public-download';

  static readonly PREF_USE_TOR: string = 'use_tor';
  static readonly PREF_SOCKS_PROXY_ADDRESS: string = 'socks_proxy_address';
  static readonly PREF_HTTP_PROXY_ADDRESS: string = 'http_proxy_address';

  static readonly PREF_OBJECT_PREFIX_FOLDER: string = 'sc_folder_';
  static readonly PREF_OBJECT_PREFIX_DEVICE: string = 'sc_device_';

  static readonly PREF_ENABLE_SYNCTHING_CAMERA: string = 'enableSyncthingCamera';
  static readonly PREF_KNOWN_WIFI_SSIDS: string = 'knownWifiSsids';
  static readonly PREF_LAST_BINARY_VERSION: string = 'lastBinaryVersion';
  static readonly PREF_LOCAL_DEVICE_ID: string = 'localDeviceID';
  static readonly PREF_LAST_RUN_TIME: string = 'last_run_time';

  static readonly PREF_CACHE_DEVICE_LASTSEEN_PREFIX: string = 'device_lastseen_';

  static readonly syncthingCameraFolderId: string = 'syncthingAndroidCamera-52x89-60es4';

  static readonly PREF_BTNSTATE_FORCE_START_STOP: string = 'btnStateForceStartStop';
  static readonly BTNSTATE_NO_FORCE_START_STOP: number = 0;
  static readonly BTNSTATE_FORCE_START: number = 1;
  static readonly BTNSTATE_FORCE_STOP: number = 2;

  static readonly PREF_EVENT_PROCESSOR_LAST_SYNC_ID: string = 'last_sync_id';
  static readonly PREF_DEBUG_FACILITIES_AVAILABLE: string = 'debug_facilities_available';
  static readonly FOLDER_TYPE_SEND_ONLY: string = 'sendonly';
  static readonly FOLDER_TYPE_SEND_RECEIVE: string = 'sendreceive';
  static readonly FOLDER_TYPE_RECEIVE_ONLY: string = 'receiveonly';
  static readonly FOLDER_TYPE_RECEIVE_ENCRYPTED: string = 'receiveencrypted';

  static readonly DEFAULT_WEBGUI_TCP_PORT: number = 8384;
  static readonly DEFAULT_DATA_TCP_PORT: number = 22000;

  // Upstream xinjinshao/SyncthingHarmonyOSNext labels the bundled Syncthing core as v1.31.0.
  // The REST /rest/system/version may report "unknown-dev" because the Go core is built
  // without -X version ldflags; keep a source-verified fallback for the UI.
  static readonly SYNCTHING_CORE_FALLBACK_VERSION: string = 'v1.31.0';

  static readonly REST_UPDATE_INTERVAL_MS: number = 3000;
  static readonly GUI_UPDATE_INTERVAL_MS: number = 1000;

  static readonly CONFIG_FILE: string = 'config.xml';
  static readonly CONFIG_TEMP_FILE: string = 'config.xml.tmp';
  static readonly PUBLIC_KEY_FILE: string = 'cert.pem';
  static readonly PRIVATE_KEY_FILE: string = 'key.pem';
  static readonly INDEX_DB_FOLDER: string = 'index-v2';
  static readonly HTTPS_CERT_FILE: string = 'https-cert.pem';
  static readonly HTTPS_KEY_FILE: string = 'https-key.pem';
  static readonly SHARED_PREFS_FILE: string = 'sharedpreferences.dat';

  static readonly LOG_FILE_ANDROID: string = 'android.log';
  static readonly LOG_FILE_SYNCTHING: string = 'syncthing.log';

  static readonly SYNCTHING_BASE_URL: string = 'http://127.0.0.1:8384';

  static readonly PREFERENCES_STORE_NAME: string = 'syncthing_preferences';

  static DYN_PREF_OBJECT_CUSTOM_SYNC_CONDITIONS(objectPrefixAndId: string): string {
    return `${objectPrefixAndId}_custom_sync_conditions`;
  }

  static DYN_PREF_OBJECT_FOLDER_RUN_SCRIPT(folderId: string): string {
    return `${Constants.PREF_OBJECT_PREFIX_FOLDER}${folderId}_run_script`;
  }

  static DYN_PREF_OBJECT_SYNC_ON_WIFI(objectPrefixAndId: string): string {
    return `${objectPrefixAndId}_${Constants.PREF_RUN_ON_WIFI}`;
  }

  static DYN_PREF_OBJECT_USE_WIFI_SSID_WHITELIST(objectPrefixAndId: string): string {
    return `${objectPrefixAndId}_${Constants.PREF_USE_WIFI_SSID_WHITELIST}`;
  }

  static DYN_PREF_OBJECT_SELECTED_WHITELIST_SSID(objectPrefixAndId: string): string {
    return `${objectPrefixAndId}_${Constants.PREF_WIFI_SSID_WHITELIST}`;
  }

  static DYN_PREF_OBJECT_SYNC_ON_METERED_WIFI(objectPrefixAndId: string): string {
    return `${objectPrefixAndId}_${Constants.PREF_RUN_ON_METERED_WIFI}`;
  }

  static DYN_PREF_OBJECT_SYNC_ON_MOBILE_DATA(objectPrefixAndId: string): string {
    return `${objectPrefixAndId}_${Constants.PREF_RUN_ON_MOBILE_DATA}`;
  }

  static DYN_PREF_OBJECT_SYNC_ON_POWER_SOURCE(objectPrefixAndId: string): string {
    return `${objectPrefixAndId}_${Constants.PREF_POWER_SOURCE}`;
  }

  static getConfigFilePath(appFilesDir: string): string {
    return `${appFilesDir}/${Constants.CONFIG_FILE}`;
  }

  static getConfigTempFilePath(appFilesDir: string): string {
    return `${appFilesDir}/${Constants.CONFIG_TEMP_FILE}`;
  }

  static getPublicKeyFilePath(appFilesDir: string): string {
    return `${appFilesDir}/${Constants.PUBLIC_KEY_FILE}`;
  }

  static getPrivateKeyFilePath(appFilesDir: string): string {
    return `${appFilesDir}/${Constants.PRIVATE_KEY_FILE}`;
  }

  static getHttpsCertFilePath(appFilesDir: string): string {
    return `${appFilesDir}/${Constants.HTTPS_CERT_FILE}`;
  }

  static getHttpsKeyFilePath(appFilesDir: string): string {
    return `${appFilesDir}/${Constants.HTTPS_KEY_FILE}`;
  }

  static getIndexDbFolderPath(appFilesDir: string): string {
    return `${appFilesDir}/${Constants.INDEX_DB_FOLDER}`;
  }

  static getSyncthingLogFilePath(appFilesDir: string): string {
    return `${appFilesDir}/${Constants.LOG_FILE_SYNCTHING}`;
  }

  static getAndroidLogFilePath(cacheDir: string): string {
    return `${cacheDir}/${Constants.LOG_FILE_ANDROID}`;
  }

  static getSyncthingBinaryPath(nativeLibraryDir: string): string {
    if (nativeLibraryDir.length === 0) {
      return Constants.FILENAME_SYNCTHING_BINARY;
    }
    return `${nativeLibraryDir}/${Constants.FILENAME_SYNCTHING_BINARY}`;
  }
}
