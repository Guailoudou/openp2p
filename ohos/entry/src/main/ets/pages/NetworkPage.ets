import { PageHeader } from '../components/PageHeader';
import {
  ManagementDevice,
  PortMapping,
  SdwanConfig,
  SdwanMember
} from '../model/ManagementModels';
import { ManagementSession } from '../service/ManagementSession';

@Component
export struct NetworkPage {
  @State private devices: ManagementDevice[] = [];
  @State private config: SdwanConfig = {
    gateway: '10.0.0.0/24',
    mode: 'fullmesh',
    centralNode: '',
    forceRelay: 0,
    punchPriority: 0,
    Nodes: []
  };
  @State private loading: boolean = false;
  @State private message: string = '';
  @State private showMemberSheet: boolean = false;
  @State private memberName: string = '';
  @State private memberIp: string = '';
  @State private memberResource: string = '';
  @State private memberConnections: PortMapping[] = [];
  @State private memberTunError: string = '';
  private session: ManagementSession = ManagementSession.getInstance();

  aboutToAppear(): void {
    this.loadData();
  }

  private async loadData(): Promise<void> {
    this.loading = true;
    this.message = '';
    try {
      const deviceResponse = await this.session.api.getDevices();
      this.devices = deviceResponse.nodes ? deviceResponse.nodes : [];
      const config = await this.session.api.getSdwan();
      config.Nodes.forEach((member: SdwanMember): void => {
        const device = this.devices.find((item: ManagementDevice): boolean => item.name === member.name);
        member.isActive = device ? device.isActive : 0;
      });
      this.config = config;
    } catch (error) {
      this.message = `加载网络配置失败：${String(error)}`;
    } finally {
      this.loading = false;
    }
  }

  private availableDevices(): ManagementDevice[] {
    return this.devices.filter((device: ManagementDevice): boolean =>
      !this.config.Nodes.some((member: SdwanMember): boolean => member.name === device.name));
  }

  private relayDevices(): ManagementDevice[] {
    return this.devices.filter((device: ManagementDevice): boolean => device.isActive === 1 &&
      (device.natType === 1 || device.hasIPv4 === 1 || device.hasUPNPorNATPMP === 1));
  }

  private edgeServer(name: string): string {
    const device = this.devices.find((item: ManagementDevice): boolean => item.name === name);
    return device && device.edgeServer ? device.edgeServer : '';
  }

  private refreshConfig(): void {
    const updated: SdwanConfig = {
      gateway: this.config.gateway,
      mode: this.config.mode,
      centralNode: this.config.centralNode,
      forceRelay: this.config.forceRelay,
      punchPriority: this.config.punchPriority,
      Nodes: this.config.Nodes.slice()
    };
    this.config = updated;
  }

  private generateUniqueIp(): string {
    const gatewayParts = this.config.gateway.split('/')[0].split('.');
    if (gatewayParts.length !== 4) {
      return '';
    }
    const prefix = `${gatewayParts[0]}.${gatewayParts[1]}.${gatewayParts[2]}`;
    for (let last = 1; last < 255; last++) {
      const candidate = `${prefix}.${last}`;
      if (!this.config.Nodes.some((member: SdwanMember): boolean => member.ip === candidate)) {
        return candidate;
      }
    }
    return '';
  }

  private addMember(device: ManagementDevice): void {
    if (this.compareVersion(device.version, '3.13.0') < 0) {
      this.message = `设备 ${device.name} 版本过低，无法加入 SD-WAN`;
      return;
    }
    const ip = this.generateUniqueIp();
    if (ip.length === 0) {
      this.message = '当前网段没有可用虚拟 IP';
      return;
    }
    this.config.Nodes.push({ name: device.name, ip: ip, resource: '', isActive: device.isActive });
    this.refreshConfig();
  }

  private showAddDevicePicker(): void {
    const available = this.availableDevices();
    if (available.length === 0) {
      this.message = '没有可加入网络的设备';
      return;
    }
    const names = available.map((device: ManagementDevice): string => device.name);
    this.getUIContext().showTextPickerDialog({
      range: names,
      selected: 0,
      value: names[0],
      canLoop: false,
      onAccept: (result: TextPickerResult): void => {
        const value = result.value;
        if (typeof value === 'string') {
          const device = available.find((item: ManagementDevice): boolean => item.name === value);
          if (device) {
            this.addMember(device);
          }
        }
      }
    });
  }

