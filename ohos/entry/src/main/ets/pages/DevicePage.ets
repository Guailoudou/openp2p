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
  @State private latestVersion: string = '';
  @State private mappings: PortMapping[] = [];
  @State private loading: boolean = false;
  @State private refreshing: boolean = false;
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
  private refreshInFlight: boolean = false;
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

  private mappingStatus(mapping: PortMapping): string {
    if (mapping.enabled !== 1) {
      return '已停用';
    }
    if (mapping.isActive !== 1) {
      return mapping.error && mapping.error.length > 0 ? '连接失败' : '连接中';
    }
    if (mapping.relayMode === 'public') {
      return '中继';
    }
    if (mapping.relayMode === 'private') {
      return '中继（私有网络）';
    }
    if (mapping.linkMode === 'ipv6') {
      return 'IPv6 直连';
    }
    if (mapping.linkMode === 'intranet') {
      return '内网直连';
    }
    return '直连';
  }

  private formatConnectTime(value: string): string {
    const numeric = Number(value);
    const timestamp = Number.isNaN(numeric) ? Date.parse(value) :
      (numeric < 1000000000000 ? numeric * 1000 : numeric);
    if (Number.isNaN(timestamp)) {
      return value;
    }
    const date = new Date(timestamp);
    const pad = (part: number): string => part < 10 ? `0${part}` : String(part);
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ` +
      `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_) {
      this.message = message;
    }
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
    if (this.sheetMode === 'confirmUpdate') {
      return '确认升级';
    }
    if (this.sheetMode === 'confirmRestart') {
      return '确认重启';
    }
    return this.selectedDeviceName;
  }

  private async loadDevices(): Promise<void> {
    this.loading = true;
    this.message = '';
    try {
      const response = await this.session.api.getDevices();
      this.devices = response.nodes ? response.nodes : [];
      this.latestVersion = response.latestVer ? response.latestVer : '';
    } catch (error) {
      this.message = `加载设备失败：${String(error)}`;
    } finally {
      this.loading = false;
    }
  }

  private async refreshDevices(): Promise<void> {
    if (this.refreshInFlight) {
      return;
    }
    this.refreshInFlight = true;
    this.refreshing = true;
    try {
      await this.loadDevices();
    } finally {
      this.refreshInFlight = false;
      this.refreshing = false;
    }
  }

  private deviceCardKey(device: ManagementDevice): string {
    return `${device.name}-${device.remark ? device.remark : ''}-${device.isActive}-${device.os}-` +
      `${device.version}-${device.lanip}-${device.ip}`;
  }

  private prepareDeviceAction(device: ManagementDevice): void {
    this.selectedDeviceName = device.name;
    this.message = '';
  }

  private handleDeviceMenuAction(device: ManagementDevice, action: string): void {
    this.prepareDeviceAction(device);
    if (action === 'mappings') {
      this.sheetMode = 'mappings';
      this.showSheet = true;
      this.openMappings();
    } else if (action === 'edit') {
      this.sheetMode = 'editDevice';
      this.showSheet = true;
      this.openDeviceEditor();
    } else if (action === 'update') {
      this.sheetMode = 'confirmUpdate';
      this.showSheet = true;
      this.requestDeviceUpdate();
    } else if (action === 'restart') {
      this.sheetMode = 'confirmRestart';
      this.showSheet = true;
      this.requestDeviceRestart();
    } else if (action === 'delete') {
      this.sheetMode = 'deleteDevice';
      this.showSheet = true;
    }
  }

  @Builder
  private deviceContextMenu(device: ManagementDevice) {
    Menu() {
      if (device.isActive === 1) {
        MenuItem({ content: '端口映射' })
          .onClick((): void => { this.handleDeviceMenuAction(device, 'mappings'); })
        MenuItem({ content: '编辑设备' })
          .onClick((): void => { this.handleDeviceMenuAction(device, 'edit'); })
        if (this.upgradeUnavailableReason(device).length === 0) {
          MenuItem({
            content: this.latestVersion.length > 0 ? `升级客户端至 ${this.latestVersion}` : '升级客户端'
          })
            .onClick((): void => { this.handleDeviceMenuAction(device, 'update'); })
        }
        MenuItem({ content: '重启设备' })
          .onClick((): void => { this.handleDeviceMenuAction(device, 'restart'); })
      }
      MenuItem({ content: '删除设备' })
        .onClick((): void => { this.handleDeviceMenuAction(device, 'delete'); })
    }.width(220)
  }

  @Builder
  private deviceSwipeActions(device: ManagementDevice) {
    Row() {
      if (device.isActive === 1) {
        Button('映射')
          .width(68).height(124).borderRadius(0)
          .fontColor($r('app.color.button_text')).backgroundColor($r('app.color.accent'))
          .onClick((): void => { this.handleDeviceMenuAction(device, 'mappings'); })
        Button('编辑')
          .width(68).height(124).borderRadius(0)
          .fontColor($r('app.color.button_text')).backgroundColor($r('app.color.accent'))
          .onClick((): void => { this.handleDeviceMenuAction(device, 'edit'); })
        if (this.upgradeUnavailableReason(device).length === 0) {
          Button('升级')
            .width(68).height(124).borderRadius(0)
            .fontColor($r('app.color.button_text')).backgroundColor($r('app.color.status_connected'))
            .onClick((): void => { this.handleDeviceMenuAction(device, 'update'); })
        }
        Button('重启')
          .width(68).height(124).borderRadius(0)
          .fontColor($r('app.color.button_text')).backgroundColor($r('app.color.status_connecting'))
          .onClick((): void => { this.handleDeviceMenuAction(device, 'restart'); })
      }
      Button('删除')
        .width(68).height(124).borderRadius(0)
        .fontColor($r('app.color.button_text')).backgroundColor($r('app.color.danger'))
        .onClick((): void => { this.handleDeviceMenuAction(device, 'delete'); })
    }.height(124).borderRadius(18).clip(true)
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
    const reason = device ? this.upgradeUnavailableReason(device) : '未找到设备';
    if (!device || reason.length > 0) {
      this.message = reason;
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

  private requestDeviceUpdate(): void {
    const device = this.selectedDevice();
    if (!device) {
      return;
    }
    const reason = this.upgradeUnavailableReason(device);
    if (reason.length > 0) {
      this.message = reason;
      return;
    }
    this.sheetMode = 'confirmUpdate';
  }

  private requestDeviceRestart(): void {
    const device = this.selectedDevice();
    if (!device || device.isActive !== 1) {
      this.message = '设备离线，无法重启';
      return;
    }
    this.sheetMode = 'confirmRestart';
  }

  private upgradeUnavailableReason(device: ManagementDevice): string {
    if (device.isActive !== 1) {
      return '设备离线，无法升级';
    }
    const os = device.os.toLowerCase();
    if (os.includes('android') || os.includes('ios') || os.includes('harmony')) {
      return '手机客户端请通过应用市场或安装包手动升级';
    }
    if (this.latestVersion.length === 0) {
      return '暂时无法获取最新版本，不能确认是否可升级';
    }
    if (device.isUpdate === 1 || this.compareVersion(device.version, this.latestVersion) >= 0) {
      return `当前已是最新版本 ${this.latestVersion}`;
    }
    return '';
  }

  private compareVersion(left: string, right: string): number {
    const leftParts = left.replace(/^v/i, '').split('.');
    const rightParts = right.replace(/^v/i, '').split('.');
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
      this.mappings = [];
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

  private peerDevices(): ManagementDevice[] {
    return this.devices.filter((item: ManagementDevice): boolean => item.name !== this.selectedDeviceName);
  }

  private showPeerDevicePicker(): void {
    const peers = this.peerDevices();
    if (peers.length === 0) {
      this.message = '没有可选的远端设备';
      return;
    }
    const names = peers.map((device: ManagementDevice): string => device.name);
    let selected = names.indexOf(this.mappingPeerNode);
    if (selected < 0) {
      selected = 0;
    }
    this.getUIContext().showTextPickerDialog({
      range: names,
      selected: selected,
      value: names[selected],
      canLoop: false,
      onAccept: (result: TextPickerResult): void => {
        const value = result.value;
        if (typeof value === 'string') {
          this.mappingPeerNode = value;
          if (this.selectedMappingIndex < 0) {
            const peer = peers.find((device: ManagementDevice): boolean => device.name === value);
            this.mappingTargetPort = peer && peer.os.toLowerCase().includes('windows') ? '3389' : '22';
          }
        }
      }
    });
  }

  private punchPriorityLabel(value: number): string {
    const labels: string[] = ['默认', 'TCP 优先', '仅 TCP', '仅 UDP'];
    return labels[value] ? labels[value] : labels[0];
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
      this.showToast('远端服务检测仅支持 TCP');
      return;
    }
    try {
      const response = await this.session.api.checkRemote(this.mappingPeerNode,
        this.edgeServer(this.mappingPeerNode), this.mappingTargetHost, Number(this.mappingTargetPort));
      this.showToast(response.error ? '远端服务不可达' : '远端服务可达');
    } catch (error) {
      this.showToast(`检测失败：${String(error)}`);
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
  private fieldLabel(title: string, description: string = '') {
    Column({ space: 2 }) {
      Text(title).width('100%').fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      if (description.length > 0) {
        Text(description).width('100%').fontSize(12).fontColor($r('app.color.text_secondary'))
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private deviceEditor() {
    Column({ space: 14 }) {
      this.fieldLabel('设备名称', '至少 8 个字符，用于管理中心识别设备')
      TextInput({ text: this.editDeviceName, placeholder: '设备名称' })
        .onChange((value: string): void => { this.editDeviceName = value; })
      this.fieldLabel('共享带宽', '允许设备用于中继的最大带宽，单位 Mbps')
      TextInput({ text: this.editBandwidth, placeholder: '共享带宽 Mbps' })
        .type(InputType.Number).onChange((value: string): void => { this.editBandwidth = value; })
      this.fieldLabel('公网监听端口', '0 表示自动选择；手动设置范围为 1-65535')
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
                Row({ space: 8 }) {
                  Text(this.mappingStatus(mapping))
                    .fontSize(12)
                    .fontColor(mapping.enabled !== 1 ? $r('app.color.status_idle') :
                      (mapping.isActive === 1 ? $r('app.color.accent') : $r('app.color.status_connecting')))
                    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                    .backgroundColor(mapping.isActive === 1 && mapping.enabled === 1 ?
                      $r('app.color.accent_soft') : $r('app.color.badge_background'))
                    .borderRadius(12)
                  if (mapping.connectTime && mapping.connectTime.length > 0 && mapping.isActive === 1) {
                    Text(this.formatConnectTime(mapping.connectTime))
                      .fontSize(12).fontColor($r('app.color.text_tertiary'))
                  }
                }.width('100%')
                if (mapping.error && mapping.error.length > 0) {
                  Text(mapping.error).width('100%').fontSize(12).fontColor($r('app.color.status_failed'))
                }
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
      Column({ space: 12 }) {
        this.fieldLabel('映射名称')
        TextInput({ text: this.mappingName, placeholder: '映射名称' })
          .width('100%').height(48)
          .onChange((value: string): void => { this.mappingName = value; })
        Row({ space: 10 }) {
          Column({ space: 6 }) {
            this.fieldLabel('协议')
            Select([{ value: 'TCP' }, { value: 'UDP' }])
              .width('100%').height(48)
              .selected(this.mappingProtocol === 'tcp' ? 0 : 1)
              .value(this.mappingProtocol === 'tcp' ? 'TCP' : 'UDP')
              .onSelect((index: number): void => { this.mappingProtocol = index === 0 ? 'tcp' : 'udp'; })
          }.width(112).alignItems(HorizontalAlign.Start)
          Column({ space: 6 }) {
            this.fieldLabel('本地端口')
            TextInput({ text: this.mappingSourcePort, placeholder: '本地端口' })
              .width('100%').height(48).type(InputType.Number)
              .onChange((value: string): void => { this.mappingSourcePort = value; })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%')
        this.fieldLabel('远端设备')
        Button() {
          Row() {
            Text(this.mappingPeerNode.length > 0 ? this.mappingPeerNode : '请选择远端设备')
              .layoutWeight(1).textAlign(TextAlign.Start).fontColor($r('app.color.text_primary'))
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(18).fontColor([$r('app.color.text_secondary')])
          }.width('100%')
        }
        .width('100%').height(48).padding({ left: 20, right: 16 })
        .backgroundColor($r('app.color.page_background'))
        .onClick((): void => { this.showPeerDevicePicker(); })
        Row({ space: 10 }) {
          Column({ space: 6 }) {
            this.fieldLabel('远端主机')
            TextInput({ text: this.mappingTargetHost, placeholder: '远端主机' })
              .width('100%').height(48)
              .onChange((value: string): void => { this.mappingTargetHost = value; })
          }.layoutWeight(2).alignItems(HorizontalAlign.Start)
          Column({ space: 6 }) {
            this.fieldLabel('远端端口')
            TextInput({ text: this.mappingTargetPort, placeholder: '远端端口' })
              .width('100%').height(48).type(InputType.Number)
              .onChange((value: string): void => { this.mappingTargetPort = value; })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%')
        this.fieldLabel('访问白名单')
        TextInput({ text: this.mappingWhitelist, placeholder: '访问白名单（可选）' })
          .width('100%').height(48)
          .onChange((value: string): void => { this.mappingWhitelist = value; })
        this.fieldLabel('指定中继节点')
        TextInput({ text: this.mappingRelayNode, placeholder: '指定中继节点（可选）' })
          .width('100%').height(48)
          .onChange((value: string): void => { this.mappingRelayNode = value; })
        Row({ space: 10 }) {
          Column({ space: 6 }) {
            this.fieldLabel('打洞优先级')
            Select([{ value: '默认' }, { value: 'TCP 优先' }, { value: '仅 TCP' }, { value: '仅 UDP' }])
              .width('100%').height(48)
              .selected(this.mappingPunchPriority)
              .value(this.punchPriorityLabel(this.mappingPunchPriority))
              .onSelect((index: number): void => { this.mappingPunchPriority = index; })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Button('检测远端服务').layoutWeight(1).height(48).onClick((): void => { this.checkRemote(); })
        }.width('100%').alignItems(VerticalAlign.Bottom)
        Button('保存').width('100%').height(48).onClick((): void => { this.saveMapping(); })
      }.width('100%')
    }.width('100%').height('100%')
  }

  @Builder
  private sheetContent() {
    Column({ space: 16 }) {
      if (this.message.length > 0) {
        Text(this.message).width('100%').fontSize(14).fontColor($r('app.color.text_secondary'))
      }
      if (this.sheetMode === 'editDevice') {
        this.deviceEditor()
      } else if (this.sheetMode === 'mappings') {
        this.mappingList()
      } else if (this.sheetMode === 'editMapping') {
        this.mappingEditor()
      } else if (this.sheetMode === 'confirmUpdate') {
        Text(`确定将设备“${this.selectedDeviceName}”升级到 ${this.latestVersion} 吗？`)
          .width('100%').fontSize(16).lineHeight(24)
        Text('升级期间连接可能短暂中断。').width('100%').fontSize(13)
          .fontColor($r('app.color.text_secondary'))
        Row({ space: 10 }) {
          Button('取消').layoutWeight(1).onClick((): void => { this.showSheet = false; })
          Button('确认升级').layoutWeight(1).onClick((): void => { this.updateDevice(); })
        }.width('100%')
      } else if (this.sheetMode === 'confirmRestart') {
        Text(`确定重启设备“${this.selectedDeviceName}”吗？`)
          .width('100%').fontSize(16).lineHeight(24)
        Text('设备重启期间所有连接都会暂时断开。').width('100%').fontSize(13)
          .fontColor($r('app.color.text_secondary'))
        Row({ space: 10 }) {
          Button('取消').layoutWeight(1).onClick((): void => { this.showSheet = false; })
          Button('确认重启').layoutWeight(1).fontColor(Color.White).backgroundColor(Color.Red)
            .onClick((): void => { this.restartDevice(); })
        }.width('100%')
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
    Refresh({ refreshing: $$this.refreshing }) {
      Scroll() {
        Column({ space: 16 }) {
          PageHeader({ title: '设备', subtitle: '管理 OpenP2P 设备与端口映射' })
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
               List() {
                 ListItem() {
                   Column({ space: 12 }) {
                     Row() {
                       Column({ space: 4 }) {
                         Text(device.remark ? device.remark : device.name)
                           .fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                         Text(device.name).fontSize(12).fontColor($r('app.color.text_tertiary'))
                       }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                       Text(device.isActive === 1 ? '在线' : '离线')
                         .fontSize(13)
                         .fontColor(device.isActive === 1 ? Color.Green : $r('app.color.text_tertiary'))
                     }.width('100%')
                     Row() {
                       Text(`${device.os} · ${device.version}`)
                         .fontSize(13).fontColor($r('app.color.text_secondary'))
                       Blank()
                       Text(device.lanip).fontSize(13).fontColor($r('app.color.text_secondary'))
                     }.width('100%')
                     Row() {
                       Text('公网 IP').fontSize(13).fontColor($r('app.color.text_tertiary'))
                       Blank()
                       Text(device.ip).fontSize(13).fontColor($r('app.color.text_secondary'))
                     }.width('100%')
                   }
                   .width('100%').height(124).padding(18)
                   .backgroundColor($r('app.color.card_background')).borderRadius(18)
                   .shadow({ radius: 12, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 4 })
                 }
                 .swipeAction({
                   end: {
                     builder: (): void => { this.deviceSwipeActions(device); }
                   },
                   edgeEffect: SwipeEdgeEffect.None
                 })
                 .onClick((): void => { this.handleDeviceMenuAction(device, 'mappings'); })
                 .bindContextMenu(this.deviceContextMenu(device), ResponseType.LongPress)
               }
               .width('100%').height(124).scrollBar(BarState.Off).edgeEffect(EdgeEffect.None)
             }, (device: ManagementDevice): string => this.deviceCardKey(device))
          }
        }
        .width('100%').padding({ left: 20, right: 20, top: 24, bottom: 128 })
      }
      .width('100%').height('100%')
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .onRefreshing((): void => { this.refreshDevices(); })
    .pullToRefresh(true)
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
    .bindSheet($$this.showSheet, this.sheetContent(), {
      height: this.sheetMode === 'mappings' || this.sheetMode === 'editMapping' ? SheetSize.LARGE : SheetSize.MEDIUM,
      dragBar: true,
      preferType: SheetType.BOTTOM,
      title: { title: this.sheetTitle() }
    })
  }
}
