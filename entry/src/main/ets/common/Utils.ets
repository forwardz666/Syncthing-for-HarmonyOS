import { util } from '@kit.ArkTS';
import { Logger } from '../common/Logger';

const TAG = 'Utils';

export class Utils {
  static generateRandomString(length: number): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    let result = '';
    for (let i = 0; i < length; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return result;
  }

  static formatBytes(bytes: number, decimals: number = 2): string {
    if (bytes === 0) {
      return '0 B';
    }
    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
  }

  static formatTransferSpeed(bytesPerSecond: number): string {
    if (bytesPerSecond <= 0) {
      return '0 B/s';
    }
    return Utils.formatBytes(bytesPerSecond) + '/s';
  }

  static formatDuration(seconds: number): string {
    if (seconds < 60) {
      return `${seconds}s`;
    }
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) {
      return `${minutes}m`;
    }
    const hours = Math.floor(minutes / 60);
    const remainingMinutes = minutes % 60;
    if (hours < 24) {
      return `${hours}h ${remainingMinutes}m`;
    }
    const days = Math.floor(hours / 24);
    const remainingHours = hours % 24;
    return `${days}d ${remainingHours}h`;
  }

  static formatUptime(seconds: number): string {
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = seconds % 60;

    const parts: string[] = [];
    if (days > 0) {
      parts.push(`${days}d`);
    }
    if (hours > 0) {
      parts.push(`${hours}h`);
    }
    if (minutes > 0) {
      parts.push(`${minutes}m`);
    }
    parts.push(`${secs}s`);
    return parts.join(' ');
  }

  static formatDate(isoDateString: string): string {
    try {
      const date = new Date(isoDateString);
      const year = date.getFullYear();
      const month = String(date.getMonth() + 1).padStart(2, '0');
      const day = String(date.getDate()).padStart(2, '0');
      const hours = String(date.getHours()).padStart(2, '0');
      const minutes = String(date.getMinutes()).padStart(2, '0');
      return `${year}-${month}-${day} ${hours}:${minutes}`;
    } catch (err) {
      Logger.w(TAG, `Error formatting date: ${JSON.stringify(err)}`);
      return isoDateString;
    }
  }

  static computeCompletionPercent(needBytes: number, globalBytes: number): number {
    if (globalBytes === 0) {
      return 100;
    }
    const completed = globalBytes - needBytes;
    if (completed <= 0) {
      return 0;
    }
    return Math.round((completed / globalBytes) * 100);
  }

  static compareDeviceIds(id1: string, id2: string): boolean {
    return id1.replace(/[-]/g, '').toUpperCase() === id2.replace(/[-]/g, '').toUpperCase();
  }

  static base64ToString(base64: string): string {
    try {
      const textDecoder = util.TextDecoder.create('utf-8');
      const base64Helper = new util.Base64Helper();
      const uint8Array = base64Helper.decodeSync(base64);
      return textDecoder.decodeToString(uint8Array);
    } catch (err) {
      Logger.e(TAG, `Error decoding base64: ${JSON.stringify(err)}`);
      return '';
    }
  }

  static stringToBase64(str: string): string {
    try {
      const textEncoder = util.TextEncoder.create();
      const base64Helper = new util.Base64Helper();
      const uint8Array = textEncoder.encodeInto(str);
      return base64Helper.encodeToStringSync(uint8Array);
    } catch (err) {
      Logger.e(TAG, `Error encoding to base64: ${JSON.stringify(err)}`);
      return '';
    }
  }

  static isEmpty(str: string | null | undefined): boolean {
    return str === null || str === undefined || str.length === 0;
  }

  static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, ms);
    });
  }

  static async retry<T>(
    fn: () => Promise<T>,
    maxRetries: number = 3,
    delayMs: number = 1000
  ): Promise<T> {
    let lastError: Error | undefined;
    for (let attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await fn();
      } catch (err) {
        lastError = err as Error;
        Logger.w(TAG, `Attempt ${attempt + 1}/${maxRetries + 1} failed: ${JSON.stringify(err)}`);
        if (attempt < maxRetries) {
          await Utils.delay(delayMs * Math.pow(2, attempt));
        }
      }
    }
    if (lastError !== undefined) {
      throw lastError;
    }
    throw new Error('Retry failed');
  }
}
