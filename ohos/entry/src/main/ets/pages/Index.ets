import common from '@ohos.app.ability.common';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { CustomTheme, ThemeControl } from '@kit.ArkUI';
import { HdsBarStyle, HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { OpenP2PController } from '../controller/OpenP2PController';
import { CoreUiState } from '../model/CoreUiState';
import { DEFAULT_THEME_COLOR, OpenP2PTheme } from '../model/OpenP2PTheme';
import { ManagementSession } from '../service/ManagementSession';
import { AppColorMode, RuntimeStateStore } from '../service/RuntimeStateStore';
import { DevicePage } from './DevicePage';
import { HomePage } from './HomePage';
import { LogsPage } from './LogsPage';
import { NetworkPage } from './NetworkPage';
import { ProfilePage } from './ProfilePage';

const DOMAIN = 0x0;
const TAG = 'OpenP2P-HdsTabs';

@Entry
@Component
struct Index {
  @State private selectedTab: number = 0;
  @State private state: CoreUiState = new CoreUiState();
  @State private showSettings: boolean = false;
  @State private managementAuthenticated: boolean = false;
  @State private managementUsername: string = '';
  @State private managementEmail: string = '';
  @State private managementPhone: string = '';
  @State private managementAddTime: string = '';
  @State private backgroundKeepAliveEnabled: boolean = true;
  @State private simulatedLocationEnabled: boolean = false;
  @State private simulatedDownloadEnabled: boolean = false;
  @State private pictureInPictureEnabled: boolean = false;
  @State private colorMode: AppColorMode = AppColorMode.SYSTEM;
  @State private appTheme: CustomTheme = new OpenP2PTheme(DEFAULT_THEME_COLOR);
  @Provide private themeColor: string = DEFAULT_THEME_COLOR;
  @Provide private themeSoftColor: string = '#1A0A59F7';
  private controller?: OpenP2PController;
  private tabsController: HdsTabsController = new HdsTabsController();
  private managementSession: ManagementSession = ManagementSession.getInstance();
  private runtimeStateStore?: RuntimeStateStore;
  private homeScroller: Scroller = new Scroller();
  private deviceScroller: Scroller = new Scroller();
  private networkScroller: Scroller = new Scroller();
  private logsScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const uiContext = this.getUIContext();
    const context = uiContext.getHostContext() as common.UIAbilityContext;
    this.runtimeStateStore = new RuntimeStateStore(context);
    this.applyThemeColor(this.runtimeStateStore.getThemeColor(), false);
    this.colorMode = this.runtimeStateStore.getColorMode();
    this.controller = new OpenP2PController(context, this.state, uiContext);
    this.backgroundKeepAliveEnabled = this.controller.isBackgroundKeepAliveEnabled();
    this.simulatedLocationEnabled = this.controller.isSimulatedLocationEnabled();
    this.simulatedDownloadEnabled = this.controller.isSimulatedDownloadEnabled();
    this.pictureInPictureEnabled = this.controller.isPictureInPictureEnabled();
    this.controller.initializePictureInPicture(uiContext).catch((error: Object): void => {
      hilog.warn(DOMAIN, TAG, 'Unable to initialize PiP: %{public}s', JSON.stringify(error));
    });
    this.controller.startPolling();
    this.initializeManagement();
  }

  aboutToDisappear(): void {
    this.controller?.stopPolling();
  }

  private applyThemeColor(color: string, persist: boolean = true): void {
    const normalized = /^#[0-9A-Fa-f]{6}$/.test(color) ? color.toUpperCase() : DEFAULT_THEME_COLOR;
    const theme = new OpenP2PTheme(normalized);
    this.themeColor = normalized;
    this.themeSoftColor = `#1A${normalized.substring(1)}`;
    this.appTheme = theme;
    ThemeControl.setDefaultTheme(theme);
    if (persist) {
      this.runtimeStateStore?.setThemeColor(normalized);
    }
  }

  private applyColorMode(mode: AppColorMode): void {
    let systemMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (mode === AppColorMode.DARK) {
      systemMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } else if (mode === AppColorMode.LIGHT) {
      systemMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.getApplicationContext().setColorMode(systemMode);
      this.colorMode = mode;
      this.runtimeStateStore?.setColorMode(mode);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Unable to apply color mode: %{public}s', JSON.stringify(error));
    }
  }

  private updateManagementAuthenticated(authenticated: boolean): void {
    const structureChanged = this.managementAuthenticated !== authenticated;
    if (structureChanged) {
      this.selectedTab = 0;
    }
    this.managementAuthenticated = authenticated;
    if (structureChanged) {
      setTimeout((): void => {
        try {
          this.tabsController.changeIndex(0);
        } catch (error) {
          hilog.warn(DOMAIN, TAG, 'Unable to reset selected tab: %{public}s', JSON.stringify(error));
        }
      }, 0);
    }
  }

  @Builder
  private homeTabBar() {
    Column({ space: 2 }) {
      SymbolGlyph(this.selectedTab === 0 ? $r('sys.symbol.house_fill') : $r('sys.symbol.house'))
        .fontSize(24)
        .fontColor([this.selectedTab === 0 ? this.themeColor : $r('app.color.text_secondary')])
      Text('主页')
        .fontSize(12)
        .fontColor(this.selectedTab === 0 ? this.themeColor : $r('app.color.text_secondary'))
    }
    .width('100%')
    .height(56)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private deviceTabBar() {
    Column({ space: 2 }) {
      SymbolGlyph($r('sys.symbol.display'))
        .fontSize(24)
        .fontColor([this.selectedTab === 1 ? this.themeColor : $r('app.color.text_secondary')])
      Text('设备')
        .fontSize(12)
        .fontColor(this.selectedTab === 1 ? this.themeColor : $r('app.color.text_secondary'))
    }
    .width('100%').height(56)
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }

  @Builder
  private networkTabBar() {
    Column({ space: 2 }) {
      SymbolGlyph($r('sys.symbol.hotspot'))
        .fontSize(24)
        .fontColor([this.selectedTab === 2 ? this.themeColor : $r('app.color.text_secondary')])
      Text('网络')
        .fontSize(12)
        .fontColor(this.selectedTab === 2 ? this.themeColor : $r('app.color.text_secondary'))
    }
    .width('100%').height(56)
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }

  @Builder
  private logsTabBar() {
    Column({ space: 2 }) {
      SymbolGlyph(this.selectedTab === (this.managementAuthenticated ? 3 : 1) ?
        $r('sys.symbol.doc_text_fill') : $r('sys.symbol.doc_text'))
        .fontSize(24)
        .fontColor([this.selectedTab === (this.managementAuthenticated ? 3 : 1) ?
          this.themeColor : $r('app.color.text_secondary')])
      Text('日志')
        .fontSize(12)
        .fontColor(this.selectedTab === (this.managementAuthenticated ? 3 : 1) ?
          this.themeColor : $r('app.color.text_secondary'))
    }
    .width('100%').height(56)
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }

  private async initializeManagement(): Promise<void> {
    try {
      const authenticated = await this.managementSession.initialize();
      this.updateManagementProfile();
      if (authenticated) {
        await this.controller?.applyManagedToken(this.managementSession.getOpenP2PToken());
      } else {
        this.controller?.unlockManagedToken();
      }
      this.updateManagementAuthenticated(authenticated);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Management login failed: %{public}s', JSON.stringify(error));
      this.updateManagementProfile();
      this.updateManagementAuthenticated(false);
      this.controller?.unlockManagedToken();
    }
  }

  private async saveManagementCredentials(username: string, password: string): Promise<boolean> {
    const authenticated = await this.managementSession.saveCredentialsAndLogin(username, password);
    this.updateManagementProfile();
    if (authenticated) {
      await this.controller?.applyManagedToken(this.managementSession.getOpenP2PToken());
    } else {
      this.controller?.unlockManagedToken();
      this.updateManagementAuthenticated(false);
      const message = this.managementSession.getLastError();
      throw new Error(message.length > 0 ? message : '管理账号登录失败');
    }
    this.updateManagementAuthenticated(authenticated);
    return authenticated;
  }

  private async clearManagementCredentials(): Promise<void> {
    await this.managementSession.clear();
    this.managementUsername = '';
    this.managementEmail = '';
    this.managementPhone = '';
    this.managementAddTime = '';
    this.updateManagementAuthenticated(false);
    this.controller?.unlockManagedToken();
  }

  private async registerManagementAccount(username: string, password: string, phone: string,
    email: string): Promise<boolean> {
    const authenticated = await this.managementSession.registerAndLogin(username, password, phone, email);
    this.updateManagementProfile();
    if (!authenticated) {
      this.controller?.unlockManagedToken();
      this.updateManagementAuthenticated(false);
      const message = this.managementSession.getLastError();
      throw new Error(message.length > 0 ? message : '注册失败，请稍后重试');
    }
    await this.controller?.applyManagedToken(this.managementSession.getOpenP2PToken());
    this.updateManagementAuthenticated(true);
    return true;
  }

  private updateManagementProfile(): void {
    const profile = this.managementSession.getProfile();
    this.managementUsername = profile.user ? profile.user : this.managementSession.getUsername();
    this.managementEmail = profile.email ? profile.email : '';
    this.managementPhone = profile.phone ? profile.phone : '';
    this.managementAddTime = profile.addtime ? profile.addtime : '';
  }

  private async setBackgroundKeepAliveEnabled(enabled: boolean): Promise<boolean> {
    const changed = await this.controller?.setBackgroundKeepAliveEnabled(enabled) === true;
    if (changed) {
      this.backgroundKeepAliveEnabled = enabled;
    }
    return changed;
  }

  private async setSimulatedLocationEnabled(enabled: boolean): Promise<boolean> {
    const changed = await this.controller?.setSimulatedLocationEnabled(enabled) === true;
    if (changed) {
      this.simulatedLocationEnabled = enabled;
    }
    return changed;
  }

  private async setSimulatedDownloadEnabled(enabled: boolean): Promise<boolean> {
    const changed = await this.controller?.setSimulatedDownloadEnabled(enabled) === true;
    if (changed) {
      this.simulatedDownloadEnabled = enabled;
    }
    return changed;
  }

  private async setPictureInPictureEnabled(enabled: boolean): Promise<boolean> {
    const changed = await this.controller?.setPictureInPictureEnabled(enabled, this.getUIContext()) === true;
    if (changed) {
      this.pictureInPictureEnabled = enabled;
    }
    return changed;
  }

  @Builder
  private settingsSheet() {
    ProfilePage({
      managementUsername: this.managementUsername,
      managementAuthenticated: this.managementAuthenticated,
      managementEmail: this.managementEmail,
      managementPhone: this.managementPhone,
      managementAddTime: this.managementAddTime,
      backgroundKeepAliveEnabled: this.backgroundKeepAliveEnabled,
      simulatedLocationEnabled: this.simulatedLocationEnabled,
      simulatedDownloadEnabled: this.simulatedDownloadEnabled,
      pictureInPictureEnabled: this.pictureInPictureEnabled,
      colorMode: this.colorMode,
      onSaveManagementCredentials: async (username: string, password: string): Promise<boolean> =>
        this.saveManagementCredentials(username, password),
      onRegisterManagementAccount: async (username: string, password: string, phone: string,
        email: string): Promise<boolean> => this.registerManagementAccount(username, password, phone, email),
      onClearManagementCredentials: async (): Promise<void> => this.clearManagementCredentials(),
      onBackgroundKeepAliveChange: async (enabled: boolean): Promise<boolean> =>
        this.setBackgroundKeepAliveEnabled(enabled),
      onSimulatedLocationChange: async (enabled: boolean): Promise<boolean> =>
        this.setSimulatedLocationEnabled(enabled),
      onSimulatedDownloadChange: async (enabled: boolean): Promise<boolean> =>
        this.setSimulatedDownloadEnabled(enabled),
      onPictureInPictureChange: async (enabled: boolean): Promise<boolean> =>
        this.setPictureInPictureEnabled(enabled),
      onThemeColorChange: (color: string): void => this.applyThemeColor(color),
      onColorModeChange: (mode: string): void => this.applyColorMode(mode as AppColorMode)
    })
  }

  @Builder
  private coreToggleButton() {
    Row() {
      Button() {
        SymbolGlyph(this.state.running ?
          $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
          .fontSize(24)
          .fontColor([this.state.running ? $r('app.color.button_text') : $r('app.color.text_primary')])
      }
      .width(56)
      .height(56)
      .type(ButtonType.Circle)
      .backgroundColor(this.state.running ? this.themeColor : Color.Transparent)
      .enabled(!this.state.busy || this.state.running)
      .accessibilityText(this.state.running ? '停止核心' : '启动核心')
      .onClick((): void => {
        this.controller?.toggleCore();
      })
    }
    .width(56)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  build() {
    WithTheme({ theme: this.appTheme }) {
    Stack() {
      HdsTabs({ controller: this.tabsController }) {
        TabContent() {
          Column() {
            HomePage({
              state: this.state,
              managementAuthenticated: this.managementAuthenticated,
              managementUsername: this.managementUsername,
              scrollController: this.homeScroller,
              onOpenSettings: (): void => {
                this.showSettings = true;
              },
              onSaveToken: (): void => {
                this.controller?.saveToken();
              },
              onSaveManagementCredentials: async (username: string, password: string): Promise<boolean> =>
                this.saveManagementCredentials(username, password),
              onRegisterManagementAccount: async (username: string, password: string, phone: string,
                email: string): Promise<boolean> => this.registerManagementAccount(username, password, phone, email)
            })
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Start).alignItems(HorizontalAlign.Start)
        }
        .tabBar(this.homeTabBar())

        if (this.managementAuthenticated) {
          TabContent() {
            Column() {
              DevicePage({ scrollController: this.deviceScroller })
            }
            .width('100%').height('100%')
            .justifyContent(FlexAlign.Start).alignItems(HorizontalAlign.Start)
          }
          .tabBar(this.deviceTabBar())

          TabContent() {
            Column() {
              NetworkPage({ scrollController: this.networkScroller })
            }
            .width('100%').height('100%')
            .justifyContent(FlexAlign.Start).alignItems(HorizontalAlign.Start)
          }
          .tabBar(this.networkTabBar())
        }

        TabContent() {
          Column() {
            LogsPage({
              state: this.state,
              scrollController: this.logsScroller,
              onExportLog: (): void => {
                this.controller?.exportLog();
              }
            })
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Start).alignItems(HorizontalAlign.Start)
        }
        .tabBar(this.logsTabBar())
      }
      .width('100%')
      .height('100%')
      .id(`openp2p-tabs-${this.managementAuthenticated}`)
      .scrollable(true)
      .barOverlap(true)
      .vertical(false)
      .barPosition(BarPosition.End)
      .onAttach((): void => {
        try {
          this.tabsController.preloadItems(this.managementAuthenticated ? [0, 1, 2, 3] : [0, 1]);
        } catch (error) {
          hilog.error(DOMAIN, TAG, 'OnAttach preloadItems failed: %{public}s', JSON.stringify(error));
        }
      })
      .barFloatingStyle({
        barWidth: this.managementAuthenticated ?
          { smallWidth: 264, mediumWidth: 288, largeWidth: 320 } :
          { smallWidth: 152, mediumWidth: 160, largeWidth: 160 },
        barSideMargin: 16,
        barBottomMargin: 0,
        miniBar: {
          miniBarBuilder: (): void => this.coreToggleButton(),
          miniBarWidth: { smallWidth: 56, mediumWidth: 56, largeWidth: 56 },
          miniBarStyle: HdsBarStyle.COLLAPSE,
          enableMiniBarBackground: true
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onTabBarClick((index: number): void => {
        this.selectedTab = index;
      })
      .onChange((index: number): void => {
        this.selectedTab = index;
      })

    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showSettings, this.settingsSheet(), {
      height: SheetSize.LARGE,
      dragBar: true,
      preferType: SheetType.BOTTOM,
      title: { title: '设置' }
    })
    }
  }
}
