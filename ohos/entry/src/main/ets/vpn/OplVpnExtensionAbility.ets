import VpnExtensionAbility from '@ohos.app.ability.VpnExtensionAbility';
import vpnExtension from '@ohos.net.vpnExtension';
import { Want } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import coreNative from 'libentry.so';

const DOMAIN = 0x0;
const TAG = 'OPL-VPN';
const STATUS_FILE = 'opl_core_status.json';
const LOCK_FILE = 'vpn_ipc.lock';
const VPN_REQUEST_FILE = 'opl_vpn_request.json';
const MAX_PACKET_SIZE = 64 * 1024;
const WRITE_TIMEOUT_MS = 50;
const VPN_INTERFACE = 'vpn-tun';
const POLL_INTERVAL_MS = 5;

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
      this.stopCore();
    });
  }

  onDestroy(): void {
    this.stopping = true;
    this.destroyVpn();
    this.stopCore();
    this.removeFile(LOCK_FILE);
    this.removeFile(VPN_REQUEST_FILE);
    this.writeStatus('stopped', 'VPN extension destroyed', this.requestId);
  }

  private async initialize(want: Want): Promise<void> {
    const state = this.readState(want);
    if (state === undefined) {
      this.writeStatus('failed', 'No core start parameters', this.requestId);
      hilog.warn(DOMAIN, TAG, 'No core start parameters; VPN extension will exit');
      return;
    }
    this.requestId = state.requestId ?? this.requestId;
    this.writeStatus('core_starting', 'Calling OpenP2PStart', this.requestId);

    hilog.info(DOMAIN, TAG, 'Calling OpenP2PStart, baseDir=%{public}s, logLevel=%{public}d',
      state.baseDir, state.logLevel);
    const coreStarted = coreNative.startCore(state.baseDir, state.token, state.shareBandwidth, state.logLevel);
    hilog.info(DOMAIN, TAG, 'OpenP2PStart returned %{public}s', String(coreStarted));
    if (!coreStarted) {
      const nativeError = this.readNativeError();
      const detail = nativeError.length > 0 ? nativeError : 'OpenP2PStart returned 0';
      this.writeStatus('failed', detail, this.requestId);
      throw new Error(detail);
    }

    const coreReady = await this.waitForCoreReady();
    if (!coreReady) {
      const nativeError = this.readNativeError();
      const detail = nativeError.length > 0
        ? nativeError
        : 'OpenP2P core failed to reach the running state';
      this.writeStatus('failed', detail, this.requestId);
      throw new Error(detail);
    }
    this.writeStatus('core_started', 'OpenP2P core is running', this.requestId);
    this.writeLock(this.requestId);

    // ClashBox starts its core first and creates TUN only after a second-stage
    // startClash request. OpenP2P has no local RPC server, so the UI sends the
    // equivalent request through a sandbox file shared by both abilities.
    if (!await this.waitForVpnRequest(this.requestId)) {
      this.writeStatus('core_started', 'Core is running; VPN interface was not requested', this.requestId);
      return;
    }
    this.writeStatus('vpn_starting', 'Creating OHOS VPN interface', this.requestId);

    // The first server response can legitimately be {"Nodes":null} when the
    // authenticated node has not been assigned to an SD-WAN yet. Keep the
    // core connected and consume later server refreshes instead of treating
    // that state as a fatal native-core failure.
    const vpnConfig = await this.waitForVpnConfig();
    if (vpnConfig === undefined) {
      return;
    }

    const vpnConnection = vpnExtension.createVpnConnection(this.context);
    this.connection = vpnConnection;
    try {
      this.vpnFd = await vpnConnection.create(vpnConfig);
    } catch (error) {
      throw new Error(`OHOS VPN creation failed: ${JSON.stringify(error)}`);
    }
    hilog.info(DOMAIN, TAG, 'OHOS VPN interface created, fd=%{public}d', this.vpnFd);
    this.writeStatus('vpn_ready', 'VPN interface created', this.requestId);
    this.readLoop();
    this.writeLoop();
  }

  private writeStatus(state: string, message: string, requestId: number = this.requestId): void {
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
    if (parameters !== undefined) {
      const baseDir = parameters['baseDir'] as string;
      const token = parameters['token'] as string;
      const shareBandwidth = parameters['shareBandwidth'] as number;
      const logLevel = parameters['logLevel'] as number;
      const requestId = parameters['requestId'] as number;
      if (baseDir !== undefined && token !== undefined &&
          baseDir.length > 0 && token.length > 0) {
        return {
          baseDir,
          token,
          shareBandwidth: shareBandwidth ?? 0,
          logLevel: logLevel ?? 1,
          requestId
        };
      }
    }

    return undefined;
  }

  private readRequestIdFromWant(want: Want): number {
    const value = want.parameters?.['requestId'] as number;
    return typeof value === 'number' && value > 0 ? value : 0;
  }

  private async waitForCoreReady(): Promise<boolean> {
    let nativeState = this.readNativeState();
    // Older prebuilt libopenp2p_ohos.so files do not expose the status symbol.
    // Keep the old behavior until the regenerated library is packaged.
    if (nativeState < 0) {
      hilog.warn(DOMAIN, TAG, 'Native core status API is unavailable; using legacy startup acknowledgement');
      return true;
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

  private async waitForVpnConfig(): Promise<vpnExtension.VpnConfig | undefined> {
    const nodeName = coreNative.getNodeName();
    while (!this.stopping) {
      // This call waits in a native worker until the Go core receives the
      // current config or a later MsgPushSDWanRefresh response.
      const configText = await coreNative.getSdwanConfig();
      let config: SdwanInfo;
      try {
        config = JSON.parse(configText) as SdwanInfo;
      } catch (_) {
        throw new Error('OpenP2P returned invalid SD-WAN JSON');
      }

      const vpnConfig = this.createVpnConfig(config, nodeName);
      if (vpnConfig !== undefined) {
        return vpnConfig;
      }

      const detail = `Core is online; waiting for node ${nodeName} to be assigned to an enabled SD-WAN`;
      this.writeStatus('vpn_waiting_config', detail, this.requestId);
      hilog.warn(DOMAIN, TAG, '%{public}s; config=%{public}s', detail, configText);
    }
    return undefined;
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

  private readLoop(): void {
    if (this.stopping || this.vpnFd < 0) {
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
    if (!this.stopping) {
      setTimeout((): void => this.readLoop(), POLL_INTERVAL_MS);
    }
  }

  private writeLoop(): void {
    if (this.stopping || this.vpnFd < 0) {
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
    if (!this.stopping) {
      setTimeout((): void => this.writeLoop(), POLL_INTERVAL_MS);
    }
  }

  private isWouldBlock(error: Object): boolean {
    const serialized = JSON.stringify(error);
    return serialized.includes('13900034') || serialized.includes('13900010');
  }

  private destroyVpn(): void {
    if (this.vpnFd >= 0) {
      try {
        fileIo.closeSync(this.vpnFd);
      } catch (_) {
        // The VPN service may already have closed the descriptor.
      }
      this.vpnFd = -1;
    }
    if (this.connection !== undefined) {
      this.connection.destroy().catch(() => undefined);
      this.connection = undefined;
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
