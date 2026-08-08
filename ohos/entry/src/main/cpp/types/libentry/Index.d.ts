export const add: (a: number, b: number) => number;
export const startCore: (baseDir: string, token: string, shareBandwidth: number, logLevel: number) => boolean;
export const getLastError: () => string;
/** 0=stopped, 1=starting, 2=running, 3=failed; -1 means the core library is old. */
export const getCoreState: () => number;
/** True while the core instance is alive; independent of network and TUN state. */
export const isCoreRunning: () => boolean;
export const getCoreLastError: () => string;
export const stopCore: () => boolean;
export const getNodeName: () => string;
export const getSdwanConfig: () => Promise<string>;
export const readTun: (buffer: ArrayBuffer) => boolean;
export const writeTun: (buffer: ArrayBuffer, timeoutMs: number) => number;