  private removeMember(index: number): void {
    const removedName = this.config.Nodes[index].name;
    this.config.Nodes.splice(index, 1);
    if (this.config.centralNode === removedName) {
      this.config.centralNode = '';
    }
    this.refreshConfig();
  }

  private updateGateway(value: string): void {
    this.config.gateway = value;
    const base = value.split('/')[0].split('.');
    if (base.length === 4) {
      const prefix = `${base[0]}.${base[1]}.${base[2]}`;
      this.config.Nodes.forEach((member: SdwanMember): void => {
        const last = member.ip.split('.').pop();
        if (last) {
          member.ip = `${prefix}.${last}`;
        }
      });
    }
    this.refreshConfig();
  }

  private async openMember(member: SdwanMember): Promise<void> {
    this.memberName = member.name;
    this.memberIp = member.ip;
    this.memberResource = member.resource ? member.resource : '';
    this.memberConnections = [];
    this.memberTunError = '';
    this.showMemberSheet = true;
    try {
      const status = await this.session.api.getMemberStatus(member.name, this.edgeServer(member.name));
      this.memberConnections = status.Apps ? status.Apps : [];
      this.memberTunError = status.tunError ? status.tunError : '';
    } catch (_) {
      this.memberConnections = [];
    }
  }

  private saveMember(): void {
    if (!this.isValidIpv4(this.memberIp) || !this.isIpInGateway(this.memberIp, this.config.gateway)) {
      this.message = '虚拟 IP 无效或不在当前网段中';
      return;
    }
    const member = this.config.Nodes.find((item: SdwanMember): boolean => item.name === this.memberName);
    if (member) {
      member.ip = this.memberIp;
      member.resource = this.memberResource;
      this.refreshConfig();
    }
    this.showMemberSheet = false;
  }

  private async saveNetwork(): Promise<void> {
    if (!this.isValidCidr(this.config.gateway)) {
      this.message = '网关必须使用正确的 IPv4/CIDR 格式';
      return;
    }
    if (this.config.mode === 'central' && this.config.centralNode.length === 0) {
      this.message = '中心组网模式必须选择中心节点';
      return;
    }
    this.loading = true;
    try {
      await this.session.api.saveSdwan(this.config);
      for (let index = 0; index < this.config.Nodes.length; index++) {
        const member = this.config.Nodes[index];
        const edge = this.edgeServer(member.name);
        if (edge.length > 0) {
          await this.session.api.refreshSdwanNode(member.name, edge);
        }
      }
      this.message = '网络配置已保存并下发';
    } catch (error) {
      this.message = `保存网络失败：${String(error)}`;
    } finally {
      this.loading = false;
    }
  }

  private compareVersion(left: string, right: string): number {
    const leftParts = left.split('.');
    const rightParts = right.split('.');
    const count = Math.max(leftParts.length, rightParts.length);
    for (let index = 0; index < count; index++) {
      const difference = Number(leftParts[index] ? leftParts[index] : '0') -
        Number(rightParts[index] ? rightParts[index] : '0');
      if (difference !== 0) {
        return difference > 0 ? 1 : -1;
      }
    }
    return 0;
  }

  private punchPriorityLabel(value: number): string {
    const labels: string[] = ['默认', 'TCP 优先', '仅 TCP', '仅 UDP'];
    return labels[value] ? labels[value] : labels[0];
  }

  private isValidIpv4(value: string): boolean {
    const parts = value.split('.');
    if (parts.length !== 4) {
      return false;
    }
    return parts.every((part: string): boolean => {
      const number = Number(part);
      return part.length > 0 && number >= 0 && number <= 255 && Math.floor(number) === number;
    });
  }

  private isValidCidr(value: string): boolean {
    const parts = value.split('/');
    if (parts.length !== 2 || !this.isValidIpv4(parts[0])) {
      return false;
    }
    const prefix = Number(parts[1]);
    return prefix >= 0 && prefix <= 32 && Math.floor(prefix) === prefix;
  }

