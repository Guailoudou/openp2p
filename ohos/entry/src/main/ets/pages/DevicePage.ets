import { PageHeader } from '../components/PageHeader';
import {
  DeviceEditRequest,
  ManagementDevice,
  MappingEditRequest,
  PortMapping
} from '../model/ManagementModels';
import { ManagementSession } from '../service/ManagementSession';

@Component
export struct DevicePage {
  @State private devices: ManagementDevice[] = [];
  @State private mappings: PortMapping[] = [];
  @State private loading: boolean = false;
  @State private message: string = '';
  @State private showSheet: boolean = false;
  @State private sheetMode: string = 'actions';
  @State private selectedDeviceName: string = '';
  @State private selectedMappingIndex: number = -1;
  @State private editDeviceName: string = '';
  @State private editBandwidth: string = '10';
  @State private editPublicPort: string = '5566';
  @State private editForceIpv6: boolean = false;
  @State private mappingName: string = '';
  @State private mappingProtocol: string = 'tcp';
  @State private mappingPunchPriority: number = 0;
  @State private mappingSourcePort: string = '222';
  @State private mappingPeerNode: string = '';
  @State private mappingTargetHost: string = 'localhost';
  @State private mappingTargetPort: string = '22';
  @State private mappingWhitelist: string = '';
  @State private mappingRelayNode: string = '';
  @State private originalProtocol: string = '';
  @State private originalSourcePort: number = 0;
  private session: ManagementSession = ManagementSession.getInstance();

  aboutToAppear(): void {
    this.loadDevices();
  }

  private selectedDevice(): ManagementDevice | undefined {
    return this.devices.find((item: ManagementDevice): boolean => item.name === this.selectedDeviceName);
  }

  private edgeServer(name: string): string {
    const device = this.devices.find((item: ManagementDevice): boolean => item.name === name);
    return device && device.edgeServer ? device.edgeServer : '';
  }

  private sheetTitle(): string {
    if (this.sheetMode === 'editDevice') {
      return '编辑设备';
    }
    if (this.sheetMode === 'mappings') {
      return '端口映射';
    }
    if (this.sheetMode === 'editMapping') {
      return this.selectedMappingIndex >= 0 ? '编辑端口映射' : '新增端口映射';
    }
    if (this.sheetMode === 'deleteDevice') {
      return '删除设备';
    }
    return this.selectedDeviceName;
  }

  private async loadDevices(): Promise<void> {
    this.loading = true;
    this.message = '';
    try {
      const response = await this.session.api.getDevices();
      this.devices = response.nodes ? response.nodes : [];
    } catch (error) {
      this.message = `加载设备失败：${String(error)}`;
    } finally {
      this.loading = false;
    }
  }

  private openActions(device: ManagementDevice): void {
    this.selectedDeviceName = device.name;
    this.sheetMode = 'actions';
    this.message = '';
    this.showSheet = true;
  }

  private openDeviceEditor(): void {
    const device = this.selectedDevice();
    if (!device) {
      return;
    }
    this.editDeviceName = device.name;
    this.editBandwidth = String(device.bandwidth ? device.bandwidth : 10);
    this.editPublicPort = String(device.publicIPPort ? device.publicIPPort : 0);
    this.editForceIpv6 = device.forcev6 === 1;
    this.sheetMode = 'editDevice';
  }

  private async saveDevice(): Promise<void> {
    const publicPort = Number(this.editPublicPort);
    if (this.editDeviceName.trim().length < 8) {
      this.message = '设备名称不能少于 8 个字符';
      return;
    }
    if (publicPort < 0 || publicPort > 65535) {
      this.message = '公网端口必须在 0-65535 之间';
      return;
    }
    const request: DeviceEditRequest = {
      newName: this.editDeviceName.trim(),
      bandwidth: Number(this.editBandwidth),
      forcev6: this.editForceIpv6 ? 1 : 0,
      publicIPPort: publicPort
    };
    this.loading = true;
    try {
      await this.session.api.editDevice(this.selectedDeviceName, request);
      this.selectedDeviceName = request.newName;
      this.message = '设备信息已保存';
      this.showSheet = false;
      await this.loadDevices();
    } catch (error) {
      this.message = `保存失败：${String(error)}`;
    } finally {
      this.loading = false;
    }
  }

