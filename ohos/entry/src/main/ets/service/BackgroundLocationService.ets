import common from '@ohos.app.ability.common';
import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0;
const TAG = 'OpenP2P-Location';
const BACKGROUND_LOCATION_INTERVAL_SECONDS = 60;

export class BackgroundLocationService {
  private static active: boolean = false;
  private static locationCallback: Callback<geoLocationManager.Location> =
    (_location: geoLocationManager.Location): void => {
      hilog.debug(DOMAIN, TAG, 'Background location heartbeat received');
    };
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async requestPermission(): Promise<boolean> {
    try {
      const manager = abilityAccessCtrl.createAtManager();
      const foregroundPermissions: Permissions[] = [
        'ohos.permission.APPROXIMATELY_LOCATION',
        'ohos.permission.LOCATION'
      ];
      const foreground = await manager.requestPermissionsFromUser(this.context, foregroundPermissions);
      // LOW_POWER location only requires approximate location. A user may
      // intentionally grant approximate location while declining precision.
      if (foreground.authResults.length === 0 || foreground.authResults[0] !== 0) {
        return false;
      }
      if (!this.hasBackgroundPermission(manager)) {
        await this.openPermissionSettings();
      }
      return true;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Location permission request failed: %{public}s', JSON.stringify(error));
      return false;
    }
  }

  hasBackgroundLocationPermission(): boolean {
    try {
      return this.hasBackgroundPermission(abilityAccessCtrl.createAtManager());
    } catch (_) {
      return false;
    }
  }

  private hasBackgroundPermission(manager: abilityAccessCtrl.AtManager): boolean {
    try {
      return manager.checkAccessTokenSync(this.context.applicationInfo.accessTokenId,
        'ohos.permission.LOCATION_IN_BACKGROUND') === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to check background location permission: %{public}s', JSON.stringify(error));
      return false;
    }
  }

  private async openPermissionSettings(): Promise<void> {
    const bundleName = this.context.abilityInfo.bundleName;
    try {
      await this.context.startAbility({
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        uri: 'application_info_entry',
        parameters: {
          settingsParamBundleName: bundleName,
          pushParams: bundleName
        }
      });
      hilog.info(DOMAIN, TAG, 'Opened application settings for background location permission');
    } catch (error) {
      throw new Error(`Unable to open application settings: ${JSON.stringify(error)}`);
    }
  }

  start(): boolean {
    if (BackgroundLocationService.active) {
      return true;
    }
    if (!this.hasBackgroundLocationPermission()) {
      hilog.warn(DOMAIN, TAG, 'Background location permission is not granted');
      return false;
    }
    try {
      const request: geoLocationManager.ContinuousLocationRequest = {
        interval: BACKGROUND_LOCATION_INTERVAL_SECONDS,
        locationScenario: geoLocationManager.PowerConsumptionScenario.LOW_POWER_CONSUMPTION
      };
      geoLocationManager.on('locationChange', request, BackgroundLocationService.locationCallback);
      BackgroundLocationService.active = true;
      hilog.info(DOMAIN, TAG, 'Background low-power location subscription started');
      return true;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Location subscription unavailable: %{public}s', JSON.stringify(error));
      return false;
    }
  }

  stop(): void {
    if (!BackgroundLocationService.active) {
      return;
    }
    try {
      geoLocationManager.off('locationChange', BackgroundLocationService.locationCallback);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to stop location subscription: %{public}s', JSON.stringify(error));
    } finally {
      BackgroundLocationService.active = false;
    }
  }
}
