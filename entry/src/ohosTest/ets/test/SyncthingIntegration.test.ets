import { describe, it, expect } from '@ohos/hypium';
import { Logger } from '../../main/ets/common/Logger';
import { ServiceLocator } from '../../main/ets/common/ServiceLocator';
import { SyncthingService } from '../../main/ets/service/SyncthingService';
import { Constants } from '../../main/ets/service/Constants';

const TAG = 'IntegrationTest';

export default function integrationTest() {
  describe('SyncthingService_Integration', () => {
    it('should_initialize_service', 0, async (done) => {
      const service = new SyncthingService();
      try {
        await service.initialize();
        expect(service.getState()).assertEqual('stopped');
        expect(service.getRestApi() !== undefined).assertEqual(true);
      } catch (err) {
        Logger.e(TAG, `Service init error: ${JSON.stringify(err)}`);
      }
      done();
    });

    it('should_start_and_stop_service', 0, async (done) => {
      const service = new SyncthingService();
      await service.initialize();

      await service.startService();
      expect(service.getState()).assertEqual('active');

      await service.stopService();
      expect(service.getState()).assertEqual('stopped');

      done();
    });

    it('should_transition_states_correctly', 0, async (done) => {
      const service = new SyncthingService();
      expect(service.getState()).assertEqual('stopped');

      await service.initialize();
      expect(service.getState()).assertEqual('stopped');

      await service.startService();
      expect(service.getState()).assertEqual('active');

      service.destroy();
      expect(service.getState()).assertEqual('stopped');

      done();
    });
  });

  describe('AppFlow_Integration', () => {
    it('should_have_all_config_constants', 0, () => {
      expect(Constants.PREF_RUN_ON_WIFI).assertEqual('run_on_wifi');
      expect(Constants.PREF_EXPERT_MODE).assertEqual('expert_mode');
      expect(Constants.PREF_VERBOSE_LOG).assertEqual('verbose_log');
      expect(Constants.FOLDER_TYPE_SEND_RECEIVE).assertEqual('sendreceive');
      expect(Constants.DEFAULT_WEBGUI_TCP_PORT).assertEqual(8384);
    });

    it('should_generate_dynamic_pref_keys', 0, () => {
      const folderId = 'test_folder_abc';
      const key = Constants.DYN_PREF_OBJECT_SYNC_ON_WIFI(`sc_folder_${folderId}`);
      expect(key).assertEqual(`sc_folder_${folderId}_run_on_wifi`);

      const customKey = Constants.DYN_PREF_OBJECT_CUSTOM_SYNC_CONDITIONS(`sc_device_xyz`);
      expect(customKey).assertEqual('sc_device_xyz_custom_sync_conditions');
    });
  });
}
