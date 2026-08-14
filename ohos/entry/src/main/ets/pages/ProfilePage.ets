import { AboutPage } from './AboutPage';
import { RegistrationForm } from '../components/RegistrationForm';
import { AppColorMode } from '../service/RuntimeStateStore';

@Component
export struct ProfilePage {
  @Consume private themeColor: string;
  @Consume private themeSoftColor: string;
  @State private showAbout: boolean = false;
  @State private showManagementAccount: boolean = false;
  @State private registrationMode: boolean = false;
  @State private showBackgroundSettings: boolean = false;
  @State private showAppearanceSettings: boolean = false;
  @State private aboutPressed: boolean = false;
  @State private accountInput: string = '';
  @State private passwordInput: string = '';
  @State private accountMessage: string = '';
  @State private savingAccount: boolean = false;
  @State private managementEmailRevealed: boolean = false;
  @State private managementPhoneRevealed: boolean = false;
  @State private savingBackgroundSetting: boolean = false;
  @State private localBackgroundKeepAliveEnabled: boolean = true;
  @State private localSimulatedLocationEnabled: boolean = false;
  @State private localSimulatedDownloadEnabled: boolean = false;
  @State private localPictureInPictureEnabled: boolean = false;
  @Prop managementUsername: string = '';
  @Prop managementAuthenticated: boolean = false;
  @Prop managementEmail: string = '';
  @Prop managementPhone: string = '';
  @Prop managementAddTime: string = '';
  @Prop backgroundKeepAliveEnabled: boolean = true;
  @Prop simulatedLocationEnabled: boolean = false;
  @Prop simulatedDownloadEnabled: boolean = false;
  @Prop pictureInPictureEnabled: boolean = false;
  @Prop colorMode: string = AppColorMode.SYSTEM;
  onSaveManagementCredentials: (username: string, password: string) => Promise<boolean> =
    async (_username: string, _password: string): Promise<boolean> => false;
  onRegisterManagementAccount: (username: string, password: string, phone: string, email: string) => Promise<boolean> =
    async (_username: string, _password: string, _phone: string, _email: string): Promise<boolean> => false;
  onClearManagementCredentials: () => Promise<void> = async (): Promise<void> => {};
  onBackgroundKeepAliveChange: (enabled: boolean) => Promise<boolean> =
    async (_enabled: boolean): Promise<boolean> => false;
  onSimulatedLocationChange: (enabled: boolean) => Promise<boolean> =
    async (_enabled: boolean): Promise<boolean> => false;
  onSimulatedDownloadChange: (enabled: boolean) => Promise<boolean> =
    async (_enabled: boolean): Promise<boolean> => false;
  onPictureInPictureChange: (enabled: boolean) => Promise<boolean> =
    async (_enabled: boolean): Promise<boolean> => false;
  onThemeColorChange: (color: string) => void = (_color: string): void => {};
  onColorModeChange: (mode: string) => void = (_mode: string): void => {};
  private themeColors: string[] = ['#0A59F7', '#7C3AED', '#009A9A', '#22A447', '#E76F00', '#D9485F'];

  aboutToAppear(): void {
    this.syncBackgroundSettingState();
  }

  private syncBackgroundSettingState(): void {
    this.localBackgroundKeepAliveEnabled = this.backgroundKeepAliveEnabled;
    this.localSimulatedLocationEnabled = this.simulatedLocationEnabled;
    this.localSimulatedDownloadEnabled = this.simulatedDownloadEnabled;
    this.localPictureInPictureEnabled = this.pictureInPictureEnabled;
  }

  private async changeBackgroundKeepAlive(enabled: boolean): Promise<void> {
    if (this.savingBackgroundSetting) {
      return;
    }
    this.localBackgroundKeepAliveEnabled = enabled;
    this.savingBackgroundSetting = true;
    try {
      if (!await this.onBackgroundKeepAliveChange(enabled)) {
        this.localBackgroundKeepAliveEnabled = !enabled;
      }
    } catch (_) {
      this.localBackgroundKeepAliveEnabled = !enabled;
    } finally {
      this.savingBackgroundSetting = false;
    }
  }

  private async changeSimulatedLocation(enabled: boolean): Promise<void> {
    if (this.savingBackgroundSetting) {
      return;
    }
    this.localSimulatedLocationEnabled = enabled;
    this.savingBackgroundSetting = true;
    try {
      if (!await this.onSimulatedLocationChange(enabled)) {
        this.localSimulatedLocationEnabled = !enabled;
      }
    } catch (_) {
      this.localSimulatedLocationEnabled = !enabled;
    } finally {
      this.savingBackgroundSetting = false;
    }
  }

