import { describe, it, expect } from '@ohos/hypium';
import { EventBus } from '../main/ets/common/EventBus';
import { NotificationManager } from '../main/ets/service/NotificationManager';

export function serviceTest(): void {
  describe('ServiceSmoke_Test', () => {
    it('notification_manager_should_be_singleton', 0, () => {
      const instance1 = NotificationManager.getInstance();
      const instance2 = NotificationManager.getInstance();
      expect(instance1 === instance2).assertEqual(true);
    });

    it('event_bus_should_emit', 0, () => {
      let received: boolean = false;
      EventBus.once('smoke', () => {
        received = true;
      });
      EventBus.emit('smoke', null);
      expect(received).assertEqual(true);
    });
  });
}

export default serviceTest;
