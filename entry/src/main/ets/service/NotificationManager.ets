import { notificationManager } from '@kit.NotificationKit';
import { Logger } from '../common/Logger';
import { Constants } from './Constants';

const TAG = 'NotificationManager';

export class NotificationManager {
  private static instance: NotificationManager | undefined;
  private notificationId: number = 1001;
  private persistentNotificationId: number = -1;
  private isShowing: boolean = false;

  static getInstance(): NotificationManager {
    if (!NotificationManager.instance) {
      NotificationManager.instance = new NotificationManager();
    }
    return NotificationManager.instance;
  }

  async showPersistentNotification(
    title: string,
    text: string,
    context: Context,
    notificationId?: number
  ): Promise<void> {
    try {
      const persistentId = notificationId === undefined ? (this.persistentNotificationId >= 0 ? this.persistentNotificationId : this.notificationId) : notificationId;
      this.persistentNotificationId = persistentId;
      if (this.notificationId <= persistentId) {
        this.notificationId = persistentId + 1;
      }
      const request: notificationManager.NotificationRequest = {
        id: persistentId,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: text,
          }
        },
        notificationSlotType: notificationManager.SlotType.CONTENT_INFORMATION,
        isOngoing: true,
        isUnremovable: false,
        tapDismissed: false,
      };

      await notificationManager.publish(request);
      this.isShowing = true;
      Logger.d(TAG, `Persistent notification shown id=${persistentId}`);
    } catch (err) {
      Logger.e(TAG, `Failed to show notification: ${JSON.stringify(err)}`);
    }
  }

  async updatePersistentNotification(title: string, text: string, notificationId?: number): Promise<void> {
    const targetId = notificationId === undefined ? this.persistentNotificationId : notificationId;
    if (targetId < 0) {
      Logger.d(TAG, 'No notification id to update');
      return;
    }
    if (notificationId !== undefined) {
      this.persistentNotificationId = notificationId;
      if (this.notificationId <= notificationId) {
        this.notificationId = notificationId + 1;
      }
    }
    if (!this.isShowing && notificationId === undefined) {
      Logger.d(TAG, 'No notification to update');
      return;
    }

    try {
      const request: notificationManager.NotificationRequest = {
        id: targetId,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: text,
          }
        },
        notificationSlotType: notificationManager.SlotType.CONTENT_INFORMATION,
        isOngoing: true,
        isUnremovable: false,
        tapDismissed: false,
      };

      await notificationManager.publish(request);
      this.isShowing = true;
      Logger.d(TAG, `Persistent notification updated id=${targetId}`);
    } catch (err) {
      Logger.e(TAG, `Failed to update notification: ${JSON.stringify(err)}`);
    }
  }

  async showDataTransferProgressNotification(
    title: string,
    text: string,
    notificationId: number,
    progressValue: number,
    fileName?: string
  ): Promise<void> {
    if (notificationId < 0) {
      Logger.d(TAG, 'No DataTransfer notification id to update');
      return;
    }
    try {
      const request: notificationManager.NotificationRequest = {
        id: notificationId,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
          systemLiveView: {
            typeCode: 8,
            title: title,
            text: text,
          }
        },
        notificationSlotType: notificationManager.SlotType.LIVE_VIEW,
        // Keep the system Live View attributes (ongoing + unremovable) so the update
        // stays on the silent system-created slot instead of being re-created as a
        // service-information notification. isAlertOnce is a second guard against
        // repeated reminder sounds on updates.
        isOngoing: true,
        isUnremovable: true,
        isAlertOnce: true,
        template: {
          name: 'downloadTemplate',
          data: {
            title: title,
            fileName: fileName === undefined ? title : fileName,
            progressValue: progressValue
          }
        },
      };

      await notificationManager.publish(request);
      this.persistentNotificationId = notificationId;
      if (this.notificationId <= notificationId) {
        this.notificationId = notificationId + 1;
      }
      this.isShowing = true;
      Logger.d(TAG, `DataTransfer progress notification updated id=${notificationId}, progress=${progressValue}`);
    } catch (err) {
      Logger.e(TAG, `Failed to update DataTransfer progress notification: ${JSON.stringify(err)}`);
    }
  }

  async dismissPersistentNotification(): Promise<void> {
    if (!this.isShowing) {
      return;
    }

    try {
      await notificationManager.cancel(this.persistentNotificationId >= 0 ? this.persistentNotificationId : this.notificationId);
      this.persistentNotificationId = -1;
      this.isShowing = false;
      Logger.d(TAG, 'Persistent notification dismissed');
    } catch (err) {
      Logger.e(TAG, `Failed to dismiss notification: ${JSON.stringify(err)}`);
    }
  }

  async showInfoNotification(
    title: string,
    text: string,
    context: Context,
    id?: number
  ): Promise<void> {
    const notifId = id || this.generateNotificationId();

    try {
      const request: notificationManager.NotificationRequest = {
        id: notifId,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: text,
          }
        },
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        isOngoing: false,
      };

      await notificationManager.publish(request);
      Logger.d(TAG, `Info notification shown: id=${notifId}`);
    } catch (err) {
      Logger.e(TAG, `Failed to show info notification: ${JSON.stringify(err)}`);
    }
  }

  async showErrorNotification(
    title: string,
    text: string,
    context: Context
  ): Promise<void> {
    const notifId = this.generateNotificationId();

    try {
      const request: notificationManager.NotificationRequest = {
        id: notifId,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: text,
          }
        },
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        isOngoing: false,
      };

      await notificationManager.publish(request);
      Logger.d(TAG, `Error notification shown: id=${notifId}`);
    } catch (err) {
      Logger.e(TAG, `Failed to show error notification: ${JSON.stringify(err)}`);
    }
  }

  async cancelNotification(id: number): Promise<void> {
    try {
      await notificationManager.cancel(id);
    } catch (err) {
      Logger.e(TAG, `Failed to cancel notification: ${JSON.stringify(err)}`);
    }
  }

  async cancelAll(): Promise<void> {
    try {
      await notificationManager.cancelAll();
      this.persistentNotificationId = -1;
      this.isShowing = false;
    } catch (err) {
      Logger.e(TAG, `Failed to cancel all notifications: ${JSON.stringify(err)}`);
    }
  }

  private generateNotificationId(): number {
    this.notificationId++;
    return this.notificationId;
  }

  isPersistentNotificationShowing(): boolean {
    return this.isShowing;
  }
}
