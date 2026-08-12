import common from '@ohos.app.ability.common';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import vpnExtension from '@ohos.net.vpnExtension';
import { BackgroundKeepAliveOptions, BackgroundKeepAliveService } from './BackgroundKeepAliveService';
import { BackgroundLocationService } from './BackgroundLocationService';
import { PictureInPictureKeepAliveService } from './PictureInPictureKeepAliveService';
import { RuntimeStateStore } from './RuntimeStateStore';
import { TokenStore } from './TokenStore';

const DOMAIN = 0x0;
const TAG = 'OpenP2P-Service';
const VPN_ABILITY = 'OplVpnExtensionAbility';
const STATUS_FILE = 'opl_core_status.json';
const LOCK_FILE = 'vpn_ipc.lock';
const VPN_REQUEST_FILE = 'opl_vpn_request.json';
const CORE_CHECK_REQUEST_FILE = 'opl_core_check_request';
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
  private backgroundLocation: BackgroundLocationService;
  private pictureInPicture: PictureInPictureKeepAliveService = PictureInPictureKeepAliveService.getInstance();

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.runtimeStateStore = new RuntimeStateStore(context);
    this.backgroundKeepAlive = new BackgroundKeepAliveService(context);
    this.backgroundLocation = new BackgroundLocationService(context);
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

  isBackgroundKeepAliveEnabled(): boolean {
    return this.runtimeStateStore.isBackgroundKeepAliveEnabled();
  }

  isSimulatedLocationEnabled(): boolean {
    return this.runtimeStateStore.isSimulatedLocationEnabled();
  }

  isSimulatedDownloadEnabled(): boolean {
    return this.runtimeStateStore.isSimulatedDownloadEnabled();
  }

  isPictureInPictureEnabled(): boolean {
    return this.runtimeStateStore.isPictureInPictureEnabled();
  }

  async setBackgroundKeepAliveEnabled(enabled: boolean): Promise<boolean> {
    this.runtimeStateStore.setBackgroundKeepAliveEnabled(enabled);
    if (!this.isCoreActive()) {
      return true;
    }
    return this.applyBackgroundStrategies();
  }

  async setSimulatedLocationEnabled(enabled: boolean): Promise<boolean> {
    this.runtimeStateStore.setSimulatedLocationEnabled(enabled);
    const available = !enabled || await this.backgroundLocation.requestPermission();
    if (!enabled) {
      this.backgroundLocation.stop();
    }
    if (this.isCoreActive()) {
      await this.applyBackgroundStrategies();
    }
    return available;
  }

  async setSimulatedDownloadEnabled(enabled: boolean): Promise<boolean> {
    this.runtimeStateStore.setSimulatedDownloadEnabled(enabled);
    const available = !enabled || await this.backgroundKeepAlive.requestNotificationPermission();
    if (this.isCoreActive()) {
      await this.applyBackgroundStrategies();
    }
    return available;
  }

  async initializePictureInPicture(uiContext: UIContext): Promise<boolean> {
    const available = await this.pictureInPicture.initialize(uiContext, this.context);
    this.pictureInPicture.setEnabled(available && this.runtimeStateStore.isPictureInPictureEnabled() &&
      this.isCoreActive());
    return available;
  }

  async setPictureInPictureEnabled(enabled: boolean, uiContext: UIContext): Promise<boolean> {
    this.runtimeStateStore.setPictureInPictureEnabled(enabled);
    const available = !enabled || await this.pictureInPicture.initialize(uiContext, this.context);
    this.pictureInPicture.setEnabled(enabled && available && this.isCoreActive());
    return available;
  }

  async onAppForeground(): Promise<void> {
    await this.pictureInPicture.stopForForeground();
    if (!this.runtimeStateStore.isDesiredRunning()) {
      this.removeFile(CORE_CHECK_REQUEST_FILE);
      return;
    }
    const foregroundStatus = this.readStatus();
    this.writeText(CORE_CHECK_REQUEST_FILE, String(Date.now()));
    // The VPN extension polls this file every 250 ms. If the request remains,
    // its process and watchdog are no longer alive, regardless of a fresh
    // status file left behind by the previous process.
    await this.sleep(750);
    if (this.fileExists(CORE_CHECK_REQUEST_FILE) && this.isWatchdogExpectedState(foregroundStatus.state)) {
      hilog.warn(DOMAIN, TAG, 'Foreground core check was not consumed; restarting VPN extension');
      this.removeFile(CORE_CHECK_REQUEST_FILE);
      await this.recoverIfNeeded(true);
      return;
    }
    await this.recoverIfNeeded();
  }

  async onAppBackground(): Promise<void> {
    if (this.isCoreActive() && this.runtimeStateStore.isPictureInPictureEnabled()) {
      await this.pictureInPicture.startForBackground();
    }
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
    this.removeFile(CORE_CHECK_REQUEST_FILE);
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
      await this.applyBackgroundStrategies();
      return;
    }
    this.writeText(VPN_REQUEST_FILE, JSON.stringify({ action: 'start', requestId: this.requestId }));
    this.writeStatus('vpn_requested', '正在请求创建 VPN 网络接口');
    await this.applyBackgroundStrategies();
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
    this.backgroundLocation.stop();
    this.pictureInPicture.setEnabled(false);
    await this.backgroundKeepAlive.stop();
  }

  async recoverIfNeeded(force: boolean = false): Promise<boolean> {
    if (!this.runtimeStateStore.isDesiredRunning()) {
      return false;
    }

    const status = this.readStatus();
    const age = status.timestamp > 0 ? Date.now() - status.timestamp : Number.MAX_SAFE_INTEGER;
    if (!force && this.isRunningState(status.state) && age <= HEARTBEAT_STALE_MS) {
      await this.applyBackgroundStrategies();
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

  private async applyBackgroundStrategies(): Promise<boolean> {
    const locationEnabled = this.runtimeStateStore.isSimulatedLocationEnabled();
    this.pictureInPicture.setEnabled(this.runtimeStateStore.isPictureInPictureEnabled());
    const options: BackgroundKeepAliveOptions = {
      continuousTask: this.runtimeStateStore.isBackgroundKeepAliveEnabled(),
      simulatedLocation: locationEnabled,
      simulatedDownload: this.runtimeStateStore.isSimulatedDownloadEnabled()
    };
    const continuousTaskAvailable = await this.backgroundKeepAlive.configure(options);
    // A location subscription created before the location continuous task is
    // active is treated as foreground-only and is suspended in background.
    const locationAvailable = locationEnabled ?
      continuousTaskAvailable && this.backgroundLocation.start() : true;
    if (!locationEnabled) {
      this.backgroundLocation.stop();
    }
    return continuousTaskAvailable && locationAvailable;
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
    try {
      if (!fileIo.accessSync(path)) {
        fileIo.mkdirSync(path, true);
      }
    } catch (error) {
      throw new Error(`Unable to prepare log directory: ${this.formatError(error)}`);
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
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, value);
    } catch (error) {
      throw new Error(`Unable to write ${name}: ${this.formatError(error)}`);
    } finally {
      if (file !== undefined) {
        try {
          fileIo.closeSync(file.fd);
        } catch (_) {
        }
      }
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

  private fileExists(name: string): boolean {
    try {
      return fileIo.accessSync(`${this.filesDir}/${name}`);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to check file %{public}s: %{public}s', name, JSON.stringify(error));
      return false;
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

  private isWatchdogExpectedState(value: string): boolean {
    return value === 'core_started' || value === 'vpn_requested' || value === 'vpn_starting' ||
      value === 'vpn_waiting_config' || value === 'vpn_ready';
  }

  private isCoreActive(): boolean {
    const status = this.readStatus();
    const age = status.timestamp > 0 ? Date.now() - status.timestamp : Number.MAX_SAFE_INTEGER;
    const activeState = status.state === 'core_started' || status.state === 'core_restarting' ||
      status.state === 'vpn_requested' || status.state === 'vpn_starting' ||
      status.state === 'vpn_waiting_config' || status.state === 'vpn_ready';
    return activeState && age <= HEARTBEAT_STALE_MS;
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
