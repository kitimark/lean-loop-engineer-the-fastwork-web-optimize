import { readFileSync } from 'node:fs';
import { hitchJudge } from '../../gate-breakpoints/src/smooth/reduce.mjs';

const readGolden = (rel) => readFileSync(new URL(`../../contracts/golden/sup/${rel}`, import.meta.url), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
export const ADAPT = readGolden('adapt.jsonl').find((r) => r.request.op === 'adapt.params').response;
export const Q = readGolden('measure.jsonl').find((r) => r.request.op === 'measure.params').response;

export const availMB = (m) => m.freeMB + m.specMB + m.purgMB + Math.max(0, m.fileMB - m.fileMinMB);
export const swapActive = (m) => ADAPT.swapOutMBPerMinMax <= m.swapOutMBPerMin;
export const thrash = (m) => ADAPT.comprMBPerMinMax <= m.comprMBPerMin;
export const cmprsHigh = (r) => r.ramMB > 0 && ADAPT.cmprsPct * r.ramMB <= 100 * r.compressorMB;

export const ceilCenti = (fl) => fl + Q.loadMarginCenti;

export function whysRest(r) {
  const out = [];
  if (availMB(r.mem) < ADAPT.floorMB) out.push('avail');
  if (r.mem.press !== 1) out.push('pressure');
  if (swapActive(r.mem)) out.push('swapOut');
  if (thrash(r.mem) || cmprsHigh(r)) out.push('compress');
  if (Q.holdersMax < r.holders) out.push('holders');
  return out;
}

export const whys = (r, fl) => [...(ceilCenti(fl) < r.loadCenti ? ['load'] : []), ...whysRest(r)];

export const quiet = (r, fl) => whys(r, fl).length === 0;

export function judge(b, a, fl) {
  if (!quiet(b, fl)) return { decision: 'refuse', phase: 'before', why: whys(b, fl) };
  if (!quiet(a, fl)) return { decision: 'refuse', phase: 'after', why: whys(a, fl) };
  if (a.time < b.time || b.time + Q.maxGapS < a.time) return { decision: 'stale' };
  return { decision: 'accept' };
}

export function baselineFloor(rs) {
  if (rs.length < Q.baseMinSamples) return null;
  if (rs.some((r) => whysRest(r).length > 0)) return null;
  const ls = rs.map((r) => r.loadCenti);
  if (Q.baseSpreadCenti < pct(100, ls) - pct(0, ls)) return null;
  if (Q.floorMaxCenti < pct(50, ls)) return null;
  return pct(50, ls);
}

export const settledAfter = (boot, rs) => rs.filter((r) => boot + Q.settleS <= r.time);

export const simFloor = (boot, rs) => baselineFloor(settledAfter(boot, rs));

const sortNat = (l) => [...l].sort((a, b) => a - b);

export function pct(k, ivs) {
  const s = sortNat(ivs);
  return s[Math.max(1, Math.floor((k * ivs.length + 99) / 100)) - 1] ?? 0;
}

export const slotOf = (ivs) => (pct(50, ivs) < 125 ? 83 : 167);

export const skipped = (slot, ivs) => ivs.reduce((s, i) => s + Math.max(0, Math.floor((2 * i + slot) / (2 * slot)) - 1), 0);

export const longCount = (ivs) => ivs.filter((i) => Q.longTenths < i).length;

export const stat = (frames, ivs) => ({ frames, long: longCount(ivs), skipped: skipped(slotOf(ivs), ivs), p50: pct(50, ivs), p95: pct(95, ivs), mx: pct(100, ivs) });

export function outcome(arm, base) {
  if (arm.length < Q.minPasses || base.length < Q.minPasses) return 'insufficient';
  const j = hitchJudge(arm, base);
  return j === 'first' ? 'better' : j === 'second' ? 'worse' : 'same';
}

export const kept = (xs) => xs.filter(([d]) => d === 'accept').map(([, v]) => v);

export const hitchesRecorded = (finalized, rows) => finalized && rows > 0;

export const PROBE = readGolden('measure.jsonl').find((r) => r.request.op === 'measure.probeParams').response;

export function probeAct({ elapsedS, limitS, traceMB, parentAlive }) {
  if (!parentAlive) return 'kill';
  if (PROBE.maxTraceMB < traceMB) return 'kill';
  if (limitS + PROBE.hardGraceS <= elapsedS) return 'kill';
  if (limitS + PROBE.graceS <= elapsedS) return 'interrupt';
  return 'wait';
}

export const mayRecord = (freeMB) => PROBE.minFreeMB <= freeMB;
