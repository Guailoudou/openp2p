import { CoreUiState } from '../model/CoreUiState';

@Component
export struct TokenCard {
  @ObjectLink state: CoreUiState;
  onSave: () => void = (): void => {};

  build() {
    Column({ space: 16 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.key_fill'))
          .fontSize(20)
          .fontColor([$r('app.color.accent')])
        Text('Token')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text('设备认证凭据')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ left: 4 })
      }

      if (this.state.tokenLocked) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.lock_fill'))
            .fontSize(15)
            .fontColor([$r('app.color.accent')])
          Text('Token 已因管理账号登录而锁定')
            .fontSize(13)
            .fontColor($r('app.color.accent'))
        }
        .width('100%')
      }

      Stack({ alignContent: Alignment.End }) {
        Row() {
          SymbolGlyph($r('sys.symbol.lock_shield'))
            .fontSize(20)
            .fontColor([$r('app.color.text_tertiary')])
            .margin({ left: 14, right: 10 })
          TextInput({ text: this.state.token, placeholder: '请输入 OpenP2P Token' })
            .type(this.state.tokenVisible ? InputType.Normal : InputType.Password)
            .showPasswordIcon(false)
            .fontSize(16)
            .height(52)
            .padding({ left: 0, right: 48 })
            .backgroundColor(Color.Transparent)
            .borderRadius(12)
            .enabled(!this.state.tokenLocked && !this.state.running && !this.state.busy)
            .onChange((value: string): void => {
              this.state.token = value.replace(/[^0-9]/g, '');
            })
        }
        .width('100%')
        .height(52)
        .backgroundColor($r('app.color.input_background'))
        .borderRadius(14)

        Button() {
          SymbolGlyph($r(this.state.tokenVisible ? 'sys.symbol.eye_slash' : 'sys.symbol.eye'))
            .fontSize(20)
            .fontColor([$r('app.color.accent')])
        }
        .type(ButtonType.Circle)
        .width(36)
        .height(36)
        .margin({ right: 8 })
        .backgroundColor(Color.Transparent)
        .enabled(!this.state.running)
        .onClick((): void => {
          this.state.tokenVisible = !this.state.tokenVisible;
        })
      }
      .width('100%')

      Button(this.state.tokenLocked ? 'Token 已锁定' : '保存 Token')
        .width('100%')
        .height(48)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.accent'))
        .backgroundColor($r('app.color.accent_soft'))
        .borderRadius(14)
        .enabled(!this.state.tokenLocked && !this.state.running && !this.state.busy)
        .onClick((): void => this.onSave())
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 22, bottom: 22 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
    .shadow({ radius: 20, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 8 })
  }
}
