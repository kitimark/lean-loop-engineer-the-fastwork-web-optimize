import { getClock, type MotionClock } from './clock';
import { listenerAction, orderCallbacks, shouldSchedule, type Entry, type ScrollVariant } from '../parts/engine.scroll/logic';

/**
 * engine.scroll. Public API: `registerScroll(id, order, cb)`; a part never touches `scroll`/`resize`/rAF itself.
 *
 * faithful (original 2.DyWL8TcE.js:2667-2782): one passive `scroll` and one passive `resize` listener, attached on the
 * first registration; an event requests one frame on the clock if none is pending; the frame runs every callback in
 * order, each one interleaving its own reads and writes. Registering also requests a frame (dE calls rE()).
 *
 * batched: same listeners and one frame, but `y/vw/vh` are read once, every callback runs its read phase first and the
 * writers they return run afterwards (all reads, then all writes).
 *
 * A callback may return a writer. faithful runs it right after its own callback (interleaved); batched defers it.
 * Callbacks that return nothing are unaffected by the variant.
 */
export interface ScrollFrame {
  t: number;
  y: number;
  vw: number;
  vh: number;
}
export type ScrollCallback = (f: ScrollFrame) => void | (() => void);

export interface ScrollEnv {
  addEventListener(type: 'scroll' | 'resize', fn: () => void): void;
  removeEventListener(type: 'scroll' | 'resize', fn: () => void): void;
  readY(): number;
  readVw(): number;
  readVh(): number;
}

export interface ScrollEngine {
  register(id: string, order: number, cb: ScrollCallback): () => void;
  /** Ask for a frame, as a `scroll` event does. */
  request(): void;
  setVariant(v: ScrollVariant): void;
  readonly variant: ScrollVariant;
}

export function createScrollEngine(clock: MotionClock, env: ScrollEnv, initial: ScrollVariant = 'faithful'): ScrollEngine {
  const cbs = new Map<number, { entry: Entry; cb: ScrollCallback }>();
  let seq = 0;
  let attached = false;
  let unsub: (() => void) | null = null;
  let lastT = Number.NaN;
  let variant = initial;

  const request = () => {
    if (!shouldSchedule(unsub !== null)) return;
    unsub = clock.subscribe(tick);
  };

  function tick(t: number) {
    // The clock may visit a tick that was re-added during the same frame; skip it, it stays subscribed for the next one.
    if (t === lastT) return;
    lastT = t;
    unsub?.();
    unsub = null;
    // orderCallbacks works on ids; key the entries by their unique seq to map back.
    const sorted = orderCallbacks([...cbs.values()].map((c) => ({ ...c.entry, id: String(c.entry.seq) }))).map((k) => cbs.get(Number(k))!);
    if (variant === 'faithful') {
      const f: ScrollFrame = {
        t,
        get y() {
          return env.readY();
        },
        get vw() {
          return env.readVw();
        },
        get vh() {
          return env.readVh();
        },
      };
      // framePlan(faithful, writers): read(i) then write(i), per callback.
      for (const c of sorted) {
        if (!cbs.has(c.entry.seq)) continue;
        const w = c.cb(f);
        if (typeof w === 'function') w();
      }
      return;
    }
    const f: ScrollFrame = { t, y: env.readY(), vw: env.readVw(), vh: env.readVh() };
    const writers: (null | (() => void))[] = [];
    for (const c of sorted) {
      if (!cbs.has(c.entry.seq)) {
        writers.push(null);
        continue;
      }
      const w = c.cb(f);
      writers.push(typeof w === 'function' ? w : null);
    }
    // framePlan(batched, writers): every read, then every write.
    for (const w of writers) w?.();
  }

  const onEvent = () => request();
  const sync = () => {
    const a = listenerAction(attached, cbs.size);
    if (a === 'attach') {
      attached = true;
      env.addEventListener('scroll', onEvent);
      env.addEventListener('resize', onEvent);
    } else if (a === 'detach') {
      attached = false;
      env.removeEventListener('scroll', onEvent);
      env.removeEventListener('resize', onEvent);
      unsub?.();
      unsub = null;
    }
  };

  return {
    register(id, order, cb) {
      const entry: Entry = { id, order, seq: seq++ };
      cbs.set(entry.seq, { entry, cb });
      sync();
      request();
      return () => {
        cbs.delete(entry.seq);
        sync();
      };
    },
    request,
    setVariant(v) {
      variant = v;
    },
    get variant() {
      return variant;
    },
  };
}

const windowEnv: ScrollEnv = {
  addEventListener: (type, fn) => window.addEventListener(type, fn, { passive: true }),
  removeEventListener: (type, fn) => window.removeEventListener(type, fn),
  readY: () => window.scrollY,
  readVw: () => window.innerWidth,
  readVh: () => window.innerHeight,
};

let shared: ScrollEngine | undefined;
/** The page engine (client only). */
export function getScrollEngine(): ScrollEngine {
  return (shared ??= createScrollEngine(getClock(), windowEnv));
}

/** Choose the variant (flags resolve at load; call once before the first frame, from the engine.scroll part). */
export function configureScroll(variant: ScrollVariant): void {
  getScrollEngine().setVariant(variant);
}

/**
 * Register a per-scroll-frame callback. `order` ascending (ties: registration order). Returns the unregister function.
 * The callback may return a writer function; see the header.
 */
export function registerScroll(id: string, order: number, cb: (f: { t: number; y: number; vw: number; vh: number }) => void | (() => void)): () => void {
  return getScrollEngine().register(id, order, cb);
}
