import { CoreUiState } from '../model/CoreUiState';

@Component
export struct StatusCard {
  @ObjectLink @Watch('onStateChanged') state: CoreUiState;
  @State private pulseScale: number = 1.0;

  private title(): string {
    if (this.state.coreState === 'core_restarting') {
      return '恢复中';
    }
    if (this.state.connected) {
      return '已连接';
    }
    if (this.state.coreState === 'failed' || this.state.coreState === 'recovery_exhausted') {
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
    if (this.state.coreState === 'failed' || this.state.coreState === 'recovery_exhausted') {
      return $r('app.color.status_failed');
    }
    if (this.state.running || this.state.busy) {
      return $r('app.color.status_connecting');
    }
    return $r('app.color.status_idle');
  }

  private symbol(): Resource {
    if (this.state.connected) {
      return $r('sys.symbol.checkmark_circle_fill');
    }
    if (this.state.coreState === 'failed' || this.state.coreState === 'recovery_exhausted') {
      return $r('sys.symbol.xmark_circle_fill');
    }
    if (this.state.running || this.state.busy) {
      return $r('sys.symbol.arrow_clockwise');
    }
    return $r('sys.symbol.circle');
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
        return '核心已连接，端口映射功能可用';
      case 'core_restarting':
        return this.state.coreMessage.length > 0 ? this.state.coreMessage : '正在自动恢复 OpenP2P 核心';
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
      case 'recovery_exhausted':
        return this.state.coreMessage.length > 0 ? this.state.coreMessage : '自动恢复次数已达到上限';
      case 'stopped':
        return '核心已停止运行';
      case 'unknown':
        return '暂时无法获取核心状态';
      case 'not_started':
      default:
        return '核心尚未启动';
    }
  }

  private onStateChanged(): void {
    if (this.state.running || this.state.busy) {
      this.startPulse();
    } else {
      this.pulseScale = 1.0;
    }
  }

  private startPulse(): void {
    animateTo({
      duration: 1200,
      curve: Curve.EaseInOut,
      iterations: -1,
      playMode: PlayMode.Alternate
    }, (): void => {
      this.pulseScale = 1.25;
    });
  }

  build() {
    Row({ space: 16 }) {
      Stack() {
        if (this.state.running || this.state.busy) {
          Circle()
            .width(44)
            .height(44)
            .fill(Color.Transparent)
            .stroke(this.color())
            .strokeWidth(2)
            .opacity(0.3)
            .scale({ x: this.pulseScale, y: this.pulseScale })
        }
        SymbolGlyph(this.symbol())
          .fontSize(26)
          .fontColor([this.color()])
      }
      .width(44)
      .height(44)

      Column({ space: 4 }) {
        Text(this.title())
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.description())
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(19)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 22, bottom: 22 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
    .shadow({ radius: 20, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 8 })
  }
}
