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

export const windowSteps = (lo, hi, p) => p.ys.filter((y) => inWin(lo, hi, y));

export function windowVec(lo, hi, p) {
  const m = p.ys.map((y) => inWin(lo, hi, y));
  const vals = {};
  WK_KEYS.forEach((k, i) => {
    vals[k] = p.rows.reduce((s, r, j) => s + (m[j] ? r[i] ?? 0 : 0), 0);
  });
  return { n: m.filter(Boolean).length, vals };
}

const shaped = (p) => p.ys.length === p.rows.length;

export function sameSteps(lo, hi, ps) {
  if (ps.length === 0) return false;
  const first = windowSteps(lo, hi, ps[0]);
  return ps.every((q) => {
    const s = windowSteps(lo, hi, q);
    return s.length === first.length && s.every((y, i) => y === first[i]);
  });
}

export const MIN_VMS = 3;

export const vmCount = (ps) => new Set(ps.map((p) => p.vm)).size;

const enoughVms = (ps) => vmCount(ps) >= MIN_VMS;

export const undecided = (base, flag) => !(enoughVms(base) && enoughVms(flag));

export function passUsable(lo, hi, base, flag) {
  const all = [...base, ...flag];
  return base.length >= MIN_RUNS && flag.length >= MIN_RUNS && all.every(shaped) && sameSteps(lo, hi, all) &&
    sameWindow(all.map((p) => windowVec(lo, hi, p)));
}

export const usable = (lo, hi, base, flag) => !undecided(base, flag) && passUsable(lo, hi, base, flag);

const spread = (xs) => [Math.min(...xs), Math.max(...xs)];

export function cmpKeys(lo, hi, base, flag) {
  const bv = base.map((p) => windowVec(lo, hi, p));
  const fv = flag.map((p) => windowVec(lo, hi, p));
  return Object.fromEntries(WK_KEYS.map((k) => [k, cmp(SLACK, spread(bv.map((v) => v.vals[k])), spread(fv.map((v) => v.vals[k])))]));
}

const judged = (lo, hi, base, flag) => judge(Object.values(cmpKeys(lo, hi, base, flag)));

export const passVerdict = (lo, hi, base, flag) => (passUsable(lo, hi, base, flag) ? judged(lo, hi, base, flag) : 'noData');

export const verdict = (lo, hi, base, flag) => (usable(lo, hi, base, flag) ? judged(lo, hi, base, flag) : 'noData');

export const zoneVerdicts = (base, flag) => ZONES.map((z) => [z.name, verdict(z.lo, z.hi, base, flag)]);

export const passOf = (pass, vm) => ({ vm, ys: pass.scroll.ys, rows: pass.scroll.reduced.perStep });
