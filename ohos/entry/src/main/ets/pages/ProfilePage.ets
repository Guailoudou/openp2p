import { PageHeader } from '../components/PageHeader';

@Component
export struct ProfilePage {
  @Builder
  private infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
      Blank()
      Text(value)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
  }

  build() {
    Scroll() {
      Column({ space: 18 }) {
        PageHeader({ title: '我的', subtitle: '应用与核心信息' })

        Column({ space: 10 }) {
          Text('O')
            .width(68)
            .height(68)
            .textAlign(TextAlign.Center)
            .fontSize(34)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.button_text'))
            .backgroundColor($r('app.color.accent'))
            .borderRadius(18)
          Text('OpenP2P')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text('HarmonyOS 原生客户端')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding(24)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(20)

        Column() {
          this.infoRow('应用版本', '1.0.0')
          Divider().color($r('app.color.divider'))
          this.infoRow('运行平台', 'HarmonyOS')
          Divider().color($r('app.color.divider'))
          this.infoRow('核心架构', 'arm64-v8a')
          Divider().color($r('app.color.divider'))
          this.infoRow('核心类型', 'OpenP2P Go Native')
        }
        .width('100%')
        .padding({ left: 18, right: 18 })
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(20)

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
      .padding({ left: 20, right: 20, top: 24, bottom: 128 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
