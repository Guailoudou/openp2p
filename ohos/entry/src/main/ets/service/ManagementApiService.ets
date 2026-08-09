import { http } from '@kit.NetworkKit';
import {
  ApiResult,
  DeviceEditRequest,
  DeviceListResponse,
  LoginRequest,
  LoginResponse,
  ManagementCredentials,
  ManagementUserProfile,
  MemberStatusResponse,
  MappingDeleteRequest,
  MappingEditRequest,
  MappingSwitchRequest,
  PortMapping,
  PortMappingResponse,
  RemoteCheckResponse,
  RemoteCheckRequest,
  SdwanConfig,
  UserProfileResponse
} from '../model/ManagementModels';

const SERVER_HOST = 'https://console.openpxp.com';
const REQUEST_TIMEOUT = 10000;

export class ManagementApiService {
  private token: string = '';

  setToken(token: string): void {
    this.token = token;
  }

  async login(credentials: ManagementCredentials): Promise<string> {
    const body: LoginRequest = {
      user: credentials.username,
      password: credentials.password
    };
    const response = await this.request<LoginResponse>('/api/v1/user/login', http.RequestMethod.POST, body, false);
    if (response.error !== 0 || !response.token || response.token.length === 0) {
      throw new Error('管理账号或密码错误');
    }
    return response.token;
  }

  async getUserProfile(): Promise<ManagementUserProfile> {
    const response = await this.request<UserProfileResponse>('/api/v1/user/profile', http.RequestMethod.POST);
    const token = response.profile?.token ? response.profile.token.trim() : '';
    if ((response.error !== undefined && response.error !== 0) || !/^\d+$/.test(token) || token === '0') {
      throw new Error('无法从用户信息获取 OpenP2P Token');
    }
    return response.profile as ManagementUserProfile;
  }

  async getDevices(): Promise<DeviceListResponse> {
    return this.request<DeviceListResponse>('/api/v1/devices', http.RequestMethod.GET);
  }

  async getSdwan(): Promise<SdwanConfig> {
    const config = await this.request<SdwanConfig>('/api/v1/sdwans/', http.RequestMethod.GET);
    config.Nodes = config.Nodes ? config.Nodes : [];
    config.centralNode = config.centralNode ? config.centralNode : '';
    config.gateway = config.gateway ? config.gateway : '10.0.0.0/24';
    config.mode = config.mode ? config.mode : 'fullmesh';
    config.forceRelay = config.forceRelay ? config.forceRelay : 0;
    config.punchPriority = config.punchPriority ? config.punchPriority : 0;
    return config;
  }

  async editDevice(name: string, request: DeviceEditRequest): Promise<ApiResult> {
    return this.request<ApiResult>(`/api/v1/device/${encodeURIComponent(name)}/edit`, http.RequestMethod.POST, request);
  }

  async deleteDevice(name: string): Promise<ApiResult> {
    return this.request<ApiResult>(`/api/v1/device/${encodeURIComponent(name)}/delete`, http.RequestMethod.GET);
  }

  async updateDevice(name: string, edgeServer: string): Promise<ApiResult> {
    return this.push<ApiResult>(name, 6, 0, edgeServer);
  }

  async restartDevice(name: string, edgeServer: string): Promise<ApiResult> {
    return this.push<ApiResult>(name, 11, 0, edgeServer);
  }

  async getMappings(name: string, edgeServer: string): Promise<PortMapping[]> {
    const response = await this.push<PortMappingResponse>(name, 7, 1, edgeServer);
    return response.Apps ? response.Apps.filter((item: PortMapping): boolean => item.srcPort > 0) : [];
  }

  async saveMapping(name: string, peerEdgeServer: string, request: MappingEditRequest): Promise<ApiResult> {
    const path = `/api/v1/device/${encodeURIComponent(name)}/push?subtype=9&edgeserver=${encodeURIComponent(peerEdgeServer)}`;
    return this.request<ApiResult>(path, http.RequestMethod.POST, request);
  }

