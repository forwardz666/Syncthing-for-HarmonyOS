import { batteryInfo, power } from '@kit.BasicServicesKit';
import { connection } from '@kit.NetworkKit';
import { Logger } from '../common/Logger';
import { EventBus, SyncthingEvents } from '../common/EventBus';
import { PreferencesManager } from '../data/PreferencesManager';
import { Constants } from './Constants';
import { RunCondition } from '../types/index';
import { BackgroundDiagnostics } from './BackgroundDiagnostics';

const TAG = 'RunConditionMonitor';

export enum RunDecision {
  SHOULD_RUN = 'shouldRun',
  SHOULD_NOT_RUN = 'shouldNotRun',
  FORCE_START = 'forceStart',
  FORCE_STOP = 'forceStop',
}

export interface RunConditionResult {
  decision: RunDecision;
  reason: string;
}

/**
 * Evaluates user-selected sync conditions against available HarmonyOS signals.
 *
 * Network, power source, battery saver, force start/stop, and timed schedule
 * checks are wired. Platform conditions that do not expose a validated HarmonyOS
 * signal stay disabled in the UI.
 */
export class RunConditionMonitor {
  private preferencesManager: PreferencesManager;
  private currentConditions: RunCondition | null = null;
  private isMonitoring: boolean = false;
  private monitorTimer: number | null = null;
  private lastResult: RunConditionResult = {
    decision: RunDecision.SHOULD_RUN,
    reason: 'Run conditions have not been evaluated yet'
  };
  private readonly MONITOR_INTERVAL_MS: number = 30000;

  constructor(preferencesManager: PreferencesManager) {
    this.preferencesManager = preferencesManager;
  }

  async startMonitoring(): Promise<void> {
    if (this.isMonitoring) {
      return;
    }
    this.isMonitoring = true;
    Logger.i(TAG, 'RunConditionMonitor started');
    await this.scheduleCheck();
  }

  stopMonitoring(): void {
    this.isMonitoring = false;
    if (this.monitorTimer !== null) {
      clearTimeout(this.monitorTimer);
      this.monitorTimer = null;
    }
    Logger.i(TAG, 'RunConditionMonitor stopped');
  }

  private async scheduleCheck(): Promise<void> {
    if (!this.isMonitoring) {
      return;
    }
    await this.checkConditions();
    this.monitorTimer = setTimeout(() => {
      this.scheduleCheck();
    }, this.MONITOR_INTERVAL_MS);
  }

  async checkConditions(): Promise<RunConditionResult> {
    try {
      this.currentConditions = await this.preferencesManager.getRunConditions();

      const forceState = await this.preferencesManager.getNumber(
        Constants.PREF_BTNSTATE_FORCE_START_STOP,
        Constants.BTNSTATE_NO_FORCE_START_STOP
      );

      if (forceState === Constants.BTNSTATE_FORCE_START) {
        return this.recordResult({
          decision: RunDecision.FORCE_START,
          reason: 'Force start requested by user'
        });
      }

      if (forceState === Constants.BTNSTATE_FORCE_STOP) {
        return this.recordResult({
          decision: RunDecision.FORCE_STOP,
          reason: 'Force stop requested by user'
        });
      }

      const shouldRun = await this.evaluateRunConditions();
      if (shouldRun) {
        EventBus.emit(SyncthingEvents.RUN_CONDITIONS_MET, null);
        return this.recordResult({
          decision: RunDecision.SHOULD_RUN,
          reason: 'All run conditions are met'
        });
      } else {
        EventBus.emit(SyncthingEvents.RUN_CONDITIONS_NOT_MET, null);
        return this.recordResult({
          decision: RunDecision.SHOULD_NOT_RUN,
          reason: this.lastResult.reason
        });
      }
    } catch (err) {
      Logger.e(TAG, `Error checking run conditions: ${JSON.stringify(err)}`);
      return this.recordResult({
        decision: RunDecision.SHOULD_NOT_RUN,
        reason: `Error: ${JSON.stringify(err)}`
      });
    }
  }

  private async evaluateRunConditions(): Promise<boolean> {
    if (!this.currentConditions) {
      return false;
    }

    const networkAllowed = await this.evaluateNetworkConditions(this.currentConditions);
    if (!networkAllowed) {
      return false;
    }

    const powerAllowed = this.evaluatePowerConditions(this.currentConditions);
    if (!powerAllowed) {
      return false;
    }

    if (this.currentConditions.runOnTimeSchedule) {
      const syncDuration = this.currentConditions.syncDurationMinutes;
      const sleepInterval = this.currentConditions.sleepIntervalMinutes;
      if (syncDuration > 0 && sleepInterval > 0) {
        const now = Date.now();
        const totalCycleMs = (syncDuration + sleepInterval) * 60 * 1000;
        const cyclePosition = now % totalCycleMs;

        if (cyclePosition >= syncDuration * 60 * 1000) {
          Logger.d(TAG, 'In sleep interval, not running');
          this.setReason('Timed schedule is currently in the sleep window');
          return false;
        }
      }
    }

    return true;
  }

