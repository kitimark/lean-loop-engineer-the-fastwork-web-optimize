import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { CLASSES, PLANNED, rowClass, endClass, slotArm, jobWindows, jobCounts, armCounts, runCounts, total, sideTotal, side, rank, sufficient, sufficientRate, jobsImplied, logFacts, restartTally, firstStall, jobOf } from '../src/window-loss.mjs';
import { MIN_KEPT, REPS_WANT, MIN_SAMPLES, JOBS_CAP, JOBS_NEEDED } from '../src/walk-budget.mjs';

const golden = readFileSync(new URL('../../contracts/golden/measure/window-loss.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const ofOp = (op) => golden.filter((g) => g.op === op);
const jobIn = (g) => ({ fin: g.end, rows: g.rows });

test('constants, class names, sides and slot arms equal the Lean golden', () => {
  const [g] = ofOp('constants');
  assert.deepEqual(CLASSES, g.classes);
  assert.equal(PLANNED, g.planned);
  assert.equal(REPS_WANT, g.repsWant);
  assert.equal(MIN_KEPT, g.minKept);
  assert.equal(MIN_SAMPLES, g.minSamples);
  assert.equal(JOBS_CAP, g.jobsCap);
  assert.equal(JOBS_NEEDED, g.jobsNeeded);
  for (const c of CLASSES) assert.equal(side(c), g.sides[c], c);
  assert.deepEqual(Array.from({ length: PLANNED }, (_, i) => slotArm(i)), g.slotArms);
});

test('rowClass replays the Lean golden rows', () => {
  const rows = ofOp('row');
  for (const g of rows) assert.equal(rowClass(g.status, g.refusal), g.class, `${g.status}/${g.refusal}`);
  assert.ok(new Set(rows.map((g) => g.class)).size >= 9);
});

test('endClass replays the Lean golden job endings, one case per branch', () => {
  const ends = ofOp('end');
  for (const g of ends) assert.equal(endClass(g.end), g.class, g.case);
  assert.deepEqual([...new Set(ends.map((g) => g.class))].sort(), ['driverNotReady', 'evaluateTimeout', 'inspectorDead', 'jobCut', 'noArtifact', 'other', 'restartFailed', 'walkDeadline']);
});

test('jobs replay the Lean golden windows, counts, arm sufficiency, sides and ranking', () => {
  const jobs = ofOp('job');
  for (const g of jobs) {
    const j = jobIn(g);
    assert.deepEqual(jobWindows(j).map((w) => w[1]), g.windows, g.case);
    const k = jobCounts(j);
    assert.deepEqual(k, g.counts, g.case);
    assert.equal(total(k), PLANNED, g.case);
    assert.deepEqual(['orig', 'base', 'lock', 'pin'].map((a) => armCounts(j, a).ok), g.armOk, g.case);
    assert.equal(sufficient(j), g.sufficient, g.case);
    assert.deepEqual(['ok', 'harness', 'simulator'].map((s) => sideTotal(k, s)), g.sides, g.case);
    assert.deepEqual(rank(k).map(([c, n]) => `${c}:${n}`), g.rank, g.case);
    for (const a of ['orig', 'base', 'lock', 'pin']) assert.equal(total(armCounts(j, a)), REPS_WANT, `${g.case} ${a}`);
  }
  assert.ok(jobs.length >= 9);
});

test('run counts sum to planned windows and equal the Lean golden', () => {
  const [g] = ofOp('run');
  const jobs = ofOp('job').map(jobIn);
  const k = runCounts(jobs);
  assert.deepEqual(k, g.counts);
  assert.equal(total(k), g.total);
  assert.equal(total(k), jobs.length * PLANNED);
  assert.equal(sufficientRate(jobs)[0], g.sufficient);
  assert.deepEqual(rank(k).map(([c, n]) => `${c}:${n}`), g.rank);
});

test('jobsImplied equals the Lean golden', () => {
  const ns = ofOp('jobs');
  for (const g of ns) assert.equal(jobsImplied(g.a, g.b), g.needed, `${g.a}/${g.b}`);
  assert.ok(ns.some((g) => g.needed === null));
});

test('logFacts reads the INCOMPLETE reason, an open restart and a timed-out attempt', () => {
  const log = [
    'touch-lock base rep 0 push 0 (springboard): ok, begin 4895 ms',
    'touch-lock lock rep 2: stalled (ok); restarting the push server (1 of 2)',
    'push server ready after 434 s (launch 1, alive 400 s, ready 434 s)',
    'touch-lock pin rep 2 push 10 (springboard): ok, begin 8977 ms',
    'touch-lock pin rep 3: stalled (pageLost); restarting the push server (2 of 2)',
    'attempt 2 failed (Runtime.evaluate timed out after 120000 ms)',
    'touch-lock: INCOMPLETE after 11 windows (walk deadline: abandoned a window in flight after 11 windows)',
  ].join('\n');
  assert.deepEqual(logFacts(log), { logReason: 'walk deadline: abandoned a window in flight after 11 windows', restartOpen: true, attemptTimedOut: true, hardStop: false });
  assert.deepEqual(restartTally(log), { stalls: { ok: 1, pageLost: 1 }, restarts: 2, readyS: [434] });
  assert.deepEqual(logFacts('touch-lock base rep 0 push 0 (springboard): ok\nwalk hard stop: killing the process group').hardStop, true);
});

test('jobOf reads a missing artifact as noArtifact and a status ok row through the refusal', () => {
  const missing = jobOf(null, null);
  assert.equal(jobCounts(missing).noArtifact, PLANNED);
  const j = jobOf({ reps: 6, incomplete: null, rows: [{ status: 'ok', frames: [], events: [], calls: [] }, { status: 'push:pageLost' }] }, '');
  assert.deepEqual(j.rows, [['ok', 'noOpen'], ['push:pageLost', null]]);
  assert.deepEqual(jobWindows(j).slice(0, 2).map((w) => w[1]), ['noOpen', 'pageLost']);
});

test('firstStall returns the index of the stalled window, whose push line precedes its stalled line', () => {
  const log = [
    'touch-lock base rep 0 push 1 (x)',
    'touch-lock lock rep 0 push 2 (x)',
    'touch-lock pin rep 0 push 3 (x)',
    'touch-lock pin rep 0: stalled (pageLost); restarting the push server',
    'push server ready after 118 s',
    'touch-lock orig rep 0 push 4 (x)',
  ].join('\n');
  assert.deepEqual(firstStall(log), { kind: 'pageLost', after: 2, readyS: 118 });
  assert.equal(firstStall('touch-lock base rep 0 push 1 (x)\ntouch-lock base rep 0: stalled (ok); restarting the push server').after, 0);
  assert.equal(firstStall('touch-lock base rep 0 push 1 (x)'), null);
});
