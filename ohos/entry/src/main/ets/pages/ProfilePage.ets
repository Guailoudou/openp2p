import { PageHeader } from '../components/PageHeader';
import { AboutPage } from './AboutPage';

@Component
export struct ProfilePage {
  @State private showAbout: boolean = false;
  @State private showManagementAccount: boolean = false;
  @State private aboutPressed: boolean = false;
  @State private accountInput: string = '';
  @State private passwordInput: string = '';
  @State private accountMessage: string = '';
  @State private savingAccount: boolean = false;
  @Prop managementUsername: string = '';
  @Prop managementAuthenticated: boolean = false;
  onSaveManagementCredentials: (username: string, password: string) => Promise<boolean> =
    async (_username: string, _password: string): Promise<boolean> => false;
  onClearManagementCredentials: () => Promise<void> = async (): Promise<void> => {};

  @Builder
  private aboutSheet() {
    AboutPage()
  }

  @Builder
  private managementAccountSheet() {
    Column({ space: 18 }) {
      TextInput({ text: this.accountInput, placeholder: '请输入管理账号' })
        .height(52)
        .fontSize(16)
        .backgroundColor($r('app.color.page_background'))
        .borderRadius(14)
        .onChange((value: string): void => {
          this.accountInput = value;
          this.accountMessage = '';
        })

      TextInput({ text: this.passwordInput, placeholder: '请输入管理密码' })
        .type(InputType.Password)
        .height(52)
        .fontSize(16)
        .backgroundColor($r('app.color.page_background'))
        .borderRadius(14)
        .onChange((value: string): void => {
          this.passwordInput = value;
          this.accountMessage = '';
        })

      if (this.accountMessage.length > 0) {
        Text(this.accountMessage)
          .width('100%')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }

      Button(this.savingAccount ? '正在登录…' : '保存并登录')
        .width('100%')
        .height(48)
        .enabled(!this.savingAccount)
        .onClick((): void => {
          this.saveManagementAccount();
        })

      if (this.managementUsername.length > 0) {
        Button('清除管理账号')
          .width('100%')
          .height(48)
          .fontColor(Color.Red)
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.clearManagementAccount();
          })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 32 })
  }

  private async saveManagementAccount(): Promise<void> {
    if (this.accountInput.trim().length === 0 || this.passwordInput.length === 0) {
      this.accountMessage = '请填写完整的账号和密码';
      return;
    }
    this.savingAccount = true;
    try {
      const authenticated = await this.onSaveManagementCredentials(this.accountInput, this.passwordInput);
      this.passwordInput = '';
      if (authenticated) {
        this.accountMessage = '';
        this.showManagementAccount = false;
      } else {
        this.accountMessage = '账号已保存，但登录失败，请检查账号密码或网络';
      }
    } catch (error) {
      this.accountMessage = `保存失败：${String(error)}`;
    } finally {
      this.savingAccount = false;
    }
  }

  private async clearManagementAccount(): Promise<void> {
    this.savingAccount = true;
    try {
      await this.onClearManagementCredentials();
      this.accountInput = '';
      this.passwordInput = '';
      this.accountMessage = '';
      this.showManagementAccount = false;
    } finally {
      this.savingAccount = false;
    }
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
              Text('管理账号')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text(this.managementUsername.length === 0 ? '设置控制台账号和密码' :
                `${this.managementUsername} · ${this.managementAuthenticated ? '已登录' : '未登录'}`)
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
            this.accountInput = this.managementUsername;
            this.passwordInput = '';
            this.accountMessage = '';
            this.showManagementAccount = true;
          })
          .bindSheet($$this.showManagementAccount, this.managementAccountSheet(), {
            height: SheetSize.MEDIUM,
            dragBar: true,
            preferType: SheetType.BOTTOM,
            title: { title: '管理账号' }
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
