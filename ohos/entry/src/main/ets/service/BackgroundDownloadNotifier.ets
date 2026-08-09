import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0;
const TAG = 'OpenP2P-Download';
const INITIAL_PROGRESS = 5;
const RECREATE_PROGRESS = 90;
const PROGRESS_UPDATE_INTERVAL_MS = 15 * 1000;
const DOWNLOAD_NOTIFICATION_IDS: number[] = [41001, 41002];

export class BackgroundDownloadNotifier {
  private notificationIndex: number = 0;
  private progress: number = INITIAL_PROGRESS;
  private timer: number = 0;
  private taskSequence: number = 1;
  private running: boolean = false;
  private updating: boolean = false;

  async start(): Promise<void> {
    this.running = true;
    this.notificationIndex = 0;
    this.progress = INITIAL_PROGRESS;
    this.taskSequence = 1;
    if (this.timer !== 0) {
      clearInterval(this.timer);
    }
    await this.cancelNotification(DOWNLOAD_NOTIFICATION_IDS[0]);
    await this.cancelNotification(DOWNLOAD_NOTIFICATION_IDS[1]);
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
    await this.cancelNotification(DOWNLOAD_NOTIFICATION_IDS[0]);
    await this.cancelNotification(DOWNLOAD_NOTIFICATION_IDS[1]);
  }

  private async advanceProgress(): Promise<void> {
    if (!this.running || this.updating) {
      return;
    }
    this.updating = true;
    try {
      this.progress++;
      await this.publishProgress();
      if (this.progress >= RECREATE_PROGRESS) {
        await this.recreateDownloadTask();
      }
    } finally {
      this.updating = false;
    }
  }

  private async recreateDownloadTask(): Promise<void> {
    const previousId = DOWNLOAD_NOTIFICATION_IDS[this.notificationIndex];
    await this.cancelNotification(previousId);
    if (!this.running) {
      return;
    }
    this.notificationIndex = (this.notificationIndex + 1) % DOWNLOAD_NOTIFICATION_IDS.length;
    this.progress = INITIAL_PROGRESS;
    this.taskSequence++;
    await this.publishProgress();
  }

  private async publishProgress(): Promise<void> {
    if (!this.running) {
      return;
    }
    try {
      if (!await notificationManager.isSupportTemplate('downloadTemplate')) {
        return;
      }
      const template: notificationManager.NotificationTemplate = {
        name: 'downloadTemplate',
        data: {
          title: 'OpenP2P 数据通道运行中',
          fileName: `后台连接数据传输 #${this.taskSequence}`,
          progressValue: this.progress
        }
      };
      const request: notificationManager.NotificationRequest = {
        id: DOWNLOAD_NOTIFICATION_IDS[this.notificationIndex],
        template,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: 'OpenP2P',
            text: '后台连接数据传输中'
          }
        }
      };
      await notificationManager.publish(request);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to update download live view: %{public}s', JSON.stringify(error));
    }
  }

  private async cancelNotification(notificationId: number): Promise<void> {
    try {
      await notificationManager.cancel(notificationId);
    } catch (_) {
      // A task may already have been removed by the system or the user.
    }
  }
}
