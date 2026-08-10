import VpnExtensionAbility from '@ohos.app.ability.VpnExtensionAbility';
import vpnExtension from '@ohos.net.vpnExtension';
import { Want } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { deviceInfo, settings } from '@kit.BasicServicesKit';
import { distributedDeviceManager } from '@kit.DistributedServiceKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import coreNative from 'libentry.so';
import { RuntimeStateStore } from '../service/RuntimeStateStore';
import { TokenStore } from '../service/TokenStore';

const DOMAIN = 0x0;
const TAG = 'OPL-VPN';
const STATUS_FILE = 'opl_core_status.json';
const LOCK_FILE = 'vpn_ipc.lock';
const VPN_REQUEST_FILE = 'opl_vpn_request.json';
const CORE_CHECK_REQUEST_FILE = 'opl_core_check_request';
const MAX_PACKET_SIZE = 64 * 1024;
const WRITE_TIMEOUT_MS = 50;
const VPN_INTERFACE = 'vpn-tun';
const POLL_INTERVAL_MS = 5;
const CORE_CHECK_INTERVAL_MS = 10 * 1000;
const CORE_CHECK_REQUEST_POLL_MS = 250;
const CORE_FAILURE_THRESHOLD = 3;
const RECOVERY_WINDOW_MS = 10 * 60 * 1000;
const MAX_RECOVERIES_PER_WINDOW = 5;
const RECOVERY_DELAYS_MS: number[] = [2 * 1000, 5 * 1000, 15 * 1000, 60 * 1000];

interface CoreState {
  baseDir: string;
  token: string;
  shareBandwidth: number;
  logLevel: number;
  requestId?: number;
}

interface VpnRequest {
  action?: string;
  requestId?: number;
}

interface SdwanNode {
  name?: string;
  ip?: string;
  resource?: string;
}

interface SdwanInfo {
  gateway?: string;
  mtu?: number;
  enable?: number;
  Nodes?: SdwanNode[];
}

interface Cidr {
  address: string;
  prefixLength: number;
}

/**
 * Owns the OHOS VPN interface and connects it to the OpenP2P Go core.
 *
 * The Go core deliberately does not call Linux route/iptables commands on
 * OpenHarmony. The system VPN service owns the interface and route table;
 * this extension only moves IP packets between the VPN fd and Go channels.
 */
export default class OplVpnExtensionAbility extends VpnExtensionAbility {
  private connection?: vpnExtension.VpnConnection;
  private vpnFd: number = -1;
  private stopping: boolean = false;
  private requestId: number = 0;
  private readBuffer: ArrayBuffer = new ArrayBuffer(MAX_PACKET_SIZE);
  private writeBuffer: ArrayBuffer = new ArrayBuffer(MAX_PACKET_SIZE);
  private launchState?: CoreState;
  private watchdogTimer: number = -1;
  private coreCheckRequestTimer: number = -1;
  private vpnGeneration: number = 0;
  private consecutiveCoreFailures: number = 0;
  private recoveryInProgress: boolean = false;
  private foregroundCheckInProgress: boolean = false;
  private recoveryTimestamps: number[] = [];
  private currentStatusState: string = 'starting';
  private currentStatusMessage: string = 'VPN 扩展已启动';

  onCreate(want: Want): void {
    this.stopping = false;
    this.requestId = this.readRequestIdFromWant(want);
    this.writeStatus('starting', 'VPN extension entered', this.requestId);
    hilog.info(DOMAIN, TAG, 'VPN extension entered; requestId=%{public}d', this.requestId);
    this.initialize(want).catch((error: Object) => {
      const detail = this.formatError(error);
      this.removeFile(LOCK_FILE);
      this.removeFile(VPN_REQUEST_FILE);
      this.writeStatus('failed', detail, this.requestId);
      hilog.error(DOMAIN, TAG, 'VPN initialization failed: %{public}s', detail);
      this.stopCoreWatchdog();
      this.stopCore();
    });
  }

  onDestroy(): void {
    this.stopping = true;
    this.stopCoreWatchdog();
    this.destroyVpn();
    this.stopCore();
    this.removeFile(LOCK_FILE);
    this.removeFile(VPN_REQUEST_FILE);
    this.removeFile(CORE_CHECK_REQUEST_FILE);
    this.writeStatus('stopped', 'VPN extension destroyed', this.requestId);
  }

