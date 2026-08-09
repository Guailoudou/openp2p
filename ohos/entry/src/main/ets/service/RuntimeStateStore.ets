import common from '@ohos.app.ability.common';
import { fileIo } from '@kit.CoreFileKit';

const STATE_FILE = 'opl_runtime_state.json';

interface RuntimeState {
  desiredRunning: boolean;
  backgroundKeepAliveEnabled?: boolean;
  simulatedLocationEnabled?: boolean;
  simulatedDownloadEnabled?: boolean;
  pictureInPictureEnabled?: boolean;
}

export class RuntimeStateStore {
  private context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  isDesiredRunning(): boolean {
    return this.readState().desiredRunning === true;
  }

  isBackgroundKeepAliveEnabled(): boolean {
    return this.readState().backgroundKeepAliveEnabled !== false;
  }

  isSimulatedLocationEnabled(): boolean {
    return this.readState().simulatedLocationEnabled === true;
  }

  isSimulatedDownloadEnabled(): boolean {
    return this.readState().simulatedDownloadEnabled === true;
  }

  isPictureInPictureEnabled(): boolean {
    return this.readState().pictureInPictureEnabled === true;
  }

  setDesiredRunning(desiredRunning: boolean): void {
    const state = this.readState();
    state.desiredRunning = desiredRunning;
    this.writeState(state);
  }

  setBackgroundKeepAliveEnabled(enabled: boolean): void {
    const state = this.readState();
    state.backgroundKeepAliveEnabled = enabled;
    this.writeState(state);
  }

  setSimulatedLocationEnabled(enabled: boolean): void {
    const state = this.readState();
    state.simulatedLocationEnabled = enabled;
    this.writeState(state);
  }

  setSimulatedDownloadEnabled(enabled: boolean): void {
    const state = this.readState();
    state.simulatedDownloadEnabled = enabled;
    this.writeState(state);
  }

  setPictureInPictureEnabled(enabled: boolean): void {
    const state = this.readState();
    state.pictureInPictureEnabled = enabled;
    this.writeState(state);
  }

  private readState(): RuntimeState {
    try {
      const path = `${this.context.filesDir}/${STATE_FILE}`;
      if (!fileIo.accessSync(path)) {
        return this.defaultState();
      }
      const state = JSON.parse(fileIo.readTextSync(path)) as RuntimeState;
      return {
        desiredRunning: state.desiredRunning === true,
        backgroundKeepAliveEnabled: state.backgroundKeepAliveEnabled !== false,
        simulatedLocationEnabled: state.simulatedLocationEnabled === true,
        simulatedDownloadEnabled: state.simulatedDownloadEnabled === true,
        pictureInPictureEnabled: state.pictureInPictureEnabled === true
      };
    } catch (_) {
      return this.defaultState();
    }
  }

  private defaultState(): RuntimeState {
    return {
      desiredRunning: false,
      backgroundKeepAliveEnabled: true,
      simulatedLocationEnabled: false,
      simulatedDownloadEnabled: false,
      pictureInPictureEnabled: false
    };
  }

  private writeState(state: RuntimeState): void {
    const path = `${this.context.filesDir}/${STATE_FILE}`;
    const file = fileIo.openSync(path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, JSON.stringify(state));
    } finally {
      fileIo.closeSync(file.fd);
    }
  }
}
