import { Logger } from './Logger';

const TAG = 'ServiceLocator';

type Factory<T> = () => T;

class ServiceRegistry {
  private singletons: Map<string, object> = new Map();
  private factories: Map<string, Factory<object>> = new Map();

  registerSingleton<T extends object>(name: string, instance: T): void {
    if (this.singletons.has(name)) {
      Logger.w(TAG, `Singleton '${name}' already registered, overwriting`);
    }
    this.singletons.set(name, instance);
    Logger.d(TAG, `Registered singleton: ${name}`);
  }

  registerFactory<T extends object>(name: string, factory: Factory<T>): void {
    this.factories.set(name, factory as Factory<object>);
    Logger.d(TAG, `Registered factory: ${name}`);
  }

  get<T extends object>(name: string): T | undefined {
    const singleton = this.singletons.get(name);
    if (singleton !== undefined) {
      return singleton as T;
    }
    const factory = this.factories.get(name);
    if (factory !== undefined) {
      const instance = factory() as T;
      this.singletons.set(name, instance as object);
      return instance;
    }
    Logger.e(TAG, `Service '${name}' not found in registry`);
    return undefined;
  }

  getOrThrow<T extends object>(name: string): T {
    const service = this.get<T>(name);
    if (service === undefined) {
      throw new Error(`Required service '${name}' is not registered`);
    }
    return service;
  }

  has(name: string): boolean {
    return this.singletons.has(name) || this.factories.has(name);
  }

  remove(name: string): void {
    this.singletons.delete(name);
    this.factories.delete(name);
  }

  clear(): void {
    this.singletons.clear();
    this.factories.clear();
  }
}

export const ServiceLocator = new ServiceRegistry();

export class ServiceNames {
  readonly EVENT_BUS: string = 'EventBus';
  readonly PREFERENCES_MANAGER: string = 'PreferencesManager';
  readonly REST_API: string = 'RestApi';
  readonly SYNCTHING_SERVICE: string = 'SyncthingService';
  readonly SYNCTHING_PROCESS_MANAGER: string = 'SyncthingProcessManager';
  readonly EVENT_PROCESSOR: string = 'EventProcessor';
  readonly RUN_CONDITION_MONITOR: string = 'RunConditionMonitor';
  readonly BACKGROUND_SYNC_MANAGER: string = 'BackgroundSyncManager';
  readonly NOTIFICATION_MANAGER: string = 'NotificationManager';
  readonly CONFIG_XML_MANAGER: string = 'ConfigXmlManager';
  readonly APPLICATION_CONTEXT: string = 'ApplicationContext';
  readonly UI_ABILITY_CONTEXT: string = 'UIAbilityContext';
}

export const SERVICE_NAMES: ServiceNames = new ServiceNames();
