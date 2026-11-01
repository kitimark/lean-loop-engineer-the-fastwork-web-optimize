/** Lean `Fw.Parts.EndPin.quietMs`: ms without a scroll or touch event before the pin may write. */
export const QUIET_MS = 120;

/** Lean `Pin`: touch state, ms since the last scroll or touch event, the last two distinct positions (`a` before `b`). */
export interface Pin {
  touching: boolean;
  since: number;
  a: number | null;
  b: number;
}

/** Lean `start`: the pin at rest on `y0`. */
export const start = (y0: number): Pin => ({ touching: false, since: 0, a: null, b: y0 });

/** Lean `reverses`: a write from `b` to `s` points against the last distinct motion `a` to `b`. */
export const reverses = (a: number | null, b: number, s: number): boolean => a !== null && (b - a) * (s - b) < 0;

/** Lean `mayWrite`: no touch down, quiet for `QUIET_MS`, off the target, and the write does not turn the page around. */
export const mayWrite = (p: Pin, s: number): boolean => !p.touching && QUIET_MS <= p.since && p.b !== s && !reverses(p.a, p.b, s);

/** Lean `Ev.down` / `Ev.up` through `step`: the touch state flips and the quiet time restarts. */
export const touch = (p: Pin, down: boolean): Pin => ({ ...p, touching: down, since: 0 });

/** Lean `step` on `Ev.move y`: the page took position `y` by itself. */
export const moved = (p: Pin, y: number): Pin => ({ ...p, since: 0, a: y === p.b ? p.a : p.b, b: y });

/** Lean `step` on `Ev.idle ms`: time passes; the pin writes `s` when `mayWrite` holds. */
export function idle(p: Pin, s: number, ms: number): [Pin, number | null] {
  const q = { ...p, since: p.since + ms };
  return mayWrite(q, s) ? [{ ...q, since: 0, a: q.b, b: s }, s] : [q, null];
}

/** Lean `due`: ms until the pin may write when only time stands in the way, else `null`. */
export const due = (p: Pin, s: number): number | null =>
  !p.touching && p.b !== s && !reverses(p.a, p.b, s) && p.since < QUIET_MS ? QUIET_MS - p.since : null;

/** Lean `observe` (through `eventOf`): one read of the page at `y`, `dt` ms after the last read. */
export function observe(p: Pin, s: number, y: number, dt: number): [Pin, number | null] {
  return y === p.b ? idle(p, s, dt) : [moved(p, y), null];
}

/** Lean `play`: the positions the page takes over an event list. */
export type Ev = ['move', number] | ['down'] | ['up'] | ['idle', number];
export function play(s: number, p: Pin, es: readonly Ev[]): number[] {
  const out: number[] = [];
  let cur = p;
  for (const e of es) {
    if (e[0] === 'move') {
      out.push(e[1]);
      cur = moved(cur, e[1]);
    } else if (e[0] === 'idle') {
      const [next, w] = idle(cur, s, e[1]);
      if (w !== null) out.push(w);
      cur = next;
    } else cur = touch(cur, e[0] === 'down');
  }
  return out;
}
