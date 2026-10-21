// The continuity metrics and the cadence verdict are Lean's (lean/Fw/Gate/Smooth.lean). The TS twin in src/smooth/reduce.mjs is
// checked here against the Lean-generated golden vectors in packages/contracts/golden/gate/smooth.jsonl.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as S from '../src/smooth/reduce.mjs';
import { slowOf, summariseTrace } from '../src/smooth/trace.mjs';
import { cellOf, hitchesOf, summary } from '../src/smooth/cadence-table.mjs';
import { intervalsOf, orderFor } from '../src/smooth/cadence.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const golden = readFileSync(resolve(here, '../../contracts/golden/gate/smooth.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const ops = (op) => golden.filter((g) => g.op === op);
const arm = (a) => a.map(([frames, bad]) => ({ frames, bad }));

test('golden: the file holds every kind of case', () => {
  assert.equal(ops('constants').length, 1);
  assert.ok(ops('metrics').length >= 12);
  assert.ok(ops('lerp').length >= 10 && ops('verdict').length >= 8 && ops('quantile').length >= 6);
});

test('constants are the Lean ones', () => {
  const c = ops('constants')[0];
  assert.deepEqual([S.STALL_PM, S.STALL_DIV, S.JUMP_PM, S.REVERSE_PM, S.BAD_TENTHS, S.MIN_REPS],
    [c.stallPm, c.stallDiv, c.jumpPm, c.reversePm, c.badTenths, c.minReps]);
});

test('metrics, flat and flagged equal the golden for every case', () => {
  for (const g of ops('metrics')) {
    const m = S.metrics(g.frames);
    assert.deepEqual(m, g.out, g.case);
    assert.equal(S.flat(m), g.flat, g.case);
    assert.equal(S.flagged(m), g.flagged, g.case);
  }
});

test('lerp rounds down like Lean, including negative values and a descending driver', () => {
  for (const g of ops('lerp')) assert.equal(S.lerp(...g.args), g.out, JSON.stringify(g.args));
});

test('worst is the componentwise maximum, as in Lean', () => {
  const byCase = Object.fromEntries(ops('metrics').map((g) => [g.case, g.out]));
  for (const g of ops('worst')) assert.deepEqual(S.worst(byCase[g.a], byCase[g.b]), g.out, `${g.a}/${g.b}`);
});

test('quantile and median equal the golden, empty input gives null', () => {
  for (const g of ops('quantile')) assert.equal(S.quantile(g.xs, g.p), g.out, JSON.stringify(g));
  const all = ops('metrics');
  const med = ops('median').find((g) => g.cases.length > 0);
  assert.deepEqual(S.median(all.map((g) => g.out)), med.out);
  assert.equal(S.median([]), ops('median').find((g) => g.cases.length === 0).out);
});

test('repeats, rates and verdicts equal the golden', () => {
  for (const g of ops('rep')) assert.deepEqual(Object.values(S.repOf(g.ivs)), g.out, JSON.stringify(g.ivs));
  for (const g of ops('rate')) assert.equal(S.rate(g.frames, g.bad), g.out);
  for (const g of ops('verdict')) {
    const [a, b, aa1, aa2] = [g.a, g.b, g.aa1, g.aa2].map(arm);
    assert.equal(S.spread(aa1, aa2), g.spread);
    assert.equal(S.armRate(a), g.rateA);
    assert.equal(S.armRate(b), g.rateB);
    assert.equal(S.verdict(a, b, aa1, aa2), g.out);
  }
});

test('the verdict set covers first, second, same and insufficient', () => {
  assert.deepEqual([...new Set(ops('verdict').map((g) => g.out))].sort(), ['first', 'insufficient', 'same', 'second']);
});

