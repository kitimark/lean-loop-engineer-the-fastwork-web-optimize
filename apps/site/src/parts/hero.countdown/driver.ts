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

  const retarget = (units: number[], now: number) => {
    for (const s of slots) {
      const value = units[s.h.unit] ?? 0;
      const t = digitAt(value, s.h.place);
      if (!started) {
        s.spring = { value: t, velocity: 0 };
        s.target = t;
        write(s);
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
      }
    }
    started = true;
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
    /** returns true on the frame where the displayed second changed */
    tick(now: number): boolean {
      const sec = remainingSeconds(opts.dateNow());
      const changed = sec !== lastSecond;
      if (changed) {
        lastSecond = sec;
        retarget(unitsFromSeconds(sec), now);
      }
      for (const s of slots) {
        if (!s.animating) continue;
        const r = springStep(s.spring, s.target, now - s.lastT);
        s.lastT = now;
        s.spring = r.state;
        write(s);
        if (r.done) s.animating = false;
      }
      return changed;
    },
    /** test hook */
    snapshot() {
      return slots.map((s) => ({ value: s.spring.value, target: s.target, animating: s.animating }));
    },
  };
}
