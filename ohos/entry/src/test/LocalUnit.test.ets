import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { punchPriorityOptionIndex, punchPriorityOptionValue } from '../main/ets/model/PunchPriority';

export default function localUnitTest() {
  describe('localUnitTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
    });
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    });
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    });
    afterAll(() => {
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    });
    it('assertContain', 0, () => {
      // Defines a test case. This API supports three parameters: test case name, filter parameter, and test case function.
      let a = 'abc';
      let b = 'b';
      // Defines a variety of assertion methods, which are used to declare expected boolean conditions.
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    });
    it('punchPriorityUsesProtocolValues', 0, () => {
      expect(punchPriorityOptionValue(0)).assertEqual(1);
      expect(punchPriorityOptionValue(1)).assertEqual(0);
      expect(punchPriorityOptionValue(2)).assertEqual(2);
      expect(punchPriorityOptionValue(3)).assertEqual(4);
      expect(punchPriorityOptionIndex(0)).assertEqual(1);
      expect(punchPriorityOptionIndex(1)).assertEqual(0);
      expect(punchPriorityOptionIndex(2)).assertEqual(2);
      expect(punchPriorityOptionIndex(4)).assertEqual(3);
      expect(punchPriorityOptionIndex(3)).assertEqual(2);
    });
  });
}