test('trace: pipeline pairs are counted by state and begin/draw/drop events by name', () => {
  const b = (id, state, ts) => ({ name: 'PipelineReporter', ph: 'b', pid: 1, cat: 'cc', id2: { local: id }, ts, args: { frame_reporter: { state } } });
  const e = (id, ts) => ({ name: 'PipelineReporter', ph: 'e', pid: 1, cat: 'cc', id2: { local: id }, ts, args: {} });
  const t = summariseTrace([
    b('0x1', 'STATE_PRESENTED_ALL', 1000), e('0x1', 18000), b('0x2', 'STATE_DROPPED', 20000), e('0x2', 60000),
    { name: 'BeginFrame', ph: 'I', ts: 1 }, { name: 'DrawFrame', ph: 'I', ts: 2 }, { name: 'DroppedFrame', ph: 'I', ts: 3 }, { name: 'DroppedFrame', ph: 'I', ts: 4 },
  ]);
  assert.equal(t.presented, 1);
  assert.equal(t.dropped, 1);
  assert.equal(t.DroppedFrame, 2);
  assert.equal(t.pipelines, 2);
  assert.equal(t.presentedMax, 170);
});

test('trace: the slow list keeps events of 15 ms or more, longest name first', () => {
  const s = slowOf([
    { name: 'Layout', ph: 'X', dur: 40000 }, { name: 'Layout', ph: 'X', dur: 20000 }, { name: 'Paint', ph: 'X', dur: 14999 },
    { name: 'Decode', ph: 'X', dur: 60000 }, { name: 'Decode', ph: 'B', dur: 90000 },
  ]);
  assert.deepEqual(s, [{ name: 'Decode', n: 1, max: 600, sum: 600 }, { name: 'Layout', n: 2, max: 400, sum: 600 }]);
});

test('cadence table: hitches are the gaps of 60 ms or more with their scroll position', () => {
  const h = hitchesOf([{ arm: 'base', rep: 2, ivs: [167, 833, 599, 600], ys: [10, 20, 30, 40], loaf: [{ d: 76, block: 0, scripts: [] }] }]);
  assert.deepEqual(h.base.map((x) => [x.rep, x.i, x.ms, x.y]), [[2, 1, 83.3, 20], [2, 3, 60, 40]]);
  assert.deepEqual(h.orig, []);
});

test('cadence: intervals are tenths of ms between rAF times; the rep order rotates', () => {
  assert.deepEqual(intervalsOf([0, 16.7, 33.4, 100]), [167, 167, 666]);
  assert.deepEqual(orderFor(['a', 'b', 'c'], 0), ['a', 'b', 'c']);
  assert.deepEqual(orderFor(['a', 'b', 'c'], 1), ['b', 'c', 'a']);
  assert.deepEqual(orderFor(['a', 'b', 'c'], 3), ['a', 'b', 'c']);
});

test('cadence table: a cell takes its verdicts from the Lean-twin verdict over the base/aa pair', () => {
  const rep = (arm, rep, bad) => ({ width: 390, arm, window: 'end', rep, ivs: [...Array(100 - bad).fill(167), ...Array(bad).fill(500)] });
  const runs = [];
  for (let r = 0; r < 5; r++) {
    runs.push(rep('orig', r, 10), rep('base', r, 0), rep('aa', r, 0), rep('cand', r, 0));
  }
  const cell = cellOf('1', { runs, traces: [], search: '?x', hash: 'h', baseHash: 'b', version: 'v' }, 390, 'end');
  assert.equal(cell.spread, 0);
  assert.equal(cell.verdicts['orig|base'], 'second');
  assert.equal(cell.verdicts['base|cand'], 'same');
  assert.equal(cell.arms.orig.rate, 1000);
  const sum = summary([cell]);
  assert.equal(sum.find((e) => e.first === 'orig' && e.second === 'base').counts.second, 1);
  const few = cellOf('2', { runs: runs.filter((r) => r.rep < 3), traces: [] }, 390, 'end');
  assert.equal(few.verdicts['orig|base'], 'insufficient');
});
