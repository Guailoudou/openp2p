import { CoreUiState } from '../model/CoreUiState';

@Component
export struct ConfigurationOverview {
  @ObjectLink @Watch('onOverviewSourceChanged') state: CoreUiState;
  @Prop @Watch('onOverviewSourceChanged') managementAuthenticated: boolean = false;
  @State private tokenSourceText: string = '未配置';
  @State private virtualNetworkText: string = '未启动';

  aboutToAppear(): void {
    this.refreshOverview();
  }

  private onOverviewSourceChanged(): void {
    this.refreshOverview();
  }

  private refreshOverview(): void {
    this.tokenSourceText = this.managementAuthenticated ? '管理账号' :
      (this.state.token.trim().length > 0 ? '本地配置' : '未配置');
    switch (this.state.coreState) {
      case 'vpn_ready':
        this.virtualNetworkText = '已就绪';
        return;
      case 'vpn_requested':
      case 'vpn_starting':
        this.virtualNetworkText = '正在创建';
        return;
      case 'vpn_waiting_config':
        this.virtualNetworkText = '等待云端配置';
        return;
      case 'failed':
      case 'recovery_exhausted':
        this.virtualNetworkText = '连接异常';
        return;
      default:
        this.virtualNetworkText = this.state.running ? '等待云端配置' : '未启动';
    }
  }

  build() {
    Column({ space: 2 }) {
      Text('配置概览').width('100%').fontSize(18).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary')).margin({ bottom: 6 })
      Row() {
        Text('Token 来源').fontSize(14).fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.tokenSourceText).fontSize(14).fontColor($r('app.color.text_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').padding({ top: 8, bottom: 8 })
      Divider().color($r('app.color.divider'))
      Row() {
        Text('虚拟网络').fontSize(14).fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.virtualNetworkText).fontSize(14).fontColor($r('app.color.text_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').padding({ top: 8, bottom: 8 })
    }
    .width('100%').padding(20).backgroundColor($r('app.color.card_background')).borderRadius(20)
    .shadow({ radius: 20, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 8 })
  }
}
