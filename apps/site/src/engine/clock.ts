/**
 * Injectable MotionClock. All JS motion subscribes here; parts never call requestAnimationFrame, setInterval or
 * setTimeout themselves (PLAN 6.5 rule 2). The clock can schedule faithfully: `{ own: true }` gives a subscriber its own
 * rAF registration per frame, and `interval()` is a real setInterval, so the faithful variants reproduce the original's
 * rAF-callback and timer counts (PL5). Default subscribers share one rAF loop that runs only while any exist.
 * Scheduling decisions are pure functions in `clock.logic.ts`.
 */
import { rerequest, sharedLoopAction, validInterval } from './clock.logic';

export type Tick = (nowMs: number) => void;

export interface SubscribeOptions {
  /** own requestAnimationFrame registration per frame (faithful counts) instead of the shared loop. */
  own?: boolean;
}

export interface MotionClock {
  subscribe(tick: Tick, opts?: SubscribeOptions): () => void;
  /** A real `setInterval(cb, ms)`; returns the cancel function. */
  interval(ms: number, cb: () => void): () => void;
}

export interface ClockEnv {
  raf(cb: (t: number) => void): number;
  caf(h: number): void;
  setInterval(cb: () => void, ms: number): unknown;
  clearInterval(h: unknown): void;
}

const windowEnv = (): ClockEnv => ({
  raf: (cb) => requestAnimationFrame(cb),
  caf: (h) => cancelAnimationFrame(h),
  setInterval: (cb, ms) => setInterval(cb, ms),
  clearInterval: (h) => clearInterval(h as number),
});

export function createRafClock(env: ClockEnv = windowEnv()): MotionClock {
  const subs = new Set<Tick>();
  let handle = 0;
  let inFrame = false; // start/stop decisions made during a frame are deferred to its end (no double registration)
  const frame = (t: number) => {
    inFrame = true;
    for (const s of subs) s(t);
    inFrame = false;
    handle = rerequest('shared', subs.size, true) ? env.raf(frame) : 0;
  };
  return {
    subscribe(tick, opts) {
      if (opts?.own) {
        let h = 0;
        let live = true;
        const f = (t: number) => {
          h = 0;
          tick(t);
          if (rerequest('own', 0, live)) h = env.raf(f);
        };
        h = env.raf(f);
        return () => {
          live = false;
          if (h !== 0) env.caf(h);
          h = 0;
        };
      }
      subs.add(tick);
      if (!inFrame && sharedLoopAction(subs.size, handle !== 0) === 'start') handle = env.raf(frame);
      return () => {
        subs.delete(tick);
        if (!inFrame && sharedLoopAction(subs.size, handle !== 0) === 'stop') {
          env.caf(handle);
          handle = 0;
        }
      };
    },
    interval(ms, cb) {
      if (!validInterval(ms)) throw new RangeError(`interval ${ms}`);
      const h = env.setInterval(cb, ms);
      return () => env.clearInterval(h);
    },
  };
}

let shared: MotionClock | undefined;
/** The page-wide clock (client only). */
export function getClock(): MotionClock {
  return (shared ??= createRafClock());
}
