import { PageHeader } from '../components/PageHeader';
import { CoreUiState } from '../model/CoreUiState';

@Component
export struct LogsPage {
  @Consume private themeColor: string;
  @Consume private themeSoftColor: string;
  @ObjectLink @Watch('onLogStateChanged') state: CoreUiState;
  onExportLog: () => void = (): void => {};
  scrollController: Scroller = new Scroller();
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
        this.scrollController.scrollToIndex(lastIndex, smooth, ScrollAlign.END);
      }
      this.scrollTimer = -1;
    }, 0);
  }

  @Builder
  private emptyState() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(48)
        .fontColor([$r('app.color.text_tertiary')])
        .opacity(0.6)
      Column({ space: 6 }) {
        Text('暂无日志')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.empty_title'))
        Text('启动核心后，日志将在这里实时显示')
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
          .textAlign(TextAlign.Center)
      }
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .padding({ left: 40, right: 40, top: 40 })
  }

  build() {
    GridRow({
      columns: { xs: 4, sm: 8, md: 12, lg: 12, xl: 12 },
      breakpoints: {
        value: ['600vp', '840vp', '1200vp', '1600vp'],
        reference: BreakpointsReference.WindowSize
      }
    }) {
      GridCol({
        span: { xs: 4, sm: 8, md: 10, lg: 10, xl: 8 },
        offset: { xs: 0, sm: 0, md: 1, lg: 1, xl: 2 }
      }) {
        Column({ space: 16 }) {
      Row({ space: 12 }) {
        Row() {
          PageHeader({ title: '日志', subtitle: '实时查看 OpenP2P 核心输出' })
        }
        .layoutWeight(1)

        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.share'))
              .fontSize(16)
              .fontColor([this.themeColor])
            Text('导出')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themeColor)
          }
        }
        .height(38)
        .padding({ left: 16, right: 16 })
        .backgroundColor(this.themeSoftColor)
        .borderRadius(19)
        .onClick((): void => this.onExportLog())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.state.logs.length === 0) {
        this.emptyState()
      } else {
        List({ space: 0, scroller: this.scrollController }) {
          ForEach(this.state.logs, (line: string, index: number) => {
            ListItem() {
              Text(line)
                .width('100%')
                .fontSize(12)
                .fontFamily('monospace')
                .fontColor(line.toLowerCase().includes('error') ?
                  $r('app.color.log_error') : $r('app.color.log_text'))
                .copyOption(CopyOptions.LocalDevice)
                .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            }
          }, (line: string, index: number): string => `${index}-${line}`)
        }
        .layoutWeight(1)
        .width('100%')
        .contentEndOffset(104)
        .backgroundColor($r('app.color.log_background'))
        .borderRadius(16)
        .edgeEffect(EdgeEffect.Spring)
        .shadow({ radius: 12, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 4 })
      }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 20, right: 20, top: 24, bottom: 24 })
      }
      .height('100%')
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
