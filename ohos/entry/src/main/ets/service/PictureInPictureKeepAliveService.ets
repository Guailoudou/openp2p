import common from '@ohos.app.ability.common';
import { BuilderNode, NodeController, PiPWindow, typeNode } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0;
const TAG = 'OpenP2P-PiP';

class PiPContentParams {
  title: string = 'OpenP2P';
}

@Builder
function buildPiPContent(params: PiPContentParams) {
  Column({ space: 6 }) {
    Text(params.title)
      .fontSize(24)
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
    Text('后台运行中')
      .fontSize(14)
      .fontColor('#CCFFFFFF')
  }
  .width('100%')
  .height('100%')
  .justifyContent(FlexAlign.Center)
  .backgroundColor('#0A59F7')
}

class PiPContentController extends NodeController {
  private node: BuilderNode<[PiPContentParams]> | null = null;
  private builder: WrappedBuilder<[PiPContentParams]> = wrapBuilder(buildPiPContent);

  makeNode(context: UIContext): FrameNode | null {
    if (this.node === null) {
      this.node = new BuilderNode(context);
      this.node.build(this.builder, new PiPContentParams());
    }
    return this.node.getFrameNode();
  }
}

export class PictureInPictureKeepAliveService {
  private static instance: PictureInPictureKeepAliveService = new PictureInPictureKeepAliveService();
  private controller?: PiPWindow.PiPController;
  private xComponent?: typeNode.XComponent;
  private xComponentController: XComponentController = new XComponentController();
  private enabled: boolean = false;

  static getInstance(): PictureInPictureKeepAliveService {
    return PictureInPictureKeepAliveService.instance;
  }

  async initialize(uiContext: UIContext, context: common.UIAbilityContext): Promise<boolean> {
    if (this.controller !== undefined) {
      this.controller.setAutoStartEnabled(this.enabled);
      return true;
    }
    try {
      if (!PiPWindow.isPiPEnabled()) {
        return false;
      }
      this.xComponent = typeNode.createNode(uiContext, 'XComponent', {
        type: XComponentType.SURFACE,
        controller: this.xComponentController
      });
      this.controller = await PiPWindow.create({
        context,
        componentController: this.xComponentController,
        templateType: PiPWindow.PiPTemplateType.VIDEO_PLAY,
        contentWidth: 160,
        contentHeight: 90,
        defaultWindowSizeType: 1,
        customUIController: new PiPContentController()
      }, this.xComponent);
      this.controller.setAutoStartEnabled(this.enabled);
      this.controller.on('stateChange', (state: PiPWindow.PiPState, reason: string): void => {
        hilog.info(DOMAIN, TAG, 'PiP state=%{public}d reason=%{public}s', state, reason);
      });
      return true;
    } catch (error) {
      this.controller = undefined;
      this.xComponent = undefined;
      hilog.warn(DOMAIN, TAG, 'PiP initialization unavailable: %{public}s', JSON.stringify(error));
      return false;
    }
  }

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
    try {
      this.controller?.setAutoStartEnabled(enabled);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to update PiP auto start: %{public}s', JSON.stringify(error));
    }
    if (!enabled) {
      this.stopForForeground();
    }
  }

  async startForBackground(): Promise<void> {
    if (!this.enabled || this.controller === undefined) {
      return;
    }
    try {
      await this.controller.startPiP();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to start PiP: %{public}s', JSON.stringify(error));
    }
  }

  async stopForForeground(): Promise<void> {
    if (this.controller === undefined) {
      return;
    }
    try {
      await this.controller.stopPiP();
    } catch (error) {
      // Returning to the foreground when PiP is not active reports a repeated
      // or abnormal-state operation. It is safe to ignore.
      hilog.debug(DOMAIN, TAG, 'PiP was not active: %{public}s', JSON.stringify(error));
    }
  }
}
