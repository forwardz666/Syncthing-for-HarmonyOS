import abilityDelegatorRegistry from '@ohos.app.ability.abilityDelegatorRegistry';
import { describe, it, expect, beforeAll } from '@ohos/hypium';
import { Logger } from '../../../main/ets/common/Logger';
import { ServiceLocator, SERVICE_NAMES } from '../../../main/ets/common/ServiceLocator';

const TAG = 'AbilityTest';

export default function abilityTest() {
  describe('EntryAbility_Test', () => {
    it('should_register_application_context_in_service_locator', 0, () => {
      const context = ServiceLocator.get<Context>(SERVICE_NAMES.APPLICATION_CONTEXT);
      expect(context !== undefined).assertEqual(true);
    });

    it('should_register_ui_ability_context', 0, () => {
      const context = ServiceLocator.get<Context>(SERVICE_NAMES.UI_ABILITY_CONTEXT);
      expect(context !== undefined).assertEqual(true);
    });
  });
}
