// Push windows of one Chromium touch-swipe run: counter sums over windows cut at the end frame, and the verdict of a flag arm per window.
// The rules (end frame, window bounds, window owner, window sums, per-window verdict) are specified and proved in Lean
// (lean/Fw/Measure/OffscreenWindows.lean); the functions up to `armVerdicts` are a copy of them, checked against the golden vectors
// packages/contracts/golden/measure/offscreen-windows.jsonl by test/offscreen-windows.test.mjs. The comparison and the judge are
// the ones of offscreen.mjs (Fw.Measure.Offscreen). Everything after them is glue: reading counts.json and the profile, the table.
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { MIN_RUNS, SLACK, cmp, judge, sameWindow, reduction } from './offscreen.mjs';

export const WKEYS = [
  'metric.RecalcStyleCount', 'metric.LayoutCount', 'trace.Paint', 'trace.RasterTask', 'trace.PaintImage', 'trace.FireAnimationFrame',
];
export const APPROACH = 34;
export const TOUCH_TAIL = 30;
export const WINDOW_NAMES = ['approach', 'end 0-19', 'end 20-59', 'end 60-119', 'end 120+', 'finish'];

// ---- copy of Fw.Measure.OffscreenWindows
// First frame at the largest value; null for no frame.
export function endFrame(ys) {
  if (ys.length === 0) return null;
  let best = 0;
  for (let i = 1; i < ys.length; i++) if (ys[i] > ys[best]) best = i;
  return best;
}

export const lastFrame = (total, tail) => Math.max(0, total - tail);
const clip = (last, x) => Math.min(x, last);
const sub = (a, b) => Math.max(0, a - b);

export function pushWindows(e, last) {
  const c = (x) => clip(last, x);
  return [
    { name: 'approach', lo: c(sub(e, APPROACH)), hi: c(e) },
    { name: 'end 0-19', lo: c(e), hi: c(e + 20) },
    { name: 'end 20-59', lo: c(e + 20), hi: c(e + 60) },
    { name: 'end 60-119', lo: c(e + 60), hi: c(e + 120) },
    { name: 'end 120+', lo: c(e + 120), hi: last },
  ];
}
export const finishWin = (e, last) => ({ name: 'finish', lo: clip(last, sub(e, APPROACH)), hi: last });
export const allWindows = (e, last) => [...pushWindows(e, last), finishWin(e, last)];

export function owner(e, last, f) {
  const w = pushWindows(e, last).find((x) => x.lo <= f && f < x.hi);
  return w ? w.name : null;
}

export const sumRange = (xs, lo, hi) => xs.slice(lo, Math.max(lo, hi)).reduce((s, x) => s + x, 0);

// run: { ys, cols: {key: [per-frame counts]}, tail }. Null when there is no frame or a column is not as long as ys.
export function runWindows(run) {
  const e = endFrame(run.ys);
  if (e === null) return null;
  if (!Object.values(run.cols).every((xs) => xs.length === run.ys.length)) return null;
  const last = lastFrame(run.ys.length, run.tail);
  const windows = allWindows(e, last).map((w) => {
    const vals = {};
    for (const [k, xs] of Object.entries(run.cols)) vals[k] = sumRange(xs, w.lo, w.hi);
    return { name: w.name, vec: { n: w.hi - w.lo, vals } };
  });
  return { end: e, windows };
}

const vecsOf = (runs, name) => runs.flatMap((r) => { const w = r.windows.find((x) => x.name === name); return w ? [w.vec] : []; });
const hasKeysOn = (ks, rs) => ks.every((k) => rs.every((v) => Number.isInteger(v.vals[k])));

export function usableOn(ks, base, flag) {
  return MIN_RUNS <= base.length && MIN_RUNS <= flag.length && sameWindow([...base, ...flag]) && hasKeysOn(ks, [...base, ...flag]);
}

const spread = (xs) => [Math.min(...xs), Math.max(...xs)];

// [cmp, base spread, flag spread] of counter k, null if a run lacks it.
export function cell(base, flag, k) {
  const bs = base.map((v) => v.vals[k]);
  const fs = flag.map((v) => v.vals[k]);
  if ([...bs, ...fs].some((x) => !Number.isInteger(x)) || bs.length === 0 || fs.length === 0) return null;
  const b = spread(bs), f = spread(fs);
  return { key: k, cmp: cmp(SLACK, b, f), base: b, flag: f, reduction: reduction(b[0], f[1]) };
}

