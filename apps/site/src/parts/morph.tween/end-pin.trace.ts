import type { TweenEnv } from './driver';

export interface PinTraceHost {
  __fwPinTrace?: (e: object) => void;
}

export function withPinTrace(env: TweenEnv, host: PinTraceHost): void {
  Object.defineProperty(env, 'trace', { configurable: true, enumerable: true, get: () => host.__fwPinTrace });
}
