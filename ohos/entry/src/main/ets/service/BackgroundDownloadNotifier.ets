import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import common from '@ohos.app.ability.common';
import { CoreStatusStore } from './CoreStatusStore';

const DOMAIN = 0x0;
const TAG = 'OpenP2P-Download';
const INITIAL_PROGRESS = 1;
const MAX_PROGRESS = 90;
const UPDATES_PER_PROGRESS = 6;
const PROGRESS_UPDATE_INTERVAL_MS = 10 * 1000;


export class BackgroundDownloadNotifier {
  private notificationId: number = -1;
  private context?: common.Context;
  private progress: number = INITIAL_PROGRESS;
  private progressUpdateCount: number = 0;
  private timer: number = 0;
  private running: boolean = false;
  private updating: boolean = false;

  async start(notificationId: number, context: common.Context): Promise<void> {
    this.context = context;
    this.running = true;
    this.notificationId = notificationId;
    this.progress = INITIAL_PROGRESS;
    this.progressUpdateCount = 0;
    if (this.timer !== 0) {
      clearInterval(this.timer);
    }
    await this.publishProgress();
    this.timer = setInterval((): void => {
      this.advanceProgress();
    }, PROGRESS_UPDATE_INTERVAL_MS);
  }

  async stop(): Promise<void> {
    this.running = false;
    if (this.timer !== 0) {
      clearInterval(this.timer);
      this.timer = 0;
    }
    this.notificationId = -1;
  }

  private async advanceProgress(): Promise<void> {
    if (!this.running || this.updating) {
      return;
    }
    this.updating = true;
    try {
      if (this.progress < MAX_PROGRESS) {
        this.progressUpdateCount++;
        if (this.progressUpdateCount >= UPDATES_PER_PROGRESS) {
          this.progress++;
          this.progressUpdateCount = 0;
        }
      }
      await this.publishProgress();
    } finally {
      this.updating = false;
    }
  }

  private connectionText(): string {
    try {
      if (this.context === undefined) {
        return '连接状态获取中';
      }
      const status = CoreStatusStore.read(this.context);
      const now = Date.now();
      const since = status.connectedSince ?? 0;
      if (status.state !== 'vpn_ready' || since <= 0 || now - (status.timestamp ?? 0) > 35 * 1000) {
        return 'VPN 未连接';
      }
      const seconds = Math.max(0, Math.floor((now - since) / 1000));
      const hours = String(Math.floor(seconds / 3600)).padStart(2, '0');
      const minutes = String(Math.floor(seconds / 60) % 60).padStart(2, '0');
      const remainder = String(seconds % 60).padStart(2, '0');
      return `已连接 ${hours}:${minutes}:${remainder}`;
    } catch (_) {
      return '连接状态获取中';
    }
  }

  private async publishProgress(): Promise<void> {
    if (!this.running || this.notificationId < 0) {
      return;
    }
    try {
      if (!await notificationManager.isSupportTemplate('downloadTemplate')) {
        return;
      }
      const connectionText = this.connectionText();
      const template: notificationManager.NotificationTemplate = {
        name: 'downloadTemplate',
        data: {
          title: 'OpenP2P',
          fileName: connectionText,
          progressValue: this.progress
        }
      };
      const request: notificationManager.NotificationRequest = {
        id: this.notificationId,
        notificationSlotType: notificationManager.SlotType.LIVE_VIEW,
        template,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
          systemLiveView: {
            typeCode: 8,
            title: 'OpenP2P',
            text: connectionText
          }
        }
      };
      await notificationManager.publish(request);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to update download live view: %{public}s', JSON.stringify(error));
    }
  }
}
