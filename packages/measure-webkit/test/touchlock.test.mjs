import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { cmp, look, reduce, refusal, tally, summarize, markdown, MIN_OPEN_FRAMES, openPhase, ARMS } from '../src/touchlock.mjs';
import { installJs, nearEndJs, windowJs } from '../src/touchlock-page.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const golden = readFileSync(join(HERE, '../../contracts/golden/measure/touch-lock.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const ops = (op) => golden.filter((g) => g.op === op);
const runOf = (g) => ({ frames: g.frames, events: g.events });

test('constants match the golden', () => {
  assert.equal(ops('constants')[0].minOpenFrames, MIN_OPEN_FRAMES);
});

test('run cases: refusal and reduction replay the golden', () => {
  assert.ok(ops('run').length >= 8);
  for (const g of ops('run')) {
    assert.equal(refusal(runOf(g)), g.refusal, g.case);
    assert.deepEqual(reduce(runOf(g)), g.result, g.case);
  }
});

test('cmp and look cases replay the golden', () => {
  for (const g of ops('cmp')) assert.equal(cmp(g.faith, g.cand), g.out, g.case);
  for (const g of ops('look')) assert.equal(look(g.faith, g.cand), g.out, g.case);
});

test('tally replays the golden', () => {
  for (const g of ops('tally')) assert.deepEqual(tally(g.runs), { accepted: g.accepted, jitter: g.jitter }, g.case);
});

test('open phase is the first open stretch only', () => {
  assert.deepEqual(openPhase([[1, 0], [2, 1], [3, 1], [4, 0], [5, 1]]), [[2, 1], [3, 1]]);
});

const fight = ops('run').find((g) => g.case === 'restore after a displaced frame');
const steady = ops('run').find((g) => g.case === 'steady open phase');
const rowOf = (arm, g) => ({ arm, frames: g.frames.map((f) => [...f, 0]), events: g.events.map((f) => [...f, 0]) });

test('summarize: a lock arm that never leaves the lock is lower; the look class is change while the base is displaced', () => {
  const rows = [rowOf('orig', fight), rowOf('base', fight), rowOf('base', fight), rowOf('lock', steady), rowOf('lock', steady), { arm: 'lock', status: 'push:beginLate' }];
  const s = summarize(rows);
  assert.equal(s.arms.base.jitterRuns, 2);
  assert.equal(s.arms.lock.jitterRuns, 0);
  assert.equal(s.arms.lock.windows, 3);
  assert.equal(s.arms.lock.failed, 1);
  assert.equal(s.verdicts.lockVsBase.fights, 'lower');
  assert.equal(s.verdicts.baseVsOrig.fights, 'overlap');
  assert.equal(s.verdicts.look, 'change');
  assert.match(markdown(s), /look change/);
});

test('summarize: no fights anywhere is overlap and the same look', () => {
  const s = summarize(ARMS.map((a) => rowOf(a, steady)));
  assert.equal(s.verdicts.lockVsBase.fights, 'overlap');
  assert.equal(s.verdicts.look, 'same');
});

test('page scripts parse', () => {
  for (const src of [installJs(false), installJs(true), nearEndJs(250), windowJs]) assert.doesNotThrow(() => new Function(`return ${src}`));
});