  private ipv4ToNumber(value: string): number {
    const parts = value.split('.');
    return ((Number(parts[0]) << 24) >>> 0) + (Number(parts[1]) << 16) +
      (Number(parts[2]) << 8) + Number(parts[3]);
  }

  private isIpInGateway(ip: string, gateway: string): boolean {
    if (!this.isValidCidr(gateway)) {
      return false;
    }
    const parts = gateway.split('/');
    const prefix = Number(parts[1]);
    if (prefix === 0) {
      return true;
    }
    const mask = (0xFFFFFFFF << (32 - prefix)) >>> 0;
    return (this.ipv4ToNumber(ip) & mask) === (this.ipv4ToNumber(parts[0]) & mask);
  }

  @Builder
  private segmentedMode() {
    Row({ space: 8 }) {
      Button('全互联')
        .layoutWeight(1)
        .fontColor(this.config.mode === 'fullmesh' ? $r('app.color.button_text') : $r('app.color.text_primary'))
        .backgroundColor(this.config.mode === 'fullmesh' ? $r('app.color.accent') : $r('app.color.page_background'))
        .onClick((): void => { this.config.mode = 'fullmesh'; this.refreshConfig(); })
      Button('中心组网')
        .layoutWeight(1)
        .fontColor(this.config.mode === 'central' ? $r('app.color.button_text') : $r('app.color.text_primary'))
        .backgroundColor(this.config.mode === 'central' ? $r('app.color.accent') : $r('app.color.page_background'))
        .onClick((): void => { this.config.mode = 'central'; this.refreshConfig(); })
    }.width('100%')
  }

  @Builder
  private nodeSelector() {
    Column({ space: 8 }) {
      Text(this.config.mode === 'central' ? '中心节点' : '指定中继节点')
        .width('100%').fontSize(14).fontColor($r('app.color.text_secondary'))
      Row({ space: 8 }) {
        Button('不指定')
          .fontColor(this.config.centralNode.length === 0 ? $r('app.color.button_text') : $r('app.color.text_primary'))
          .backgroundColor(this.config.centralNode.length === 0 ? $r('app.color.accent') : $r('app.color.page_background'))
          .onClick((): void => { this.config.centralNode = ''; this.refreshConfig(); })
        ForEach(this.relayDevices(), (device: ManagementDevice) => {
          Button(device.name)
            .fontColor(this.config.centralNode === device.name ? $r('app.color.button_text') : $r('app.color.text_primary'))
            .backgroundColor(this.config.centralNode === device.name ? $r('app.color.accent') :
              $r('app.color.page_background'))
            .onClick((): void => { this.config.centralNode = device.name; this.refreshConfig(); })
        }, (device: ManagementDevice): string => device.name)
      }.width('100%')
    }.width('100%')
  }

