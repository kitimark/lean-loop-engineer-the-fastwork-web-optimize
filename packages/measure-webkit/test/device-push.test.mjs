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
  for (const g of of('pushvisit')) assert.deepEqual(D.visitVals(g.frames, g.hiEnd, g.starts, g.startsC, g.off, g.recs), g.values, g.name);
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

test('the Latin-square order is read from the golden: each arm once per round and per position, no repeats', () => {
  const [c] = of('pushconsts');
  const ids = D.latinOrder().map((a) => a.id);
  assert.deepEqual(ids, c.order);
  assert.deepEqual(D.LATIN_ROWS.flat().map((a) => a.id), ids);
  assert.equal(ids.length, 16);
  for (const r of c.latin) assert.deepEqual([...r].sort(), c.arms.map((a) => a.id).sort());
  for (let p = 0; p < 4; p++) assert.deepEqual(c.latin.map((r) => r[p]).sort(), c.arms.map((a) => a.id).sort());
  assert.ok(D.pushOk(D.latinOrder()) && D.noRepeat(D.latinOrder()));
  assert.deepEqual(D.slotOf(5), { round: 1, position: 1 });
  assert.equal(D.slotOf(16), null);
  const [pl] = of('pushplan');
  assert.equal(pl.latinOk, true);
  assert.equal(pl.latinNoRepeat, true);
});

test('the column probe session: arms, order and contrasts are read from the golden', () => {
  const [c] = of('colscons');
  assert.equal(c.probeFlag, 'morph.columns:probe-off');
  assert.deepEqual(D.COLS_ARMS.map((a) => a.id), ['base', 'cols-off', 'flip', 'flip+cols-off']);
  const ids = D.colsOrder().map((a) => a.id);
  assert.deepEqual(ids, c.order);
  assert.equal(ids.length, 16);
  for (const r of c.latin) assert.deepEqual([...r].sort(), D.COLS_ARMS.map((a) => a.id).sort());
  for (let p = 0; p < 4; p++) assert.deepEqual(c.latin.map((r) => r[p]).sort(), D.COLS_ARMS.map((a) => a.id).sort());
  assert.ok(D.colsOk(D.colsOrder()) && D.noRepeat(D.colsOrder()));
  const [p] = of('pushconsts');
  assert.deepEqual(c.order.map((id) => c.arms.findIndex((a) => a.id === id)), p.order.map((id) => p.arms.findIndex((a) => a.id === id)));
  for (const { ref, arm } of D.COLS_CONTRASTS) {
    const [x, y] = [ref, arm].map((id) => D.COLS_ARMS.find((a) => a.id === id));
    assert.deepEqual(y.flags, [...x.flags, c.probeFlag]);
  }
});

test('contrast causes and the take count follow the golden', () => {
  for (const g of of('colscause')) {
    assert.deepEqual(D.causes(g.ref, g.arm), g.causes, g.name);
    assert.equal(D.pushLabel(g.ref, g.arm), g.label, g.name);
  }
  for (const g of of('coltrace')) {
    assert.equal(D.pushesOf(g.events), g.pushes, g.name);
    assert.equal(D.takenOf(g.events), g.taken, g.name);
  }
});

test('a contrast names the label, the verdict and the cause per column', () => {
  const v = (x) => [x, 1, 1, 1, 1, 1, 1, 1];
  const r = D.contrastOf([v(10), v(50), v(90)], [v(160), v(165), v(170)]);
  assert.equal(r.label, 'same');
  assert.equal(r.cells.p95, 'same');
  assert.equal(r.causes.p95, 'withinSpread');
  assert.equal(r.refSpread.p95, 80);
  assert.equal(D.contrastOf([v(10)], [v(1)]).label, 'unresolved');
});

test('the flip session: three arms, six rounds, order and slots are read from the golden', () => {
  const [c] = of('flipcons');
  assert.deepEqual(D.FLIP_ARMS.map((a) => a.id), ['base', 'morph.geom:on', 'morph.tween:geom-timed']);
  const ids = D.flipOrder().map((a) => a.id);
  assert.deepEqual(ids, c.order);
  assert.equal(ids.length, 18);
  for (const r of c.latin) assert.deepEqual([...r].sort(), D.FLIP_ARMS.map((a) => a.id).sort());
  for (let p = 0; p < 3; p++) for (const a of D.FLIP_ARMS) assert.equal(c.latin.filter((r) => r[p] === a.id).length, 2);
  assert.ok(D.flipOk(D.flipOrder()) && D.noRepeat(D.flipOrder()));
  assert.deepEqual(D.flipSlotOf(7), { round: 2, position: 1 });
  assert.equal(D.flipSlotOf(18), null);
});
