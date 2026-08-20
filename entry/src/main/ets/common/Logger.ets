import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG_PREFIX: string = 'Syncthing';

export class Logger {
  private static verboseLogEnabled: boolean = false;

  static setVerboseLog(enabled: boolean): void {
    Logger.verboseLogEnabled = enabled;
  }

  static isVerboseLogEnabled(): boolean {
    return Logger.verboseLogEnabled;
  }

  private static formatMessage(tag: string, msg: string): string {
    return `[${TAG_PREFIX}][${tag}] ${msg}`;
  }

  static debug(tag: string, msg: string): void {
    if (Logger.verboseLogEnabled) {
      hilog.debug(DOMAIN, tag, '%{public}s', Logger.formatMessage(tag, msg));
    }
  }

  static info(tag: string, msg: string): void {
    hilog.info(DOMAIN, tag, '%{public}s', Logger.formatMessage(tag, msg));
  }

  static warn(tag: string, msg: string): void {
    hilog.warn(DOMAIN, tag, '%{public}s', Logger.formatMessage(tag, msg));
  }

  static error(tag: string, msg: string): void {
    hilog.error(DOMAIN, tag, '%{public}s', Logger.formatMessage(tag, msg));
  }

  static fatal(tag: string, msg: string): void {
    hilog.fatal(DOMAIN, tag, '%{public}s', Logger.formatMessage(tag, msg));
  }

  static d(tag: string, msg: string): void {
    Logger.debug(tag, msg);
  }

  static i(tag: string, msg: string): void {
    Logger.info(tag, msg);
  }

  static w(tag: string, msg: string): void {
    Logger.warn(tag, msg);
  }

  static e(tag: string, msg: string): void {
    Logger.error(tag, msg);
  }
}
