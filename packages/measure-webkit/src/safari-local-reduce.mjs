// Twin of lean/Fw/Sup/Measure.lean (TS stand-in until the reductions run as fwcore); test/safari-local-reduce.test.mjs replays every
// row of golden/sup/measure.jsonl. Intervals are tenths of ms, loads are hundredths, memory is MB. No glue lives here.
import { readFileSync } from 'node:fs';
import { hitchJudge } from '../../gate-breakpoints/src/smooth/reduce.mjs';

const readGolden = (rel) => readFileSync(new URL(`../../contracts/golden/sup/${rel}`, import.meta.url), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
/** The slot sampler's parameters (golden/sup/adapt.jsonl, Fw.Sup.Adapt.Params). */
export const ADAPT = readGolden('adapt.jsonl').find((r) => r.request.op === 'adapt.params').response;
/** The quiet rule's parameters (Lean `QParams`, `longTenths`). */
export const Q = readGolden('measure.jsonl').find((r) => r.request.op === 'measure.params').response;

export const availMB = (m) => m.freeMB + m.specMB + m.purgMB + Math.max(0, m.fileMB - m.fileMinMB);
export const swapActive = (m) => ADAPT.swapOutMBPerMinMax <= m.swapOutMBPerMin;
export const thrash = (m) => ADAPT.comprMBPerMinMax <= m.comprMBPerMin;
export const cmprsHigh = (r) => r.ramMB > 0 && ADAPT.cmprsPct * r.ramMB <= 100 * r.compressorMB;

/** Lean `ceilCenti`: the load ceiling (centi) of a machine whose idle floor is `fl`. */
export const ceilCenti = (fl) => fl + Q.loadMarginCenti;

/** Lean `whysRest`: every reason other than load that a reading (`{time, loadCenti, mem, ramMB, compressorMB, holders}`) is not quiet, in a fixed order. */
export function whysRest(r) {
  const out = [];
  if (availMB(r.mem) < ADAPT.floorMB) out.push('avail');
  if (r.mem.press !== 1) out.push('pressure');
  if (swapActive(r.mem)) out.push('swapOut');
  if (thrash(r.mem) || cmprsHigh(r)) out.push('compress');
  if (Q.holdersMax < r.holders) out.push('holders');
  return out;
}

/** Lean `whys`: every reason a reading is not quiet on a machine with idle floor `fl` (centi), in a fixed order. */
export const whys = (r, fl) => [...(ceilCenti(fl) < r.loadCenti ? ['load'] : []), ...whysRest(r)];

/** Lean `quiet`. */
export const quiet = (r, fl) => whys(r, fl).length === 0;

/** Lean `judge`: the decision on a pass from the readings before and after it. */
export function judge(b, a, fl) {
  if (!quiet(b, fl)) return { decision: 'refuse', phase: 'before', why: whys(b, fl) };
  if (!quiet(a, fl)) return { decision: 'refuse', phase: 'after', why: whys(a, fl) };
  if (a.time < b.time || b.time + Q.maxGapS < a.time) return { decision: 'stale' };
  return { decision: 'accept' };
}

/** Lean `baselineFloor`: the median load of a baseline window, or null (too few readings, a reading loud in any term but load, a wide spread, a median above the cap). */
export function baselineFloor(rs) {
  if (rs.length < Q.baseMinSamples) return null;
  if (rs.some((r) => whysRest(r).length > 0)) return null;
  const ls = rs.map((r) => r.loadCenti);
  if (Q.baseSpreadCenti < pct(100, ls) - pct(0, ls)) return null;
  if (Q.floorMaxCenti < pct(50, ls)) return null;
  return pct(50, ls);
}

/** Lean `settledAfter`: the readings taken at least `settleS` seconds after the device booted. */
export const settledAfter = (boot, rs) => rs.filter((r) => boot + Q.settleS <= r.time);

/** Lean `simFloor`: the idle floor with the Simulator booted; only readings after the settle period count. */
export const simFloor = (boot, rs) => baselineFloor(settledAfter(boot, rs));

const sortNat = (l) => [...l].sort((a, b) => a - b);

/** Lean `pct`: nearest-rank percentile (0 for none). */
export function pct(k, ivs) {
  const s = sortNat(ivs);
  return s[Math.max(1, Math.floor((k * ivs.length + 99) / 100)) - 1] ?? 0;
}

/** Lean `slotOf`: the refresh slot, 8.3 ms when the median interval is under 12.5 ms, else 16.7 ms. */
export const slotOf = (ivs) => (pct(50, ivs) < 125 ? 83 : 167);

/** Lean `skipped`: whole refresh slots missed. */
export const skipped = (slot, ivs) => ivs.reduce((s, i) => s + Math.max(0, Math.floor((2 * i + slot) / (2 * slot)) - 1), 0);

/** Lean `longCount`: intervals over 25 ms. */
export const longCount = (ivs) => ivs.filter((i) => Q.longTenths < i).length;

/** Lean `stat`. */
export const stat = (frames, ivs) => ({ frames, long: longCount(ivs), skipped: skipped(slotOf(ivs), ivs), p50: pct(50, ivs), p95: pct(95, ivs), mx: pct(100, ivs) });

/** Lean `outcome`: per-pass counts of a metric (lower is smoother) of an arm against the default's. */
export function outcome(arm, base) {
  if (arm.length < Q.minPasses || base.length < Q.minPasses) return 'insufficient';
  const j = hitchJudge(arm, base);
  return j === 'first' ? 'better' : j === 'second' ? 'worse' : 'same';
}

/** Lean `kept`: the values of the accepted passes. `xs` is `[[decision, value]]`. */
export const kept = (xs) => xs.filter(([d]) => d === 'accept').map(([, v]) => v);

/** Lean `hitchesRecorded`. */
export const hitchesRecorded = (finalized, rows) => finalized && rows > 0;

/** The recorder's bounds (Lean `ProbeLimits`). */
export const PROBE = readGolden('measure.jsonl').find((r) => r.request.op === 'measure.probeParams').response;

/** Lean `probeAct`: what to do at one look at a running recording (`wait`, `interrupt`, `kill`). */
export function probeAct({ elapsedS, limitS, traceMB, parentAlive }) {
  if (!parentAlive) return 'kill';
  if (PROBE.maxTraceMB < traceMB) return 'kill';
  if (limitS + PROBE.hardGraceS <= elapsedS) return 'kill';
  if (limitS + PROBE.graceS <= elapsedS) return 'interrupt';
  return 'wait';
}

/** Lean `mayRecord`: a recording starts only when the disk has room for it. */
export const mayRecord = (freeMB) => PROBE.minFreeMB <= freeMB;
