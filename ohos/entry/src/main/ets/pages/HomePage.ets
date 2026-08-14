import { PageHeader } from '../components/PageHeader';
import { StatusCard } from '../components/StatusCard';
import { TokenCard } from '../components/TokenCard';
import { ConfigurationOverview } from '../components/ConfigurationOverview';
import { RegistrationForm } from '../components/RegistrationForm';
import { CoreUiState } from '../model/CoreUiState';

@Component
export struct HomePage {
  @Consume private themeColor: string;
  @Consume private themeSoftColor: string;
  @ObjectLink state: CoreUiState;
  @Prop managementAuthenticated: boolean = false;
  @Prop managementUsername: string = '';
  @State private showManagementAccount: boolean = false;
  @State private registrationMode: boolean = false;
  @State private accountInput: string = '';
  @State private passwordInput: string = '';
  @State private accountMessage: string = '';
  @State private savingAccount: boolean = false;
  scrollController: Scroller = new Scroller();
  onOpenSettings: () => void = (): void => {};
  onSaveToken: () => void = (): void => {};
  onSaveManagementCredentials: (username: string, password: string) => Promise<boolean> =
    async (_username: string, _password: string): Promise<boolean> => false;
  onRegisterManagementAccount: (username: string, password: string, phone: string, email: string) => Promise<boolean> =
    async (_username: string, _password: string, _phone: string, _email: string): Promise<boolean> => false;

  @Builder
  private managementAccountSheet() {
    if (this.registrationMode) {
      RegistrationForm({
        onRegister: async (username: string, password: string, phone: string, email: string): Promise<boolean> =>
          this.onRegisterManagementAccount(username, password, phone, email),
        onRegistered: (): void => {
          this.registrationMode = false;
          this.showManagementAccount = false;
        }
      })
    } else {
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
        Button('注册账号')
          .width('100%').height(48).fontColor(this.themeColor)
          .backgroundColor(Color.Transparent).enabled(!this.savingAccount)
          .onClick((): void => { this.registrationMode = true; })
      }
      .width('100%').height('100%').padding({ left: 20, right: 20, top: 16, bottom: 32 })
    }
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
    Scroll(this.scrollController) {
      Column({ space: 18 }) {
        Row({ space: 12 }) {
          Row() {
            PageHeader({ title: 'OpenP2P', subtitle: '安全、轻量的点对点连接' })
          }
          .layoutWeight(1)

          Button() {
            SymbolGlyph($r('sys.symbol.gearshape_fill'))
              .fontSize(22)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(44)
          .height(44)
          .type(ButtonType.Circle)
          .backgroundColor($r('app.color.card_background'))
          .shadow({ radius: 10, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 4 })
          .accessibilityText('设置')
          .onClick((): void => {
            this.onOpenSettings();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        StatusCard({ state: this.state })
        ConfigurationOverview({ state: this.state, managementAuthenticated: this.managementAuthenticated })
        if (!this.managementAuthenticated) {
          TokenCard({ state: this.state, onSave: this.onSaveToken })
          Button('登录管理账号')
            .width('100%').height(48).fontColor(this.themeColor)
            .backgroundColor(this.themeSoftColor).borderRadius(14)
            .onClick((): void => {
              this.accountInput = this.managementUsername;
              this.passwordInput = '';
              this.accountMessage = '';
              this.registrationMode = false;
              this.showManagementAccount = true;
            })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, top: 24, bottom: 128 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .backgroundColor($r('app.color.page_background'))
    .bindSheet($$this.showManagementAccount, this.managementAccountSheet(), {
      height: this.registrationMode ? SheetSize.LARGE : SheetSize.MEDIUM,
      dragBar: true,
      preferType: SheetType.BOTTOM,
      title: { title: this.registrationMode ? '注册账号' : '管理账号' }
    })
  }
}
