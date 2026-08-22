import { fileIo } from '@kit.CoreFileKit';
import { Logger } from '../common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../common/ServiceLocator';

const TAG = 'BackgroundDiagnostics';
const LOG_FILE_NAME = 'background-diagnostics.log';
const MAX_LOG_BYTES = 128 * 1024;

export class BackgroundDiagnostics {
  static record(event: string, detail: string = ''): void {
    const line = `${new Date().toISOString()} ${event}${detail.length > 0 ? ' ' + detail : ''}`;
    Logger.i(TAG, line);
    try {
      const context = ServiceLocator.get<Context>(SERVICE_NAMES.APPLICATION_CONTEXT);
      if (context === undefined) {
        return;
      }
      const path = `${context.filesDir}/${LOG_FILE_NAME}`;
      BackgroundDiagnostics.rotateIfNeeded(path);
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.APPEND);
      try {
        fileIo.writeSync(file.fd, `${line}\n`);
      } finally {
        fileIo.closeSync(file);
      }
    } catch (err) {
      Logger.w(TAG, `Failed to write diagnostic event: ${JSON.stringify(err)}`);
    }
  }

  private static rotateIfNeeded(path: string): void {
    try {
      const stat = fileIo.statSync(path);
      if (stat.size <= MAX_LOG_BYTES) {
        return;
      }
      fileIo.unlinkSync(path);
    } catch (err) {
    }
  }
}
