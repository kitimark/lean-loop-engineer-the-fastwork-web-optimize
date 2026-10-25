// Zone verdict of the webkit-sim scroll lane: the TS twin of lean/Fw/Measure/OffscreenWebKit.lean, replayed against
// packages/contracts/golden/measure/offscreen-webkit.jsonl. The compare and judge rules are the Chromium twins
// (Fw.Measure.Offscreen cmp, judge, sameWindow); this module adds the window by scroll y and the equal-step-set rule.
import { MIN_RUNS, SLACK, cmp, judge, sameWindow } from '../../measure-chromium/src/offscreen.mjs';

export const WK_KEYS = [
  'RecalculateStyles', 'Layout', 'Paint', 'Composite', 'RenderingFrame', 'FireAnimationFrame', 'TimerFire',
  'ObserverCallback', 'EventDispatch', 'FunctionCall', 'ScheduleStyleRecalculation', 'InvalidateLayout',
];
export const END_CUT = 5200;
export const ZONES = [
  { name: 'z4500', lo: 4500, hi: 4950 },
  { name: 'z5000', lo: 5000, hi: END_CUT },
  { name: 'finish', lo: 4500, hi: END_CUT },
  { name: 'whole', lo: 0, hi: END_CUT },
];

const inWin = (lo, hi, y) => lo <= y && y <= hi;

/** The scroll positions of the steps in [lo, hi]. */
export const windowSteps = (lo, hi, p) => p.ys.filter((y) => inWin(lo, hi, y));

/** One pass's window: the step count and, per counter, the sum over the window's steps (a short row reads 0). */
export function windowVec(lo, hi, p) {
  const m = p.ys.map((y) => inWin(lo, hi, y));
  const vals = {};
  WK_KEYS.forEach((k, i) => {
    vals[k] = p.rows.reduce((s, r, j) => s + (m[j] ? r[i] ?? 0 : 0), 0);
  });
  return { n: m.filter(Boolean).length, vals };
}

const shaped = (p) => p.ys.length === p.rows.length;

/** Every pass holds the same steps in the window, and there is a pass. */
export function sameSteps(lo, hi, ps) {
  if (ps.length === 0) return false;
  const first = windowSteps(lo, hi, ps[0]);
  return ps.every((q) => {
    const s = windowSteps(lo, hi, q);
    return s.length === first.length && s.every((y, i) => y === first[i]);
  });
}

export function usable(lo, hi, base, flag) {
  const all = [...base, ...flag];
  return base.length >= MIN_RUNS && flag.length >= MIN_RUNS && all.every(shaped) && sameSteps(lo, hi, all) &&
    sameWindow(all.map((p) => windowVec(lo, hi, p)));
}

const spread = (xs) => [Math.min(...xs), Math.max(...xs)];

/** Per counter: the compare of the flag's spread with the base's. */
export function cmpKeys(lo, hi, base, flag) {
  const bv = base.map((p) => windowVec(lo, hi, p));
  const fv = flag.map((p) => windowVec(lo, hi, p));
  return Object.fromEntries(WK_KEYS.map((k) => [k, cmp(SLACK, spread(bv.map((v) => v.vals[k])), spread(fv.map((v) => v.vals[k])))]));
}

export function verdict(lo, hi, base, flag) {
  if (!usable(lo, hi, base, flag)) return 'noData';
  return judge(Object.values(cmpKeys(lo, hi, base, flag)));
}

export const zoneVerdicts = (base, flag) => ZONES.map((z) => [z.name, verdict(z.lo, z.hi, base, flag)]);

/** The passes of one `webkit-sim` session file: `passes[].scroll` with `ys` and `reduced.perStep`. */
export const passOf = (pass) => ({ ys: pass.scroll.ys, rows: pass.scroll.reduced.perStep });
