import common from '@ohos.app.ability.common';
import { CoreUiState } from '../model/CoreUiState';
import { CoreService, CoreStatus } from '../service/CoreService';
import { LogExportService } from '../service/LogExportService';

const MAX_VISIBLE_LOG_LINES = 500;
const MAX_UINT64 = '18446744073709551615';

export class OpenP2PController {
  private state: CoreUiState;
  private service: CoreService;
  private logExportService: LogExportService;
  private uiContext: UIContext;
  private pollTimer: number = -1;
  private lastLogText: string = '';
  private visibleLogText: string = '';

  constructor(context: common.UIAbilityContext, state: CoreUiState, uiContext: UIContext) {
    this.state = state;
    this.service = new CoreService(context);
    this.logExportService = new LogExportService(context);
    this.uiContext = uiContext;
  }

  startPolling(): void {
    this.loadStoredToken();
    this.resetVisibleLogs();
    this.refresh();
    if (this.pollTimer < 0) {
      this.pollTimer = setInterval((): void => this.refresh(), 500);
    }
  }

  stopPolling(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private showToast(message: string): void {
    try {
      this.uiContext.getPromptAction().showToast({ message });
    } catch (_) {
    }
  }

  async toggleCore(): Promise<void> {
    if (this.state.busy) {
      if (this.state.running) {
        await this.stopCore();
      }
      return;
    }
    if (this.state.running) {
      await this.stopCore();
    } else {
      await this.startCore();
    }
  }

  async saveToken(): Promise<void> {
    if (this.state.tokenLocked || this.state.running || this.state.busy) {
      return;
    }
    const token = this.state.token.trim();
    const error = this.validateToken(token);
    if (error.length > 0) {
      this.showToast(error);
      return;
    }
    this.state.busy = true;
    try {
      await this.service.saveToken(token);
      this.state.token = token;
      this.showToast('Token 已安全保存在本机');
    } catch (error) {
      this.showToast(this.errorMessage(error));
    } finally {
      this.state.busy = false;
    }
  }

  async applyManagedToken(token: string): Promise<void> {
    const normalized = token.trim();
    const error = this.validateToken(normalized);
    if (error.length > 0) {
      throw new Error(error);
    }
    await this.service.saveToken(normalized);
    this.state.token = normalized;
    this.state.tokenLocked = true;
  }

  unlockManagedToken(): void {
    this.state.tokenLocked = false;
  }

  isBackgroundKeepAliveEnabled(): boolean {
    return this.service.isBackgroundKeepAliveEnabled();
  }

  isSimulatedLocationEnabled(): boolean {
    return this.service.isSimulatedLocationEnabled();
  }

  isSimulatedDownloadEnabled(): boolean {
    return this.service.isSimulatedDownloadEnabled();
  }

  isPictureInPictureEnabled(): boolean {
    return this.service.isPictureInPictureEnabled();
  }

  async initializePictureInPicture(uiContext: UIContext): Promise<void> {
    await this.service.initializePictureInPicture(uiContext);
  }

  async setBackgroundKeepAliveEnabled(enabled: boolean): Promise<boolean> {
    const available = await this.service.setBackgroundKeepAliveEnabled(enabled);
    if (enabled) {
      this.showToast(available ? '持续后台任务已开启' : '设置已保存，系统任务不可用时将依赖其他保活方式');
    } else {
      this.showToast('持续后台任务已关闭');
    }
    return true;
  }

  async setSimulatedLocationEnabled(enabled: boolean): Promise<boolean> {
    const available = await this.service.setSimulatedLocationEnabled(enabled);
    if (!available && enabled) {
      this.showToast('设置已保存，授予定位和后台定位权限后生效');
      return true;
    }
    this.showToast(enabled ? '模拟定位已开启，请在系统设置中选择“始终允许”' : '模拟定位保活已关闭');
    return true;
  }

  async setSimulatedDownloadEnabled(enabled: boolean): Promise<boolean> {
    const available = await this.service.setSimulatedDownloadEnabled(enabled);
    if (!available && enabled) {
      this.showToast('设置已保存，开启通知权限后生效');
      return true;
    }
    this.showToast(enabled ? '模拟下载保活已开启' : '模拟下载保活已关闭');
    return true;
  }

  async setPictureInPictureEnabled(enabled: boolean, uiContext: UIContext): Promise<boolean> {
    const available = await this.service.setPictureInPictureEnabled(enabled, uiContext);
    if (!available && enabled) {
      this.showToast('设置已保存，当前设备不支持画中画');
      return true;
    }
    this.showToast(enabled ? '画中画保活已开启' : '画中画保活已关闭');
    return true;
  }

  async exportLog(): Promise<void> {
    try {
      const exported = await this.logExportService.export();
      if (exported) {
        this.showToast('日志已导出为 openp2p.log');
      }
    } catch (error) {
      this.showToast(`导出日志失败：${this.errorMessage(error)}`);
    }
  }

  private async loadStoredToken(): Promise<void> {
    try {
      const token = await this.service.loadToken();
      if (this.state.token.length === 0 && token.length > 0) {
        this.state.token = token;
      }
    } catch (error) {
      this.showToast(`读取本地 Token 失败：${this.errorMessage(error)}`);
    }
  }

  private async startCore(): Promise<void> {
    const token = this.state.token.trim();
    const error = this.validateToken(token);
    if (error.length > 0) {
      this.showToast(error);
      return;
    }

    this.state.busy = true;
    this.state.running = true;
    this.state.connected = false;
    this.state.token = token;
    this.resetVisibleLogs();
    try {
      this.showToast('核心已启动，正在登录');
      await this.service.start(token);
      this.showToast('核心已连接');
    } catch (error) {
      this.showToast(this.errorMessage(error));
    } finally {
      this.state.busy = false;
      this.refresh();
    }
  }

  private async stopCore(): Promise<void> {
    this.state.busy = true;
    this.state.running = false;
    this.state.connected = false;
    try {
      await this.service.stop();
      this.showToast('核心已停止');
    } catch (error) {
      this.showToast(this.errorMessage(error));
    } finally {
      this.state.busy = false;
      this.refresh();
    }
  }

  private refresh(): void {
    this.applyStatus(this.service.readStatus());
    this.applyLogText(this.service.readLogText());
  }

  private applyStatus(status: CoreStatus): void {
    this.state.coreState = status.state;
    this.state.coreMessage = status.message;
    this.state.running = this.isRunningState(status.state);
    this.state.connected = status.state === 'core_started' || status.state === 'vpn_requested' ||
      status.state === 'vpn_starting' || status.state === 'vpn_waiting_config' || status.state === 'vpn_ready';
  }

  private applyLogText(text: string): void {
    if (text === this.lastLogText) {
      return;
    }
    let appended = text;
    if (text.startsWith(this.lastLogText)) {
      appended = text.substring(this.lastLogText.length);
    }
    this.lastLogText = text;
    this.visibleLogText += appended;

    const lines = this.visibleLogText.split('\n').filter((line: string): boolean => line.trim().length > 0);
    const start = Math.max(0, lines.length - MAX_VISIBLE_LOG_LINES);
    this.state.logs = lines.slice(start);
  }

  private resetVisibleLogs(): void {
    this.lastLogText = this.service.readLogText();
    this.visibleLogText = '';
    this.state.logs = [];
  }

  private isRunningState(value: string): boolean {
    return value === 'requested' || value === 'starting' || value === 'core_starting' ||
      value === 'core_started' || value === 'core_restarting' || value === 'vpn_requested' || value === 'vpn_starting' ||
      value === 'vpn_waiting_config' || value === 'vpn_ready';
  }

  private validateToken(value: string): string {
    if (!/^\d+$/.test(value)) {
      return 'Token 只能包含十进制数字';
    }
    let normalized = value.replace(/^0+/, '');
    if (normalized.length === 0) {
      normalized = '0';
    }
    if (normalized === '0') {
      return 'Token 不能为 0';
    }
    if (normalized.length > MAX_UINT64.length ||
      (normalized.length === MAX_UINT64.length && normalized > MAX_UINT64)) {
      return 'Token 超出 uint64 范围';
    }
    return '';
  }

  private errorMessage(error: Object): string {
    const value = error as Record<string, Object>;
    const message = value['message'];
    return typeof message === 'string' && message.length > 0 ? message : String(error);
  }
}
