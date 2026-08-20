import { preferences } from '@kit.ArkData';
import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { Constants } from '../service/Constants';
import { PreferenceValue, RunCondition, SharedPreferenceEntry, SharedPreferencesData } from '../types/index';

const TAG = 'PreferencesManager';
const STORE_NAME = Constants.PREFERENCES_STORE_NAME;

export class PreferencesManager {
  private static instance: PreferencesManager | undefined;
  private dataPreferences: preferences.Preferences | null = null;
  private context: Context | null = null;
  private initPromise: Promise<void> | null = null;

  static getInstance(): PreferencesManager {
    if (!PreferencesManager.instance) {
      PreferencesManager.instance = new PreferencesManager();
    }
    return PreferencesManager.instance;
  }

  async initialize(context: Context): Promise<void> {
    if (this.initPromise !== null) {
      return this.initPromise;
    }
    this.context = context;

    this.initPromise = new Promise<void>(async (resolve, reject) => {
      try {
        this.dataPreferences = await preferences.getPreferences(context, STORE_NAME);
        Logger.i(TAG, 'PreferencesManager initialized');
        resolve();
      } catch (err) {
        Logger.e(TAG, `Failed to initialize PreferencesManager: ${JSON.stringify(err)}`);
        reject(err);
      }
    });

    return this.initPromise;
  }

  private ensureInitialized(): preferences.Preferences {
    if (this.dataPreferences === null) {
      throw new Error('PreferencesManager not initialized. Call initialize() first.');
    }
    return this.dataPreferences;
  }

  async getString(key: string, defaultValue: string = ''): Promise<string> {
    try {
      const prefs = this.ensureInitialized();
      if (!await this.has(key)) {
        return defaultValue;
      }
      const value = await prefs.get(key, defaultValue);
      return value as string;
    } catch (err) {
      Logger.d(TAG, `Using default string pref '${key}'`);
      return defaultValue;
    }
  }

  async getBoolean(key: string, defaultValue: boolean = false): Promise<boolean> {
    try {
      const prefs = this.ensureInitialized();
      if (!await this.has(key)) {
        return defaultValue;
      }
      const value = await prefs.get(key, defaultValue);
      return value as boolean;
    } catch (err) {
      Logger.d(TAG, `Using default boolean pref '${key}'`);
      return defaultValue;
    }
  }

  async getNumber(key: string, defaultValue: number = 0): Promise<number> {
    try {
      const prefs = this.ensureInitialized();
      if (!await this.has(key)) {
        return defaultValue;
      }
      const value = await prefs.get(key, defaultValue);
      return value as number;
    } catch (err) {
      Logger.d(TAG, `Using default number pref '${key}'`);
      return defaultValue;
    }
  }

  async putString(key: string, value: string): Promise<void> {
    try {
      const prefs = this.ensureInitialized();
      await prefs.put(key, value);
      await prefs.flush();
    } catch (err) {
      Logger.e(TAG, `Error putting string pref '${key}': ${JSON.stringify(err)}`);
    }
  }

  async putBoolean(key: string, value: boolean): Promise<void> {
    try {
      const prefs = this.ensureInitialized();
      await prefs.put(key, value);
      await prefs.flush();
    } catch (err) {
      Logger.e(TAG, `Error putting boolean pref '${key}': ${JSON.stringify(err)}`);
    }
  }

  async putNumber(key: string, value: number): Promise<void> {
    try {
      const prefs = this.ensureInitialized();
      await prefs.put(key, value);
      await prefs.flush();
    } catch (err) {
      Logger.e(TAG, `Error putting number pref '${key}': ${JSON.stringify(err)}`);
    }
  }

  async remove(key: string): Promise<void> {
    try {
      const prefs = this.ensureInitialized();
      await prefs.delete(key);
      await prefs.flush();
    } catch (err) {
      Logger.e(TAG, `Error removing pref '${key}': ${JSON.stringify(err)}`);
    }
  }

  async has(key: string): Promise<boolean> {
    try {
      const prefs = this.ensureInitialized();
      return await prefs.has(key);
    } catch (err) {
      Logger.d(TAG, `Preference '${key}' is not set`);
      return false;
    }
  }

  async getAll(): Promise<SharedPreferencesData> {
    try {
      this.ensureInitialized();
      return new Array<SharedPreferenceEntry>();
    } catch (err) {
      Logger.e(TAG, `Error getting all prefs: ${JSON.stringify(err)}`);
      return new Array<SharedPreferenceEntry>();
    }
  }

  async clear(): Promise<void> {
    try {
      const prefs = this.ensureInitialized();
      await prefs.clear();
      await prefs.flush();
      Logger.i(TAG, 'All preferences cleared');
    } catch (err) {
      Logger.e(TAG, `Error clearing prefs: ${JSON.stringify(err)}`);
    }
  }

  async isVerboseLogEnabled(): Promise<boolean> {
    return await this.getBoolean(Constants.PREF_VERBOSE_LOG, false);
  }

  async getRunConditions(): Promise<RunCondition> {
    return {
      runOnMobileData: await this.getBoolean(Constants.PREF_RUN_ON_MOBILE_DATA, false),
      runOnRoaming: await this.getBoolean(Constants.PREF_RUN_ON_ROAMING, false),
      runOnWifi: await this.getBoolean(Constants.PREF_RUN_ON_WIFI, true),
      runOnMeteredWifi: await this.getBoolean(Constants.PREF_RUN_ON_METERED_WIFI, true),
      useWifiSsidWhitelist: await this.getBoolean(Constants.PREF_USE_WIFI_SSID_WHITELIST, false),
      wifiSsidWhitelist: await this.getString(Constants.PREF_WIFI_SSID_WHITELIST, ''),
      powerSource: await this.getString(Constants.PREF_POWER_SOURCE, Constants.POWER_SOURCE_CHARGER_BATTERY),
      respectBatterySaving: await this.getBoolean(Constants.PREF_RESPECT_BATTERY_SAVING, true),
      respectMasterSync: await this.getBoolean(Constants.PREF_RESPECT_MASTER_SYNC, true),
      runInFlightMode: await this.getBoolean(Constants.PREF_RUN_IN_FLIGHT_MODE, false),
      runOnTimeSchedule: await this.getBoolean(Constants.PREF_RUN_ON_TIME_SCHEDULE, false),
      syncDurationMinutes: await this.getNumber(Constants.PREF_SYNC_DURATION_MINUTES, 0),
      sleepIntervalMinutes: await this.getNumber(Constants.PREF_SLEEP_INTERVAL_MINUTES, 0),
      alwaysRunInBackground: await this.getBoolean(Constants.PREF_START_SERVICE_ON_BOOT, false),
    };
  }

  async getWebUiUsername(): Promise<string> {
    return await this.getString(Constants.PREF_WEBUI_USERNAME, '');
  }

  async getWebUiPassword(): Promise<string> {
    return await this.getString(Constants.PREF_WEBUI_PASSWORD, '');
  }

  async getAppTheme(): Promise<string> {
    return await this.getString(Constants.PREF_APP_THEME, 'system');
  }

  async getLocalDeviceId(): Promise<string> {
    return await this.getString(Constants.PREF_LOCAL_DEVICE_ID, '');
  }

  async setLocalDeviceId(deviceId: string): Promise<void> {
    await this.putString(Constants.PREF_LOCAL_DEVICE_ID, deviceId);
  }
}
