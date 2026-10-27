import { progress, sameKey, stateKey } from './logic';

export interface StageFrame {
  y: number;
  maxY: number;
  t: number;
}

export interface StageEnv {
  read(): StageFrame;
  publish(p: number): void;
  pointer(none: boolean): void;
}

export interface StageDriver {
  frame(): (() => void) | undefined;
}

export function createStageDriver(env: StageEnv): StageDriver {
  let last = stateKey(0);
  return {
    frame() {
      const p = progress(env.read());
      const key = stateKey(p);
      if (sameKey(key, last)) return undefined;
      const pointerChanged = key[0] !== last[0];
      last = key;
      return () => {
        env.publish(p);
        if (pointerChanged) env.pointer(key[0]!);
      };
    },
  };
}
