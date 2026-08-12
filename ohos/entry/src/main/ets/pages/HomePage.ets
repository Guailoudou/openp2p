import { PageHeader } from '../components/PageHeader';
import { StatusCard } from '../components/StatusCard';
import { TokenCard } from '../components/TokenCard';
import { ConfigurationOverview } from '../components/ConfigurationOverview';
import { CoreUiState } from '../model/CoreUiState';

@Component
export struct HomePage {
  @ObjectLink state: CoreUiState;
  @Prop managementAuthenticated: boolean = false;
  @Prop managementUsername: string = '';
  @State private showManagementAccount: boolean = false;
  @State private accountInput: string = '';
  @State private passwordInput: string = '';
  @State private accountMessage: string = '';
  @State private savingAccount: boolean = false;
  onToggleCore: () => void = (): void => {};
  onSaveToken: () => void = (): void => {};
  onSaveManagementCredentials: (username: string, password: string) => Promise<boolean> =
    async (_username: string, _password: string): Promise<boolean> => false;

  @Builder
  private managementAccountSheet() {
    Column({ space: 18 }) {
      TextInput({ text: this.accountInput, placeholder: '请输入管理账号' })
        .height(52).fontSize(16).backgroundColor($r('app.color.page_background')).borderRadius(14)
        .onChange((value: string): void => { this.accountInput = value; this.accountMessage = ''; })
      TextInput({ text: this.passwordInput, placeholder: '请输入管理密码' })
        .type(InputType.Password).height(52).fontSize(16)
        .backgroundColor($r('app.color.page_background')).borderRadius(14)
        .onChange((value: string): void => { this.passwordInput = value; this.accountMessage = ''; })
      if (this.accountMessage.length > 0) {
        Text(this.accountMessage).width('100%').fontSize(14).fontColor($r('app.color.status_failed'))
      }
      Button(this.savingAccount ? '正在登录…' : '保存并登录')
        .width('100%').height(48).enabled(!this.savingAccount)
        .onClick((): void => { this.saveManagementAccount(); })
    }
    .width('100%').height('100%').padding({ left: 20, right: 20, top: 16, bottom: 32 })
  }

  private async saveManagementAccount(): Promise<void> {
    const username = this.accountInput.trim();
    if (username.length === 0) {
      this.accountMessage = '请输入管理账号';
      return;
    }
    if (this.passwordInput.length === 0) {
      this.accountMessage = '请输入管理密码';
      return;
    }
    this.savingAccount = true;
    try {
      if (await this.onSaveManagementCredentials(username, this.passwordInput)) {
        this.passwordInput = '';
        this.accountMessage = '';
        this.showManagementAccount = false;
        this.getUIContext().getPromptAction().showToast({ message: '登录成功' });
      } else {
        this.accountMessage = '登录失败，请检查账号密码或网络';
      }
    } catch (error) {
      const value = error as Record<string, Object>;
      const message = value['message'];
      this.accountMessage = typeof message === 'string' && message.length > 0 ? message : '登录失败';
    } finally {
      this.savingAccount = false;
    }
  }

  build() {
    Scroll() {
      Column({ space: 18 }) {
        PageHeader({ title: 'OpenP2P', subtitle: '安全、轻量的点对点连接' })
        StatusCard({ state: this.state })
        ConfigurationOverview({ state: this.state, managementAuthenticated: this.managementAuthenticated })
        if (!this.managementAuthenticated) {
          TokenCard({ state: this.state, onSave: this.onSaveToken })
          Button('登录管理账号')
            .width('100%').height(48).fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.accent_soft')).borderRadius(14)
            .onClick((): void => {
              this.accountInput = this.managementUsername;
              this.passwordInput = '';
              this.accountMessage = '';
              this.showManagementAccount = true;
            })
        }

        Column() {
          Button() {
            Row({ space: 10 }) {
              if (this.state.busy) {
                LoadingProgress()
                  .width(22)
                  .height(22)
                  .color($r('app.color.button_text'))
              } else {
                SymbolGlyph(this.state.running ?
                  $r('sys.symbol.stop_circle_fill') : $r('sys.symbol.play_fill'))
                  .fontSize(20)
                  .fontColor([$r('app.color.button_text')])
                Text(this.state.running ? '停止核心' : '启动核心')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.button_text'))
              }
            }
            .justifyContent(FlexAlign.Center)
          }
          .width('100%')
          .height(56)
          .backgroundColor(this.state.running ? $r('app.color.danger') : $r('app.color.accent'))
          .borderRadius(16)
          .enabled(!this.state.busy)
          .shadow({
            radius: this.state.running ? 12 : 18,
            color: this.state.running ? $r('app.color.danger_shadow') : $r('app.color.accent_shadow'),
            offsetX: 0,
            offsetY: 6
          })
          .onClick((): void => this.onToggleCore())
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 24, bottom: 128 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .bindSheet($$this.showManagementAccount, this.managementAccountSheet(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      preferType: SheetType.BOTTOM,
      title: { title: '管理账号' }
    })
  }
}