  private async evaluateNetworkConditions(conditions: RunCondition): Promise<boolean> {
    if (!canIUse('SystemCapability.Communication.NetManager.Core')) {
      Logger.w(TAG, 'NetManager syscap unavailable, skipping network run-condition checks');
      return true;
    }

    try {
      const defaultNet = await connection.getDefaultNet();
      const capabilities = await connection.getNetCapabilities(defaultNet);
      const bearers: Array<connection.NetBearType> = capabilities.bearerTypes;
      const caps: Array<connection.NetCap> = capabilities.networkCap === undefined ? [] : capabilities.networkCap;
      const isWifi = this.hasBearer(bearers, connection.NetBearType.BEARER_WIFI);
      const isCellular = this.hasBearer(bearers, connection.NetBearType.BEARER_CELLULAR);
      const isUnmetered = this.hasNetCap(caps, connection.NetCap.NET_CAPABILITY_NOT_METERED);

      if (isWifi && !conditions.runOnWifi) {
        Logger.i(TAG, 'Wi-Fi network is active but Wi-Fi sync is disabled');
        this.setReason('Wi-Fi network is active but Wi-Fi sync is disabled');
        return false;
      }
      if (isWifi && !isUnmetered && !conditions.runOnMeteredWifi) {
        Logger.i(TAG, 'Metered Wi-Fi network is active but metered Wi-Fi sync is disabled');
        this.setReason('Metered Wi-Fi network is active but metered Wi-Fi sync is disabled');
        return false;
      }
      if (isCellular && !conditions.runOnMobileData) {
        Logger.i(TAG, 'Cellular network is active but mobile-data sync is disabled');
        this.setReason('Cellular network is active but mobile-data sync is disabled');
        return false;
      }
      if (!isWifi && !isCellular && !conditions.runOnMobileData && !conditions.runOnWifi) {
        Logger.i(TAG, 'Default network is neither Wi-Fi nor cellular and no network type is allowed');
        this.setReason('Default network type is not allowed');
        return false;
      }
      return true;
    } catch (err) {
      Logger.w(TAG, `Network run-condition check failed: ${JSON.stringify(err)}`);
      this.setReason(`Network condition check failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  private evaluatePowerConditions(conditions: RunCondition): boolean {
    if (!canIUse('SystemCapability.PowerManager.BatteryManager.Core')) {
      Logger.w(TAG, 'BatteryManager syscap unavailable, skipping power-source run-condition checks');
      return true;
    }

    try {
      const pluggedType = batteryInfo.pluggedType;
      const isCharging = pluggedType === batteryInfo.BatteryPluggedType.AC ||
        pluggedType === batteryInfo.BatteryPluggedType.USB ||
        pluggedType === batteryInfo.BatteryPluggedType.WIRELESS ||
        batteryInfo.chargingStatus === batteryInfo.BatteryChargeState.ENABLE ||
        batteryInfo.chargingStatus === batteryInfo.BatteryChargeState.FULL;

      if (conditions.powerSource === Constants.POWER_SOURCE_CHARGER && !isCharging) {
        this.setReason('Charging power is required but the device is on battery');
        return false;
      }
      if (conditions.powerSource === Constants.POWER_SOURCE_BATTERY && isCharging) {
        this.setReason('Battery power is required but the device is charging');
        return false;
      }
    } catch (err) {
      Logger.w(TAG, `Power-source condition check failed: ${JSON.stringify(err)}`);
      this.setReason(`Power-source condition check failed: ${JSON.stringify(err)}`);
      return false;
    }

    if (conditions.respectBatterySaving && canIUse('SystemCapability.PowerManager.PowerManager.Core')) {
      try {
        const mode = power.getPowerMode();
        if (mode === power.DevicePowerMode.MODE_POWER_SAVE ||
          mode === power.DevicePowerMode.MODE_EXTREME_POWER_SAVE ||
          mode === power.DevicePowerMode.MODE_CUSTOM_POWER_SAVE) {
          this.setReason('Power save mode is active');
          return false;
        }
      } catch (err) {
        Logger.w(TAG, `Power-save condition check failed: ${JSON.stringify(err)}`);
        this.setReason(`Power-save condition check failed: ${JSON.stringify(err)}`);
        return false;
      }
    }

    return true;
  }

  private hasBearer(bearers: Array<connection.NetBearType>, expected: connection.NetBearType): boolean {
    for (let i = 0; i < bearers.length; i++) {
      if (bearers[i] === expected) {
        return true;
      }
    }
    return false;
  }

  private hasNetCap(caps: Array<connection.NetCap>, expected: connection.NetCap): boolean {
    for (let i = 0; i < caps.length; i++) {
      if (caps[i] === expected) {
        return true;
      }
    }
    return false;
  }

  async getButtonState(): Promise<number> {
    return await this.preferencesManager.getNumber(
      Constants.PREF_BTNSTATE_FORCE_START_STOP,
      Constants.BTNSTATE_NO_FORCE_START_STOP
    );
  }

  getLastResult(): RunConditionResult {
    return this.lastResult;
  }

  private setReason(reason: string): void {
    this.lastResult = {
      decision: RunDecision.SHOULD_NOT_RUN,
      reason
    };
  }

  private recordResult(result: RunConditionResult): RunConditionResult {
    this.lastResult = result;
    Logger.i(TAG, `Run condition result: ${result.decision}, reason=${result.reason}`);
    BackgroundDiagnostics.record('runConditions.result', `decision=${result.decision}, reason=${result.reason}`);
    return result;
  }

  async setForceStart(): Promise<void> {
    await this.preferencesManager.putNumber(
      Constants.PREF_BTNSTATE_FORCE_START_STOP,
      Constants.BTNSTATE_FORCE_START
    );
    await this.checkConditions();
  }

  async setForceStop(): Promise<void> {
    await this.preferencesManager.putNumber(
      Constants.PREF_BTNSTATE_FORCE_START_STOP,
      Constants.BTNSTATE_FORCE_STOP
    );
    await this.checkConditions();
  }

  async clearForceStartStop(): Promise<void> {
    await this.preferencesManager.putNumber(
      Constants.PREF_BTNSTATE_FORCE_START_STOP,
      Constants.BTNSTATE_NO_FORCE_START_STOP
    );
    await this.checkConditions();
  }
}
