import { PageHeader } from '../components/PageHeader';
import { StatusCard } from '../components/StatusCard';
import { TokenCard } from '../components/TokenCard';
import { CoreUiState } from '../model/CoreUiState';

@Component
export struct HomePage {
  @ObjectLink state: CoreUiState;
  onToggleCore: () => void = (): void => {};
  onSaveToken: () => void = (): void => {};

  build() {
    Scroll() {
      Column({ space: 18 }) {
        PageHeader({ title: 'OpenP2P', subtitle: '安全、轻量的点对点连接' })
        StatusCard({ state: this.state })
        TokenCard({ state: this.state, onSave: this.onSaveToken })

        Button() {
          if (this.state.busy) {
            LoadingProgress()
              .width(22)
              .height(22)
              .color($r('app.color.button_text'))
          } else {
            Text(this.state.running ? '停止核心' : '启动核心')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.button_text'))
          }
        }
        .width('100%')
        .height(54)
        .backgroundColor(this.state.running ? $r('app.color.danger') : $r('app.color.accent'))
        .enabled(!this.state.busy)
        .onClick((): void => this.onToggleCore())

        Text('连接成功以核心日志出现 “login ok” 为准')
          .width('100%')
          .textAlign(TextAlign.Center)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 24, bottom: 128 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