  @Builder
  private memberSheet() {
    Scroll() {
      Column({ space: 16 }) {
        TextInput({ text: this.memberIp, placeholder: '虚拟 IP' })
          .onChange((value: string): void => { this.memberIp = value; })
        TextInput({ text: this.memberResource, placeholder: '可访问资源（可选）' })
          .onChange((value: string): void => { this.memberResource = value; })
        if (this.memberTunError.length > 0) {
          Text(`TUN 异常：${this.memberTunError}`).width('100%').fontSize(14).fontColor(Color.Red)
        }
        if (this.memberConnections.length > 0) {
          Text('连接状态').width('100%').fontSize(16).fontWeight(FontWeight.Medium)
          ForEach(this.memberConnections, (mapping: PortMapping) => {
            Row() {
              Text(mapping.peerNode).layoutWeight(1).fontColor($r('app.color.text_primary'))
              Text(mapping.isActive === 1 ? '已连接' : (mapping.error ? mapping.error : '连接中'))
                .fontSize(13).fontColor(mapping.isActive === 1 ? Color.Green : $r('app.color.text_secondary'))
            }.width('100%').padding(12).backgroundColor($r('app.color.page_background')).borderRadius(12)
          }, (mapping: PortMapping): string => `${mapping.peerNode}-${mapping.appName}`)
        }
        Button('保存成员设置').width('100%').height(48).onClick((): void => { this.saveMember(); })
      }.width('100%').padding({ left: 20, right: 20, top: 12, bottom: 32 })
    }.width('100%').height('100%')
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        PageHeader({ title: '网络', subtitle: '管理 SD-WAN 网关、模式与成员' })
        Button('刷新网络配置')
          .width('100%').height(42).onClick((): void => { this.loadData(); })
        if (this.message.length > 0) {
          Text(this.message)
            .width('100%').padding(14).fontSize(14).fontColor($r('app.color.text_secondary'))
            .backgroundColor($r('app.color.card_background')).borderRadius(14)
        }
        Column({ space: 14 }) {
          Text('组网设置').width('100%').fontSize(18).fontWeight(FontWeight.Medium)
          TextInput({ text: this.config.gateway, placeholder: '网关，例如 10.0.0.0/24' })
            .onChange((value: string): void => { this.updateGateway(value); })
          this.segmentedMode()
          this.nodeSelector()
          if (this.config.mode !== 'central') {
            Row() {
              Text('强制中继').layoutWeight(1).fontColor($r('app.color.text_primary'))
              Toggle({ type: ToggleType.Switch, isOn: this.config.forceRelay === 1 })
                .onChange((value: boolean): void => {
                  this.config.forceRelay = value ? 1 : 0;
                  this.refreshConfig();
                })
            }.width('100%')
          }
          Text('打洞优先级').width('100%').fontSize(14).fontColor($r('app.color.text_secondary'))
          Select([{ value: '默认' }, { value: 'TCP 优先' }, { value: '仅 TCP' }, { value: '仅 UDP' }])
            .selected(this.config.punchPriority)
            .value(this.punchPriorityLabel(this.config.punchPriority))
            .onSelect((index: number): void => { this.config.punchPriority = index; this.refreshConfig(); })
        }
        .width('100%').padding(18).backgroundColor($r('app.color.card_background')).borderRadius(18)

        Column({ space: 12 }) {
          Text('网络成员').width('100%').fontSize(18).fontWeight(FontWeight.Medium)
          if (this.config.Nodes.length === 0) {
            Text('暂无成员').fontSize(14).fontColor($r('app.color.text_secondary')).padding(18)
          }
          ForEach(this.config.Nodes, (member: SdwanMember, index: number) => {
            Row({ space: 10 }) {
              Column({ space: 3 }) {
                Text(member.name).fontSize(16).fontWeight(FontWeight.Medium)
                Text(`${member.ip} · ${member.isActive === 1 ? '在线' : '离线'}`)
                  .fontSize(13).fontColor($r('app.color.text_secondary'))
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Button('编辑').onClick((): void => { this.openMember(member); })
              Button('移除').fontColor(Color.Red).onClick((): void => { this.removeMember(index); })
            }.width('100%').padding(12).backgroundColor($r('app.color.page_background')).borderRadius(14)
          }, (member: SdwanMember): string => member.name)
        }
        .width('100%').padding(18).backgroundColor($r('app.color.card_background')).borderRadius(18)

        if (this.availableDevices().length > 0) {
          Column({ space: 10 }) {
            Text('可加入设备').width('100%').fontSize(18).fontWeight(FontWeight.Medium)
            Text(`当前有 ${this.availableDevices().length} 台设备可加入`)
              .width('100%').fontSize(13).fontColor($r('app.color.text_secondary'))
            Button('滑动选择设备')
              .width('100%').height(48).onClick((): void => { this.showAddDevicePicker(); })
          }.width('100%').padding(18).backgroundColor($r('app.color.card_background')).borderRadius(18)
        }

        Button(this.loading ? '正在保存…' : '保存网络配置')
          .width('100%').height(50).enabled(!this.loading).onClick((): void => { this.saveNetwork(); })
      }
      .width('100%').padding({ left: 20, right: 20, top: 24, bottom: 128 })
    }
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
    .bindSheet($$this.showMemberSheet, this.memberSheet(), {
      height: SheetSize.LARGE,
      dragBar: true,
      preferType: SheetType.BOTTOM,
      title: { title: this.memberName }
    })
  }
}
