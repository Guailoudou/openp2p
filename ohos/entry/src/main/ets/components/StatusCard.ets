import { CoreUiState } from '../model/CoreUiState';

@Component
export struct StatusCard {
  @ObjectLink state: CoreUiState;

  private title(): string {
    if (this.state.connected) {
      return '已连接';
    }
    if (this.state.coreState === 'failed') {
      return '启动失败';
    }
    if (this.state.running || this.state.busy) {
      return '连接中';
    }
    return '未启动';
  }

  private color(): ResourceColor {
    if (this.state.connected) {
      return $r('app.color.status_connected');
    }
    if (this.state.coreState === 'failed') {
      return $r('app.color.status_failed');
    }
    if (this.state.running || this.state.busy) {
      return $r('app.color.status_connecting');
    }
    return $r('app.color.status_idle');
  }

  private description(): string {
    if (this.state.connected) {
      return '核心已成功登录并建立连接';
    }
    switch (this.state.coreState) {
      case 'requested':
        return '正在请求启动网络扩展';
      case 'starting':
      case 'core_starting':
        return '正在启动 OpenP2P 核心';
      case 'core_started':
        return '核心已启动，正在登录服务器';
      case 'vpn_requested':
        return '正在请求创建虚拟网络接口';
      case 'vpn_starting':
        return '正在创建虚拟网络接口';
      case 'vpn_waiting_config':
        return '正在等待虚拟网络配置';
      case 'vpn_ready':
        return '虚拟网络接口已就绪';
      case 'failed':
        return '启动失败，请前往日志页面查看详情';
      case 'stopped':
        return '核心已停止运行';
      case 'unknown':
        return '暂时无法获取核心状态';
      case 'not_started':
      default:
        return '核心尚未启动';
    }
  }

  build() {
    Row({ space: 12 }) {
      Circle()
        .width(14)
        .height(14)
        .fill(this.color())
      Column({ space: 3 }) {
        Text(this.title())
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.description())
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
    .shadow({ radius: 16, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 6 })
  }
}
