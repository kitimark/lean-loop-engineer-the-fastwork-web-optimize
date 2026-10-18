import type { StageEnv } from '../registry/only';

/**
 * The fixed ScrollEnv of a stage. The page's scroll engine (engine/scroll.ts) reads `window.scrollY`, `innerWidth` and
 * `innerHeight` at frame time, so the stage pins those three to the stage parameters and every part sees `y/vw/vh` as
 * given, whatever the real viewport is. The clock stays the real MotionClock. Media queries and layout follow the real
 * viewport: a run that wants layout parity sets the browser viewport to `vw x vh` (`mismatch` reports when it does not).
 * Writes happen once at mount, never per frame.
 */
export interface EnvTarget {
  scrollY: number;
  innerWidth: number;
  innerHeight: number;
}

export interface Pinned {
  restore(): void;
  /** the real viewport differs from the pinned one */
  mismatch: boolean;
}

const KEYS = ['scrollY', 'innerWidth', 'innerHeight'] as const;

export function pinEnv(win: EnvTarget, env: StageEnv): Pinned {
  const real = { vw: win.innerWidth, vh: win.innerHeight };
  const saved = KEYS.map((k) => [k, Object.getOwnPropertyDescriptor(win, k)] as const);
  const vals: Record<(typeof KEYS)[number], number> = { scrollY: env.y, innerWidth: env.vw, innerHeight: env.vh };
  for (const k of KEYS) Object.defineProperty(win, k, { configurable: true, get: () => vals[k] });
  return {
    mismatch: real.vw !== env.vw || real.vh !== env.vh,
    restore() {
      for (const [k, d] of saved) {
        if (d) Object.defineProperty(win, k, d);
        else delete (win as unknown as Record<string, unknown>)[k];
      }
    },
  };
}