  private async updateDevice(): Promise<void> {
    const device = this.selectedDevice();
    if (!device || device.isActive !== 1) {
      this.message = '设备离线，无法升级';
      return;
    }
    if (device.os === 'Android') {
      this.message = 'Android 设备请手动升级';
      return;
    }
    try {
      await this.session.api.updateDevice(device.name, this.edgeServer(device.name));
      this.message = '升级指令已发送';
      this.showSheet = false;
    } catch (error) {
      this.message = `升级失败：${String(error)}`;
    }
  }

  private async restartDevice(): Promise<void> {
    const device = this.selectedDevice();
    if (!device || device.isActive !== 1) {
      this.message = '设备离线，无法重启';
      return;
    }
    try {
      await this.session.api.restartDevice(device.name, this.edgeServer(device.name));
      this.message = '重启指令已发送';
      this.showSheet = false;
    } catch (error) {
      this.message = `重启失败：${String(error)}`;
    }
  }

  private async deleteDevice(): Promise<void> {
    try {
      const result = await this.session.api.deleteDevice(this.selectedDeviceName);
      if (result.error && result.error !== 0) {
        throw new Error(`error ${result.error}`);
      }
      this.message = '设备已删除';
      this.showSheet = false;
      await this.loadDevices();
    } catch (error) {
      this.message = `删除失败：${String(error)}`;
    }
  }

  private async openMappings(): Promise<void> {
    const device = this.selectedDevice();
    if (!device || device.isActive !== 1) {
      this.message = '设备离线，无法读取端口映射';
      return;
    }
    this.sheetMode = 'mappings';
    this.loading = true;
    try {
      this.mappings = await this.session.api.getMappings(device.name, this.edgeServer(device.name));
    } catch (error) {
      this.mappings = [];
      this.message = `读取端口映射失败：${String(error)}`;
    } finally {
      this.loading = false;
    }
  }

  private openMappingEditor(index: number): void {
    this.selectedMappingIndex = index;
    if (index >= 0) {
      const mapping = this.mappings[index];
      this.mappingName = mapping.appName;
      this.mappingProtocol = mapping.protocol;
      this.mappingPunchPriority = mapping.punchPriority;
      this.mappingSourcePort = String(mapping.srcPort);
      this.mappingPeerNode = mapping.peerNode;
      this.mappingTargetHost = mapping.dstHost;
      this.mappingTargetPort = String(mapping.dstPort);
      this.mappingWhitelist = mapping.whitelist ? mapping.whitelist : '';
      this.mappingRelayNode = mapping.specRelayNode ? mapping.specRelayNode : '';
      this.originalProtocol = mapping.protocol;
      this.originalSourcePort = mapping.srcPort;
    } else {
      this.mappingName = '新建映射';
      this.mappingProtocol = 'tcp';
      this.mappingPunchPriority = 0;
      this.mappingSourcePort = '222';
      const peer = this.devices.find((item: ManagementDevice): boolean => item.name !== this.selectedDeviceName);
      this.mappingPeerNode = peer ? peer.name : '';
      this.mappingTargetHost = 'localhost';
      this.mappingTargetPort = peer && peer.os.toLowerCase().includes('windows') ? '3389' : '22';
      this.mappingWhitelist = '';
      this.mappingRelayNode = '';
      this.originalProtocol = '';
      this.originalSourcePort = 0;
    }
    this.sheetMode = 'editMapping';
  }

  private validateMapping(): string {
    const sourcePort = Number(this.mappingSourcePort);
    const targetPort = Number(this.mappingTargetPort);
    if (this.mappingName.length === 0 || this.mappingName.length > 32) {
      return '映射名称必须为 1-32 个字符';
    }
    if (this.mappingPeerNode.length === 0) {
      return '请选择远端设备';
    }
    if (sourcePort < 0 || sourcePort > 65535 || targetPort < 0 || targetPort > 65535) {
      return '端口必须在 0-65535 之间';
    }
    const occupied = this.mappings.some((item: PortMapping): boolean =>
      item.srcPort === sourcePort && item.protocol === this.mappingProtocol &&
      !(item.srcPort === this.originalSourcePort && item.protocol === this.originalProtocol));
    return occupied ? '该本地端口已被其他映射占用' : '';
  }

