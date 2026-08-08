import common from '@ohos.app.ability.common';
import { promptAction } from '@kit.ArkUI';
import { CoreUiState } from '../model/CoreUiState';
import { CoreService, CoreStatus } from '../service/CoreService';
import { LogExportService } from '../service/LogExportService';

const MAX_VISIBLE_LOG_LINES = 500;
const MAX_UINT64 = '18446744073709551615';

export class OpenP2PController {
  private state: CoreUiState;
  private service: CoreService;
  private logExportService: LogExportService;
  private pollTimer: number = -1;
  private lastLogText: string = '';

  constructor(context: common.UIAbilityContext, state: CoreUiState) {
    this.state = state;
    this.service = new CoreService(context);
    this.logExportService = new LogExportService(context);
  }

  startPolling(): void {
    this.loadStoredToken();
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

  async toggleCore(): Promise<void> {
    if (this.state.busy) {
      return;
    }
    if (this.state.running) {
      await this.stopCore();
    } else {
      await this.startCore();
    }
  }

  async saveToken(): Promise<void> {
    if (this.state.running || this.state.busy) {
      return;
    }
    const token = this.state.token.trim();
    const error = this.validateToken(token);
    if (error.length > 0) {
      promptAction.showToast({ message: error });
      return;
    }
    this.state.busy = true;
    try {
      await this.service.saveToken(token);
      this.state.token = token;
      promptAction.showToast({ message: 'Token 已安全保存在本机' });
    } catch (error) {
      promptAction.showToast({ message: this.errorMessage(error) });
    } finally {
      this.state.busy = false;
    }
  }

  async exportLog(): Promise<void> {
    try {
      const exported = await this.logExportService.export();
      if (exported) {
        promptAction.showToast({ message: '日志已导出为 openp2p.log' });
      }
    } catch (error) {
      promptAction.showToast({ message: `导出日志失败：${this.errorMessage(error)}` });
    }
  }

  private async loadStoredToken(): Promise<void> {
    try {
      const token = await this.service.loadToken();
      if (this.state.token.length === 0 && token.length > 0) {
        this.state.token = token;
      }
    } catch (error) {
      promptAction.showToast({ message: `读取本地 Token 失败：${this.errorMessage(error)}` });
    }
  }

  private async startCore(): Promise<void> {
    const token = this.state.token.trim();
    const error = this.validateToken(token);
    if (error.length > 0) {
      promptAction.showToast({ message: error });
      return;
    }

    this.state.busy = true;
    this.state.connected = false;
    this.state.token = token;
    // Do not treat a login line from an earlier session as current success.
    this.lastLogText = this.service.readLogText();
    try {
      await this.service.start(token);
      promptAction.showToast({ message: '核心已启动，正在登录' });
    } catch (error) {
      promptAction.showToast({ message: this.errorMessage(error) });
    } finally {
      this.state.busy = false;
      this.refresh();
    }
  }

  private async stopCore(): Promise<void> {
    this.state.busy = true;
    try {
      await this.service.stop();
      this.state.connected = false;
      promptAction.showToast({ message: '核心已停止' });
    } catch (error) {
      promptAction.showToast({ message: this.errorMessage(error) });
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
    if (status.state === 'stopped' || status.state === 'not_started' || status.state === 'failed' ||
      status.state === 'recovery_exhausted') {
      this.state.connected = false;
    }
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

    for (const line of appended.split('\n')) {
      if (line.toLowerCase().includes('login ok')) {
        // This is intentionally identical to the Flutter connection check.
        this.state.connected = true;
      }
    }

    const lines = text.split('\n').filter((line: string): boolean => line.trim().length > 0);
    const start = Math.max(0, lines.length - MAX_VISIBLE_LOG_LINES);
    this.state.logs = lines.slice(start);
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
