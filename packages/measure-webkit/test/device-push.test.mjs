// The push-visit twin against the Lean golden (Fw.Device.PhoneArms, packages/contracts/golden/device/phone-arms.jsonl).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as D from '../src/device-push.mjs';

const lines = readFileSync(new URL('../../contracts/golden/device/phone-arms.jsonl', import.meta.url), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('every push golden kind has lines', () => {
  for (const k of ['pushconsts', 'pushspan', 'pushpct', 'pushvisit', 'pushclock', 'pushlabel', 'pushplan']) assert.ok(of(k).length > 0, k);
});

test('constants: three visits, 5 requests of 4 steps, ten pushes, four arms', () => {
  const [c] = of('pushconsts');
  assert.equal(c.minVisits, 3);
  assert.equal(c.patternAsks + c.burstAsks, 5);
  assert.equal(c.steps.length, 20);
  assert.equal(c.pushes, 10);
  assert.equal(c.steps.filter((s) => s !== 'hold').length, c.pushes);
  assert.deepEqual(c.pattern, c.steps.slice(0, c.pattern.length));
  assert.deepEqual(c.arms.map((a) => a.id), ['base', 'morph.geom:on', 'morph.tween:geom-timed', 'morph.stage:on']);
  assert.deepEqual(D.pushRounds(3).map((a) => a.id), c.rounds);
});

test('windows, spans, change times and the intervals inside the spans', () => {
  for (const g of of('pushspan')) {
    assert.deepEqual(D.changeTimes(g.frames), g.changes, g.name);
    assert.deepEqual(D.windows(g.hiEnd, g.starts), g.windows, g.name);
    assert.deepEqual(D.spans(g.frames, g.hiEnd, g.starts), g.spans, g.name);
    assert.deepEqual(D.spanDts(D.spans(g.frames, g.hiEnd, g.starts), g.frames), g.dts, g.name);
  }
});

test('percentile and the over-limit count', () => {
  for (const g of of('pushpct')) {
    assert.equal(D.pct(g.p, g.values), g.pct, JSON.stringify(g));
    assert.equal(D.over(D.PUSH.overLimit, g.values), g.over, JSON.stringify(g));
  }
});

test('the values of a visit', () => {
  for (const g of of('pushvisit')) assert.deepEqual(D.visitVals(g.frames, g.hiEnd, g.starts, g.off, g.recs), g.values, g.name);
  assert.equal(D.PUSH_METRICS.length, of('pushvisit')[0].values.length);
});

test('clock offset or refusal', () => {
  for (const g of of('pushclock')) assert.equal(D.clockOff(g.tlA, g.tlB, g.pgA, g.pgB), g.off, JSON.stringify(g));
});

test('arm label under the visit rule', () => {
  for (const g of of('pushlabel')) assert.equal(D.pushLabel(g.base, g.arm), g.label, g.name);
});

test('the plan', () => {
  const [p] = of('pushplan');
  assert.equal(D.pushOk(D.pushRounds(3)), p.ok3);
  assert.equal(D.pushOk(D.pushRounds(2)), p.ok2);
  assert.equal(D.noRepeat(D.pushRounds(3)), p.noRepeat3);
});
