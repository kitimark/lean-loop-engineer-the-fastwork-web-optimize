import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as A from '../src/device-flip-attr.mjs';
import { toHundredths } from '../src/profile/reduce.mjs';

const lines = readFileSync(new URL('../../contracts/golden/device/phone-arms.jsonl', import.meta.url), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);
const recs = (rows) => rows.map(([type, s, e]) => ({ type, s, e }));

test('the record type to work table follows the golden', () => {
  const [w] = of('flipwork');
  assert.deepEqual(w.types.map((t) => A.workOf(t)), w.works);
  assert.deepEqual(A.BUSY_WORKS, w.busyWorks);
  assert.equal(A.workOf('Composite'), A.WAIT);
  assert.ok(!A.BUSY_WORKS.includes(A.WAIT));
  assert.equal(w.idleNum / w.idleDen, 1 / 2);
});

test('times per work, busy time, the dominant work and the lead record follow the golden', () => {
  const cases = of('flipattr');
  assert.ok(cases.length >= 16);
  for (const c of cases) {
    const rs = recs(c.recs);
    assert.deepEqual(A.BUSY_WORKS.map((w) => A.workTime(c.a, c.b, rs, w)), c.times, c.name);
    assert.equal(A.workTime(c.a, c.b, rs, A.WAIT), c.wait, c.name);
    assert.equal(A.busy(c.a, c.b, rs), c.busy, c.name);
    assert.equal(A.dominant(c.a, c.b, rs), c.work, c.name);
    assert.equal(A.leadOf(c.a, c.b, rs), c.lead, c.name);
  }
});

test('the tail keeps the intervals at or over the limit', () => {
  for (const c of of('fliptail')) assert.deepEqual(A.tailOf(c.limit, c.ds), c.tail);
});

test('busy time never exceeds the interval (guard on a nested and an overlapping set)', () => {
  const rs = recs([['FunctionCall', 0, 9000], ['Layout', 500, 4000], ['Paint', 3500, 8000], ['Composite', 7000, 12000]]);
  assert.ok(A.busy(0, 10000, rs) <= 10000);
});

test('recsOf shifts the page clock and orders by start then longest first', () => {
  const sec = (hc) => hc / 100000;
  const tree = [{ type: 'Paint', startTime: sec(2000), endTime: sec(3000), children: [] },
    { type: 'FunctionCall', startTime: sec(1000), endTime: sec(9000), children: [{ type: 'Layout', startTime: sec(1000), endTime: sec(2000), children: [] }] }];
  const r = A.recsOf(tree, 100);
  assert.deepEqual(r.map((x) => [x.type, x.s, x.e]), [['FunctionCall', 900, 8900], ['Layout', 900, 1900], ['Paint', 1900, 2900]]);
  assert.equal(toHundredths(0.01 * 1000), 1000);
});
