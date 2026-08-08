@Observed
export class CoreUiState {
  token: string = '';
  tokenVisible: boolean = false;
  busy: boolean = false;
  running: boolean = false;
  connected: boolean = false;
  coreState: string = 'not_started';
  coreMessage: string = '核心尚未启动';
  logs: Array<string> = [];
}
