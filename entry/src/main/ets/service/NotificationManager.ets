import { notificationManager } from '@kit.NotificationKit';
import { Logger } from '../common/Logger';
import { Constants } from './Constants';

const TAG = 'NotificationManager';

export class NotificationManager {
  private static instance: NotificationManager | undefined;
  private notificationId: number = 1001;
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
      const persistentId = notificationId === undefined ? this.notificationId : notificationId;
      this.notificationId = persistentId;
      const request: notificationManager.NotificationRequest = {
        id: persistentId,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: text,
          }
        },
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
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
    const targetId = notificationId === undefined ? this.notificationId : notificationId;
    if (targetId < 0) {
      Logger.d(TAG, 'No notification id to update');
      return;
    }
    if (notificationId !== undefined) {
      this.notificationId = notificationId;
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
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
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

  async dismissPersistentNotification(): Promise<void> {
    if (!this.isShowing) {
      return;
    }

    try {
      await notificationManager.cancel(this.notificationId);
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