  private async initialize(want: Want): Promise<void> {
    let state = this.readState(want);
    if (state === undefined) {
      state = await this.readStoredState();
    }
    if (state === undefined) {
      this.writeStatus('failed', '缺少核心启动参数，且没有可恢复的本地运行状态', this.requestId);
      hilog.warn(DOMAIN, TAG, 'No valid core start parameters or stored recovery state');
      return;
    }
    this.requestId = state.requestId ?? this.requestId;
    this.launchState = state;
    this.writeStatus('core_starting', 'Calling OpenP2PStart', this.requestId);

    hilog.info(DOMAIN, TAG, 'Calling OpenP2PStart, baseDir=%{public}s, logLevel=%{public}d',
      state.baseDir, state.logLevel);
    const coreStarted = coreNative.startCore(
      state.baseDir, state.token, this.deviceNodeCandidate(), state.shareBandwidth, state.logLevel);
    hilog.info(DOMAIN, TAG, 'OpenP2PStart returned %{public}s', String(coreStarted));
    if (!coreStarted) {
      const nativeError = this.readNativeError();
      const detail = nativeError.length > 0 ? nativeError : 'OpenP2PStart returned 0';
      this.writeStatus('failed', detail, this.requestId);
      throw new Error(detail);
    }

    // OpenP2PGetStatus becomes 2 only after RunAsModule has completed
    // GNetwork.Connect(), so liveness monitoring must not begin before this
    // server-login gate succeeds.
    const serverConnected = await this.waitForServerConnected();
    if (!serverConnected) {
      const nativeError = this.readNativeError();
      const detail = nativeError.length > 0
        ? nativeError
        : 'OpenP2P core failed to reach the running state';
      this.writeStatus('failed', detail, this.requestId);
      throw new Error(detail);
    }
    this.writeStatus('core_started', '核心已启动，端口映射功能可用', this.requestId);
    this.writeLock(this.requestId);
    this.startCoreWatchdog();

    // ClashBox starts its core first and creates TUN only after a second-stage
    // startClash request. OpenP2P has no local RPC server, so the UI sends the
    // equivalent request through a sandbox file shared by both abilities.
    if (!await this.waitForVpnRequest(this.requestId)) {
      this.writeStatus('core_started', '核心正在运行，未请求创建 SD-WAN 接口', this.requestId);
      return;
    }
    this.writeStatus('vpn_starting', '正在创建鸿蒙 VPN 接口', this.requestId);

    // The first server response can legitimately be {"Nodes":null} when the
    // authenticated node has not been assigned to an SD-WAN yet. Keep the
    // core connected and consume later server refreshes instead of treating
    // that state as a fatal native-core failure.
    await this.monitorVpnConfig();
  }

