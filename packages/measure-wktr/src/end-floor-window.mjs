import { rpf100, overallNames } from './end-wktr.mjs';

export const PIN_N = 48;
export const PIN_REPS = 12;
export const MIN_REPS = 6;

export const PIN = { empty: 'empty', pinned: 'pinned', fewer: 'fewer reps', unpinned: 'unpinned' };

export function pinOf(wins) {
  if (wins.length === 0) return PIN.empty;
  if (!wins.every((w) => w === PIN_N)) return PIN.unpinned;
  return wins.length === PIN_REPS ? PIN.pinned : PIN.fewer;
}

export const RC = { empty: 'empty', steady: 'steady', accelerated: 'accelerated', transient: 'transient', elsewhere: 'elsewhere', resumes: 'resumes' };

export const tickOf = (t) => ({ r: t[0], m: t[1], q: t[2], d: t[3] });
export const clsOf = (t) => (t.m > 0 ? 'tick' : t.q > 0 ? 'quiet' : 'idle');

function settles(ts) {
  let s = false;
  for (const t of ts) {
    const c = clsOf(t);
    if (c === 'tick') { if (s) return false; } else if (c === 'quiet') s = true;
  }
  return true;
}

const has = (c, ts) => ts.some((t) => clsOf(t) === c);
const laterRecalc = (ts) => ts.some((t) => clsOf(t) !== 'tick' && t.r > 0);

export function repClass(ts) {
  const ht = has('tick', ts);
  const hq = has('quiet', ts);
  if (!(ht || hq)) return RC.empty;
  if (!settles(ts)) return RC.resumes;
  if (laterRecalc(ts)) return RC.elsewhere;
  if (!hq) return RC.steady;
  if (!ht) return RC.accelerated;
  return RC.transient;
}

export function startupLen(ts) {
  let n = 0;
  while (n < ts.length && clsOf(ts[n]) === 'tick') n += 1;
  return n;
}

export function armVerdict(reps) {
  if (reps.length < MIN_REPS) return 'unread';
  const cs = reps.map(repClass);
  return cs.every((c) => c === cs[0]) ? cs[0] : 'mixed';
}

export const classRate = (c, reps) => rpf100(reps.flat().filter((t) => clsOf(t) === c).map((t) => t.r));

export const overall = (vs) => overallNames(vs.filter((v) => v !== 'unread'));

export function repsOfRow(row) {
  const fs = row.rs?.frames ?? [];
  const wins = row.rs?.wins ?? [];
  if (fs.length === 0 || fs.some((f) => !Array.isArray(f.u))) return [];
  const out = [];
  let at = 0;
  for (const w of wins) {
    out.push(fs.slice(at, at + w).map((f) => tickOf([f.r, f.u[0], f.u[1], f.u[2]])));
    at += w;
  }
  return out;
}

const span = (xs) => (xs.length === 0 ? '-' : `${Math.min(...xs)} to ${Math.max(...xs)}`);

export function windowFacts(row) {
  const reps = repsOfRow(row);
  const fs = row.rs?.frames ?? [];
  const wins = row.rs?.wins ?? [];
  const firsts = [];
  const lasts = [];
  let at = 0;
  for (const w of wins) {
    if (w > 0 && fs[at] && fs[at + w - 1]) firsts.push(fs[at]);
    if (w > 0 && fs[at + w - 1]) lasts.push(fs[at + w - 1]);
    at += w;
  }
  const num = (xs) => xs.filter((x) => typeof x === 'number');
  return {
    pin: pinOf(wins),
    reps,
    verdict: armVerdict(reps),
    startup: reps.map(startupLen),
    classes: reps.map(repClass),
    tick: classRate('tick', reps),
    quiet: classRate('quiet', reps),
    idle: classRate('idle', reps),
    nTick: reps.flat().filter((t) => clsOf(t) === 'tick').length,
    nQuiet: reps.flat().filter((t) => clsOf(t) === 'quiet').length,
    nIdle: reps.flat().filter((t) => clsOf(t) === 'idle').length,
    phase0: num(firsts.map((f) => f.h)),
    ms: num(lasts.map((f) => f.t)),
    listed0: num(firsts.map((f) => (Array.isArray(f.u) ? f.u[3] : undefined))),
  };
}

export const factsText = (x) => [
  `pin ${x.pin} (${x.reps.length} reps),`,
  `class ${x.verdict},`,
  `rep classes ${x.classes.length === 0 ? '-' : [...new Set(x.classes)].sort().join(' ')},`,
  `start-up frames ${span(x.startup)},`,
  `frames ticking ${x.nTick} quiet ${x.nQuiet} idle ${x.nIdle},`,
  `recalcs per 100 frames ticking ${x.tick} quiet ${x.quiet} idle ${x.idle},`,
  `first-frame phase ${span(x.phase0)} per mille,`,
  `window ms ${span(x.ms)},`,
  `accelerated tracks at first frame ${span(x.listed0)}`,
].join(' ');
