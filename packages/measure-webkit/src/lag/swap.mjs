import { readFileSync } from 'node:fs';
import { verdict, frac } from './reduce.mjs';

const CONST = readFileSync(new URL('../../../contracts/golden/measure/wkcost.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l)).find((l) => l.kind === 'swapConst');
const FREEZE_CONST = readFileSync(new URL('../../../contracts/golden/measure/wkcost.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l)).find((l) => l.kind === 'swapFreezeConst');
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

export function bgOf(ns) {
  if (ns.length === 0) return 'unknown';
  if (ns.every((n) => BUSY_MIN <= n)) return 'busy';
  if (ns.every((n) => n < BUSY_MIN)) return 'idle';
  return 'mixed';
}

export const swapNeighbours = (k, n) => [...(k > 0 ? [k - 1] : []), ...(k + 1 < n ? [k] : [])];

export const BUCKET_US = FREEZE_CONST.bucketUs;
export const BUSY_BUCKET = FREEZE_CONST.busyBucket;
export const LONG_RUN_MIN = FREEZE_CONST.longRunMin;

export function longRuns(xs) {
  let cur = 0, n = 0;
  for (const x of xs) {
    if (BUSY_BUCKET <= x) cur++;
    else { if (LONG_RUN_MIN <= cur) n++; cur = 0; }
  }
  return LONG_RUN_MIN <= cur ? n + 1 : n;
}

export function median2(xs) {
  const s = [...xs].sort((a, b) => a - b);
  return s.length === 0 ? 0 : s[(s.length - 1) >> 1] + s[s.length >> 1];
}

export const usableOf = (frozen) => frozen.filter((s) => s[1] !== 'unknown');

export function frozenCell(frozen, idle) {
  const usable = usableOf(frozen);
  if (usable.length === 0) return 'noSamples';
  if (usable.some((s) => s[1] !== 'idle')) return 'busyRemains';
  if (idle.length === 0) return 'noIdleLevel';
  return 2 * Math.max(...idle) < median2(usable.map((s) => s[0])) ? 'notAtIdle' : 'atIdle';
}

export const sharePct = (u2, f2) => (u2 > 0 ? Math.floor(((u2 - f2) * 100) / u2) : null);

export const zoneVerdict = (off, on) => verdict(asFrac(off), asFrac(on));

const LANE_CONST = readFileSync(new URL('../../../contracts/golden/measure/wkcost.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l)).find((l) => l.kind === 'swapLaneConst');
export const LANE_BUDGET_MIN = LANE_CONST.budgetMin;

export function busyFrozen(busy, frozen) {
  if (busy.length === 0) return 'noBusy';
  if (frozen.length === 0) return 'noFrozen';
  const v = zoneVerdict(busy, frozen);
  return v === 'lower' ? 'removed' : v === 'higher' ? 'raised' : 'overlap';
}

export const busyWindows = (ns) => ns.filter((n) => BUSY_MIN <= n).length;

export const perCaptureTenths = (rows, captures) => (captures === 0 ? 0 : Math.floor((rows * 20 + captures) / (2 * captures)));

export const perFrameMilli = (rows, frames) => (frames === 0 ? null : Math.floor((rows * 2000 + frames) / (2 * frames)));

export const unitFits = (elapsedMs, estimateMs) => elapsedMs + estimateMs <= LANE_BUDGET_MIN * 60000;

export const armOrder = (shift) => [['faithful', 'nolayout', 'full'], ['nolayout', 'full', 'faithful'], ['full', 'faithful', 'nolayout']][shift % 3];

export const laneUnits = (shift) => {
  const arms = armOrder(shift);
  return [
    ...arms.map((a) => `swap:${a}-a`), ...arms.map((a) => `zone:${a}-a`),
    'swap:faithful-frozen-a', 'zone:faithful-frozen-a', 'swap:faithful-b', 'zone:faithful-b',
    ...arms.filter((a) => a !== 'faithful').map((a) => `zone:${a}-b`), 'zone:faithful-frozen-b',
  ];
};

export const pooled = (rows, captures) => ({
  windows: rows.length, captures, busyWindows: busyWindows(rows),
  tenthsPerCapture: perCaptureTenths(rows.reduce((a, b) => a + b, 0), captures), median2: median2(rows),
});
