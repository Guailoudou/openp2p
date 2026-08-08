import common from '@ohos.app.ability.common';
import { fileIo } from '@kit.CoreFileKit';

const STATE_FILE = 'opl_runtime_state.json';

interface RuntimeState {
  desiredRunning: boolean;
}

export class RuntimeStateStore {
  private context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  isDesiredRunning(): boolean {
    try {
      const path = `${this.context.filesDir}/${STATE_FILE}`;
      if (!fileIo.accessSync(path)) {
        return false;
      }
      const state = JSON.parse(fileIo.readTextSync(path)) as RuntimeState;
      return state.desiredRunning === true;
    } catch (_) {
      return false;
    }
  }

  setDesiredRunning(desiredRunning: boolean): void {
    const path = `${this.context.filesDir}/${STATE_FILE}`;
    const file = fileIo.openSync(path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, JSON.stringify({ desiredRunning } as RuntimeState));
    } finally {
      fileIo.closeSync(file.fd);
    }
  }
}
