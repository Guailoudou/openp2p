import {
  AbilityConstant,
  ConfigurationConstant,
  UIAbility,
  Want
} from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { CoreService } from '../service/CoreService';
import { AppColorMode, RuntimeStateStore } from '../service/RuntimeStateStore';

const DOMAIN = 0x0000;
const BACKGROUND_RECOVERY_INTERVAL_MS = 10 * 1000;

export default class EntryAbility extends UIAbility {
  private coreService?: CoreService;
  private backgroundRecoveryTimer: number = 0;
  private recovering: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.coreService = new CoreService(this.context);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    this.stopBackgroundRecovery();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', 'Ability onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      this.applyStoredColorMode();
      this.coreService?.initializePictureInPicture(windowStage.getMainWindowSync().getUIContext())
        .catch((error: Object): void => {
          hilog.warn(DOMAIN, 'testTag', 'PiP initialization unavailable: %{public}s', JSON.stringify(error));
        });
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  private applyStoredColorMode(): void {
    const mode = new RuntimeStateStore(this.context).getColorMode();
    let systemMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (mode === AppColorMode.DARK) {
      systemMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } else if (mode === AppColorMode.LIGHT) {
      systemMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    try {
      this.context.getApplicationContext().setColorMode(systemMode);
    } catch (error) {
      hilog.error(DOMAIN, 'testTag', 'Failed to restore colorMode. Cause: %{public}s', JSON.stringify(error));
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    this.stopBackgroundRecovery();
    this.coreService?.onAppForeground().catch((error: Object) => {
      hilog.warn(DOMAIN, 'testTag', 'Foreground core check failed: %{public}s', JSON.stringify(error));
    });
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    this.startBackgroundRecovery();
    this.coreService?.onAppBackground().catch((error: Object) => {
      hilog.warn(DOMAIN, 'testTag', 'Unable to start background strategies: %{public}s', JSON.stringify(error));
    });
  }

  private startBackgroundRecovery(): void {
    if (this.backgroundRecoveryTimer !== 0) {
      return;
    }
    this.backgroundRecoveryTimer = setInterval((): void => {
      if (this.recovering) {
        return;
      }
      this.recovering = true;
      this.coreService?.recoverIfNeeded()
        .catch((error: Object): void => {
          hilog.warn(DOMAIN, 'testTag', 'Background recovery failed: %{public}s', JSON.stringify(error));
        })
        .finally((): void => {
          this.recovering = false;
        });
    }, BACKGROUND_RECOVERY_INTERVAL_MS);
  }

  private stopBackgroundRecovery(): void {
    if (this.backgroundRecoveryTimer !== 0) {
      clearInterval(this.backgroundRecoveryTimer);
      this.backgroundRecoveryTimer = 0;
    }
  }
}
