import { askView, COUNT_DELAY_MS, COUNT_DUR_MS, countAt, type View } from './logic';

/** A clock the drivers subscribe to (the engine's MotionClock subset). */
export interface DriverClock {
  subscribe(tick: (t: number) => void): () => void;
}

/** Visible means: intersecting at a ratio of at least 0.35 (thresholds 0, 0.35, 0.6 as in the original). */
export function observeVisible(el: Element, onChange: (visible: boolean) => void): () => void {
  const io = new IntersectionObserver(([e]) => onChange(!!(e?.isIntersecting && e.intersectionRatio >= 0.35)), { threshold: [0, 0.35, 0.6] });
  io.observe(el);
  return () => io.disconnect();
}

export interface CountEnv {
  clock: DriverClock;
  /** the four stat nodes' writers, in the order of PROFILE_TARGET; `fmt` turns the number into the shown text */
  targets: ReadonlyArray<{ n: number; write(v: number): void }>;
}

/**
 * The profile count-up: on becoming visible every number is 0, then (after 180 ms) runs to its target in 1080 ms with
 * an ease-out cubic (Lean `countAt`). Under reduced motion the targets show at once. Frames only while running.
 */
export function createCountUp(env: CountEnv, reduced: () => boolean) {
  let off: (() => void) | null = null;
  const stop = () => {
    off?.();
    off = null;
  };
  const showAll = (t: number) => {
    for (const x of env.targets) x.write(countAt({ n: x.n, t }));
  };
  return {
    /** the stage became visible */
    start(now: number) {
      stop();
      if (reduced()) {
        for (const x of env.targets) x.write(x.n);
        return;
      }
      showAll(0);
      let t0 = -1;
      off = env.clock.subscribe((tt) => {
        if (t0 < 0) t0 = tt;
        const t = tt - t0;
        showAll(t);
        if (t >= COUNT_DELAY_MS + COUNT_DUR_MS) stop();
      });
    },
    /** the stage left the view: stop, keep the numbers */
    cancel: stop,
  };
}

export interface AskEnv {
  clock: DriverClock;
  /** query lengths per topic (Lean `askView` takes them) */
  queries: readonly string[];
  /** writes the typed text and the caret into the field */
  write(text: string, caret: boolean): void;
  /** called only when the structural part of the view changes (list, leaving, results) */
  onView(v: View): void;
}

/**
 * The search typing loop (Lean `askView`): while the stage is visible, each frame computes the view from the elapsed time
 * and writes the text; the list state is reported only when it changes. Leaving resets everything.
 */
export function createAskDriver(env: AskEnv) {
  const lens = env.queries.map((q) => q.length);
  let off: (() => void) | null = null;
  let last: View | null = null;
  const same = (a: View, b: View) => a.shown === b.shown && a.leaving === b.leaving && a.results === b.results;
  return {
    start() {
      this.stop();
      let t0 = -1;
      last = null;
      off = env.clock.subscribe((tt) => {
        if (t0 < 0) t0 = tt;
        const v = askView({ lens, t: tt - t0 });
        env.write(env.queries[v.topic]!.slice(0, v.len), v.caret);
        if (!last || !same(last, v)) env.onView(v);
        last = v;
      });
    },
    stop() {
      off?.();
      off = null;
      if (last) {
        env.write('', false);
        env.onView({ len: 0, topic: 0, shown: 0, leaving: false, results: false, caret: false });
      }
      last = null;
    },
  };
}
