import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';

export interface CoreStatus {
  state: string;
  message: string;
  timestamp: number;
  requestId: number;
  coreAlive?: boolean;
  controlOnline?: boolean;
  vpnFdReady?: boolean;
  vpnGeneration?: number;
  coreTunGeneration?: number;
  lastPacketInMs?: number;
  lastPacketOutMs?: number;
  connectedSince?: number;
}

export class CoreStatusStore {
  private static store?: preferences.Preferences;

  private static getStore(context: common.Context): preferences.Preferences {
    if (CoreStatusStore.store === undefined) {
      if (!preferences.isStorageTypeSupported(preferences.StorageType.GSKV)) {
        throw new Error('GSKV shared core status storage is unavailable');
      }
      CoreStatusStore.store = preferences.getPreferencesSync(context, {
        name: 'opl_core_status_v1', storageType: preferences.StorageType.GSKV
      });
    }
    return CoreStatusStore.store;
  }

  static read(context: common.Context): CoreStatus {
    const value = CoreStatusStore.getStore(context).getSync('snapshot', []) as string[];
    if (value.length === 0) {
      return { state: 'not_started', message: '核心尚未启动', timestamp: 0, requestId: 0 };
    }
    if (value.length !== 12) {
      throw new Error('Invalid shared core status snapshot');
    }
    return {
      state: value[0], message: value[1], timestamp: Number(value[2]), requestId: Number(value[3]),
      coreAlive: value[4] === '1', controlOnline: value[5] === '1', vpnFdReady: value[6] === '1',
      vpnGeneration: Number(value[7]), coreTunGeneration: Number(value[8]),
      lastPacketInMs: Number(value[9]), lastPacketOutMs: Number(value[10]), connectedSince: Number(value[11])
    };
  }

  static write(context: common.Context, status: CoreStatus): void {
    // One native value keeps all fields in the same cross-process snapshot.
    const value: string[] = [
      status.state, status.message, String(status.timestamp), String(status.requestId),
      status.coreAlive ? '1' : '0', status.controlOnline ? '1' : '0', status.vpnFdReady ? '1' : '0',
      String(status.vpnGeneration ?? 0), String(status.coreTunGeneration ?? 0),
      String(status.lastPacketInMs ?? 0), String(status.lastPacketOutMs ?? 0), String(status.connectedSince ?? 0)
    ];
    CoreStatusStore.getStore(context).putSync('snapshot', value);
  }
}