  async deleteMapping(name: string, edgeServer: string, mapping: PortMapping): Promise<ApiResult> {
    const request: MappingDeleteRequest = {
      appName: mapping.appName,
      protocol0: mapping.protocol,
      srcPort0: mapping.srcPort,
      peerNode: mapping.peerNode,
      dstHost: mapping.dstHost,
      dstPort: mapping.dstPort
    };
    return this.push<ApiResult>(name, 9, 0, edgeServer, request);
  }

  async switchMapping(name: string, mapping: PortMapping, enabled: number): Promise<ApiResult> {
    const body: MappingSwitchRequest = {
      appName: mapping.appName,
      peerNode: mapping.peerNode,
      protocol: mapping.protocol,
      srcPort: mapping.srcPort,
      enabled: enabled
    };
    return this.request<ApiResult>(`/api/v1/device/${encodeURIComponent(name)}/switchapp`,
      http.RequestMethod.POST, body);
  }

  async checkRemote(peerNode: string, edgeServer: string, host: string, port: number): Promise<RemoteCheckResponse> {
    const body: RemoteCheckRequest = { host: host, port: port };
    return this.push<RemoteCheckResponse>(peerNode, 19, 1, edgeServer, body);
  }

  async saveSdwan(config: SdwanConfig): Promise<ApiResult> {
    return this.request<ApiResult>('/api/v1/sdwan/edit', http.RequestMethod.POST, config);
  }

  async refreshSdwanNode(name: string, edgeServer: string): Promise<ApiResult> {
    return this.push<ApiResult>(name, 22, 0, edgeServer);
  }

  async getMemberStatus(name: string, edgeServer: string): Promise<MemberStatusResponse> {
    return this.push<MemberStatusResponse>(name, 17, 1, edgeServer);
  }

  private async push<T>(name: string, subtype: number, rsp: number, edgeServer: string,
    body?: Object): Promise<T> {
    const path = `/api/v1/device/${encodeURIComponent(name)}/push?subtype=${subtype}&rsp=${rsp}` +
      `&edgeserver=${encodeURIComponent(edgeServer)}`;
    return this.request<T>(path, http.RequestMethod.POST, body);
  }

  private async request<T>(path: string, method: http.RequestMethod, body?: Object,
    authenticated: boolean = true): Promise<T> {
    const request = http.createHttp();
    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    };
    if (authenticated) {
      if (this.token.length === 0) {
        request.destroy();
        throw new Error('管理账号未登录');
      }
      headers.Authorization = this.token;
    }
    const options: http.HttpRequestOptions = {
      method: method,
      header: headers,
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      connectTimeout: REQUEST_TIMEOUT,
      readTimeout: REQUEST_TIMEOUT
    };
    if (body !== undefined) {
      options.extraData = JSON.stringify(body);
    }
    try {
      const response = await request.request(`${SERVER_HOST}${path}`, options);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`管理服务请求失败 (${response.responseCode})`);
      }
      const text = response.result as string;
      if (text.length === 0) {
        const emptyResult: ApiResult = {};
        return emptyResult as T;
      }
      const parsed = JSON.parse(text) as Record<string, Object>;
      const businessError = parsed['error'];
      let businessErrorCode = 0;
      if (typeof businessError === 'number') {
        businessErrorCode = businessError;
      } else if (typeof businessError === 'boolean') {
        businessErrorCode = businessError ? 1 : 0;
      } else if (typeof businessError === 'string' && businessError.length > 0) {
        const parsedCode = Number(businessError);
        businessErrorCode = Number.isNaN(parsedCode) ? 1 : parsedCode;
      }
      if (businessErrorCode !== 0) {
        const detailValue = parsed['message'] ? parsed['message'] : parsed['msg'];
        const detail = typeof detailValue === 'string' && detailValue.length > 0 ? `: ${detailValue}` : '';
        throw new Error(`管理服务操作失败 (${businessErrorCode})${detail}`);
      }
      return parsed as T;
    } finally {
      request.destroy();
    }
  }
}
