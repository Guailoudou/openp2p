import { bundleManager } from '@kit.AbilityKit';

@Component
export struct AboutPage {
  @State private appVersion: string = '未知';

  aboutToAppear(): void {
    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.appVersion = bundleInfo.versionName;
    } catch (_) {
      this.appVersion = '未知';
    }
  }

  @Builder
  private infoRow(icon: Resource, label: string, value: string) {
    Row({ space: 14 }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([$r('app.color.accent')])
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
      Text(value)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .padding({ top: 16, bottom: 16, left: 18, right: 18 })
  }

  @Builder
  private openSourceRow() {
    Row({ space: 14 }) {
      SymbolGlyph($r('sys.symbol.link'))
        .fontSize(18)
        .fontColor([$r('app.color.accent')])
      Text('软件开源')
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
      Hyperlink('https://github.com/openp2p-cn/openp2p', 'OpenP2P')
        .color($r('app.color.accent'))
    }
    .width('100%')
    .padding({ top: 16, bottom: 16, left: 18, right: 18 })
  }

  build() {
    Scroll() {
      Column({ space: 18 }) {
        Column({ space: 12 }) {
          Image($r('app.media.openp2p1024'))
            .width(80)
            .height(80)
            .objectFit(ImageFit.Cover)
            .borderRadius(20)

          Text('OpenP2P')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text('HarmonyOS 原生客户端')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding({ top: 28, bottom: 28 })
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(20)
        .shadow({ radius: 16, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 6 })

        Column() {
          this.infoRow($r('sys.symbol.info_circle'), '应用版本', this.appVersion)
          Divider().color($r('app.color.divider')).padding({ left: 18, right: 18 })
          this.infoRow($r('sys.symbol.display'), '运行平台', 'HarmonyOS')
          Divider().color($r('app.color.divider')).padding({ left: 18, right: 18 })
          this.infoRow($r('sys.symbol.gearshape_fill'), '核心架构', 'arm64-v8a')
          Divider().color($r('app.color.divider')).padding({ left: 18, right: 18 })
          this.infoRow($r('sys.symbol.hammer_fill'), '核心类型', 'OpenP2P Go Native')
          Divider().color($r('app.color.divider')).padding({ left: 18, right: 18 })
          this.openSourceRow()
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(20)
        .shadow({ radius: 16, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 6 })

        Text('OpenP2P 提供安全、轻量的点对点网络连接能力。本客户端使用 ArkTS 与 ArkUI 原生组件构建。')
          .width('100%')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(22)
          .padding(18)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(16)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 32 })
    }
    .width('100%')
    .height('100%')
    .nestedScroll({
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST
    })
  }
}
