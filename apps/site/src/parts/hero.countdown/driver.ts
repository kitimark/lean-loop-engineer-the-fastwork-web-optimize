import type { MotionClock, Tick } from '../../engine/clock';
import {
  digitAt,
  digitPlaces,
  faceOffsetPx,
  remainingSeconds,
  springStep,
  stripOffsetCells,
  unitsFromSeconds,
  type SpringState,
} from './logic';

/** What the driver writes to: a node with a style.transform. Real elements satisfy it; tests pass plain objects. */
export interface Writable {
  style: { transform: string };
}
export interface DigitHandle {
  /** index of the unit (0 days .. 3 seconds) and the place value of this digit */
  unit: number;
  place: number;
  /** faithful: ten face nodes (digit 0..9); strip: exactly one strip node */
  nodes: Writable[];
}

interface Slot {
  h: DigitHandle;
  spring: SpringState;
  target: number;
  lastT: number;
  animating: boolean;
  cell: number;
}

export interface DriverOptions {
  variant: 'faithful' | 'strip';
  digits: DigitHandle[];
  /** `Date.now()` (injectable so a capture can pin it) */
  dateNow: () => number;
  /** reduced motion: jump to the target without the spring (the original reads `matches` at each change) */
  reduced: () => boolean;
}

/**
 * One writer for every digit, ticked by the MotionClock. Replaces the original's `setInterval(1 s)` and one
 * rAF spring per digit (N2:3791-3867, 3933-3936) with a single subscriber: same maths, same writes
 * (a transform on each of the 10 faces per frame while a digit moves; one strip transform in `strip`).
 * Delta: the 1 s refresh happens on the first frame after the second changes, not on a timer.
 */
export function createCountdownDriver(opts: DriverOptions) {
  const slots: Slot[] = opts.digits.map((h) => ({
    h,
    spring: { value: 0, velocity: 0 },
    target: 0,
    lastT: 0,
    animating: false,
    cell: 0,
  }));
  let lastSecond = -1;
  let started = false;

  const write = (s: Slot) => {
    if (!(s.cell > 0)) return;
    if (opts.variant === 'strip') {
      s.h.nodes[0]!.style.transform = `translateY(${stripOffsetCells(s.spring.value) * s.cell}px)`;
    } else {
      for (let f = 0; f < s.h.nodes.length; f++) {
        s.h.nodes[f]!.style.transform = `translateY(${faceOffsetPx(f, s.spring.value, s.cell)}px)`;
      }
    }
  };

  /** slots whose spring chain the original (re)starts in this refresh (faithful scheduling) */
  let started_: number[] = [];

  const retarget = (units: number[], now: number) => {
    started_ = [];
    for (let i = 0; i < slots.length; i++) {
      const s = slots[i]!;
      const value = units[s.h.unit] ?? 0;
      const t = digitAt(value, s.h.place);
      if (!started) {
        s.spring = { value: t, velocity: 0 };
        s.target = t;
        write(s);
        if (!opts.reduced()) started_.push(i); // the original's effect also runs one rAF chain at mount
        continue;
      }
      if (t === s.target) continue;
      s.target = t;
      if (opts.reduced()) {
        s.spring = { value: t, velocity: 0 };
        s.animating = false;
        write(s);
      } else {
        s.spring = { value: s.spring.value, velocity: 0 }; // the original restarts from rest at the current value
        s.lastT = now;
        s.animating = true;
        started_.push(i);
      }
    }
    started = true;
  };

  const refresh = (now: number): { changed: boolean; started: number[] } => {
    const sec = remainingSeconds(opts.dateNow());
    const changed = sec !== lastSecond;
    if (changed) {
      lastSecond = sec;
      retarget(unitsFromSeconds(sec), now);
    } else started_ = [];
    return { changed, started: started_ };
  };

  /** One spring frame of one digit; true when its chain is done. */
  const step = (i: number, now: number): boolean => {
    const s = slots[i];
    if (!s) return true;
    const r = springStep(s.spring, s.target, now - s.lastT);
    s.lastT = now;
    s.spring = r.state;
    write(s);
    if (r.done) s.animating = false;
    return r.done;
  };

  return {
    /** digit count per unit (React renders this shape; it changes only at powers of ten) */
    shape(): number[] {
      const u = unitsFromSeconds(remainingSeconds(opts.dateNow()));
      return u.map((v, i) => digitPlaces(v, i > 0).length);
    },
    /** spacer offsetHeight changed (ResizeObserver) */
    setCell(index: number, px: number) {
      const s = slots[index];
      if (!s) return;
      s.cell = px;
      write(s);
    },
    refresh,
    step,
    /** shared-loop form: refresh, then step every animating digit; true on the frame where the second changed */
    tick(now: number): boolean {
      const { changed } = refresh(now);
      for (let i = 0; i < slots.length; i++) if (slots[i]!.animating) step(i, now);
      return changed;
    },
    /** test hook */
    snapshot() {
      return slots.map((s) => ({ value: s.spring.value, target: s.target, animating: s.animating }));
    },
  };
}

