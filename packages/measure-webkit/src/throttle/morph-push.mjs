import { stretches } from './morph-end.mjs';
import { excludeReason } from './finish-report.mjs';

// TS twin of the per-push window and the per-arm verdict in lean/Fw/Measure/PushCycle.lean (golden: pushConstants, pushInWin, pushWindows,
// pushVerdict, pushQuiet). Stand-ins with no Lean golden: the timeline-to-page-time conversion (pageMs), pushStarts, buildPush, the report glue.
export const PUSH_MS = 680;
export const LEAD_MS = 17;
export const TAIL_MS = 100;
export const SLOW_MS = 34;
export const MIN_WINS = 3;
export const MIN_VMS = 3;
export const KEYS = Object.freeze(['style', 'layout', 'paint', 'raf', 'slow']);
export const ROW_TYPES = Object.freeze({ RecalculateStyles: 'style', Layout: 'layout', Paint: 'paint' });

const sum = (l) => l.reduce((a, b) => a + b, 0);
const winStart = (t0) => Math.max(0, t0 - LEAD_MS);
const winEnd = (t0) => t0 + PUSH_MS + TAIL_MS;
export const inWin = (t0, t) => winStart(t0) <= t && t < winEnd(t0);
export const countIn = (t0, ts) => ts.filter((t) => inWin(t0, t)).length;
export const rowsIn = (t0, ty, rows) => countIn(t0, rows.filter((r) => r[0] === ty).map((r) => r[1]));
export function slowIn(t0, ft) {
  const ends = [];
  for (let i = 1; i < ft.length; i++) if (ft[i] - ft[i - 1] > SLOW_MS) ends.push(ft[i]);
  return countIn(t0, ends);
}
export const winOf = (r, t0) => [rowsIn(t0, 'RecalculateStyles', r.rows), rowsIn(t0, 'Layout', r.rows), rowsIn(t0, 'Paint', r.rows), countIn(t0, r.rafs), slowIn(t0, r.frames)];
export const complete = (r, t0) => winEnd(t0) <= r.endMs;
export const windows = (r, starts) => starts.filter((t0) => complete(r, t0)).map((t0) => winOf(r, t0));

export const usableVms = (vs) => vs.filter((v) => v.wins.length >= MIN_WINS);
export const vmCount = (vs) => new Set(usableVms(vs).map((v) => v.vm)).size;
export const rate = (xs) => (xs.length === 0 ? 0 : Math.floor((sum(xs) * 1000) / xs.length));
export const vmVec = (v) => KEYS.map((_, i) => rate(v.wins.map((w) => w[i])));
const spread = (xs) => (xs.length === 0 ? null : [Math.min(...xs), Math.max(...xs)]);
const cmp = (b, f) => (f[1] < b[0] ? 'less' : b[1] < f[0] ? 'more' : 'same');

export function armCmps(base, arm) {
  const bv = usableVms(base).map(vmVec), av = usableVms(arm).map(vmVec);
  return KEYS.flatMap((_, i) => {
    const b = spread(bv.map((x) => x[i])), f = spread(av.map((x) => x[i]));
    return b && f ? [cmp(b, f)] : [];
  });
}

export function armVerdict(base, arm) {
  if (vmCount(base) < MIN_VMS) return 'undecided:fewBase';
  if (vmCount(arm) < MIN_VMS) return 'undecided:fewArm';
  const cs = armCmps(base, arm);
  return cs.includes('more') ? 'noGain' : cs.includes('less') ? 'gain' : 'noGain';
}

export const quiet = (w) => w[0] === 0 && w[1] === 0 && w[2] === 0 && w[3] === 0;
export const rafFree = (w) => w[3] === 0;
export function quietVerdict(p, vs) {
  if (vmCount(vs) < MIN_VMS) return 'undecided';
  return usableVms(vs).every((v) => v.wins.every(p)) ? 'quiet' : 'stirred';
}

/** Timeline seconds to page ms through the sync mark: page time of the mark `p`, its timeline time `s`. */
export const pageMs = (t, sync) => Math.round(sync.p + (t - sync.s) * 1000);

/** The page ms of the first recorder frame of every open stretch: the push seen. */
export const pushStarts = (rec) => stretches(rec.o).map(([a]) => Math.round(rec.t[a]));

