import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { RestApi } from '../network/RestApi';
import { Event } from '../model/Index';
import { L10n } from '../common/L10n';

const TAG = 'RecentChangesPage';

interface FileChange {
  fileName: string;
  folderName: string;
  action: string;
  time: string;
  size: number;
}

@Entry
@Component
struct RecentChangesPage {
  @State changes: FileChange[] = [];
  @State isLoading: boolean = true;
  @State statusText: string = '';

  private restApi: RestApi | null = null;

  aboutToAppear(): void {
    Logger.i(TAG, 'RecentChangesPage appearing');
    this.loadChanges();
  }

  private async loadChanges(): Promise<void> {
    this.isLoading = true;
    try {
      const api = ServiceLocator.get<RestApi>(SERVICE_NAMES.REST_API);
      if (api === undefined) {
        this.statusText = L10n.t('app.string.syncthing_not_ready');
        return;
      }
      this.restApi = api;
      const result = await api.getEvents(undefined, 80, 1);
      if (result.success && result.data !== undefined) {
        const changes: FileChange[] = [];
        for (let i = result.data.length - 1; i >= 0; i--) {
          const change = this.eventToChange(result.data[i]);
          if (change !== null) {
            changes.push(change);
          }
        }
        if (changes.length === 0) {
          for (let i = result.data.length - 1; i >= 0; i--) {
            changes.push(this.genericEventToChange(result.data[i]));
          }
        }
        this.changes = changes;
        this.statusText = L10n.fmt('app.string.recent_event_count', changes.length);
      } else {
        this.statusText = result.error || L10n.t('app.string.recent_changes_load_failed');
      }
    } catch (err) {
      Logger.e(TAG, `Failed to load recent changes: ${JSON.stringify(err)}`);
      this.statusText = L10n.t('app.string.recent_changes_load_failed');
    } finally {
      this.isLoading = false;
    }
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
        .onClick(() => this.getUIContext().getRouter().back())

        Text(L10n.t('app.string.recent_changes'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 })
          .layoutWeight(1)

        Button(L10n.t('app.string.refresh'))
          .fontSize(14)
          .fontColor('#007AFF')
          .backgroundColor(Color.Transparent)
          .onClick(() => this.loadChanges())
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
          Text(L10n.t('app.string.loading_changes'))
            .fontSize(14)
            .fontColor('#777')
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.changes.length === 0) {
        Column({ space: 12 }) {
          Text(this.statusText.length > 0 ? this.statusText : L10n.t('app.string.no_recent_changes'))
            .fontSize(16)
            .fontColor('#888')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 2 }) {
          ForEach(this.changes, (change: FileChange) => {
            ListItem() {
              this.changeItem(change)
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  changeItem(change: FileChange) {
    Row() {
      Column({ space: 4 }) {
        Text(change.fileName)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333')

        Text(`${change.folderName} - ${change.time}`)
          .fontSize(12)
          .fontColor('#999')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(this.translateAction(change.action))
        .fontSize(11)
        .fontColor('#FFF')
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .borderRadius(4)
        .backgroundColor(this.getActionColor(change.action))
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
  }

  private translateAction(action: string): string {
    switch (action) {
      case 'Added': return L10n.t('app.string.action_added');
      case 'Modified': return L10n.t('app.string.action_modified');
      case 'Deleted': return L10n.t('app.string.action_deleted');
      case 'Synced': return L10n.t('app.string.action_synced');
      case 'Connected': return L10n.t('app.string.action_connected');
      case 'Disconnected': return L10n.t('app.string.action_disconnected');
      case 'Scanning': return L10n.t('app.string.action_scanning');
      case 'Event': return L10n.t('app.string.action_event');
      default: return action;
    }
  }

  getActionColor(action: string): string {
    switch (action) {
      case 'Added': return '#34C759';
      case 'Modified': return '#007AFF';
      case 'Deleted': return '#FF4444';
      case 'Synced': return '#34C759';
      case 'Connected': return '#34C759';
      case 'Scanning': return '#007AFF';
      default: return '#999';
    }
  }

  private eventToChange(event: Event): FileChange | null {
    if (!this.isVisibleEvent(event.type)) {
      return null;
    }
    const data = event.data as Record<string, Object>;
    const folder = this.objectToString(data['folder'], 'Syncthing');
    const fileName = this.extractFileName(event.type, data);
    const action = this.actionForEvent(event.type, data);
    return {
      fileName,
      folderName: folder,
      action,
      time: this.formatTime(event.time),
      size: this.extractSize(data)
    };
  }

  private genericEventToChange(event: Event): FileChange {
    const data = event.data as Record<string, Object>;
    return {
      fileName: event.type,
      folderName: this.objectToString(data['folder'], 'Syncthing'),
      action: 'Event',
      time: this.formatTime(event.time),
      size: 0
    };
  }

  private isVisibleEvent(type: string): boolean {
    return type === 'ItemStarted'
      || type === 'ItemFinished'
      || type === 'LocalChangeDetected'
      || type === 'RemoteChangeDetected'
      || type === 'StateChanged'
      || type === 'FolderCompletion'
      || type === 'DeviceConnected'
      || type === 'DeviceDisconnected';
  }

  private extractFileName(type: string, data: Record<string, Object>): string {
    const item = this.objectToString(data['item'], '');
    if (item.length > 0) {
      return item;
    }
    const path = this.objectToString(data['path'], '');
    if (path.length > 0) {
      return path;
    }
    if (type === 'DeviceConnected' || type === 'DeviceDisconnected') {
      const name = this.objectToString(data['deviceName'], '');
      const id = this.objectToString(data['id'], '');
      return name.length > 0 ? name : id;
    }
    return type;
  }

  private actionForEvent(type: string, data: Record<string, Object>): string {
    const action = this.objectToString(data['action'], '');
    if (action.length > 0) {
      return action;
    }
    if (type === 'ItemFinished') {
      return 'Synced';
    }
    if (type === 'StateChanged') {
      const toState = this.objectToString(data['to'], '');
      return toState.length > 0 ? toState : 'Scanning';
    }
    if (type === 'DeviceConnected') {
      return 'Connected';
    }
    if (type === 'DeviceDisconnected') {
      return 'Disconnected';
    }
    return type;
  }

  private extractSize(data: Record<string, Object>): number {
    const value = data['size'];
    if (typeof value === 'number') {
      return value;
    }
    return 0;
  }

  private objectToString(value: Object | undefined, fallback: string): string {
    if (value === undefined || value === null) {
      return fallback;
    }
    return String(value);
  }

  private formatTime(value: string): string {
    if (value.length < 19) {
      return value;
    }
    return value.substring(0, 19).replace('T', ' ');
  }
}