  private async saveMapping(): Promise<void> {
    const validation = this.validateMapping();
    if (validation.length > 0) {
      this.message = validation;
      return;
    }
    const request: MappingEditRequest = {
      appName: this.mappingName,
      protocol: this.mappingProtocol,
      punchPriority: this.mappingPunchPriority,
      srcPort: Number(this.mappingSourcePort),
      protocol0: this.originalProtocol,
      srcPort0: this.originalSourcePort,
      peerNode: this.mappingPeerNode,
      dstHost: this.mappingTargetHost,
      dstPort: Number(this.mappingTargetPort),
      whitelist: this.mappingWhitelist,
      specRelayNode: this.mappingRelayNode
    };
    this.loading = true;
    try {
      await this.session.api.saveMapping(this.selectedDeviceName, this.edgeServer(this.mappingPeerNode), request);
      this.message = '端口映射已保存';
      await this.openMappings();
    } catch (error) {
      this.message = `保存失败：${String(error)}`;
    } finally {
      this.loading = false;
    }
  }

  private async checkRemote(): Promise<void> {
    if (this.mappingProtocol !== 'tcp') {
      this.message = '远端服务检测仅支持 TCP';
      return;
    }
    try {
      const response = await this.session.api.checkRemote(this.mappingPeerNode,
        this.edgeServer(this.mappingPeerNode), this.mappingTargetHost, Number(this.mappingTargetPort));
      this.message = response.error ? '远端服务不可达' : '远端服务可达';
    } catch (error) {
      this.message = `检测失败：${String(error)}`;
    }
  }

  private async toggleMapping(index: number): Promise<void> {
    const mapping = this.mappings[index];
    const enabled = mapping.enabled === 1 ? 0 : 1;
    try {
      await this.session.api.switchMapping(this.selectedDeviceName, mapping, enabled);
      this.mappings[index].enabled = enabled;
      this.mappings = [...this.mappings];
    } catch (error) {
      this.message = `切换失败：${String(error)}`;
    }
  }

  private async deleteMapping(index: number): Promise<void> {
    const mapping = this.mappings[index];
    try {
      await this.session.api.deleteMapping(this.selectedDeviceName,
        this.edgeServer(this.selectedDeviceName), mapping);
      this.mappings.splice(index, 1);
      this.mappings = [...this.mappings];
      this.message = '端口映射已删除';
    } catch (error) {
      this.message = `删除失败：${String(error)}`;
    }
  }

  @Builder
  private deviceActions() {
    Column({ space: 12 }) {
      Button('端口映射').width('100%').height(48).onClick((): void => { this.openMappings(); })
      Button('编辑设备').width('100%').height(48).onClick((): void => { this.openDeviceEditor(); })
      Button('升级客户端').width('100%').height(48).onClick((): void => { this.updateDevice(); })
      Button('重启设备').width('100%').height(48).onClick((): void => { this.restartDevice(); })
      Button('删除设备')
        .width('100%').height(48).fontColor(Color.Red).backgroundColor(Color.Transparent)
        .onClick((): void => { this.sheetMode = 'deleteDevice'; })
    }.width('100%')
  }

  @Builder
  private deviceEditor() {
    Column({ space: 14 }) {
      TextInput({ text: this.editDeviceName, placeholder: '设备名称' })
        .onChange((value: string): void => { this.editDeviceName = value; })
      TextInput({ text: this.editBandwidth, placeholder: '共享带宽 Mbps' })
        .type(InputType.Number).onChange((value: string): void => { this.editBandwidth = value; })
      TextInput({ text: this.editPublicPort, placeholder: '公网端口' })
        .type(InputType.Number).onChange((value: string): void => { this.editPublicPort = value; })
      Row() {
        Text('强制使用 IPv6').layoutWeight(1).fontColor($r('app.color.text_primary'))
        Toggle({ type: ToggleType.Switch, isOn: this.editForceIpv6 })
          .onChange((value: boolean): void => { this.editForceIpv6 = value; })
      }.width('100%')
      Button('保存').width('100%').height(48).onClick((): void => { this.saveDevice(); })
    }.width('100%')
  }

