import { refusal, repOrder } from './touchlock.mjs';
import { MIN_KEPT, REPS_WANT, MIN_SAMPLES, TARGET, JOBS_CAP, jobsFor } from './walk-budget.mjs';

export const CLASSES = Object.freeze([
  'ok', 'noOpen', 'tooShort', 'lockMoved', 'pageLost', 'beginLate', 'swipeLate', 'noMove', 'refusedPage',
  'driverNotReady', 'restartFailed', 'inspectorDead', 'evaluateTimeout', 'walkDeadline', 'jobCut', 'planShort', 'noArtifact', 'other',
]);

const SIMULATOR = ['pageLost', 'beginLate', 'swipeLate', 'noMove', 'driverNotReady', 'restartFailed', 'inspectorDead', 'evaluateTimeout'];

export const side = (c) => (c === 'ok' ? 'ok' : SIMULATOR.includes(c) ? 'simulator' : 'harness');

export const ARMS_N = 4;

export const PLANNED = REPS_WANT * ARMS_N;

export function rowClass(status, why) {
  if (status === 'ok') return why ?? 'ok';
  const s = String(status ?? '');
  for (const c of ['pageLost', 'beginLate', 'swipeLate', 'noMove']) if (s === c || s === `push:${c}`) return c;
  return s.startsWith('refused:') ? 'refusedPage' : 'other';
}

const has = (s, t) => s.includes(t);

export const reasonOf = (e) => e.logReason ?? e.incomplete;

export function endClass(e) {
  if (!e.present) return 'noArtifact';
  const s = reasonOf(e);
  if (s == null) return 'other';
  if (has(s, 'touch-driver-not-ready')) return 'driverNotReady';
  if (has(s, 'restart failed')) return 'restartFailed';
  if (has(s, 'the inspector is dead')) return 'inspectorDead';
  if (e.restartOpen) return 'restartFailed';
  if (has(s, 'walk deadline')) return e.attemptTimedOut ? 'evaluateTimeout' : 'walkDeadline';
  if (has(s, 'walk not finished')) return 'jobCut';
  return 'other';
}

export const slotArm = (i) => repOrder(Math.floor(i / ARMS_N))[i % ARMS_N] ?? 'orig';

export function windowClass(job, i) {
  if (!job.fin.present) return 'noArtifact';
  const r = job.rows[i];
  if (r) return rowClass(r[0], r[1]);
  return job.fin.reps !== 0 && job.fin.reps * ARMS_N <= i ? 'planShort' : endClass(job.fin);
}

export const jobWindows = (job) => Array.from({ length: PLANNED }, (_, i) => [slotArm(i), windowClass(job, i)]);

export const tally = (classes) => {
  const k = Object.fromEntries(CLASSES.map((c) => [c, 0]));
  for (const c of classes) k[c]++;
  return k;
};

export const jobCounts = (job) => tally(jobWindows(job).map((w) => w[1]));

export const armCounts = (job, arm) => tally(jobWindows(job).filter((w) => w[0] === arm).map((w) => w[1]));

export const runCounts = (jobs) => tally(jobs.flatMap((j) => jobWindows(j).map((w) => w[1])));

export const total = (k) => CLASSES.reduce((s, c) => s + k[c], 0);

export const sideTotal = (k, s) => CLASSES.filter((c) => side(c) === s).reduce((n, c) => n + k[c], 0);

export const rank = (k) => {
  const lost = CLASSES.filter((c) => c !== 'ok').map((c, i) => ({ c, n: k[c], i }));
  return lost.sort((a, b) => b.n - a.n || a.i - b.i).map((x) => [x.c, x.n]);
};

export const ARM_IDS = Object.freeze(['orig', 'base', 'lock', 'pin']);

export const sufficient = (job) => ARM_IDS.every((a) => MIN_KEPT <= armCounts(job, a).ok);

export const sufficientRate = (jobs) => [jobs.filter(sufficient).length, jobs.length];

export const jobsImplied = (a, b) => jobsFor(MIN_SAMPLES, a, b, TARGET.num, TARGET.den, JOBS_CAP);

// TS stand-in (not golden-checked): the sim.log facts and the artifact reading.
const WINDOW_LINE = /^touch-lock \S+ rep \d+ push \d+ \(/;
const READY_LINE = /^push server ready after/;
const RESTART_LINE = /restarting the push server/;
const TIMEOUT_LINE = /attempt \d+ failed \(.*timed out/;

export function logFacts(text) {
  const lines = text.split('\n');
  let logReason = null;
  let lastWindow = -1;
  let lastRestart = -1;
  let lastReady = -1;
  let lastTimeout = -1;
  let hardStop = false;
  lines.forEach((l, i) => {
    const m = l.match(/^touch-lock: INCOMPLETE after \d+ windows \((.*)$/);
    if (m) logReason = m[1].replace(/\)\s*$/, '');
    if (WINDOW_LINE.test(l)) lastWindow = i;
    if (RESTART_LINE.test(l)) lastRestart = i;
    if (READY_LINE.test(l)) lastReady = i;
    if (TIMEOUT_LINE.test(l)) lastTimeout = i;
    if (/walk hard stop/.test(l)) hardStop = true;
  });
  return { logReason, restartOpen: lastRestart > lastWindow && lastRestart > lastReady, attemptTimedOut: lastTimeout > lastWindow, hardStop };
}

export function restartTally(text) {
  const stalls = {};
  const readyS = [];
  let restarts = 0;
  let afterRestart = false;
  for (const l of text.split('\n')) {
    const m = l.match(/: stalled \((\w+)\); restarting the push server/);
    if (m) { stalls[m[1]] = (stalls[m[1]] ?? 0) + 1; restarts++; afterRestart = true; continue; }
    const r = l.match(/^push server ready after (\d+) s/);
    if (r && afterRestart) { readyS.push(Number(r[1])); afterRestart = false; }
  }
  return { stalls, restarts, readyS };
}

export function firstStall(text) {
  let done = 0;
  let ready = null;
  let first = null;
  for (const l of text.split('\n')) {
    if (WINDOW_LINE.test(l)) done++;
    const m = l.match(/: stalled \((\w+)\); restarting the push server/);
    if (m && !first) first = { kind: m[1], after: done };
    const r = l.match(/^push server ready after (\d+) s/);
    if (r && first && ready === null) ready = Number(r[1]);
  }
  return first && { ...first, readyS: ready };
}

export function jobOf(touchLock, simLog) {
  if (touchLock == null) return { fin: { present: false, reps: 0, incomplete: null, logReason: null, restartOpen: false, attemptTimedOut: false }, rows: [] };
  const f = logFacts(simLog ?? '');
  const rows = touchLock.rows.map((r) => {
    const run = { frames: (r.frames ?? []).map((x) => [x[0], x[1]]), events: (r.events ?? []).map((x) => [x[0], x[1]]), calls: (r.calls ?? []).map((x) => [x[0], x[1]]) };
    return [r.status, r.status === 'ok' ? refusal(run) : null];
  });
  const incomplete = touchLock.incomplete ?? (touchLock.fault ? `fault ${touchLock.fault}` : null);
  return { fin: { present: true, reps: touchLock.reps ?? 0, incomplete, logReason: f.logReason, restartOpen: f.restartOpen, attemptTimedOut: f.attemptTimedOut }, rows };
}
