import { PageHeader } from '../components/PageHeader';
import { CoreUiState } from '../model/CoreUiState';

@Component
export struct LogsPage {
  @ObjectLink @Watch('onLogStateChanged') state: CoreUiState;
  onExportLog: () => void = (): void => {};
  private logScroller: Scroller = new Scroller();
  private scrollTimer: number = -1;

  aboutToAppear(): void {
    this.scrollToLatest(false);
  }

  aboutToDisappear(): void {
    if (this.scrollTimer >= 0) {
      clearTimeout(this.scrollTimer);
      this.scrollTimer = -1;
    }
  }

  private onLogStateChanged(): void {
    this.scrollToLatest(true);
  }

  private scrollToLatest(smooth: boolean): void {
    if (this.state.logs.length === 0) {
      return;
    }
    if (this.scrollTimer >= 0) {
      clearTimeout(this.scrollTimer);
    }
    this.scrollTimer = setTimeout((): void => {
      const lastIndex = this.state.logs.length - 1;
      if (lastIndex >= 0) {
        this.logScroller.scrollToIndex(lastIndex, smooth, ScrollAlign.END);
      }
      this.scrollTimer = -1;
    }, 0);
  }

  build() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        Row() {
          PageHeader({ title: '日志', subtitle: '实时查看 OpenP2P 核心输出' })
        }
        .layoutWeight(1)

        Button('导出日志')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.accent'))
          .height(36)
          .padding({ left: 14, right: 14 })
          .backgroundColor($r('app.color.accent_soft'))
          .borderRadius(18)
          .onClick((): void => this.onExportLog())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.state.logs.length === 0) {
        Column({ space: 12 }) {
          Text('暂无日志')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.empty_title'))
          Text('启动核心后，日志将在这里实时显示')
            .fontSize(14)
            .fontColor($r('app.color.text_tertiary'))
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 2, scroller: this.logScroller }) {
          ForEach(this.state.logs, (line: string, index: number) => {
            ListItem() {
              Text(line)
                .width('100%')
                .fontSize(12)
                .fontFamily('monospace')
                .fontColor(line.toLowerCase().includes('error') ?
                  $r('app.color.log_error') : $r('app.color.log_text'))
                .copyOption(CopyOptions.LocalDevice)
                .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            }
          }, (line: string, index: number): string => `${index}-${line}`)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ top: 8, bottom: 8 })
        .contentEndOffset(104)
        .backgroundColor($r('app.color.log_background'))
        .borderRadius(16)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 24, bottom: 24 })
    .backgroundColor($r('app.color.page_background'))
  }
}
