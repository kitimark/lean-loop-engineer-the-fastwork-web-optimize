// The continuity metrics and the cadence verdict are Lean's (lean/Fw/Gate/Smooth.lean). The TS twin in src/smooth/reduce.mjs is
// checked here against the Lean-generated golden vectors in packages/contracts/golden/gate/smooth.jsonl.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as S from '../src/smooth/reduce.mjs';

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