export function verdictOn(ks, base, flag) {
  if (!usableOn(ks, base, flag)) return 'noData';
  return judge(ks.map((k) => cell(base, flag, k)).filter((c) => c).map((c) => c.cmp));
}

// base, flag: arrays of runWindows results.
export function armVerdicts(base, flag) {
  return WINDOW_NAMES.map((n) => {
    const b = vecsOf(base, n), f = vecsOf(flag, n);
    return { window: n, verdict: verdictOn(WKEYS, b, f), usable: usableOn(WKEYS, b, f), cells: WKEYS.map((k) => cell(b, f, k)) };
  });
}

// ---- glue: counts.json and the profile -> a run, directories of runs -> arms, the table
export const PROFILE_ID = 'swipe-touch-v1';

// Frames of the `tail` segment of a profile JSON.
export function profileTail(profile) {
  const seg = (profile.segments ?? []).find((s) => s.name === 'tail');
  if (!seg || !Number.isInteger(seg.frames)) throw new Error(`profile ${profile.id}: no tail segment with a frame count`);
  return seg.frames;
}

// counts.json (profile swipe-touch-v1) -> run. A frame without a counter has none of it; a counter no frame has is an error.
export function runFromCounts(counts, tail) {
  if (counts.profile?.id !== PROFILE_ID) throw new Error(`counts.json profile is ${counts.profile?.id}, only ${PROFILE_ID} windows are defined`);
  const frames = counts.frames;
  const tailFrames = frames.filter((f) => f.phase === 'tail').length;
  if (tailFrames !== tail) throw new Error(`profile tail is ${tail} frames, counts.json has ${tailFrames} tail frames`);
  const cols = {};
  for (const k of WKEYS) {
    if (!frames.some((f) => f.counts[k] !== undefined)) throw new Error(`counter ${k} is in no frame`);
    cols[k] = frames.map((f) => f.counts[k] ?? 0);
  }
  return { ys: frames.map((f) => Math.round(f.scrollY * 1000)), cols, tail };
}

export function findCounts(dir) {
  const out = [];
  const walk = (d) => {
    for (const e of readdirSync(d, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
      if (e.isDirectory()) walk(join(d, e.name));
      else if (e.name === 'counts.json') out.push(join(d, e.name));
    }
  };
  walk(dir);
  return out;
}

export function readArm(dir, tail) {
  return findCounts(dir).map((path) => {
    const counts = JSON.parse(readFileSync(path, 'utf8'));
    const w = runWindows(runFromCounts(counts, tail));
    if (!w) throw new Error(`${path}: no windows`);
    return { path, search: counts.meta?.search ?? null, ...w };
  });
}

const fmt = (b) => (b[0] === b[1] ? `${b[0]}` : `${b[0]}..${b[1]}`);
const shortKey = (k) => k.replace(/^(metric|trace)\./, '');

// "RasterTask 236 to 61": the base end of the spread nearest the flag and the flag end nearest the base.
export function cellText(c) {
  if (c.cmp === 'less') return `${shortKey(c.key)} ${c.base[0]} to ${c.flag[1]}`;
  return `${shortKey(c.key)} ${c.base[1]} to ${c.flag[0]}`;
}

// One flag arm: per window the verdict and the counters that are not the same.
export function summarizeArm(baseRuns, flagRuns) {
  return armVerdicts(baseRuns, flagRuns).map((v) => ({
    window: v.window, verdict: v.verdict, usable: v.usable,
    less: v.cells.filter((c) => c && c.cmp === 'less').map(cellText),
    more: v.cells.filter((c) => c && c.cmp === 'more').map(cellText),
  }));
}

export function markdown(arms, baseRuns) {
  const L = [];
  L.push(`End frame per run: ${[...new Set(baseRuns.map((r) => r.end))].join(', ')} (base), windows from the end frame, slack ${SLACK}, ${MIN_RUNS} runs per arm.`);
  L.push('', `| window | ${Object.keys(arms).join(' | ')} |`, `|---${'|---'.repeat(Object.keys(arms).length)}|`);
  for (const n of WINDOW_NAMES) {
    const cellsOf = Object.values(arms).map((s) => {
      const w = s.find((x) => x.window === n);
      const parts = [];
      if (w.less.length) parts.push(`less: ${w.less.join(', ')}`);
      if (w.more.length) parts.push(`more: ${w.more.join(', ')}`);
      return `${w.verdict}${w.usable ? '' : ' (not usable)'}${parts.length ? `; ${parts.join('; ')}` : ''}`;
    });
    L.push(`| ${n} | ${cellsOf.join(' | ')} |`);
  }
  return L.join('\n') + '\n';
}
