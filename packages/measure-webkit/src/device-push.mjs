import { readFileSync } from 'node:fs';
import { armLabel, cells } from './device-phone-arms.mjs';
import { spread, verdict } from './device-session.mjs';
import { driftOk, meanOffset, offsetOf } from './profile/reduce.mjs';

const GOLDEN = readFileSync(new URL('../../contracts/golden/device/phone-arms.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l));
export const PUSH = Object.freeze(GOLDEN.find((l) => l.kind === 'pushconsts'));
export const PUSH_ARMS = Object.freeze(PUSH.arms.map((a) => Object.freeze(a)));
export const PUSH_METRICS = PUSH.metrics;
export const COUNT_KINDS = Object.freeze(['RecalculateStyles', 'Layout', 'Paint', 'FireAnimationFrame']);

export const changeTimes = (fs) => fs.slice(1).filter((f, i) => f[1] !== fs[i][1] || f[2] !== fs[i][2]).map((f) => f[0]);

export const morphEnd = (lo, hi, fs) => changeTimes(fs).filter((t) => lo <= t && t < hi).reduce((m, t) => Math.max(m, t), lo);

export const windows = (hiEnd, ts) => ts.map((t, i) => [t, i + 1 < ts.length ? ts[i + 1] : hiEnd]);
export const spans = (fs, hiEnd, ts) => windows(hiEnd, ts).map((w) => [w[0], morphEnd(w[0], w[1], fs)]);

export const dts = (fs) => fs.slice(1).map((f, i) => f[0] - fs[i][0]);
export const framesIn = (s, fs) => fs.filter((f) => s[0] <= f[0] && f[0] <= s[1]);
export const spanDts = (sps, fs) => sps.flatMap((s) => dts(framesIn(s, fs)));

export function pct(p, xs) {
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.floor((p * xs.length + 99) / 100) - 1] ?? 0;
}
export const over = (lim, xs) => xs.filter((x) => lim < x).length;

export const countIn = (kind, off, s, rs) => rs.filter((r) => r[0] === kind && s[0] <= r[1] - off && r[1] - off <= s[1]).length;
export const countsOf = (kind, off, sps, rs) => sps.reduce((n, s) => n + countIn(kind, off, s, rs), 0);

export const shifted = (ts, durs) => ts.slice(0, Math.min(ts.length, durs.length)).map((t, i) => [t, t + durs[i]]);
export const durations = (sps) => sps.map((s) => s[1] - s[0]);

export function visitVals(fs, hiEnd, ts, tsC, off, rs) {
  const sps = spans(fs, hiEnd, ts);
  const d = spanDts(sps, fs);
  const spsC = shifted(tsC, durations(sps));
  return [pct(95, d), pct(99, d), pct(100, d), over(PUSH.overLimit, d), ...COUNT_KINDS.map((k) => countsOf(k, off, spsC, rs))];
}

export const clockOff = (tlA, tlB, pgA, pgB) => {
  const a = offsetOf(tlA, pgA), b = offsetOf(tlB, pgB);
  return driftOk(a, b) ? meanOffset(a, b) : null;
};

export const columns = (k, vs) => Array.from({ length: k }, (_, i) => vs.map((v) => v[i] ?? 0));

export function pushLabel(base, arm) {
  if (base.length < PUSH.minVisits || arm.length < PUSH.minVisits) return 'unresolved';
  const k = PUSH_METRICS.length;
  return armLabel(columns(k, base), columns(k, arm));
}

export const pushRounds = (r) => Array.from({ length: r }, () => PUSH_ARMS).flat();
export const pushOk = (order) => PUSH_ARMS.every((a) => order.filter((x) => x.id === a.id).length >= PUSH.minVisits);
export const noRepeat = (order) => order.every((a, i) => i === 0 || a.id !== order[i - 1].id);

const armById = (id) => PUSH_ARMS.find((a) => a.id === id) ?? (() => { throw new Error(`unknown arm ${id}`); })();
export const LATIN_ROWS = Object.freeze(PUSH.latin.map((r) => Object.freeze(r.map(armById))));
export const latinOrder = () => PUSH.order.map(armById);
export const slotOf = (i) => (PUSH.slots[i] ? { round: PUSH.slots[i][0], position: PUSH.slots[i][1] } : null);

export const FLIP = Object.freeze(GOLDEN.find((l) => l.kind === 'flipcons'));
export const FLIP_ARMS = Object.freeze(FLIP.arms.map((a) => Object.freeze(a)));
const flipById = (id) => FLIP_ARMS.find((a) => a.id === id) ?? (() => { throw new Error(`unknown flip arm ${id}`); })();
export const FLIP_ROWS = Object.freeze(FLIP.latin.map((r) => Object.freeze(r.map(flipById))));
export const flipOrder = () => FLIP.order.map(flipById);
export const flipSlotOf = (i) => (FLIP.slots[i] ? { round: FLIP.slots[i][0], position: FLIP.slots[i][1] } : null);
export const flipOk = (order) => FLIP_ARMS.every((a) => order.filter((x) => x.id === a.id).length >= PUSH.minVisits);

export function pushCells(base, arm) {
  if (base.length < PUSH.minVisits || arm.length < PUSH.minVisits) return null;
  const k = PUSH_METRICS.length;
  return Object.fromEntries(cells(columns(k, base), columns(k, arm)).map((v, i) => [PUSH_METRICS[i], v]));
}

export const COLS = Object.freeze(GOLDEN.find((l) => l.kind === 'colscons'));
export const COLS_ARMS = Object.freeze(COLS.arms.map((a) => Object.freeze(a)));
const colsById = (id) => COLS_ARMS.find((a) => a.id === id) ?? (() => { throw new Error(`unknown cols arm ${id}`); })();
export const COLS_ROWS = Object.freeze(COLS.latin.map((r) => Object.freeze(r.map(colsById))));
export const colsOrder = () => COLS.order.map(colsById);
export const COLS_CONTRASTS = Object.freeze(COLS.contrasts.map((c) => Object.freeze({ ...c })));
export const colsOk = (order) => COLS_ARMS.every((a) => order.filter((x) => x.id === a.id).length >= PUSH.minVisits);

export function cause(ref, arm) {
  const v = verdict(ref, arm);
  if (v === 'beats' || v === 'worse') return 'decided';
  if (v === 'unresolved') return 'unresolved';
  const [rLo, rHi, aLo, aHi] = [Math.min(...ref), Math.max(...ref), Math.min(...arm), Math.max(...arm)];
  return aHi < rLo || rHi < aLo ? 'withinSpread' : 'overlap';
}

export function causes(ref, arm) {
  const k = PUSH_METRICS.length;
  if (ref.length < PUSH.minVisits || arm.length < PUSH.minVisits) return Array.from({ length: k }, () => 'unresolved');
  const [rc, ac] = [columns(k, ref), columns(k, arm)];
  return rc.map((c, i) => cause(c, ac[i]));
}

export const takenOf = (evs) => evs.reduce((n, e, i) => n + (e === 'take' && evs[i - 1] === 'push' ? 1 : 0), 0);
export const pushesOf = (evs) => evs.filter((e) => e === 'push').length;

export function contrastOf(ref, arm) {
  const k = PUSH_METRICS.length;
  const cs = causes(ref, arm);
  const cl = ref.length >= PUSH.minVisits && arm.length >= PUSH.minVisits ? columns(k, ref) : null;
  return {
    label: pushLabel(ref, arm), cells: pushCells(ref, arm), causes: Object.fromEntries(PUSH_METRICS.map((m, i) => [m, cs[i]])),
    refSpread: cl ? Object.fromEntries(PUSH_METRICS.map((m, i) => [m, spread(cl[i])])) : null,
  };
}