  private writeStatus(state: string, message: string, requestId: number = this.requestId): void {
    this.currentStatusState = state;
    this.currentStatusMessage = message;
    try {
      const path = `${this.context.filesDir}/${STATUS_FILE}`;
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, JSON.stringify({ state, message, timestamp: Date.now(), requestId }));
      fileIo.closeSync(file.fd);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to write core status: %{public}s', JSON.stringify(error));
    }
  }

  private readState(want?: Want): CoreState | undefined {
    // Token is accepted only from the start request. Never read or modify
    // OpenP2P config.json, and never persist the token in an IPC state file.
    const parameters = want?.parameters;
    if (parameters === undefined || parameters === null) {
      return undefined;
    }

    const baseDir = parameters['baseDir'];
    const token = parameters['token'];
    const shareBandwidth = parameters['shareBandwidth'];
    const logLevel = parameters['logLevel'];
    const requestId = parameters['requestId'];
    if (typeof baseDir === 'string' && typeof token === 'string' &&
        baseDir.length > 0 && token.length > 0) {
      return {
        baseDir,
        token,
        shareBandwidth: typeof shareBandwidth === 'number' ? shareBandwidth : 10,
        logLevel: typeof logLevel === 'number' ? logLevel : 1,
        requestId: typeof requestId === 'number' ? requestId : undefined
      };
    }

    return undefined;
  }

  private async readStoredState(): Promise<CoreState | undefined> {
    const runtimeState = new RuntimeStateStore(this.context);
    if (!runtimeState.isDesiredRunning()) {
      return undefined;
    }
    try {
      const token = await new TokenStore().load();
      if (token.length === 0) {
        return undefined;
      }
      const pendingRequestId = this.readPendingRequestId();
      hilog.info(DOMAIN, TAG, 'Restoring core parameters from secure local state');
      return {
        baseDir: this.context.filesDir,
        token,
        shareBandwidth: 10,
        logLevel: 1,
        requestId: pendingRequestId > 0 ? pendingRequestId : Date.now()
      };
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Unable to restore core parameters: %{public}s', JSON.stringify(error));
      return undefined;
    }
  }

  private readPendingRequestId(): number {
    try {
      const path = `${this.context.filesDir}/${STATUS_FILE}`;
      if (!fileIo.accessSync(path)) {
        return 0;
      }
      const status = JSON.parse(fileIo.readTextSync(path)) as Record<string, Object> | null;
      if (status === null) {
        return 0;
      }
      const requestId = status['requestId'];
      return typeof requestId === 'number' && requestId > 0 ? requestId : 0;
    } catch (_) {
      return 0;
    }
  }

  private readRequestIdFromWant(want: Want): number {
    const parameters = want.parameters;
    if (parameters === undefined || parameters === null) {
      return 0;
    }
    const value = parameters['requestId'];
    return typeof value === 'number' && value > 0 ? value : 0;
  }

  private async waitForServerConnected(): Promise<boolean> {
    let nativeState = this.readNativeState();
    // Never acknowledge startup or enable the watchdog without a native API
    // that can prove the server login completed.
    if (nativeState < 0) {
      hilog.error(DOMAIN, TAG, 'Native core status API is unavailable; server connection cannot be verified');
      return false;
    }

    const deadline = Date.now() + 35 * 1000;
    while (!this.stopping && Date.now() < deadline) {
      nativeState = this.readNativeState();
      if (nativeState === 2) {
        return true;
      }
      if (nativeState === 3 || nativeState === 0) {
        return false;
      }
      await this.sleep(250);
    }
    return false;
  }

  private readNativeState(): number {
    try {
      return coreNative.getCoreState();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to read native core state: %{public}s', JSON.stringify(error));
      return -1;
    }
  }

  private isNativeCoreRunning(): boolean {
    try {
      return coreNative.isCoreRunning();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to query native core liveness: %{public}s', JSON.stringify(error));
      return this.readNativeState() === 2;
    }
  }

  private readNativeError(): string {
    try {
      const detailed = coreNative.getCoreLastError();
      if (detailed.length > 0) {
        return detailed;
      }
      return coreNative.getLastError();
    } catch (error) {
      return JSON.stringify(error);
    }
  }

  private async waitForVpnRequest(requestId: number): Promise<boolean> {
    const deadline = Date.now() + 60 * 1000;
    while (!this.stopping && Date.now() < deadline) {
      const request = this.readVpnRequest();
      if (request !== undefined && request.action === 'start' &&
          (requestId <= 0 || request.requestId === requestId)) {
        this.removeFile(VPN_REQUEST_FILE);
        return true;
      }
      await this.sleep(200);
    }
    return false;
  }

  private readVpnRequest(): VpnRequest | undefined {
    try {
      const path = `${this.context.filesDir}/${VPN_REQUEST_FILE}`;
      if (!fileIo.accessSync(path)) {
        return undefined;
      }
      return JSON.parse(fileIo.readTextSync(path)) as VpnRequest;
    } catch (_) {
      return undefined;
    }
  }

  private writeLock(requestId: number): void {
    if (requestId <= 0) {
      return;
    }
    try {
      const path = `${this.context.filesDir}/${LOCK_FILE}`;
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, String(requestId));
      fileIo.closeSync(file.fd);
      hilog.info(DOMAIN, TAG, 'VPN extension handshake written, requestId=%{public}d', requestId);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to write VPN extension handshake: %{public}s', JSON.stringify(error));
    }
  }

  private removeFile(name: string): void {
    try {
      const path = `${this.context.filesDir}/${name}`;
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to remove %{public}s: %{public}s', name, JSON.stringify(error));
    }
  }

  private sleep(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, milliseconds);
    });
  }

  private async monitorVpnConfig(): Promise<void> {
    const nodeName = coreNative.getNodeName();
    while (!this.stopping) {
      // This call waits in a native worker until the Go core receives the
      // current config or a later MsgPushSDWanRefresh response.
      const configText = await coreNative.getSdwanConfig();
      let config: SdwanInfo;
      try {
        const parsed = JSON.parse(configText) as SdwanInfo | null;
        if (parsed === null) {
          await this.destroyVpn();
          this.writeStatus('vpn_waiting_config', '核心已连接，正在等待有效的 SD-WAN 配置', this.requestId);
          continue;
        }
        config = parsed;
      } catch (_) {
        throw new Error('OpenP2P returned invalid SD-WAN JSON');
      }

      if (config.enable === 0) {
        await this.destroyVpn();
        this.writeStatus('core_started', '核心正在运行，云端已关闭 SD-WAN/TUN', this.requestId);
        continue;
      }

      const vpnConfig = this.createVpnConfig(config, nodeName);
      if (vpnConfig === undefined) {
        await this.destroyVpn();
        const detail = `核心已连接，端口映射可用；节点 ${nodeName} 暂未加入 SD-WAN`;
        this.writeStatus('vpn_waiting_config', detail, this.requestId);
        hilog.warn(DOMAIN, TAG, '%{public}s; config=%{public}s', detail, configText);
        continue;
      }

      if (!await this.replaceVpn(vpnConfig)) {
        this.writeStatus('vpn_waiting_config', '核心已连接，鸿蒙 VPN 接口创建失败', this.requestId);
      }
    }
  }

  private async replaceVpn(config: vpnExtension.VpnConfig): Promise<boolean> {
    await this.destroyVpn();
    if (this.stopping) {
      return false;
    }
    const vpnConnection = vpnExtension.createVpnConnection(this.context);
    this.connection = vpnConnection;
    try {
      this.vpnFd = await vpnConnection.create(config);
    } catch (error) {
      this.connection = undefined;
      try {
        await vpnConnection.destroy();
      } catch (_) {
      }
      hilog.error(DOMAIN, TAG, 'OHOS VPN creation failed: %{public}s', JSON.stringify(error));
      return false;
    }
    const generation = ++this.vpnGeneration;
    hilog.info(DOMAIN, TAG, 'OHOS VPN interface created or refreshed, fd=%{public}d', this.vpnFd);
    this.writeStatus('vpn_ready', '核心已连接，SD-WAN 接口已就绪', this.requestId);
    this.readLoop(generation);
    this.writeLoop(generation);
    return true;
  }

  private createVpnConfig(info: SdwanInfo, nodeName: string): vpnExtension.VpnConfig | undefined {
    if (info.gateway === undefined || info.gateway.length === 0 || !Array.isArray(info.Nodes)) {
      return undefined;
    }
    const gateway = this.parseCidr(info.gateway);
    if (gateway === undefined) {
      return undefined;
    }
    let localIp = '';
    for (const node of info.Nodes) {
      if (node.name === nodeName && node.ip !== undefined) {
        localIp = node.ip;
        break;
      }
    }
    if (localIp.length === 0) {
      return undefined;
    }

    const routes: Array<vpnExtension.RouteInfo> = [
      this.createRoute(this.networkAddress(gateway.address, gateway.prefixLength), gateway.prefixLength)
    ];
    for (const node of info.Nodes) {
      if (node.resource === undefined || node.resource.length === 0) {
        continue;
      }
      for (const resource of node.resource.split(',')) {
        const cidr = this.parseCidr(resource.trim());
        if (cidr !== undefined) {
          routes.push(this.createRoute(this.networkAddress(cidr.address, cidr.prefixLength), cidr.prefixLength));
        }
      }
    }

    return {
      addresses: [{ address: { address: localIp, family: 1 }, prefixLength: gateway.prefixLength }],
      routes,
      mtu: info.mtu !== undefined && info.mtu > 0 ? info.mtu : 1420,
      isIPv4Accepted: true,
      isIPv6Accepted: false,
      isBlocking: false
    };
  }

  private createRoute(address: string, prefixLength: number): vpnExtension.RouteInfo {
    return {
      interface: VPN_INTERFACE,
      destination: { address: { address, family: 1 }, prefixLength },
      gateway: { address: '0.0.0.0', family: 1 },
      hasGateway: false,
      isDefaultRoute: false
    };
  }

  private parseCidr(value: string): Cidr | undefined {
    const parts = value.split('/');
    if (parts.length !== 2) {
      return undefined;
    }
    const prefixLength = Number(parts[1]);
    const octets = parts[0].split('.');
    if (octets.length !== 4 || prefixLength < 0 || prefixLength > 32) {
      return undefined;
    }
    for (const octet of octets) {
      const number = Number(octet);
      if (number < 0 || number > 255 || !Number.isInteger(number)) {
        return undefined;
      }
    }
    return { address: parts[0], prefixLength };
  }

  private networkAddress(address: string, prefixLength: number): string {
    const octets = address.split('.').map((value: string): number => Number(value));
    const fullOctets = Math.floor(prefixLength / 8);
    const remainingBits = prefixLength % 8;
    for (let index = 0; index < 4; index++) {
      if (index < fullOctets) {
        continue;
      }
      if (index === fullOctets && remainingBits > 0) {
        octets[index] = octets[index] & (256 - Math.pow(2, 8 - remainingBits));
      } else {
        octets[index] = 0;
      }
    }
    return octets.join('.');
  }

  private readLoop(generation: number): void {
    if (this.stopping || this.vpnFd < 0 || generation !== this.vpnGeneration) {
      return;
    }
    try {
      const length = fileIo.readSync(this.vpnFd, this.readBuffer, { length: MAX_PACKET_SIZE, offset: 0 });
      if (length > 0) {
        coreNative.readTun(this.readBuffer.slice(0, length));
      }
    } catch (error) {
      // A non-blocking VPN fd reports EAGAIN while there is no packet. That
      // is normal; only terminate the bridge for a real descriptor failure.
      if (!this.isWouldBlock(error as Object)) {
        hilog.error(DOMAIN, TAG, 'VPN read failed: %{public}s', JSON.stringify(error));
        this.stopping = true;
      }
    }
    if (!this.stopping && generation === this.vpnGeneration) {
      setTimeout((): void => this.readLoop(generation), POLL_INTERVAL_MS);
    }
  }

  private writeLoop(generation: number): void {
    if (this.stopping || this.vpnFd < 0 || generation !== this.vpnGeneration) {
      return;
    }
    try {
      const length = coreNative.writeTun(this.writeBuffer, WRITE_TIMEOUT_MS);
      if (length > 0) {
        fileIo.writeSync(this.vpnFd, this.writeBuffer, { length, offset: 0 });
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'VPN write failed: %{public}s', JSON.stringify(error));
      this.stopping = true;
    }
    if (!this.stopping && generation === this.vpnGeneration) {
      setTimeout((): void => this.writeLoop(generation), POLL_INTERVAL_MS);
    }
  }

  private isWouldBlock(error: Object): boolean {
    const serialized = JSON.stringify(error);
    return serialized.includes('13900034') || serialized.includes('13900010');
  }

  private startCoreWatchdog(): void {
    if (this.watchdogTimer >= 0) {
      return;
    }
    this.consecutiveCoreFailures = 0;
    this.watchdogTimer = setInterval((): void => {
      this.checkCoreLiveness();
    }, CORE_CHECK_INTERVAL_MS);
    this.coreCheckRequestTimer = setInterval((): void => {
      this.handleCoreCheckRequest();
    }, CORE_CHECK_REQUEST_POLL_MS);
    hilog.info(DOMAIN, TAG, 'Core liveness watchdog started');
  }

  private stopCoreWatchdog(): void {
    if (this.watchdogTimer >= 0) {
      clearInterval(this.watchdogTimer);
      this.watchdogTimer = -1;
    }
    if (this.coreCheckRequestTimer >= 0) {
      clearInterval(this.coreCheckRequestTimer);
      this.coreCheckRequestTimer = -1;
    }
  }

  private handleCoreCheckRequest(): void {
    const path = `${this.context.filesDir}/${CORE_CHECK_REQUEST_FILE}`;
    try {
      if (!fileIo.accessSync(path)) {
        return;
      }
      fileIo.unlinkSync(path);
      hilog.info(DOMAIN, TAG, 'Immediate core liveness check requested by foreground UI');
      this.checkCoreOnForeground().catch((error: Object) => {
        hilog.error(DOMAIN, TAG, 'Foreground core liveness check failed: %{public}s', this.formatError(error));
      });
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to handle immediate core check request: %{public}s', JSON.stringify(error));
    }
  }

  private checkCoreLiveness(): void {
    if (this.stopping || this.recoveryInProgress || this.foregroundCheckInProgress) {
      return;
    }
    if (this.isNativeCoreRunning()) {
      this.consecutiveCoreFailures = 0;
      // Refresh the timestamp used by the UIAbility to detect whether this
      // extension process was reclaimed by the system.
      this.writeStatus(this.currentStatusState, this.currentStatusMessage, this.requestId);
      return;
    }

    this.consecutiveCoreFailures++;
    hilog.warn(DOMAIN, TAG, 'Core liveness check failed %{public}d/%{public}d',
      this.consecutiveCoreFailures, CORE_FAILURE_THRESHOLD);
    if (this.consecutiveCoreFailures >= CORE_FAILURE_THRESHOLD) {
      this.recoverCore().catch((error: Object) => {
        hilog.error(DOMAIN, TAG, 'Core recovery worker failed: %{public}s', this.formatError(error));
      });
    }
  }

  private async checkCoreOnForeground(): Promise<void> {
    if (this.stopping || this.recoveryInProgress || this.foregroundCheckInProgress) {
      return;
    }
    this.foregroundCheckInProgress = true;
    try {
      if (this.isNativeCoreRunning()) {
        this.consecutiveCoreFailures = 0;
        this.writeStatus(this.currentStatusState, this.currentStatusMessage, this.requestId);
        return;
      }
      hilog.warn(DOMAIN, TAG, 'Foreground core liveness check failed 1/2; checking again in 1 second');
      await this.sleep(1000);
      if (this.stopping || this.recoveryInProgress) {
        return;
      }
      if (this.isNativeCoreRunning()) {
        this.consecutiveCoreFailures = 0;
        this.writeStatus(this.currentStatusState, this.currentStatusMessage, this.requestId);
        return;
      }
      this.consecutiveCoreFailures = CORE_FAILURE_THRESHOLD;
      hilog.warn(DOMAIN, TAG, 'Foreground core liveness check failed 2/2; recovering immediately');
      await this.recoverCore(true);
    } finally {
      this.foregroundCheckInProgress = false;
    }
  }

  private async recoverCore(immediate: boolean = false): Promise<void> {
    if (this.recoveryInProgress || this.stopping || this.launchState === undefined) {
      return;
    }
    this.recoveryInProgress = true;
    try {
      const now = Date.now();
      this.recoveryTimestamps = this.recoveryTimestamps.filter((value: number): boolean =>
        now - value < RECOVERY_WINDOW_MS);
      if (this.recoveryTimestamps.length >= MAX_RECOVERIES_PER_WINDOW) {
        this.exhaustRecovery();
        return;
      }

      const attempt = this.recoveryTimestamps.length + 1;
      const delayIndex = Math.min(attempt - 1, RECOVERY_DELAYS_MS.length - 1);
      const delay = immediate ? 0 : RECOVERY_DELAYS_MS[delayIndex];
      this.recoveryTimestamps.push(now);
      const recoveryMessage = immediate
        ? `前台连续两次检查失败，立即执行第 ${attempt} 次恢复`
        : `检测到核心已停止，${delay / 1000} 秒后执行第 ${attempt} 次恢复`;
      this.writeStatus('core_restarting', recoveryMessage, this.requestId);
      if (delay > 0) {
        await this.sleep(delay);
      }
      if (this.stopping || this.launchState === undefined) {
        return;
      }

      this.stopCore();
      await this.sleep(250);
      const state = this.launchState;
      const started = coreNative.startCore(
        state.baseDir, state.token, this.deviceNodeCandidate(), state.shareBandwidth, state.logLevel);
      if (!started || !await this.waitForServerConnected()) {
        const detail = this.readNativeError();
        this.writeStatus('core_restarting',
          `第 ${attempt} 次核心恢复失败${detail.length > 0 ? `：${detail}` : ''}`, this.requestId);
        return;
      }

      this.consecutiveCoreFailures = 0;
      if (this.vpnFd >= 0) {
        this.writeStatus('vpn_ready', '核心已自动恢复，SD-WAN 接口继续运行', this.requestId);
      } else {
        this.writeStatus('core_started', '核心已自动恢复，端口映射功能可用', this.requestId);
      }
      this.writeLock(this.requestId);
      hilog.info(DOMAIN, TAG, 'Core recovered on attempt %{public}d', attempt);
    } finally {
      this.recoveryInProgress = false;
    }
  }

  private deviceNodeCandidate(): string {
    const marketName = deviceInfo.marketName.trim();
    const productModel = deviceInfo.productModel.trim();
    let settingsName = '';
    try {
      settingsName = settings.getValueSync(this.context, settings.general.DEVICE_NAME, '').trim();
      if (this.isUsableDeviceName(settingsName) && !this.isModelName(settingsName, marketName, productModel)) {
        return settingsName;
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to read local device name: %{public}s', this.formatError(error));
    }

    const distributedName = this.readDistributedDeviceName();
    if (this.isUsableDeviceName(distributedName)) {
      return distributedName;
    }
    if (this.isUsableDeviceName(settingsName)) {
      return settingsName;
    }
    if (this.isUsableDeviceName(marketName)) {
      return marketName;
    }
    return this.isUsableDeviceName(productModel) ? productModel : 'HarmonyOS-device';
  }

  private readDistributedDeviceName(): string {
    let manager: distributedDeviceManager.DeviceManager | undefined;
    try {
      manager = distributedDeviceManager.createDeviceManager(this.context.applicationInfo.name);
      return manager.getLocalDeviceName().trim();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to read distributed local device name: %{public}s', this.formatError(error));
      return '';
    } finally {
      if (manager !== undefined) {
        try {
          distributedDeviceManager.releaseDeviceManager(manager);
        } catch (error) {
          hilog.warn(DOMAIN, TAG, 'Unable to release device manager: %{public}s', this.formatError(error));
        }
      }
    }
  }

  private isUsableDeviceName(value: string): boolean {
    return value.length > 0 && value.toLowerCase() !== 'default';
  }

  private isModelName(value: string, marketName: string, productModel: string): boolean {
    const normalized = value.toLocaleLowerCase();
    return (marketName.length > 0 && normalized === marketName.toLocaleLowerCase()) ||
      (productModel.length > 0 && normalized === productModel.toLocaleLowerCase());
  }

  private exhaustRecovery(): void {
    this.stopping = true;
    this.stopCoreWatchdog();
    this.destroyVpn();
    this.stopCore();
    this.removeFile(LOCK_FILE);
    this.removeFile(VPN_REQUEST_FILE);
    this.writeStatus('recovery_exhausted', '10 分钟内已恢复 5 次，自动恢复暂时停止', this.requestId);
    hilog.error(DOMAIN, TAG, 'Core recovery limit reached');
  }

  private async destroyVpn(): Promise<void> {
    this.vpnGeneration++;
    if (this.vpnFd >= 0) {
      try {
        fileIo.closeSync(this.vpnFd);
      } catch (_) {
        // The VPN service may already have closed the descriptor.
      }
      this.vpnFd = -1;
    }
    if (this.connection !== undefined) {
      const connection = this.connection;
      this.connection = undefined;
      try {
        await connection.destroy();
      } catch (_) {
        // The VPN service may already have destroyed the connection.
      }
    }
  }

  private stopCore(): void {
    try {
      coreNative.stopCore();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Unable to stop OpenP2P core: %{public}s', JSON.stringify(error));
    }
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
