import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { VERDICTS, OUTCOMES, eligible, redoFits, verdict, outcomeOf, finalClass, withRedo, redoTally } from '../src/window-retry.mjs';
import { blockMs, JOB } from '../src/walk-budget.mjs';
import { rowClass } from '../src/window-loss.mjs';

const golden = readFileSync(new URL('../../contracts/golden/measure/window-retry.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const ofOp = (op) => golden.filter((g) => g.op === op);

const askOf = (g) => ({ status: g.status, refusal: g.refusal, redone: g.redone, driverOn: g.driverOn, dl: g.dl, now: g.now, reserve: g.reserve, left: g.left });

test('constants equal the Lean golden', () => {
  const [g] = ofOp('constants');
  assert.deepEqual(VERDICTS, g.verdicts);
  assert.deepEqual(OUTCOMES, g.outcomes);
  assert.equal(blockMs(1), g.redoMs);
  assert.equal(JOB.timeoutMs - JOB.postMs - JOB.graceMs - JOB.slackMs, g.deadlineMs);
  assert.deepEqual(g.blockMs.map((_, n) => blockMs(n)), g.blockMs);
});

test('verdict replays the Lean golden, one case per branch', () => {
  const vs = ofOp('verdict');
  for (const g of vs) assert.equal(verdict(askOf(g)), g.verdict, g.case);
  assert.deepEqual([...new Set(vs.map((g) => g.verdict))].sort(), [...VERDICTS].sort());
});

test('the deadline edge: a redo fits to the millisecond', () => {
  const edge = ofOp('verdict').filter((g) => g.case === 'redoEdge' || g.case === 'noTimeEdge');
  assert.equal(edge.length, 2);
  assert.equal(edge[1].now, edge[0].now + 1);
  assert.equal(redoFits(edge[0].dl, edge[0].now, edge[0].reserve, edge[0].left), true);
  assert.equal(redoFits(edge[1].dl, edge[1].now, edge[1].reserve, edge[1].left), false);
});

test('outcome, eligibility and the final class replay the Lean golden; only a recovered redo passes', () => {
  for (const g of ofOp('outcome')) {
    assert.equal(outcomeOf(g.status, g.refusal), g.outcome, `${g.status}/${g.refusal}`);
    assert.equal(eligible(g.status, g.refusal), g.eligible, `${g.status}/${g.refusal}`);
    if (g.final !== null) assert.equal(finalClass(g.refusal, outcomeOf(g.status, g.refusal)), g.final);
    assert.equal(outcomeOf(g.status, g.refusal) === 'recovered', rowClass(g.status, g.refusal) === 'ok');
  }
  for (const first of ['noOpen', 'tooShort']) for (const o of OUTCOMES) assert.equal(finalClass(first, o) === 'ok', o === 'recovered');
});

test('price equals the Lean golden', () => {
  for (const g of ofOp('price')) {
    const slack = Math.max(0, g.dl - (g.now + g.reserve + blockMs(g.left)));
    assert.equal(slack, g.slack);
    assert.equal(Math.floor(slack / 38000), g.redos);
  }
});

const gap = (arm) => ({ arm, rep: 0, status: 'ok', calls: [], frames: [] });
const passing = () => ({ arm: 'base', rep: 0, status: 'ok', calls: [[7, 1, 0]], frames: Array.from({ length: 12 }, (_, i) => [i * 10, 1, i]) });
const short = () => ({ arm: 'base', rep: 0, status: 'ok', calls: [[7, 1, 0]], frames: Array.from({ length: 3 }, (_, i) => [i * 10, 1, i]) });
const room = () => ({ driverOn: true, dl: 2400000, now: 300000, reserve: 30000, left: 10 });

test('withRedo leaves a kept window and a stall alone and calls run for neither', async () => {
  let calls = 0;
  const run = async () => { calls++; return passing(); };
  const kept = passing();
  assert.equal(await withRedo(kept, { ask: room, run }), kept);
  const stall = { arm: 'base', rep: 0, status: 'push:pageLost' };
  assert.equal(await withRedo(stall, { ask: room, run }), stall);
  assert.equal(calls, 0);
});

test('withRedo reruns a noOpen once and takes the redo row when it passes', async () => {
  let calls = 0;
  const second = passing();
  const got = await withRedo(gap('base'), { ask: room, run: async () => { calls++; return second; } });
  assert.equal(calls, 1);
  assert.equal(got.redo.from, 'noOpen');
  assert.equal(got.redo.outcome, 'recovered');
  assert.equal(got.frames, second.frames);
});

test('withRedo keeps the first row and its refusal name when the redo also fails, never a pass', async () => {
  const first = short();
  for (const [second, outcome] of [[gap('base'), 'noOpen'], [short(), 'tooShort'], [{ status: 'push:swipeLate' }, 'failed'], [null, 'failed']]) {
    const got = await withRedo(first, { ask: room, run: async () => second });
    assert.equal(got.redo.from, 'tooShort');
    assert.equal(got.redo.outcome, outcome);
    assert.equal(got.frames, first.frames);
    assert.notEqual(got.redo.outcome, 'recovered');
  }
  const thrown = await withRedo(first, { ask: room, run: async () => { throw new Error('lost'); } });
  assert.equal(thrown.redo.outcome, 'failed');
  assert.equal(thrown.redo.status, 'error');
  assert.equal(thrown.frames, first.frames);
});

test('withRedo names a declined redo and does not run it', async () => {
  let calls = 0;
  const run = async () => { calls++; return passing(); };
  const late = await withRedo(gap('base'), { ask: () => ({ ...room(), now: 2100000, left: 4 }), run });
  assert.deepEqual(late.redo, { from: 'noOpen', outcome: 'noTime' });
  const down = await withRedo(gap('base'), { ask: () => ({ ...room(), driverOn: false }), run });
  assert.deepEqual(down.redo, { from: 'noOpen', outcome: 'noDriver' });
  assert.equal(calls, 0);
});

test('withRedo times the redo with the injected clock and tallies outcomes by name', async () => {
  const ticks = [10000, 52000];
  const now = () => ticks.shift();
  const got = await withRedo(gap('base'), { ask: room, run: async () => passing(), now });
  assert.equal(got.redo.ms, 42000);
  assert.deepEqual(redoTally([got, { redo: { outcome: 'noTime' } }, { redo: { outcome: 'noTime' } }, {}]), { recovered: 1, noTime: 2 });
});
