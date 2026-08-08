import { webview } from '@kit.ArkWeb';
import { PageHeader } from '../components/PageHeader';
import { AboutPage } from './AboutPage';

@Component
export struct ProfilePage {
  @State private showAbout: boolean = false;
  @State private showManagementCenter: boolean = false;
  @State private aboutPressed: boolean = false;
  private managementCenterController: webview.WebviewController = new webview.WebviewController();

  @Builder
  private aboutSheet() {
    AboutPage()
  }

  @Builder
  private managementCenterSheet() {
    Web({
      src: 'https://console.openpxp.com/',
      controller: this.managementCenterController
    })
      .width('100%')
      .height('100%')
      .javaScriptAccess(true)
      .domStorageAccess(true)
  }

  build() {
    Scroll() {
      Column({ space: 18 }) {
        PageHeader({ title: '我的', subtitle: '应用设置与信息' })

        Column({ space: 12 }) {
          Row({ space: 14 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.display'))
                .fontSize(24)
                .fontColor([$r('app.color.accent')])
            }
            .width(44)
            .height(44)
            .backgroundColor($r('app.color.accent_soft'))
            .borderRadius(12)
            .justifyContent(FlexAlign.Center)

            Column({ space: 3 }) {
              Text('管理中心')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('打开 Web 管理控制台')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(18)
              .fontColor([$r('app.color.text_tertiary')])
          }
          .width('100%')
          .padding(18)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(16)
          .shadow({ radius: 16, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 6 })
          .onClick((): void => {
            this.showManagementCenter = true;
          })
          .bindSheet($$this.showManagementCenter, this.managementCenterSheet(), {
            height: SheetSize.LARGE,
            dragBar: true,
            preferType: SheetType.BOTTOM,
            title: { title: '管理中心' }
          })

          Row({ space: 14 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.info_circle_fill'))
                .fontSize(24)
                .fontColor([$r('app.color.accent')])
            }
            .width(44)
            .height(44)
            .backgroundColor($r('app.color.accent_soft'))
            .borderRadius(12)
            .justifyContent(FlexAlign.Center)

            Column({ space: 3 }) {
              Text('关于')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('查看版本和软件信息')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(18)
              .fontColor([$r('app.color.text_tertiary')])
          }
          .width('100%')
          .padding(18)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(16)
          .shadow({ radius: 16, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 6 })
          .gesture(
            LongPressGesture()
              .onAction((): void => {
                this.aboutPressed = true;
              })
              .onActionEnd((): void => {
                this.aboutPressed = false;
              })
          )
          .onClick((): void => {
            this.showAbout = true;
          })
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 24, bottom: 128 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .bindSheet($$this.showAbout, this.aboutSheet(), {
      height: SheetSize.LARGE,
      dragBar: true,
      preferType: SheetType.BOTTOM,
      title: { title: '关于' }
    })
  }
}
