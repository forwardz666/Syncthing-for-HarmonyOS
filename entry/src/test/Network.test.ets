import { describe, it, expect } from '@ohos/hypium';
import { ApiRequest } from '../main/ets/network/ApiRequest';

export function networkTest(): void {
  describe('NetworkSmoke_Test', () => {
    it('api_request_should_build_urls', 0, () => {
      const url = ApiRequest.buildUrl('/rest/system/status');
      expect(url).assertEqual('https://localhost:8384/rest/system/status');
    });
  });
}

export default networkTest;
