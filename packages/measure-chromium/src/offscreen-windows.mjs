import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { MIN_RUNS, SLACK, cmp, judge, sameWindow, reduction } from './offscreen.mjs';

export const WKEYS = [
  'metric.RecalcStyleCount', 'metric.LayoutCount', 'trace.Paint', 'trace.RasterTask', 'trace.PaintImage', 'trace.FireAnimationFrame',
];
export const APPROACH = 34;
export const TOUCH_TAIL = 30;
export const WINDOW_NAMES = ['approach', 'end 0-19', 'end 20-59', 'end 60-119', 'end 120+', 'finish'];

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

export function runPlan(run) {
  const e = endFrame(run.ys);
  if (e === null) return null;
  if (!Object.values(run.cols).every((xs) => xs.length === run.ys.length)) return null;
  return { end: e, wins: allWindows(e, lastFrame(run.ys.length, run.tail)) };
}

const sumVec = (cols, w) => {
  const vals = {};
  for (const [k, xs] of Object.entries(cols)) vals[k] = sumRange(xs, w.lo, w.hi);
  return { n: w.hi - w.lo, vals };
};

export function runWindows(run) {
  const p = runPlan(run);
  if (p === null) return null;
  return { end: p.end, windows: p.wins.map((w) => ({ name: w.name, vec: sumVec(run.cols, w) })) };
}

export const capWin = (m, w) => ({ ...w, hi: Math.min(w.hi, w.lo + m) });
const lenOf = (wins, n) => { const w = wins.find((x) => x.name === n); return w ? w.hi - w.lo : null; };
export function commonLen(plans, n) {
  const ls = plans.map((p) => lenOf(p.wins, n)).filter((x) => x !== null);
  return ls.length === 0 ? 0 : Math.min(...ls);
}
export function cappedRun(run, cap) {
  const p = runPlan(run);
  if (p === null) return null;
  return { end: p.end, windows: p.wins.map((w) => ({ name: w.name, vec: sumVec(run.cols, capWin(cap(w.name), w)) })) };
}

const vecsOf = (runs, name) => runs.flatMap((r) => { const w = r.windows.find((x) => x.name === name); return w ? [w.vec] : []; });
const hasKeysOn = (ks, rs) => ks.every((k) => rs.every((v) => Number.isInteger(v.vals[k])));

export function usableOn(ks, base, flag) {
  return MIN_RUNS <= base.length && MIN_RUNS <= flag.length && sameWindow([...base, ...flag]) && hasKeysOn(ks, [...base, ...flag]);
}

const spread = (xs) => [Math.min(...xs), Math.max(...xs)];

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

export function armVerdicts(base, flag) {
  return WINDOW_NAMES.map((n) => {
    const b = vecsOf(base, n), f = vecsOf(flag, n);
    return { window: n, verdict: verdictOn(WKEYS, b, f), usable: usableOn(WKEYS, b, f), cells: WKEYS.map((k) => cell(b, f, k)) };
  });
}

export function ownVerdicts(baseRuns, flagRuns) {
  const plans = [...baseRuns, ...flagRuns].map(runPlan).filter((p) => p !== null);
  const frames = (n) => commonLen(plans, n);
  const capped = (rs) => rs.map((r) => cappedRun(r, frames)).filter((r) => r !== null);
  return armVerdicts(capped(baseRuns), capped(flagRuns)).map((v) => ({ ...v, frames: frames(v.window) }));
}

export const MIN_END_120 = 20;
export const MIN_FRAMES = Object.fromEntries(allWindows(APPROACH, APPROACH + 120 + MIN_END_120).map((w) => [w.name, w.hi - w.lo]));

export function minVerdicts(baseRuns, flagRuns) {
  return ownVerdicts(baseRuns, flagRuns).map((v) => {
    const enough = MIN_FRAMES[v.window] <= v.frames;
    return { ...v, minFrames: MIN_FRAMES[v.window], enough, own: v.verdict, verdict: enough ? v.verdict : 'noData' };
  });
}

export const PROFILE_ID = 'swipe-touch-v1';

export function profileTail(profile) {
  const seg = (profile.segments ?? []).find((s) => s.name === 'tail');
  if (!seg || !Number.isInteger(seg.frames)) throw new Error(`profile ${profile.id}: no tail segment with a frame count`);
  return seg.frames;
}

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
    const run = runFromCounts(counts, tail);
    const w = runWindows(run);
    if (!w) throw new Error(`${path}: no windows`);
    return { path, search: counts.meta?.search ?? null, run, ...w };
  });
}

const fmt = (b) => (b[0] === b[1] ? `${b[0]}` : `${b[0]}..${b[1]}`);
const shortKey = (k) => k.replace(/^(metric|trace)\./, '');

export function cellText(c) {
  if (c.cmp === 'less') return `${shortKey(c.key)} ${c.base[0]} to ${c.flag[1]}`;
  return `${shortKey(c.key)} ${c.base[1]} to ${c.flag[0]}`;
}

export function summarizeArm(baseRuns, flagRuns) {
  return minVerdicts(baseRuns.map((r) => r.run), flagRuns.map((r) => r.run)).map((v) => ({
    window: v.window, frames: v.frames, minFrames: v.minFrames, verdict: v.verdict, own: v.own, usable: v.usable, enough: v.enough,
    less: v.cells.filter((c) => c && c.cmp === 'less').map(cellText),
    more: v.cells.filter((c) => c && c.cmp === 'more').map(cellText),
  }));
}

const endsOf = (runs) => [...new Set(runs.map((r) => r.end))].join(', ');

export function markdown(arms, baseRuns, flagRuns = {}) {
  const L = [];
  const ends = [`${endsOf(baseRuns)} (base)`, ...Object.entries(flagRuns).map(([n, rs]) => `${endsOf(rs)} (${n})`)];
  L.push(`End frame per run: ${ends.join(', ')}; each window starts at the run's own end frame and is cut to the frames every run has, slack ${SLACK}, ${MIN_RUNS} runs per arm; a window with fewer frames than its minimum in any run is noData.`);
  L.push('', `| window | ${Object.keys(arms).join(' | ')} |`, `|---${'|---'.repeat(Object.keys(arms).length)}|`);
  for (const n of WINDOW_NAMES) {
    const cellsOf = Object.values(arms).map((s) => {
      const w = s.find((x) => x.window === n);
      const parts = [];
      if (w.less.length) parts.push(`less: ${w.less.join(', ')}`);
      if (w.more.length) parts.push(`more: ${w.more.join(', ')}`);
      const short = !w.enough ? ` (below ${w.minFrames} frames, own-end rule: ${w.own})` : w.usable ? '' : ' (not usable)';
      return `${w.verdict}${short}${parts.length ? `; ${parts.join('; ')}` : ''} [${w.frames} frames, min ${w.minFrames}]`;
    });
    L.push(`| ${n} | ${cellsOf.join(' | ')} |`);
  }
  return L.join('\n') + '\n';
}
