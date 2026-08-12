interface PageHeaderOptions {
  title: string;
  subtitle: string;
}

@Builder
export function PageHeader(options: PageHeaderOptions) {
  Column({ space: 6 }) {
    Text(options.title)
      .fontSize(30)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_primary'))
      .letterSpacing(0.5)
    Text(options.subtitle)
      .fontSize(14)
      .fontColor($r('app.color.text_secondary'))
      .letterSpacing(0.2)
  }
  .width('100%')
  .alignItems(HorizontalAlign.Start)
  .padding({ bottom: 4 })
}
