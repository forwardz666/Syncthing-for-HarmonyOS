import { cert } from '@kit.DeviceCertificateKit';
import { Logger } from '../common/Logger';

const TAG = 'SyncthingTrustManager';

export class SyncthingTrustManager {
  private httpsCertPath: string;
  private caCertPem: string | null = null;
  private initialized: boolean = false;

  constructor(httpsCertPath: string) {
    this.httpsCertPath = httpsCertPath;
  }

  async initialize(): Promise<void> {
    if (this.initialized) {
      return;
    }
    Logger.d(TAG, `Initializing trust manager with cert: ${this.httpsCertPath}`);
    try {
      this.initialized = true;
      Logger.i(TAG, 'SyncthingTrustManager initialized');
    } catch (err) {
      Logger.e(TAG, `Failed to initialize trust manager: ${JSON.stringify(err)}`);
      throw new Error(JSON.stringify(err));
    }
  }

  getCaCertPath(): string {
    return this.httpsCertPath;
  }

  async isInitialized(): Promise<boolean> {
    return this.initialized;
  }
}
