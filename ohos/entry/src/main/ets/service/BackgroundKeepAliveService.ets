import common from '@ohos.app.ability.common';
import { wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0;
const TAG = 'OpenP2P-Background';
const ENTRY_ABILITY = 'EntryAbility';

export class BackgroundKeepAliveService {
  private static active: boolean = false;
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async start(): Promise<boolean> {
    if (BackgroundKeepAliveService.active) {
      return true;
    }
    try {
      const agent = await wantAgent.getWantAgent({
        wants: [{
          deviceId: '',
          bundleName: this.context.abilityInfo.bundleName,
          abilityName: ENTRY_ABILITY
        }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      });
      await backgroundTaskManager.startBackgroundRunning(
        this.context,
        backgroundTaskManager.BackgroundMode.MULTI_DEVICE_CONNECTION,
        agent
      );
      BackgroundKeepAliveService.active = true;
      hilog.info(DOMAIN, TAG, 'Continuous background task started');
      return true;
    } catch (error) {
      // The VPN extension remains the primary owner. Unsupported devices or
      // policy verification failures therefore degrade safely without
      // interrupting the core.
      hilog.warn(DOMAIN, TAG, 'Continuous background task unavailable: %{public}s', JSON.stringify(error));
      return false;
    }
  }

  async stop(): Promise<void> {
    try {
      await backgroundTaskManager.stopBackgroundRunning(this.context);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to stop continuous background task: %{public}s', JSON.stringify(error));
    } finally {
      BackgroundKeepAliveService.active = false;
    }
  }
}
