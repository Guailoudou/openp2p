import common from '@ohos.app.ability.common';
import { SymbolGlyphModifier, window } from '@kit.ArkUI';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { OpenP2PController } from '../controller/OpenP2PController';
import { CoreUiState } from '../model/CoreUiState';
import { HomePage } from './HomePage';
import { LogsPage } from './LogsPage';
import { ProfilePage } from './ProfilePage';

const DOMAIN = 0x0;
const TAG = 'OpenP2P-HdsTabs';

@Entry
@Component
struct Index {
  @State private selectedTab: number = 0;
  @State private state: CoreUiState = new CoreUiState();
  @State private naviIndicatorHeight: number = 0;
  private controller?: OpenP2PController;
  private tabsController: HdsTabsController = new HdsTabsController();

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    this.controller = new OpenP2PController(context, this.state);
    this.controller.startPolling();
    this.updateNaviIndicatorHeight(context);
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

  build() {
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

      TabContent() {
        LogsPage({ state: this.state })
      }
      .tabBar(this.tabBar($r('sys.symbol.doc_text'), $r('sys.symbol.doc_text_fill'), '日志'))

      TabContent() {
        ProfilePage()
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
