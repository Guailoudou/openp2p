import common from '@ohos.app.ability.common';
import { wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BackgroundDownloadNotifier } from './BackgroundDownloadNotifier';

const DOMAIN = 0x0;
const TAG = 'OpenP2P-Background';
const ENTRY_ABILITY = 'EntryAbility';

export interface BackgroundKeepAliveOptions {
  continuousTask: boolean;
  simulatedLocation: boolean;
}

export class BackgroundKeepAliveService {
  private static active: boolean = false;
  private static activeModes: string = '';
  private static downloadNotifier: BackgroundDownloadNotifier = new BackgroundDownloadNotifier();
  private static cancelListenerRegistered: boolean = false;
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    if (!BackgroundKeepAliveService.cancelListenerRegistered) {
      backgroundTaskManager.on('continuousTaskCancel',
        (_info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
          BackgroundKeepAliveService.active = false;
          BackgroundKeepAliveService.activeModes = '';
          BackgroundKeepAliveService.downloadNotifier.stop();
        });
      BackgroundKeepAliveService.cancelListenerRegistered = true;
    }
  }

  async requestNotificationPermission(): Promise<boolean> {
    try {
      if (await notificationManager.isNotificationEnabled()) {
        return true;
      }
      await notificationManager.requestEnableNotification(this.context);
      // A successful request means the user accepted the authorization flow.
      // Avoid querying immediately because the permission state can propagate
      // after this promise resolves on some devices.
      return true;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Notification permission unavailable: %{public}s', JSON.stringify(error));
      return false;
    }
  }

  async configure(options: BackgroundKeepAliveOptions): Promise<boolean> {
    const modes: string[] = [];
    if (options.continuousTask) {
      modes.push('dataTransfer');
    }
    if (options.simulatedLocation) {
      modes.push('location');
    }
    if (modes.length === 0) {
      await this.stop();
      return true;
    }
    try {
      const signature = modes.join(',');
      if (BackgroundKeepAliveService.active) {
        if (BackgroundKeepAliveService.activeModes === signature) {
          return true;
        }
        const notification = await backgroundTaskManager.updateBackgroundRunning(this.context, modes);
        if (modes.includes('dataTransfer')) {
          await BackgroundKeepAliveService.downloadNotifier.start(notification.notificationId, this.context);
        }
      } else {
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
        const notification = await backgroundTaskManager.startBackgroundRunning(this.context, modes, agent);
        if (modes.includes('dataTransfer')) {
          await BackgroundKeepAliveService.downloadNotifier.start(notification.notificationId, this.context);
        }
      }
      BackgroundKeepAliveService.active = true;
      BackgroundKeepAliveService.activeModes = signature;
      if (!modes.includes('dataTransfer')) {
        await BackgroundKeepAliveService.downloadNotifier.stop();
      }
      hilog.info(DOMAIN, TAG, 'Continuous background task configured: %{public}s', signature);
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
    await BackgroundKeepAliveService.downloadNotifier.stop();
    if (!BackgroundKeepAliveService.active) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(this.context);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to stop continuous background task: %{public}s', JSON.stringify(error));
    } finally {
      BackgroundKeepAliveService.active = false;
      BackgroundKeepAliveService.activeModes = '';
    }
  }
}
