import { Logger } from './Logger';

const TAG = 'EventBus';

export type EventPayload = Object | string | number | boolean | null;
export type EventCallback = (data: EventPayload) => void;

export class EventBus {
  private static readonly EVENT_NAMESPACE = 'syncthing';
  private static listeners: Map<string, Array<EventCallback>> = new Map();

  static on(eventName: string, callback: EventCallback): void {
    const fullEventName = EventBus.buildEventName(eventName);
    let callbacks = EventBus.listeners.get(fullEventName);
    if (callbacks === undefined) {
      callbacks = new Array<EventCallback>();
      EventBus.listeners.set(fullEventName, callbacks);
    }
    callbacks.push(callback);
    Logger.d(TAG, `Subscribed to event: ${fullEventName}`);
  }

  static once(eventName: string, callback: EventCallback): void {
    const fullEventName = EventBus.buildEventName(eventName);
    const onceCallback: EventCallback = (data: EventPayload): void => {
      EventBus.off(eventName);
      callback(data);
    };
    EventBus.on(eventName, onceCallback);
    Logger.d(TAG, `Subscribed once to event: ${fullEventName}`);
  }

  static off(eventName: string): void {
    const fullEventName = EventBus.buildEventName(eventName);
    EventBus.listeners.delete(fullEventName);
    Logger.d(TAG, `Unsubscribed from event: ${fullEventName}`);
  }

  static emit(eventName: string, data: EventPayload): void {
    const fullEventName = EventBus.buildEventName(eventName);
    const callbacks = EventBus.listeners.get(fullEventName);
    if (callbacks !== undefined) {
      callbacks.forEach((callback: EventCallback): void => {
        callback(data);
      });
    }
    Logger.d(TAG, `Emitted event: ${fullEventName}`);
  }

  private static buildEventName(eventName: string): string {
    return `${EventBus.EVENT_NAMESPACE}:${eventName}`;
  }
}

export class SyncthingEventNames {
  readonly SERVICE_STATE_CHANGED: string = 'service:stateChanged';
  readonly SERVICE_ERROR: string = 'service:error';
  readonly SYNC_STARTING: string = 'sync:starting';
  readonly SYNC_STARTED: string = 'sync:started';
  readonly SYNC_STOPPED: string = 'sync:stopped';
  readonly SYNC_PAUSED: string = 'sync:paused';
  readonly SYNC_RESUMED: string = 'sync:resumed';
  readonly DEVICE_CONNECTED: string = 'device:connected';
  readonly DEVICE_DISCONNECTED: string = 'device:disconnected';
  readonly DEVICE_PAUSED: string = 'device:paused';
  readonly DEVICE_RESUMED: string = 'device:resumed';
  readonly FOLDER_SYNC_PROGRESS: string = 'folder:syncProgress';
  readonly FOLDER_COMPLETION: string = 'folder:completion';
  readonly FOLDER_ERRORS: string = 'folder:errors';
  readonly FOLDER_SCAN_PROGRESS: string = 'folder:scanProgress';
  readonly CONFIG_SAVED: string = 'config:saved';
  readonly CONFIG_CHANGED: string = 'config:changed';
  readonly ITEM_STARTED: string = 'item:started';
  readonly ITEM_FINISHED: string = 'item:finished';
  readonly DOWNLOAD_PROGRESS: string = 'download:progress';
  readonly EVENT_DATA_UPDATED: string = 'event:dataUpdated';
  readonly API_AVAILABLE: string = 'api:available';
  readonly API_UNAVAILABLE: string = 'api:unavailable';
  readonly NETWORK_CHANGED: string = 'network:changed';
  readonly POWER_CHANGED: string = 'power:changed';
  readonly BATTERY_CHANGED: string = 'battery:changed';
  readonly RUN_CONDITIONS_MET: string = 'runConditions:met';
  readonly RUN_CONDITIONS_NOT_MET: string = 'runConditions:notMet';
  readonly NOTIFICATION_SHOW: string = 'notification:show';
  readonly NOTIFICATION_UPDATE: string = 'notification:update';
  readonly NOTIFICATION_DISMISS: string = 'notification:dismiss';
}

export const SyncthingEvents: SyncthingEventNames = new SyncthingEventNames();
