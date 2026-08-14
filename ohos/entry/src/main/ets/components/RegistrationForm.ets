@Component
export struct RegistrationForm {
  @Consume private themeColor: string;
  @State private username: string = '';
  @State private password: string = '';
  @State private passwordConfirmation: string = '';
  @State private phone: string = '';
  @State private email: string = '';
  @State private agreed: boolean = false;
  @State private registering: boolean = false;
  @State private message: string = '';
  onRegister: (username: string, password: string, phone: string, email: string) => Promise<boolean> =
    async (_username: string, _password: string, _phone: string, _email: string): Promise<boolean> => false;
  onRegistered: () => void = (): void => {};

  private async submit(): Promise<void> {
    const username = this.username.trim();
    if (username.length < 8 || this.password.length < 8) {
      this.message = '用户名和密码不能少于 8 个字符';
      return;
    }
    if (this.password !== this.passwordConfirmation) {
      this.message = '两次输入的密码不一致';
      return;
    }
    if (!this.agreed) {
      this.message = '请先阅读并同意用户协议和隐私协议';
      return;
    }
    this.registering = true;
    this.message = '';
    try {
      if (await this.onRegister(username, this.password, this.phone, this.email)) {
        this.password = '';
        this.passwordConfirmation = '';
        this.onRegistered();
        this.getUIContext().getPromptAction().showToast({ message: '注册成功，已自动登录' });
      } else {
        this.message = '注册失败，请稍后重试';
      }
    } catch (error) {
      const value = error as Record<string, Object>;
      const detail = value['message'];
      this.message = typeof detail === 'string' && detail.length > 0 ? detail : '注册失败，请稍后重试';
    } finally {
      this.registering = false;
    }
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Text('注册后将自动登录，并同步该账号的 OpenP2P Token。')
          .width('100%').fontSize(14).fontColor($r('app.color.text_secondary'))
        TextInput({ text: this.username, placeholder: '用户名（至少 8 个字符）' })
          .height(52).fontSize(16).backgroundColor($r('app.color.page_background')).borderRadius(14)
          .onChange((value: string): void => { this.username = value; this.message = ''; })
        TextInput({ text: this.password, placeholder: '密码（至少 8 个字符）' })
          .type(InputType.Password).height(52).fontSize(16)
          .backgroundColor($r('app.color.page_background')).borderRadius(14)
          .onChange((value: string): void => { this.password = value; this.message = ''; })
        TextInput({ text: this.passwordConfirmation, placeholder: '再次输入密码' })
          .type(InputType.Password).height(52).fontSize(16)
          .backgroundColor($r('app.color.page_background')).borderRadius(14)
          .onChange((value: string): void => { this.passwordConfirmation = value; this.message = ''; })
        TextInput({ text: this.phone, placeholder: '手机号（选填）' })
          .type(InputType.PhoneNumber).height(52).fontSize(16)
          .backgroundColor($r('app.color.page_background')).borderRadius(14)
          .onChange((value: string): void => { this.phone = value; this.message = ''; })
        TextInput({ text: this.email, placeholder: '邮箱（选填，用来找回密码）' })
          .type(InputType.Email).height(52).fontSize(16)
          .backgroundColor($r('app.color.page_background')).borderRadius(14)
          .onChange((value: string): void => { this.email = value; this.message = ''; })
        Row({ space: 8 }) {
          Toggle({ type: ToggleType.Checkbox, isOn: this.agreed })
            .selectedColor(this.themeColor)
            .onChange((value: boolean): void => { this.agreed = value; this.message = ''; })
          Text('我已阅读并同意').fontSize(14).fontColor($r('app.color.text_secondary'))
          Hyperlink('https://console.openpxp.com/agreement', '用户协议')
            .color(this.themeColor)
          Text('和').fontSize(14).fontColor($r('app.color.text_secondary'))
          Hyperlink(
            'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2013507738654513472',
            '隐私协议'
          )
            .color(this.themeColor)
        }
        .width('100%').alignItems(VerticalAlign.Center)
        if (this.message.length > 0) {
          Text(this.message).width('100%').fontSize(14).fontColor($r('app.color.status_failed'))
        }
        Button(this.registering ? '正在注册…' : '注册并登录')
          .width('100%').height(48).enabled(!this.registering)
          .onClick((): void => { this.submit(); })
      }
      .width('100%').padding({ left: 20, right: 20, top: 8, bottom: 32 })
    }
    .width('100%').height('100%')
  }
}
