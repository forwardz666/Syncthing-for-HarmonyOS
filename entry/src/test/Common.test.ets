import { describe, it, expect } from '@ohos/hypium';
import { Constants } from '../main/ets/service/Constants';

export function commonTest(): void {
  describe('CommonSmoke_Test', () => {
    it('constants_should_be_available', 0, () => {
      expect(Constants.DEFAULT_WEBGUI_TCP_PORT).assertEqual(8384);
      expect(Constants.DEFAULT_DATA_TCP_PORT).assertEqual(22000);
    });
  });
}

export default commonTest;
