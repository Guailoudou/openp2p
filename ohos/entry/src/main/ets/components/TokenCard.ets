import { CoreUiState } from '../model/CoreUiState';

@Component
export struct TokenCard {
  @ObjectLink state: CoreUiState;
  onSave: () => void = (): void => {};

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('访问 Token')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(this.state.running ? '运行期间不可修改' : 'uint64')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      }

      Stack({ alignContent: Alignment.End }) {
        TextInput({ text: this.state.token, placeholder: '请输入 OpenP2P Token' })
          .type(this.state.tokenVisible ? InputType.Normal : InputType.Password)
          .showPasswordIcon(false)
          .fontSize(16)
          .height(52)
          .padding({ left: 14, right: 52 })
          .backgroundColor($r('app.color.input_background'))
          .borderRadius(12)
          .enabled(!this.state.running && !this.state.busy)
          .onChange((value: string): void => {
            this.state.token = value.replace(/[^0-9]/g, '');
          })
        Button(this.state.tokenVisible ? '隐藏' : '显示')
          .type(ButtonType.Normal)
          .fontSize(12)
          .fontColor($r('app.color.accent'))
          .backgroundColor(Color.Transparent)
          .margin({ right: 4 })
          .enabled(!this.state.running)
          .onClick((): void => {
            this.state.tokenVisible = !this.state.tokenVisible;
          })
      }
      .width('100%')

      Button('保存 Token')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor($r('app.color.accent'))
        .backgroundColor($r('app.color.accent_soft'))
        .borderRadius(12)
        .enabled(!this.state.running && !this.state.busy)
        .onClick((): void => this.onSave())

      Text('Token 通过 Asset Store 加密保存在本机，启动时仅作为参数传入核心，不会写入 config.json')
        .width('100%')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
  }
}
