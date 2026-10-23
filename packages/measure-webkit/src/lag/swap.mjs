// Twin of lean/Fw/Measure/SwapWindow.lean; test/lag-swap.test.mjs checks it against golden/measure/wkcost.jsonl.
// Times are integer microseconds on the Timeline clock; a window is [start, stop].
import { readFileSync } from 'node:fs';
import { verdict, frac } from './reduce.mjs';

/** The constants Lean owns (Fw.Measure.SwapWindow), read from the generated golden, not typed here. */
const CONST = readFileSync(new URL('../../../contracts/golden/measure/wkcost.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l)).find((l) => l.kind === 'swapConst');
export const REST_US = CONST.restUs;
export const SWAP_US = CONST.swapUs;
export const PERIOD_US = CONST.periodUs;
export const PERIODS = CONST.periods;
export const TOL_US = CONST.tolUs;
export const DEADLINE_US = CONST.deadlineUs;
export const KINDS = Object.freeze(['Layout', 'Paint', 'Composite', 'RecalculateStyles']);

/** The windows a loop that starts at `s0` shows: n swaps one period apart (Lean `nominal`). */
export const nominal = (s0, n) => Array.from({ length: n }, (_, k) => [s0 + k * PERIOD_US, s0 + k * PERIOD_US + SWAP_US]);

/** Window k is as long as the swap and the next starts one period later, both within the tolerance (Lean `validAt`). */
export function validAt(ws, k) {
  const w = ws[k];
  if (!w) return false;
  if (Math.abs(w[1] - w[0] - SWAP_US) > TOL_US) return false;
  const v = ws[k + 1];
  return v ? Math.abs(v[0] - w[0] - PERIOD_US) <= TOL_US : true;
}

/** `swap:k`, `rest:k` or `outside`; a window holds its start and not its stop, the last window has no rest (Lean `phaseOf`). */
export function phaseOf(ws, t) {
  for (let k = 0; k < ws.length; k++) {
    const w = ws[k], v = ws[k + 1];
    if (!v) return w[0] <= t && t < w[1] ? `swap:${k}` : 'outside';
    if (t < w[0]) return 'outside';
    if (t < w[1]) return `swap:${k}`;
    if (t < v[0]) return `rest:${k}`;
  }
  return 'outside';
}

/** Records of type `ty` that start in phase `p`; a record is [type, start] (Lean `countIn`). */
export const countIn = (ws, p, ty, recs) => recs.filter((r) => r[0] === ty && phaseOf(ws, r[1]) === p).length;

/** Counts [phase, type, n] for every window's swap and rest, then `outside`, in the order of the Lean golden. */
export function countCells(ws, recs, types) {
  const phases = [...ws.flatMap((_, k) => [`swap:${k}`, `rest:${k}`]), 'outside'];
  return phases.flatMap((p) => types.map((ty) => [p, ty, countIn(ws, p, ty, recs)]));
}

const asFrac = (xs) => xs.map((x) => frac(x, 1));

/**
 * The verdict on one window and one event kind from the per-pass counts: a1 and a2 the two faithful captures (the A/A floor),
 * c the crop captures, dropped the passes whose window was not valid (Lean `cell`).
 */
export function cell(a1, a2, c, dropped) {
  if (a1.length === 0 || a2.length === 0 || c.length === 0) return dropped > 0 ? 'unresolved:drift' : 'unresolved:noSamples';
  if (verdict(asFrac(a1), asFrac(a2)) !== 'overlap') return 'unresolved:floorBroken';
  const v = verdict(asFrac([...a1, ...a2]), asFrac(c));
  return v === 'lower' ? 'win' : v === 'higher' ? 'loss' : 'unresolved:overlap';
}

/** Frames a 60 Hz display shows in one swap: the Layout passes the faithful loop makes there, the crop makes none (Lean `swapFrames`, `predictedLayout`). */
export const FRAMES_60 = CONST.frames60;