  @Builder
  private mappingList() {
    Column({ space: 12 }) {
      Button('新增端口映射')
        .width('100%').height(46).onClick((): void => { this.openMappingEditor(-1); })
      if (this.loading) {
        LoadingProgress().width(36).height(36)
      } else if (this.mappings.length === 0) {
        Text('暂无端口映射').fontColor($r('app.color.text_secondary')).padding(24)
      } else {
        List({ space: 10 }) {
          ForEach(this.mappings, (mapping: PortMapping, index: number) => {
            ListItem() {
              Column({ space: 10 }) {
                Row() {
                  Column({ space: 3 }) {
                    Text(mapping.appName).fontSize(17).fontWeight(FontWeight.Medium)
                    Text(`${mapping.protocol.toUpperCase()} ${mapping.srcPort}  →  ${mapping.peerNode}:${mapping.dstPort}`)
                      .fontSize(13).fontColor($r('app.color.text_secondary'))
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Toggle({ type: ToggleType.Switch, isOn: mapping.enabled === 1 })
                    .onChange((): void => { this.toggleMapping(index); })
                }.width('100%')
                Row({ space: 10 }) {
                  Button('编辑').layoutWeight(1).onClick((): void => { this.openMappingEditor(index); })
                  Button('删除').layoutWeight(1).fontColor(Color.Red)
                    .onClick((): void => { this.deleteMapping(index); })
                }.width('100%')
              }
              .width('100%').padding(14).backgroundColor($r('app.color.page_background')).borderRadius(14)
            }
          }, (mapping: PortMapping): string => `${mapping.protocol}-${mapping.srcPort}`)
        }.width('100%').layoutWeight(1)
      }
    }.width('100%').height('100%')
  }

  @Builder
  private mappingEditor() {
    Scroll() {
      Column({ space: 14 }) {
        TextInput({ text: this.mappingName, placeholder: '映射名称' })
          .onChange((value: string): void => { this.mappingName = value; })
        Select([{ value: 'TCP' }, { value: 'UDP' }])
          .selected(this.mappingProtocol === 'tcp' ? 0 : 1)
          .onSelect((index: number): void => { this.mappingProtocol = index === 0 ? 'tcp' : 'udp'; })
        TextInput({ text: this.mappingSourcePort, placeholder: '本地端口' })
          .type(InputType.Number).onChange((value: string): void => { this.mappingSourcePort = value; })
        Text('远端设备').width('100%').fontSize(14).fontColor($r('app.color.text_secondary'))
        Row({ space: 8 }) {
          ForEach(this.devices.filter((item: ManagementDevice): boolean => item.name !== this.selectedDeviceName),
            (device: ManagementDevice) => {
              Button(device.name)
                .fontColor(this.mappingPeerNode === device.name ? $r('app.color.button_text') : $r('app.color.text_primary'))
                .backgroundColor(this.mappingPeerNode === device.name ? $r('app.color.accent') : $r('app.color.page_background'))
                .onClick((): void => { this.mappingPeerNode = device.name; })
            }, (device: ManagementDevice): string => device.name)
        }.width('100%')
        TextInput({ text: this.mappingTargetHost, placeholder: '远端主机' })
          .onChange((value: string): void => { this.mappingTargetHost = value; })
        TextInput({ text: this.mappingTargetPort, placeholder: '远端端口' })
          .type(InputType.Number).onChange((value: string): void => { this.mappingTargetPort = value; })
        TextInput({ text: this.mappingWhitelist, placeholder: '访问白名单（可选）' })
          .onChange((value: string): void => { this.mappingWhitelist = value; })
        TextInput({ text: this.mappingRelayNode, placeholder: '指定中继节点（可选）' })
          .onChange((value: string): void => { this.mappingRelayNode = value; })
        Text('打洞优先级').width('100%').fontSize(14).fontColor($r('app.color.text_secondary'))
        Select([{ value: '默认' }, { value: 'TCP 优先' }, { value: '仅 TCP' }, { value: '仅 UDP' }])
          .selected(this.mappingPunchPriority)
          .onSelect((index: number): void => { this.mappingPunchPriority = index; })
        Row({ space: 10 }) {
          Button('检测远端服务').layoutWeight(1).onClick((): void => { this.checkRemote(); })
          Button('保存').layoutWeight(1).onClick((): void => { this.saveMapping(); })
        }.width('100%')
      }.width('100%')
    }.width('100%').height('100%')
  }

  @Builder
  private sheetContent() {
    Column({ space: 16 }) {
      if (this.message.length > 0) {
        Text(this.message).width('100%').fontSize(14).fontColor($r('app.color.text_secondary'))
      }
      if (this.sheetMode === 'actions') {
        this.deviceActions()
      } else if (this.sheetMode === 'editDevice') {
        this.deviceEditor()
      } else if (this.sheetMode === 'mappings') {
        this.mappingList()
      } else if (this.sheetMode === 'editMapping') {
        this.mappingEditor()
      } else {
        Text(`确定从管理中心删除设备“${this.selectedDeviceName}”吗？`)
          .width('100%').fontSize(16).lineHeight(24)
        Button('确认删除')
          .width('100%').height(48).fontColor(Color.White).backgroundColor(Color.Red)
          .onClick((): void => { this.deleteDevice(); })
      }
    }
    .width('100%').height(this.sheetMode === 'mappings' || this.sheetMode === 'editMapping' ? '100%' : undefined)
    .padding({ left: 20, right: 20, top: 12, bottom: 32 })
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        PageHeader({ title: '设备', subtitle: '管理 OpenP2P 设备与端口映射' })
        Button('刷新设备')
          .width('100%').height(42).onClick((): void => { this.loadDevices(); })
        if (this.message.length > 0) {
          Text(this.message)
            .width('100%').padding(14).fontSize(14).fontColor($r('app.color.text_secondary'))
            .backgroundColor($r('app.color.card_background')).borderRadius(14)
        }
        if (this.loading && this.devices.length === 0) {
          LoadingProgress().width(42).height(42).margin({ top: 48 })
        } else if (this.devices.length === 0) {
          Text('暂无设备').fontSize(16).fontColor($r('app.color.text_secondary')).padding(48)
        } else {
          ForEach(this.devices, (device: ManagementDevice) => {
            Column({ space: 12 }) {
              Row() {
                Column({ space: 4 }) {
                  Text(device.remark ? device.remark : device.name)
                    .fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                  Text(device.name).fontSize(12).fontColor($r('app.color.text_tertiary'))
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text(device.isActive === 1 ? '在线' : '离线')
                  .fontSize(13).fontColor(device.isActive === 1 ? Color.Green : $r('app.color.text_tertiary'))
              }.width('100%')
              Row() {
                Text(`${device.os} · ${device.version}`).fontSize(13).fontColor($r('app.color.text_secondary'))
                Blank()
                Text(device.lanip).fontSize(13).fontColor($r('app.color.text_secondary'))
              }.width('100%')
              Row() {
                Text('公网 IP').fontSize(13).fontColor($r('app.color.text_tertiary'))
                Blank()
                Text(device.ip).fontSize(13).fontColor($r('app.color.text_secondary'))
              }.width('100%')
            }
            .width('100%').padding(18).backgroundColor($r('app.color.card_background')).borderRadius(18)
            .shadow({ radius: 12, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 4 })
            .onClick((): void => { this.openActions(device); })
          }, (device: ManagementDevice): string => device.name)
        }
      }
      .width('100%').padding({ left: 20, right: 20, top: 24, bottom: 128 })
    }
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
    .bindSheet($$this.showSheet, this.sheetContent(), {
      height: this.sheetMode === 'mappings' || this.sheetMode === 'editMapping' ? SheetSize.LARGE : SheetSize.MEDIUM,
      dragBar: true,
      preferType: SheetType.BOTTOM,
      title: { title: this.sheetTitle() }
    })
  }
}
