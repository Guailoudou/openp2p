export interface ManagementCredentials {
  username: string;
  password: string;
}

export interface LoginRequest {
  user: string;
  password: string;
}

export interface LoginResponse {
  error: number;
  token?: string;
}

export interface ManagementUserProfile {
  token?: string;
  user?: string;
  email?: string;
  phone?: string;
  addtime?: string;
}

export interface UserProfileResponse {
  error?: number;
  profile?: ManagementUserProfile;
}

export interface ManagementDevice {
  id?: string;
  name: string;
  remark?: string;
  os: string;
  version: string;
  ip: string;
  ipv6?: string;
  lanip: string;
  isActive: number;
  isUpdate?: number;
  removed?: boolean;
  activetime?: string;
  addtime?: string;
  bandwidth?: number;
  publicIPPort?: number;
  forcev6?: number;
  natType?: number;
  hasIPv4?: number;
  hasUPNPorNATPMP?: number;
  edgeServer?: string;
}

export interface DeviceListResponse {
  nodes?: ManagementDevice[];
  latestVer?: string;
}

export interface PortMapping {
  appName: string;
  protocol: string;
  punchPriority: number;
  srcPort: number;
  peerNode: string;
  peerUser?: string;
  dstHost: string;
  dstPort: number;
  whitelist?: string;
  peerIP?: string;
  peerNatType?: number;
  relayNode?: string;
  specRelayNode?: string;
  relayMode?: string;
  linkMode?: string;
  isActive?: number;
  enabled: number;
  connectTime?: string;
  error?: string;
}

export interface PortMappingResponse {
  Apps?: PortMapping[];
  error?: number;
}

export interface MemberStatusResponse {
  Apps?: PortMapping[];
  tunError?: string;
  error?: number;
}

export interface SdwanMember {
  name: string;
  ip: string;
  resource?: string;
  isActive?: number;
}

export interface SdwanConfig {
  gateway: string;
  mode: string;
  centralNode: string;
  forceRelay: number;
  punchPriority: number;
  Nodes: SdwanMember[];
}

export interface RemoteCheckResponse {
  error?: number;
}

export interface ApiResult {
  error?: number;
}

export interface DeviceEditRequest {
  newName: string;
  bandwidth: number;
  forcev6: number;
  publicIPPort: number;
}

export interface MappingEditRequest {
  appName: string;
  protocol: string;
  punchPriority: number;
  srcPort: number;
  protocol0: string;
  srcPort0: number;
  peerNode: string;
  dstHost: string;
  dstPort: number;
  whitelist: string;
  specRelayNode: string;
}

export interface MappingSwitchRequest {
  appName: string;
  peerNode: string;
  protocol: string;
  srcPort: number;
  enabled: number;
}

export interface MappingDeleteRequest {
  appName: string;
  protocol0: string;
  srcPort0: number;
  peerNode: string;
  dstHost: string;
  dstPort: number;
}

export interface RemoteCheckRequest {
  host: string;
  port: number;
}
