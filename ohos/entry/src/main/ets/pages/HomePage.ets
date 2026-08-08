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

        Column() {
          Button() {
            Row({ space: 10 }) {
              if (this.state.busy) {
                LoadingProgress()
                  .width(22)
                  .height(22)
                  .color($r('app.color.button_text'))
              } else {
                SymbolGlyph(this.state.running ?
                  $r('sys.symbol.stop_circle_fill') : $r('sys.symbol.play_fill'))
                  .fontSize(20)
                  .fontColor([$r('app.color.button_text')])
                Text(this.state.running ? '停止核心' : '启动核心')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.button_text'))
              }
            }
            .justifyContent(FlexAlign.Center)
          }
          .width('100%')
          .height(56)
          .backgroundColor(this.state.running ? $r('app.color.danger') : $r('app.color.accent'))
          .borderRadius(16)
          .enabled(!this.state.busy)
          .shadow({
            radius: this.state.running ? 12 : 18,
            color: this.state.running ? $r('app.color.danger_shadow') : $r('app.color.accent_shadow'),
            offsetX: 0,
            offsetY: 6
          })
          .onClick((): void => this.onToggleCore())
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 24, bottom: 128 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
