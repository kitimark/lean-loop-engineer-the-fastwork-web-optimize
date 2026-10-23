import { readFileSync } from 'node:fs';
import { verdict, frac } from './reduce.mjs';

const CONST = readFileSync(new URL('../../../contracts/golden/measure/wkcost.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l)).find((l) => l.kind === 'swapConst');
export const REST_US = CONST.restUs;
export const SWAP_US = CONST.swapUs;
export const PERIOD_US = CONST.periodUs;
export const PERIODS = CONST.periods;
export const TOL_US = CONST.tolUs;
export const DEADLINE_US = CONST.deadlineUs;
export const MIN_FAITHFUL = CONST.minFaithful;
export const BUSY_MIN = CONST.busyMin;
export const KINDS = Object.freeze(['Layout', 'Paint', 'Composite', 'RecalculateStyles']);

export const nominal = (s0, n) => Array.from({ length: n }, (_, k) => [s0 + k * PERIOD_US, s0 + k * PERIOD_US + SWAP_US]);

export function validAt(ws, k) {
  const w = ws[k];
  if (!w) return false;
  if (Math.abs(w[1] - w[0] - SWAP_US) > TOL_US) return false;
  const v = ws[k + 1];
  return v ? Math.abs(v[0] - w[0] - PERIOD_US) <= TOL_US : true;
}

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

export const countIn = (ws, p, ty, recs) => recs.filter((r) => r[0] === ty && phaseOf(ws, r[1]) === p).length;

export function countCells(ws, recs, types) {
  const phases = [...ws.flatMap((_, k) => [`swap:${k}`, `rest:${k}`]), 'outside'];
  return phases.flatMap((p) => types.map((ty) => [p, ty, countIn(ws, p, ty, recs)]));
}

const asFrac = (xs) => xs.map((x) => frac(x, 1));

export function cell(a1, a2, c, dropped) {
  if (a1.length === 0 || a2.length === 0 || c.length === 0) return dropped > 0 ? 'unresolved:drift' : 'unresolved:noSamples';
  if (a1.length < MIN_FAITHFUL || a2.length < MIN_FAITHFUL) return 'unresolved:fewSamples';
  if (verdict(asFrac(a1), asFrac(a2)) !== 'overlap') return 'unresolved:floorBroken';
  const v = verdict(asFrac([...a1, ...a2]), asFrac(c));
  return v === 'lower' ? 'win' : v === 'higher' ? 'loss' : 'unresolved:overlap';
}

export const FRAMES_60 = CONST.frames60;

/** Lean `bgOf`: what the rest windows next to a swap window say about work that is not the carousel. */
export function bgOf(ns) {
  if (ns.length === 0) return 'unknown';
  if (ns.every((n) => BUSY_MIN <= n)) return 'busy';
  if (ns.every((n) => n < BUSY_MIN)) return 'idle';
  return 'mixed';
}

/** Lean `swapNeighbours`: the rest windows before and after swap window k of n. */
export const swapNeighbours = (k, n) => [...(k > 0 ? [k - 1] : []), ...(k + 1 < n ? [k] : [])];
