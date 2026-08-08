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
  private controller?: OpenP2PController;
  private tabsController: HdsTabsController = new HdsTabsController();
  private managementSession: ManagementSession = ManagementSession.getInstance();

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    this.controller = new OpenP2PController(context, this.state);
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
      this.naviIndicatorHeight = px2vp(avoidArea.bottomRect.height);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to query navigation indicator height: %{public}s', JSON.stringify(error));
    }
  }

  private async initializeManagement(): Promise<void> {
    try {
      const authenticated = await this.managementSession.initialize();
      this.managementUsername = this.managementSession.getUsername();
      this.managementAuthenticated = authenticated;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Management login failed: %{public}s', JSON.stringify(error));
      this.managementUsername = this.managementSession.getUsername();
      this.managementAuthenticated = false;
    }
  }

  private async saveManagementCredentials(username: string, password: string): Promise<boolean> {
    const authenticated = await this.managementSession.saveCredentialsAndLogin(username, password);
    this.managementUsername = this.managementSession.getUsername();
    this.managementAuthenticated = authenticated;
    return authenticated;
  }

  private async clearManagementCredentials(): Promise<void> {
    await this.managementSession.clear();
    this.managementUsername = '';
    this.managementAuthenticated = false;
    this.selectedTab = 0;
    this.tabsController.changeIndex(0);
  }

  build() {
    Row(){
      HdsTabs({ controller: this.tabsController }) {
        TabContent() {
          HomePage({
            state: this.state,
            onToggleCore: (): void => {
              this.controller?.toggleCore();
            },
            onSaveToken: (): void => {
              this.controller?.saveToken();
            }
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
          .tabBar(this.tabBar($r('sys.symbol.display'), $r('sys.symbol.display'), '网络'))
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
            onSaveManagementCredentials: async (username: string, password: string): Promise<boolean> =>
              this.saveManagementCredentials(username, password),
            onClearManagementCredentials: async (): Promise<void> => this.clearManagementCredentials()
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
