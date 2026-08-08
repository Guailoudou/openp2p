import common from '@ohos.app.ability.common';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import vpnExtension from '@ohos.net.vpnExtension';
import { BackgroundKeepAliveService } from './BackgroundKeepAliveService';
import { RuntimeStateStore } from './RuntimeStateStore';
import { TokenStore } from './TokenStore';

const DOMAIN = 0x0;
const TAG = 'OpenP2P-Service';
const VPN_ABILITY = 'OplVpnExtensionAbility';
const STATUS_FILE = 'opl_core_status.json';
const LOCK_FILE = 'vpn_ipc.lock';
const VPN_REQUEST_FILE = 'opl_vpn_request.json';
const LOG_FILE = 'log/openp2p.log';
const HEARTBEAT_STALE_MS = 35 * 1000;
const RECOVERY_COOLDOWN_MS = 10 * 60 * 1000;

export interface CoreStatus {
  state: string;
  message: string;
  timestamp: number;
  requestId: number;
}

interface CoreLaunchState {
  baseDir: string;
  token: string;
  shareBandwidth: number;
  logLevel: number;
  requestId: number;
}

export class CoreService {
  private context: common.UIAbilityContext;
  private requestId: number = 0;
  private tokenStore: TokenStore = new TokenStore();
  private runtimeStateStore: RuntimeStateStore;
  private backgroundKeepAlive: BackgroundKeepAliveService;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.runtimeStateStore = new RuntimeStateStore(context);
    this.backgroundKeepAlive = new BackgroundKeepAliveService(context);
  }

  get filesDir(): string {
    return this.context.filesDir;
  }

  readStatus(): CoreStatus {
    try {
      const path = `${this.filesDir}/${STATUS_FILE}`;
      if (!fileIo.accessSync(path)) {
        return this.emptyStatus('not_started', '核心尚未启动');
      }
      const value = JSON.parse(fileIo.readTextSync(path)) as CoreStatus;
      return {
        state: value.state ?? 'unknown',
        message: value.message ?? '',
        timestamp: value.timestamp ?? 0,
        requestId: value.requestId ?? 0
      };
    } catch (error) {
      return this.emptyStatus('unknown', this.formatError(error));
    }
  }

  readLogText(): string {
    try {
      const path = `${this.filesDir}/${LOG_FILE}`;
      if (!fileIo.accessSync(path)) {
        return '';
      }
      return fileIo.readTextSync(path);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to read core log: %{public}s', JSON.stringify(error));
      return '';
    }
  }

  loadToken(): Promise<string> {
    return this.tokenStore.load();
  }

  saveToken(token: string): Promise<void> {
    return this.tokenStore.save(token);
  }

  async start(token: string): Promise<void> {
    await this.saveToken(token);
    this.runtimeStateStore.setDesiredRunning(true);
    this.ensureLogDirectory();
    this.requestId = Date.now();

    const launchState: CoreLaunchState = {
      baseDir: this.filesDir,
      token,
      shareBandwidth: 10,
      logLevel: 1,
      requestId: this.requestId
    };

    this.removeFile(STATUS_FILE);
    this.removeFile(LOCK_FILE);
    this.removeFile(VPN_REQUEST_FILE);
    this.writeStatus('requested', '正在请求启动 VPN 扩展');

    try {
      await vpnExtension.startVpnExtensionAbility({
        deviceId: '',
        bundleName: this.context.abilityInfo.bundleName,
        abilityName: VPN_ABILITY,
        parameters: {
          baseDir: launchState.baseDir,
          token: launchState.token,
          shareBandwidth: launchState.shareBandwidth,
          logLevel: launchState.logLevel,
          requestId: launchState.requestId
        }
      });
    } catch (error) {
      const detail = this.formatError(error);
      this.writeStatus('failed', detail);
      throw new Error(`无法启动 VPN 扩展：${detail}`);
    }

    const coreReady = await this.waitForCoreReady();
    if (!coreReady) {
      const status = this.readStatus();
      throw new Error(status.message.length > 0 ? status.message : '等待 OpenP2P 核心启动超时');
    }

    const status = this.readStatus();
    if (status.state === 'vpn_ready' || status.state === 'vpn_waiting_config' ||
      status.state === 'vpn_requested' || status.state === 'vpn_starting') {
      await this.backgroundKeepAlive.start();
      return;
    }
    this.writeText(VPN_REQUEST_FILE, JSON.stringify({ action: 'start', requestId: this.requestId }));
    this.writeStatus('vpn_requested', '正在请求创建 VPN 网络接口');
    await this.backgroundKeepAlive.start();
  }

  async stop(): Promise<void> {
    this.runtimeStateStore.setDesiredRunning(false);
    try {
      await vpnExtension.stopVpnExtensionAbility({
        deviceId: '',
        bundleName: this.context.abilityInfo.bundleName,
        abilityName: VPN_ABILITY
      });
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'VPN extension already stopped: %{public}s', JSON.stringify(error));
    }
    this.removeFile(LOCK_FILE);
    this.removeFile(VPN_REQUEST_FILE);
    this.writeStatus('stopped', '核心已停止');
    await this.backgroundKeepAlive.stop();
  }

  async recoverIfNeeded(): Promise<boolean> {
    if (!this.runtimeStateStore.isDesiredRunning()) {
      return false;
    }

    const status = this.readStatus();
    const age = status.timestamp > 0 ? Date.now() - status.timestamp : Number.MAX_SAFE_INTEGER;
    if (this.isRunningState(status.state) && age <= HEARTBEAT_STALE_MS) {
      await this.backgroundKeepAlive.start();
      return false;
    }
    if (status.state === 'recovery_exhausted' && age < RECOVERY_COOLDOWN_MS) {
      return false;
    }

    const token = await this.loadToken();
    if (token.length === 0) {
      hilog.warn(DOMAIN, TAG, 'Automatic recovery skipped because no stored token is available');
      return false;
    }
    hilog.info(DOMAIN, TAG, 'Recovering desired OpenP2P session; status=%{public}s, age=%{public}d',
      status.state, age);
    await this.start(token);
    return true;
  }

  private async waitForCoreReady(): Promise<boolean> {
    const deadline = Date.now() + 35 * 1000;
    while (Date.now() < deadline) {
      const status = this.readStatus();
      if (status.state === 'core_started' || status.state === 'vpn_ready' ||
        status.state === 'vpn_waiting_config' || status.state === 'vpn_requested' ||
        status.state === 'vpn_starting') {
        if (this.hasHandshake(status.requestId)) {
          return true;
        }
      }
      if (status.state === 'failed' || status.state === 'stopped') {
        return false;
      }
      await this.sleep(250);
    }
    return false;
  }

  private hasHandshake(requestId: number): boolean {
    try {
      const path = `${this.filesDir}/${LOCK_FILE}`;
      if (!fileIo.accessSync(path)) {
        return false;
      }
      const value = fileIo.readTextSync(path).trim();
      return value.length > 0 && (requestId <= 0 || value === String(requestId));
    } catch (_) {
      return false;
    }
  }

  private ensureLogDirectory(): void {
    const path = `${this.filesDir}/log`;
    if (!fileIo.accessSync(path)) {
      fileIo.mkdirSync(path, true);
    }
  }

  private writeStatus(state: string, message: string): void {
    const status: CoreStatus = {
      state,
      message,
      timestamp: Date.now(),
      requestId: this.requestId
    };
    this.writeText(STATUS_FILE, JSON.stringify(status));
  }

  private writeText(name: string, value: string): void {
    const path = `${this.filesDir}/${name}`;
    const file = fileIo.openSync(path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, value);
    } finally {
      fileIo.closeSync(file.fd);
    }
  }

  private removeFile(name: string): void {
    try {
      const path = `${this.filesDir}/${name}`;
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to remove %{public}s: %{public}s', name, JSON.stringify(error));
    }
  }

  private emptyStatus(state: string, message: string): CoreStatus {
    return { state, message, timestamp: 0, requestId: 0 };
  }

  private isRunningState(value: string): boolean {
    return value === 'requested' || value === 'starting' || value === 'core_starting' ||
      value === 'core_started' || value === 'core_restarting' || value === 'vpn_requested' ||
      value === 'vpn_starting' || value === 'vpn_waiting_config' || value === 'vpn_ready';
  }

  private sleep(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, milliseconds);
    });
  }

  private formatError(error: Object): string {
    const value = error as Record<string, Object>;
    const message = value['message'];
    if (typeof message === 'string' && message.length > 0) {
      return message;
    }
    const serialized = JSON.stringify(error);
    return serialized === '{}' ? String(error) : serialized;
  }
}
