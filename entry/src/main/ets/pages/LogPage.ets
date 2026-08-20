import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';
import { RestApi } from '../network/RestApi';
import { SystemLogEntry } from '../model/Index';
import { L10n } from '../common/L10n';

const TAG = 'LogPage';

@Entry
@Component
struct LogPage {
  @State logMessages: string[] = [];
  @State isLoading: boolean = true;
  @State statusText: string = '';

  private restApi: RestApi | null = null;

  aboutToAppear(): void {
    Logger.i(TAG, 'LogPage appearing');
    this.loadLogs();
  }

  private async loadLogs(): Promise<void> {
    this.isLoading = true;
    try {
      const api = ServiceLocator.get<RestApi>(SERVICE_NAMES.REST_API);
      if (api === undefined) {
        this.statusText = L10n.t('app.string.syncthing_not_ready');
        return;
      }
      this.restApi = api;
      const result = await api.getSystemLog();
      if (result.success && result.data !== undefined) {
        const messages: string[] = [];
        const entries = result.data.messages;
        const start = entries.length > 120 ? entries.length - 120 : 0;
        for (let i = start; i < entries.length; i++) {
          messages.push(this.formatLogEntry(entries[i]));
        }
        this.logMessages = messages.reverse();
        this.statusText = L10n.fmt('app.string.log_entry_count', entries.length);
      } else {
        this.statusText = result.error || L10n.t('app.string.logs_load_failed');
      }
    } catch (err) {
      Logger.e(TAG, `Failed to load logs: ${JSON.stringify(err)}`);
      this.statusText = L10n.t('app.string.logs_load_failed');
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

        Text(L10n.t('app.string.logs'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 })
          .layoutWeight(1)

        Button(L10n.t('app.string.clear'))
          .fontSize(14)
          .fontColor('#FF4444')
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.logMessages = [];
          })

        Button(L10n.t('app.string.refresh'))
          .fontSize(14)
          .fontColor('#007AFF')
          .backgroundColor(Color.Transparent)
          .onClick(() => this.loadLogs())
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
          Text(L10n.t('app.string.loading_logs'))
            .fontSize(14)
            .fontColor('#777')
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.logMessages.length === 0) {
        Column() {
          Text(this.statusText.length > 0 ? this.statusText : L10n.t('app.string.no_log_entries'))
            .fontSize(16)
            .fontColor('#888')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.logMessages, (msg: string, index: number) => {
            ListItem() {
              Text(msg)
                .fontSize(11)
                .fontFamily('monospace')
                .fontColor('#333')
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .width('100%')
                .backgroundColor(index % 2 === 0 ? '#FFFFFF' : '#F8F8F8')
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  private formatLogEntry(entry: SystemLogEntry): string {
    const level = entry.level === undefined || entry.level.length === 0 ? 'LOG' : entry.level;
    return `${entry.when} [${level}] ${entry.message}`;
  }
}
