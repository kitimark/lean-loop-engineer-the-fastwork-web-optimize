export const QUIET_MS = 120;

export interface Pin {
  touching: boolean;
  since: number;
  a: number | null;
  b: number;
}

export const start = (y0: number): Pin => ({ touching: false, since: 0, a: null, b: y0 });

export const reverses = (a: number | null, b: number, s: number): boolean => a !== null && (b - a) * (s - b) < 0;

export const mayWrite = (p: Pin, s: number): boolean => !p.touching && QUIET_MS <= p.since && p.b !== s && !reverses(p.a, p.b, s);

/** Lean `live`: a finger is down or the last scroll or touch event is younger than the quiet time. */
export const live = (q: Pin): boolean => q.touching || q.since < QUIET_MS;

export type Why = 'touching' | 'live' | 'onTarget' | 'reversal';

/** Lean `why`: the first failing condition of `mayWrite`, in the order touch, quiet time, target, turn; null means write. */
export function why(q: Pin, s: number): Why | null {
  if (q.touching) return 'touching';
  if (q.since < QUIET_MS) return 'live';
  if (q.b === s) return 'onTarget';
  if (reverses(q.a, q.b, s)) return 'reversal';
  return null;
}

export const touch = (p: Pin, down: boolean): Pin => ({ ...p, touching: down, since: 0 });

export const moved = (p: Pin, y: number): Pin => ({ ...p, since: 0, a: y === p.b ? p.a : p.b, b: y });

export function idle(p: Pin, s: number, ms: number): [Pin, number | null] {
  const q = { ...p, since: p.since + ms };
  return mayWrite(q, s) ? [{ ...q, since: 0, a: q.b, b: s }, s] : [q, null];
}

export const due = (p: Pin, s: number): number | null =>
  !p.touching && p.b !== s && !reverses(p.a, p.b, s) && p.since < QUIET_MS ? QUIET_MS - p.since : null;

export function observe(p: Pin, s: number, y: number, dt: number): [Pin, number | null] {
  return y === p.b ? idle(p, s, dt) : [moved(p, y), null];
}

/** Lean `Outcome.name`: what one reading of the page did (`moved`, `write`, or the reason the pin declined). */
export type Outcome = 'moved' | 'write' | Why;

/** Lean `outcome`, from the state before `observe`. */
export function outcome(p: Pin, s: number, y: number, dt: number): Outcome {
  if (y !== p.b) return 'moved';
  return why({ ...p, since: p.since + dt }, s) ?? 'write';
}

/** An idle event carries the target the driver read when it ran (Lean `Ev.idle ms s`). */
export type Ev = ['move', number] | ['down'] | ['up'] | ['idle', number, number];
export function play(p: Pin, es: readonly Ev[]): number[] {
  const out: number[] = [];
  let cur = p;
  for (const e of es) {
    if (e[0] === 'move') {
      out.push(e[1]);
      cur = moved(cur, e[1]);
    } else if (e[0] === 'idle') {
      const [next, w] = idle(cur, e[2], e[1]);
      if (w !== null) out.push(w);
      cur = next;
    } else cur = touch(cur, e[0] === 'down');
  }
  return out;
}
