@Component
export struct PageHeader {
  @Prop title: string = '';
  @Prop subtitle: string = '';

  build() {
    Column({ space: 6 }) {
      Text(this.title)
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .letterSpacing(0.5)
      Text(this.subtitle)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .letterSpacing(0.2)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ bottom: 4 })
  }
}
