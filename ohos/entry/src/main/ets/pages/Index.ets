import common from '@ohos.app.ability.common';
import { SymbolGlyphModifier, window } from '@kit.ArkUI';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { OpenP2PController } from '../controller/OpenP2PController';
import { CoreUiState } from '../model/CoreUiState';
import { ManagementSession } from '../service/ManagementSession';
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
  @State private naviIndicatorHeight: number = 0;
  @State private managementAuthenticated: boolean = false;
  @State private managementUsername: string = '';
  @State private managementEmail: string = '';
  @State private managementPhone: string = '';
  @State private managementAddTime: string = '';
  @State private backgroundKeepAliveEnabled: boolean = true;
  @State private simulatedLocationEnabled: boolean = false;
  @State private simulatedDownloadEnabled: boolean = false;
  @State private pictureInPictureEnabled: boolean = false;
  private controller?: OpenP2PController;
  private tabsController: HdsTabsController = new HdsTabsController();
  private managementSession: ManagementSession = ManagementSession.getInstance();

  aboutToAppear(): void {
    const uiContext = this.getUIContext();
    const context = uiContext.getHostContext() as common.UIAbilityContext;
    this.controller = new OpenP2PController(context, this.state, uiContext);
    this.backgroundKeepAliveEnabled = this.controller.isBackgroundKeepAliveEnabled();
    this.simulatedLocationEnabled = this.controller.isSimulatedLocationEnabled();
    this.simulatedDownloadEnabled = this.controller.isSimulatedDownloadEnabled();
    this.pictureInPictureEnabled = this.controller.isPictureInPictureEnabled();
    this.controller.initializePictureInPicture(uiContext).catch((error: Object): void => {
      hilog.warn(DOMAIN, TAG, 'Unable to initialize PiP: %{public}s', JSON.stringify(error));
    });
    this.controller.startPolling();
    this.updateNaviIndicatorHeight(context);
    this.initializeManagement();
  }

  aboutToDisappear(): void {
    this.controller?.stopPolling();
  }

  private tabBar(normalSymbol: Resource, selectedSymbol: Resource, title: string): BottomTabBarStyle {
    const icon: TabBarSymbol = {
      normal: new SymbolGlyphModifier(normalSymbol),
      selected: new SymbolGlyphModifier(selectedSymbol)
    };
    return BottomTabBarStyle.of(icon, title);
  }

  private async updateNaviIndicatorHeight(context: common.UIAbilityContext): Promise<void> {
    try {
      const mainWindow = await window.getLastWindow(context);
      const avoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.naviIndicatorHeight = this.getUIContext().px2vp(avoidArea.bottomRect.height);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to query navigation indicator height: %{public}s', JSON.stringify(error));
    }
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
      this.managementAuthenticated = authenticated;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Management login failed: %{public}s', JSON.stringify(error));
      this.updateManagementProfile();
      this.managementAuthenticated = false;
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
      this.managementAuthenticated = false;
      const message = this.managementSession.getLastError();
      throw new Error(message.length > 0 ? message : '管理账号登录失败');
    }
    this.managementAuthenticated = authenticated;
    this.selectedTab = 4;
    setTimeout((): void => {
      this.tabsController.changeIndex(4);
    }, 0);
    return authenticated;
  }

  private async clearManagementCredentials(): Promise<void> {
    await this.managementSession.clear();
    this.managementUsername = '';
    this.managementEmail = '';
    this.managementPhone = '';
    this.managementAddTime = '';
    this.managementAuthenticated = false;
    this.controller?.unlockManagedToken();
    // 未登录时页签依次为：首页、日志、我的；与 Android 一致，退出后停留在“我的”。
    this.selectedTab = 2;
    this.tabsController.changeIndex(2);
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

  build() {
    Row(){
      HdsTabs({ controller: this.tabsController }) {
        TabContent() {
          HomePage({
            state: this.state,
            managementAuthenticated: this.managementAuthenticated,
            managementUsername: this.managementUsername,
            onToggleCore: (): void => {
              this.controller?.toggleCore();
            },
            onSaveToken: (): void => {
              this.controller?.saveToken();
            },
            onSaveManagementCredentials: async (username: string, password: string): Promise<boolean> =>
              this.saveManagementCredentials(username, password)
          })
        }
        .tabBar(this.tabBar($r('sys.symbol.house'), $r('sys.symbol.house_fill'), '主页'))

        if (this.managementAuthenticated) {
          TabContent() {
            DevicePage()
          }
          .tabBar(this.tabBar($r('sys.symbol.display'), $r('sys.symbol.display'), '设备'))

          TabContent() {
            NetworkPage()
          }
          .tabBar(this.tabBar($r('sys.symbol.hotspot'), $r('sys.symbol.hotspot'), '网络'))
        }

        TabContent() {
          LogsPage({
            state: this.state,
            onExportLog: (): void => {
              this.controller?.exportLog();
            }
          })
        }
        .tabBar(this.tabBar($r('sys.symbol.doc_text'), $r('sys.symbol.doc_text_fill'), '日志'))

        TabContent() {
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
            onSaveManagementCredentials: async (username: string, password: string): Promise<boolean> =>
              this.saveManagementCredentials(username, password),
            onClearManagementCredentials: async (): Promise<void> => this.clearManagementCredentials(),
            onBackgroundKeepAliveChange: async (enabled: boolean): Promise<boolean> =>
              this.setBackgroundKeepAliveEnabled(enabled),
            onSimulatedLocationChange: async (enabled: boolean): Promise<boolean> =>
              this.setSimulatedLocationEnabled(enabled),
            onSimulatedDownloadChange: async (enabled: boolean): Promise<boolean> =>
              this.setSimulatedDownloadEnabled(enabled),
            onPictureInPictureChange: async (enabled: boolean): Promise<boolean> =>
              this.setPictureInPictureEnabled(enabled)
          })
        }
        .tabBar(this.tabBar($r('sys.symbol.person'), $r('sys.symbol.person_fill'), '我的'))
      }
      .width('100%')
      .height('100%')
      .scrollable(false)
      .barOverlap(true)
      .vertical(false)
      .barPosition(BarPosition.End)
      .onAttach((): void => {
        try {
          this.tabsController.preloadItems([0, 1, 2, 3, 4]);
        } catch (error) {
          hilog.error(DOMAIN, TAG, 'OnAttach preloadItems failed: %{public}s', JSON.stringify(error));
        }
      })
      .barFloatingStyle({
        barBottomMargin: this.naviIndicatorHeight > 0 ? this.naviIndicatorHeight :
          $r('sys.float.padding_level8'),
        adaptToHandedness: true,
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onChange((index: number): void => {
        this.selectedTab = index;
      })
    }

  }
}