  private async changeSimulatedDownload(enabled: boolean): Promise<void> {
    if (this.savingBackgroundSetting) {
      return;
    }
    this.localSimulatedDownloadEnabled = enabled;
    this.savingBackgroundSetting = true;
    try {
      if (!await this.onSimulatedDownloadChange(enabled)) {
        this.localSimulatedDownloadEnabled = !enabled;
      }
    } catch (_) {
      this.localSimulatedDownloadEnabled = !enabled;
    } finally {
      this.savingBackgroundSetting = false;
    }
  }

  private async changePictureInPicture(enabled: boolean): Promise<void> {
    if (this.savingBackgroundSetting) {
      return;
    }
    this.localPictureInPictureEnabled = enabled;
    this.savingBackgroundSetting = true;
    try {
      if (!await this.onPictureInPictureChange(enabled)) {
        this.localPictureInPictureEnabled = !enabled;
      }
    } catch (_) {
      this.localPictureInPictureEnabled = !enabled;
    } finally {
      this.savingBackgroundSetting = false;
    }
  }

  @Builder
  private backgroundSettingsSheet() {
    Scroll() {
      Column({ space: 12 }) {
        Row({ space: 14 }) {
          this.backgroundSettingLabel($r('sys.symbol.lock_fill'), '持续后台任务', '使用系统长时任务维持连接')
          Toggle({ type: ToggleType.Switch, isOn: $$this.localBackgroundKeepAliveEnabled })
            .selectedColor(this.themeColor)
            .enabled(!this.savingBackgroundSetting)
            .onChange((enabled: boolean): void => {
            this.changeBackgroundKeepAlive(enabled);
          })
        }
        .width('100%').padding(16).backgroundColor($r('app.color.card_background')).borderRadius(16)

        Row({ space: 14 }) {
          this.backgroundSettingLabel($r('sys.symbol.compass_circle'), '模拟定位', '使用低功耗后台定位模式')
          Toggle({ type: ToggleType.Switch, isOn: $$this.localSimulatedLocationEnabled })
            .selectedColor(this.themeColor)
            .enabled(!this.savingBackgroundSetting)
            .onChange((enabled: boolean): void => {
            this.changeSimulatedLocation(enabled);
          })
        }
        .width('100%').padding(16).backgroundColor($r('app.color.card_background')).borderRadius(16)

        Row({ space: 14 }) {
          this.backgroundSettingLabel($r('sys.symbol.circle_and_arrow_down'), '模拟下载', '使用数据传输实况通知')
          Toggle({ type: ToggleType.Switch, isOn: $$this.localSimulatedDownloadEnabled })
            .selectedColor(this.themeColor)
            .enabled(!this.savingBackgroundSetting)
            .onChange((enabled: boolean): void => {
            this.changeSimulatedDownload(enabled);
          })
        }
        .width('100%').padding(16).backgroundColor($r('app.color.card_background')).borderRadius(16)

        Row({ space: 14 }) {
          this.backgroundSettingLabel($r('sys.symbol.media_center'), '画中画', '进入后台时显示运行小窗')
          Toggle({ type: ToggleType.Switch, isOn: $$this.localPictureInPictureEnabled })
            .selectedColor(this.themeColor)
            .enabled(!this.savingBackgroundSetting)
            .onChange((enabled: boolean): void => {
            this.changePictureInPicture(enabled);
          })
        }
        .width('100%').padding(16).backgroundColor($r('app.color.card_background')).borderRadius(16)
      }
      .width('100%')
      .constraintSize({ maxWidth: 760 })
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, top: 8, bottom: 32 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
  }

  @Builder
  private backgroundSettingLabel(icon: Resource, title: string, subtitle: string) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.themeColor])
    }
    .width(42)
    .height(42)
    .backgroundColor(this.themeSoftColor)
    .borderRadius(12)
    .justifyContent(FlexAlign.Center)

    Column({ space: 3 }) {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(subtitle)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private colorModeOption(mode: string, title: string) {
    Row({ space: 12 }) {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      .layoutWeight(1)
      if (this.colorMode === mode) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(22)
          .fontColor([this.themeColor])
      }
    }
    .width('100%')
    .padding({ left: 2, right: 2, top: 10, bottom: 10 })
    .onClick((): void => this.onColorModeChange(mode))
  }

  @Builder
  private appearanceSettingsSheet() {
    Scroll() {
      Column({ space: 18 }) {
        Column({ space: 2 }) {
          Text('深色模式')
            .width('100%')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          this.colorModeOption(AppColorMode.SYSTEM, '跟随系统')
          this.colorModeOption(AppColorMode.DARK, '始终深色')
          this.colorModeOption(AppColorMode.LIGHT, '始终浅色')
        }
        .width('100%')
        .padding(18)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)

        Column({ space: 14 }) {
          Text('主题色')
            .width('100%')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Row({ space: 12 }) {
            ForEach(this.themeColors, (color: string) => {
              Button() {
                if (this.themeColor === color) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(20)
                    .fontColor([Color.White])
                }
              }
              .width(44)
              .height(44)
              .type(ButtonType.Circle)
              .backgroundColor(color)
              .border({
                width: this.themeColor === color ? 3 : 0,
                color: $r('app.color.card_background')
              })
              .onClick((): void => this.onThemeColorChange(color))
            }, (color: string): string => color)
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
        }
        .width('100%')
        .padding(18)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)

      }
      .width('100%')
      .constraintSize({ maxWidth: 760 })
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, top: 8, bottom: 32 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
  }

  @Builder
  private aboutSheet() {
    AboutPage()
  }

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
        if (this.managementAuthenticated) {
        this.profileItem('账号', this.managementUsername)
        this.managementEmailItem()
        this.managementPhoneItem()
        this.profileItem('注册时间', this.managementAddTime.length > 0 ? this.managementAddTime : '未知')
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.lock_fill')).fontSize(16).fontColor([this.themeColor])
          Text('OpenP2P Token 已自动同步并锁定')
            .fontSize(13).fontColor(this.themeColor)
        }.width('100%')
        Blank().layoutWeight(1)
        Button(this.savingAccount ? '正在退出…' : '退出登录')
          .width('100%')
          .height(48)
          .fontColor(Color.Red)
          .backgroundColor(Color.Transparent)
          .enabled(!this.savingAccount)
          .onClick((): void => {
            this.confirmClearManagementAccount();
          })
        } else {
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
          Button('注册账号')
            .width('100%').height(48).fontColor(this.themeColor)
            .backgroundColor(Color.Transparent).enabled(!this.savingAccount)
            .onClick((): void => { this.registrationMode = true; })
        }
      }
      .width('100%').height('100%')
      .constraintSize({ maxWidth: 640 })
      .padding({ left: 20, right: 20, top: 16, bottom: 32 })
    }
  }

  @Builder
  private profileItem(label: string, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor($r('app.color.text_secondary'))
      Blank()
      Text(value).fontSize(15).fontColor($r('app.color.text_primary')).textAlign(TextAlign.End)
    }
    .width('100%').padding(14).backgroundColor($r('app.color.page_background')).borderRadius(12)
  }

  @Builder
  private managementEmailItem() {
    Row() {
      Text('邮箱').fontSize(14).fontColor($r('app.color.text_secondary'))
      Blank()
      Text(this.managementEmailRevealed ? this.fullManagementEmail() : this.maskedManagementEmail())
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.End)
    }
    .width('100%').padding(14).backgroundColor($r('app.color.page_background')).borderRadius(12)
    .onClick((): void => {
      if (this.managementEmail.trim().length > 0) {
        this.managementEmailRevealed = true;
      }
    })
  }

  @Builder
  private managementPhoneItem() {
    Row() {
      Text('手机').fontSize(14).fontColor($r('app.color.text_secondary'))
      Blank()
      Text(this.managementPhoneRevealed ? this.fullManagementPhone() : this.maskedManagementPhone())
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.End)
    }
    .width('100%').padding(14).backgroundColor($r('app.color.page_background')).borderRadius(12)
    .onClick((): void => {
      if (this.managementPhone.trim().length > 0) {
        this.managementPhoneRevealed = true;
      }
    })
  }

  private fullManagementEmail(): string {
    const email = this.managementEmail.trim();
    return email.length > 0 ? email : '未填写';
  }

  private maskedManagementEmail(): string {
    const email = this.managementEmail.trim();
    if (email.length === 0) {
      return '未填写';
    }
    const atIndex = email.indexOf('@');
    if (atIndex < 0) {
      return this.maskContactValue(email);
    }
    const localPart = email.substring(0, atIndex);
    const domainPart = email.substring(atIndex);
    if (localPart.length <= 1) {
      return `***${domainPart}`;
    }
    if (localPart.length === 2) {
      return `${localPart.substring(0, 1)}***${domainPart}`;
    }
    return `${localPart.substring(0, 1)}***${localPart.substring(localPart.length - 1)}${domainPart}`;
  }

  private fullManagementPhone(): string {
    const phone = this.managementPhone.trim();
    return phone.length > 0 ? phone : '未填写';
  }

  private maskedManagementPhone(): string {
    const phone = this.managementPhone.trim();
    if (phone.length === 0) {
      return '未填写';
    }
    return this.maskContactValue(phone);
  }

  private maskContactValue(value: string): string {
    if (value.length <= 4) {
      return '****';
    }
    if (value.length <= 7) {
      return `${value.substring(0, 2)}***${value.substring(value.length - 2)}`;
    }
    return `${value.substring(0, 3)}****${value.substring(value.length - 4)}`;
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
      this.accountMessage = `登录失败：${this.errorMessage(error)}`;
    } finally {
      this.savingAccount = false;
    }
  }

  private errorMessage(error: Object): string {
    const value = error as Record<string, Object>;
    const message = value['message'];
    return typeof message === 'string' && message.length > 0 ? message : String(error);
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

  private confirmClearManagementAccount(): void {
    this.getUIContext().showAlertDialog({
      title: '退出登录',
      message: '退出后将隐藏设备和网络页面，确定继续吗？',
      autoCancel: true,
      buttons: [
        { value: '取消', action: (): void => {} },
        {
          value: '退出登录',
          style: DialogButtonStyle.HIGHLIGHT,
          action: (): void => { this.clearManagementAccount(); }
        }
      ]
    });
  }

  build() {
    Scroll() {
      Column({ space: 18 }) {
        Column({ space: 12 }) {
          Row({ space: 14 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.person_fill'))
                .fontSize(24)
                .fontColor([this.themeColor])
            }
            .width(44)
            .height(44)
            .backgroundColor(this.themeSoftColor)
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
            this.registrationMode = false;
            this.managementEmailRevealed = false;
            this.managementPhoneRevealed = false;
            this.showManagementAccount = true;
          })
          .bindSheet($$this.showManagementAccount, this.managementAccountSheet(), {
            height: this.registrationMode ? SheetSize.LARGE : SheetSize.MEDIUM,
            dragBar: true,
            preferType: SheetType.BOTTOM,
            title: { title: this.registrationMode ? '注册账号' : '管理账号' }
          })

          Row({ space: 14 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.lock_fill'))
                .fontSize(24)
                .fontColor([this.themeColor])
            }
            .width(44)
            .height(44)
            .backgroundColor(this.themeSoftColor)
            .borderRadius(12)
            .justifyContent(FlexAlign.Center)

            Column({ space: 3 }) {
              Text('后台保活')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('持续任务、定位、下载与画中画设置')
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
            this.syncBackgroundSettingState();
            this.showBackgroundSettings = true;
          })
          .bindSheet($$this.showBackgroundSettings, this.backgroundSettingsSheet(), {
            height: SheetSize.MEDIUM,
            dragBar: true,
            preferType: SheetType.BOTTOM,
            title: { title: '后台保活' }
          })

          Row({ space: 14 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.gearshape_fill'))
                .fontSize(24)
                .fontColor([this.themeColor])
            }
            .width(44)
            .height(44)
            .backgroundColor(this.themeSoftColor)
            .borderRadius(12)
            .justifyContent(FlexAlign.Center)

            Column() {
              Text('外观设置')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
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
            this.showAppearanceSettings = true;
          })
          .bindSheet($$this.showAppearanceSettings, this.appearanceSettingsSheet(), {
            height: SheetSize.MEDIUM,
            dragBar: true,
            preferType: SheetType.BOTTOM,
            title: { title: '外观设置' }
          })

          Row({ space: 14 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.info_circle_fill'))
                .fontSize(24)
                .fontColor([this.themeColor])
            }
            .width(44)
            .height(44)
            .backgroundColor(this.themeSoftColor)
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
      .constraintSize({ maxWidth: 760 })
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, top: 8, bottom: 32 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .nestedScroll({
      scrollForward: NestedScrollMode.SELF_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST
    })
    .backgroundColor($r('app.color.page_background'))
    .bindSheet($$this.showAbout, this.aboutSheet(), {
      height: SheetSize.LARGE,
      dragBar: true,
      preferType: SheetType.BOTTOM,
      title: { title: '关于' }
    })
  }
}
