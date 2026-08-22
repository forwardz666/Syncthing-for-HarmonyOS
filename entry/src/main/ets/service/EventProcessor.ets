import { Logger } from '../common/Logger';
import { EventBus, SyncthingEvents } from '../common/EventBus';
import { RestApi } from '../network/RestApi';
import { Constants } from './Constants';
import { Event } from '../model/Event';
import { PreferencesManager } from '../data/PreferencesManager';

const TAG = 'EventProcessor';

export class EventProcessor {
  private restApi: RestApi;
  private preferencesManager: PreferencesManager;
  private isRunning: boolean = false;
  private lastEventId: number = 0;
  private pollTimer: number | null = null;
  private readonly POLL_INTERVAL_MS: number = 3000;
  private readonly MAX_EVENTS_PER_POLL: number = 100;

  private processedEventGlobalIds: Set<number> = new Set();

  constructor(restApi: RestApi) {
    this.restApi = restApi;
    this.preferencesManager = PreferencesManager.getInstance();
  }

  async start(): Promise<void> {
    if (this.isRunning) {
      Logger.w(TAG, 'EventProcessor already running');
      return;
    }

    this.isRunning = true;
    try {
      this.lastEventId = await this.preferencesManager.getNumber(
        Constants.PREF_EVENT_PROCESSOR_LAST_SYNC_ID, 0
      );
    } catch (err) {
      this.lastEventId = 0;
    }

    Logger.i(TAG, `EventProcessor started, lastEventId=${this.lastEventId}`);
    this.schedulePoll();
  }

  stop(): void {
    this.isRunning = false;
    if (this.pollTimer !== null) {
      clearTimeout(this.pollTimer);
      this.pollTimer = null;
    }
    Logger.i(TAG, 'EventProcessor stopped');
  }

  getIsRunning(): boolean {
    return this.isRunning;
  }

  getLastEventId(): number {
    return this.lastEventId;
  }

  private schedulePoll(): void {
    if (!this.isRunning) {
      return;
    }
    this.pollTimer = setTimeout(() => {
      this.pollEvents();
    }, this.POLL_INTERVAL_MS);
  }

  private async pollEvents(): Promise<void> {
    if (!this.isRunning) {
      return;
    }

    try {
      const result = await this.restApi.getEvents(
        this.lastEventId,
        this.MAX_EVENTS_PER_POLL
      );

      if (result.success && result.data) {
        this.processEvents(result.data);
      }
    } catch (err) {
      Logger.d(TAG, `Event poll error: ${JSON.stringify(err)}`);
    } finally {
      this.schedulePoll();
    }
  }

  private processEvents(events: Event[]): void {
    if (events.length === 0) {
      return;
    }

    for (const event of events) {
      if (this.processedEventGlobalIds.has(event.globalId)) {
        continue;
      }

      this.processedEventGlobalIds.add(event.globalId);

      if (this.processedEventGlobalIds.size > 10000) {
        const minId = Math.min(...Array.from(this.processedEventGlobalIds));
        this.processedEventGlobalIds.delete(minId);
      }

      if (event.id > this.lastEventId) {
        this.lastEventId = event.id;
      }

      this.handleEvent(event);
    }

    this.preferencesManager.putNumber(
      Constants.PREF_EVENT_PROCESSOR_LAST_SYNC_ID,
      this.lastEventId
    );

    EventBus.emit(SyncthingEvents.EVENT_DATA_UPDATED, 'events');
  }

  private handleEvent(event: Event): void {
    Logger.d(TAG, `Processing event: ${event.type} (id=${event.id})`);

    switch (event.type) {
      case 'StartupCompleted':
        EventBus.emit(SyncthingEvents.SYNC_STARTED, null);
        break;

      case 'DeviceConnected':
        EventBus.emit(SyncthingEvents.DEVICE_CONNECTED, null);
        break;

      case 'DeviceDisconnected':
        EventBus.emit(SyncthingEvents.DEVICE_DISCONNECTED, null);
        break;

      case 'DevicePaused':
        EventBus.emit(SyncthingEvents.DEVICE_PAUSED, null);
        break;

      case 'DeviceResumed':
        EventBus.emit(SyncthingEvents.DEVICE_RESUMED, null);
        break;

      case 'DownloadProgress':
        EventBus.emit(SyncthingEvents.DOWNLOAD_PROGRESS, null);
        break;

      case 'FolderSummary':
        EventBus.emit(SyncthingEvents.FOLDER_SYNC_PROGRESS, null);
        break;

      case 'FolderCompletion':
        EventBus.emit(SyncthingEvents.FOLDER_COMPLETION, null);
        break;

      case 'FolderErrors':
        EventBus.emit(SyncthingEvents.FOLDER_ERRORS, null);
        break;

      case 'FolderScanProgress':
        EventBus.emit(SyncthingEvents.FOLDER_SCAN_PROGRESS, null);
        break;

      case 'ItemStarted':
        EventBus.emit(SyncthingEvents.ITEM_STARTED, null);
        break;

      case 'ItemFinished':
        EventBus.emit(SyncthingEvents.ITEM_FINISHED, null);
        break;

      case 'ConfigSaved':
        EventBus.emit(SyncthingEvents.CONFIG_SAVED, null);
        break;

      default:
        break;
    }
  }
}
