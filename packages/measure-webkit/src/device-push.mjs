// Twin of the push-visit section of lean/Fw/Device/PhoneArms.lean (task phone-morph-push); test/device-push.test.mjs checks every
// function against the pushspan / pushpct / pushvisit / pushclock / pushlabel / pushplan lines of
// packages/contracts/golden/device/phone-arms.jsonl. Integer units: times in hundredths of a ms, positions in tenth px, morph per mille.
// TS stand-in until the reductions run as fwcore: nothing below decides anything the Lean section does not.
import { readFileSync } from 'node:fs';
import { armLabel } from './device-phone-arms.mjs';
import { driftOk, meanOffset, offsetOf } from './profile/reduce.mjs';

const GOLDEN = readFileSync(new URL('../../contracts/golden/device/phone-arms.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l));
export const PUSH = Object.freeze(GOLDEN.find((l) => l.kind === 'pushconsts'));
export const PUSH_ARMS = Object.freeze(PUSH.arms.map((a) => Object.freeze(a)));
export const PUSH_METRICS = PUSH.metrics;
export const COUNT_KINDS = Object.freeze(['RecalculateStyles', 'Layout', 'Paint', 'FireAnimationFrame']);

/** Times of the frames whose scroll position or morph amount differs from the frame before. A frame is [t, y, r]. */
export const changeTimes = (fs) => fs.slice(1).filter((f, i) => f[1] !== fs[i][1] || f[2] !== fs[i][2]).map((f) => f[0]);

/** The last time in [lo, hi) at which the page still changed, or lo. */
export const morphEnd = (lo, hi, fs) => changeTimes(fs).filter((t) => lo <= t && t < hi).reduce((m, t) => Math.max(m, t), lo);

/** [start, next start) for each touch start; the last window runs to hiEnd. */
export const windows = (hiEnd, ts) => ts.map((t, i) => [t, i + 1 < ts.length ? ts[i + 1] : hiEnd]);
export const spans = (fs, hiEnd, ts) => windows(hiEnd, ts).map((w) => [w[0], morphEnd(w[0], w[1], fs)]);

export const dts = (fs) => fs.slice(1).map((f, i) => f[0] - fs[i][0]);
export const framesIn = (s, fs) => fs.filter((f) => s[0] <= f[0] && f[0] <= s[1]);
export const spanDts = (sps, fs) => sps.flatMap((s) => dts(framesIn(s, fs)));

/** Nearest-rank percentile (p in 1..100); 0 for the empty list. */
export function pct(p, xs) {
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.floor((p * xs.length + 99) / 100) - 1] ?? 0;
}
export const over = (lim, xs) => xs.filter((x) => lim < x).length;

/** Records ([kind, t] on the Timeline clock) of `kind` inside a span after moving the clock by `off`. */
export const countIn = (kind, off, s, rs) => rs.filter((r) => r[0] === kind && s[0] <= r[1] - off && r[1] - off <= s[1]).length;
export const countsOf = (kind, off, sps, rs) => sps.reduce((n, s) => n + countIn(kind, off, s, rs), 0);

/** The counts lane's spans: its touch starts, each as long as the span of the same push in the frames lane. */
export const shifted = (ts, durs) => ts.slice(0, Math.min(ts.length, durs.length)).map((t, i) => [t, t + durs[i]]);
export const durations = (sps) => sps.map((s) => s[1] - s[0]);

/** The values of one visit, in the order of PUSH_METRICS: tail stats from the frames lane, counts from the counts lane. */
export function visitVals(fs, hiEnd, ts, tsC, off, rs) {
  const sps = spans(fs, hiEnd, ts);
  const d = spanDts(sps, fs);
  const spsC = shifted(tsC, durations(sps));
  return [pct(95, d), pct(99, d), pct(100, d), over(PUSH.overLimit, d), ...COUNT_KINDS.map((k) => countsOf(k, off, spsC, rs))];
}

/** The Timeline-to-page clock offset, or null when the two marks disagree. */
export const clockOff = (tlA, tlB, pgA, pgB) => {
  const a = offsetOf(tlA, pgA), b = offsetOf(tlB, pgB);
  return driftOk(a, b) ? meanOffset(a, b) : null;
};

export const columns = (k, vs) => Array.from({ length: k }, (_, i) => vs.map((v) => v[i] ?? 0));

/** The label of one arm (rows are per-visit value lists); unresolved unless base and arm both have PUSH.minVisits visits. */
export function pushLabel(base, arm) {
  if (base.length < PUSH.minVisits || arm.length < PUSH.minVisits) return 'unresolved';
  const k = PUSH_METRICS.length;
  return armLabel(columns(k, base), columns(k, arm));
}

export const pushRounds = (r) => Array.from({ length: r }, () => PUSH_ARMS).flat();
export const pushOk = (order) => PUSH_ARMS.every((a) => order.filter((x) => x.id === a.id).length >= PUSH.minVisits);
export const noRepeat = (order) => order.every((a, i) => i === 0 || a.id !== order[i - 1].id);
