import { commonTest } from './Common.test.ets';
import { networkTest } from './Network.test.ets';
import { serviceTest } from './Service.test.ets';

export default function testAll() {
  commonTest();
  networkTest();
  serviceTest();
}