/**
 * What a pass keeps of its timeline: the style, layout and paint rows and the page rAF requests that fall inside some push window, in page ms,
 * the push starts and the end of the recording; `drift` is the sync mark's disagreement with a second one at the end (ms).
 */
export function buildPush({ rows, sync, sync2, rafs, rec, endP }) {
  const starts = pushStarts(rec);
  const near = (t) => starts.some((t0) => inWin(t0, t));
  const s = { p: sync.p, s: sync.s };
  const drift = sync2 ? Math.round(sync2.p - pageMs(sync2.s, s)) : null;
  return {
    starts, endMs: Math.round(endP), drift,
    rows: rows.filter((r) => r[0] in ROW_TYPES).map((r) => [r[0], pageMs(r[1], s)]).filter((r) => near(r[1])),
    rafs: rafs.map(Math.round).filter(near),
  };
}

/** The same for a pass of one timeline per cycle: `segs` are {rows, sync, sync2} (each timeline has its own clock and its own sync marks); `drift` is the largest disagreement of a segment's two marks. */
export function buildPushSegs({ segs, rafs, rec, endP }) {
  const starts = pushStarts(rec);
  const near = (t) => starts.some((t0) => inWin(t0, t));
  const drifts = segs.filter((g) => g.sync2).map((g) => Math.round(g.sync2.p - pageMs(g.sync2.s, { p: g.sync.p, s: g.sync.s })));
  return {
    starts, endMs: Math.round(endP), drift: drifts.reduce((m, d) => (Math.abs(d) > Math.abs(m) ? d : m), 0), segs: segs.length,
    rows: segs.flatMap((g) => g.rows.filter((r) => r[0] in ROW_TYPES).map((r) => [r[0], pageMs(r[1], { p: g.sync.p, s: g.sync.s })])).filter((r) => near(r[1])),
    rafs: rafs.map(Math.round).filter(near),
  };
}

export const syncOf = (rows, message, page) => {
  const r = rows.find((x) => x[0] === 'TimeStamp' && x[3] === message);
  return r ? { p: page, s: r[1] } : null;
};

export const passUsable = (p) => p.profile === 'push' && !!p.push && excludeReason(p) === null;
export const passRec = (p) => ({ rows: p.push.rows, rafs: p.push.rafs, frames: p.rec.t.map(Math.round), endMs: p.push.endMs });

/** One VM per job file of one run; `vmId` makes the id unique across runs. */
export function vmsOf(jobs, arm, vmId) {
  return jobs.map((j, i) => {
    const ps = (j.passes ?? []).filter((p) => p.arm === arm && passUsable(p));
    return { vm: vmId(j, i), passes: ps.length, wins: ps.flatMap((p) => windows(passRec(p), p.push.starts)), drift: ps.map((p) => p.push.drift) };
  });
}

const mean = (xs) => (xs.length ? Math.round((sum(xs) * 10) / xs.length) / 10 : null);

/** The table of one dispatch (one arm): per job the passes, windows and the mean counters per window. */
export function morphReportMd(jobs) {
  const arms = [...new Set(jobs.flatMap((j) => (j.passes ?? []).map((p) => p.arm)))];
  const out = ['# Per-push windows (push to morph end, Lean PushCycle)', ''];
  for (const arm of arms) {
    const vms = vmsOf(jobs, arm, (j, i) => i + 1);
    out.push(`## ${arm}`, '', '| job | passes | windows | style | layout | paint | rAF | slow | sync drift ms |', '| --- | --- | --- | --- | --- | --- | --- | --- | --- |');
    vms.forEach((v, i) => {
      const col = (k) => mean(v.wins.map((w) => w[k]));
      out.push(`| ${jobs[i].vm} | ${v.passes} | ${v.wins.length} | ${KEYS.map((_, k) => col(k)).join(' | ')} | ${v.drift.join(' ')} |`);
    });
    out.push('', `usable VMs ${vmCount(vms)}; quiet ${quietVerdict(quiet, vms)}; no page rAF ${quietVerdict(rafFree, vms)}`, '');
    const lost = jobs.flatMap((j) => j.failed ?? []);
    if (lost.length) out.push(`failed: ${lost.join('; ')}`, '');
  }
  return `${out.join('\n')}\n`;
}