export interface FaithfulOptions {
  clock: MotionClock;
  driver: ReturnType<typeof createCountdownDriver>;
  /** `performance.now()` (the original's spring start time) */
  perfNow: () => number;
  /** called after each refresh with whether the displayed second changed */
  onRefresh?: (changed: boolean) => void;
  /** where `visibilitychange` fires (default `document`) */
  doc?: VisibilitySource;
}

/** The part of `Document` the visibility hook needs (tests pass an EventTarget). */
export type VisibilitySource = Pick<EventTarget, 'addEventListener' | 'removeEventListener'>;

/**
 * The "refresh now" event of Lean `Fw.Parts.HeroCountdown.refreshNow`: every `visibilitychange`, hidden or visible,
 * runs `refresh` once (N2:3938-3940, the same function as the 1 s interval), so the digits shown after it equal the
 * current time's. Returns the cleanup.
 */
export function onVisibilityChange(doc: VisibilitySource, refresh: () => void): () => void {
  doc.addEventListener('visibilitychange', refresh);
  return () => doc.removeEventListener('visibilitychange', refresh);
}

/**
 * Faithful scheduling, same structure as the original: one `setInterval(1000)` that refreshes the clock reading
 * (N2:3930-3936, plus one immediate call at 3929), and per digit its own rAF chain that starts when the digit's
 * target changes, cancels the previous chain, and stops when the spring settles (N2:3830-3838).
 * Returns the cleanup (cancels the interval and every chain).
 */
export function startFaithful(o: FaithfulOptions): () => void {
  const chains = new Map<number, () => void>();
  const stop = (i: number) => {
    chains.get(i)?.();
    chains.delete(i);
  };
  const refresh = () => {
    const r = o.driver.refresh(o.perfNow());
    for (const i of r.started) {
      stop(i);
      chains.set(
        i,
        o.clock.subscribe(
          (t) => {
            if (o.driver.step(i, t)) stop(i);
          },
          { own: true },
        ),
      );
    }
    o.onRefresh?.(r.changed);
  };
  refresh();
  const cancel = o.clock.interval(1000, refresh);
  const doc = o.doc ?? (typeof document === 'undefined' ? undefined : document);
  const unlisten = doc ? onVisibilityChange(doc, refresh) : () => {};
  return () => {
    cancel();
    unlisten();
    for (const i of [...chains.keys()]) stop(i);
  };
}

export function oneChainClock(clock: MotionClock): MotionClock {
  const chains = new Set<{ tick: Tick }>();
  let off: (() => void) | null = null;
  const frame = (t: number) => {
    for (const c of [...chains]) if (chains.has(c)) c.tick(t);
  };
  return {
    subscribe(tick, opts) {
      if (!opts?.own) return clock.subscribe(tick, opts);
      const c = { tick };
      chains.add(c);
      off ??= clock.subscribe(frame);
      return () => {
        chains.delete(c);
        if (chains.size === 0 && off) {
          off();
          off = null;
        }
      };
    },
    interval: (ms, cb) => clock.interval(ms, cb),
  };
}
