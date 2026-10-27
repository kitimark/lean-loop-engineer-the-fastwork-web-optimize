import test from 'node:test';
import assert from 'node:assert/strict';
import { recordsOf, valuesOf, summarize, nearEndJs, positionCheck, FRAMES_START_JS } from '../src/device-push-run.mjs';
import { pushTables } from '../src/device-push-tables.mjs';
import { PUSH, PUSH_ARMS, PUSH_METRICS } from '../src/device-push.mjs';

test('recordsOf keeps the counted kinds and the first wk:a and wk:b marks', () => {
  const rows = [['TimeStamp', 1, 1, 'wk:a'], ['Layout', 2, 2.1, ''], ['Paint', 3, 3, ''], ['ScheduleStyleRecalculation', 3, 3, ''], ['TimeStamp', 4, 4, 'wk:b'], ['TimeStamp', 5, 5, 'wk:b']];
  const r = recordsOf(rows);
  assert.deepEqual(r.rs.map((x) => x[0]), ['Layout', 'Paint']);
  assert.equal(r.tlA, 100000);
  assert.equal(r.tlB, 400000);
});

const touches = Array.from({ length: PUSH.pushes }, (_, i) => 100000 + i * 50000);
const frames = (() => {
  const f = [];
  for (let t = 100000; t < 620000; t += 1000) {
    const since = touches.map((s) => t - s).filter((d) => d >= 0).pop();
    f.push([t, 0, since < 10000 ? Math.round(since / 10) : 0]);
  }
  return f;
})();
const hiEnd = frames[frames.length - 1][0] + 1;
const counts = { ts: touches, a: 0, b: 1000000, tlA: 5000, tlB: 1005000, rs: [['Layout', 5000 + 100000 + 2000], ['Paint', 5000 + 100000 + 3000], ['Layout', 5000 + 400000 + 200000]] };

test('valuesOf gives one value per metric and counts inside the push spans only', () => {
  const v = valuesOf(counts, { ts: touches, f: frames, hiEnd, vh: 700, maxY: 9000 });
  assert.equal(v.push.length, PUSH_METRICS.length);
  assert.equal(v.push[0], 1000);
  assert.equal(v.push[3], 0);
  assert.equal(v.push[PUSH_METRICS.indexOf('Layout')], 1);
  assert.equal(v.push[PUSH_METRICS.indexOf('Paint')], 1);
});

test('valuesOf refuses a lane that missed a push and clocks that drift apart', () => {
  const fr = { ts: touches, f: frames, hiEnd, vh: 700, maxY: 9000 };
  assert.throws(() => valuesOf(counts, { ...fr, ts: touches.slice(1) }), /touch starts/);
  assert.throws(() => valuesOf({ ...counts, ts: touches.slice(1) }, fr), /touch starts/);
  assert.throws(() => valuesOf({ ...counts, tlB: counts.tlB + 900000 }, fr), /drift/);
});

test('summarize: three visits per arm label the arms against the base, fewer stay unresolved', () => {
  const mk = (arm, p95) => ({ arm, vals: [p95, p95, p95, 0, 10, 10, 10, 10] });
  const rows = [];
  for (let i = 0; i < 3; i++) for (const a of PUSH_ARMS) rows.push(mk(a.id, a.id === 'base' ? 3000 : 1500));
  const s = summarize(rows);
  assert.equal(s.length, PUSH_ARMS.length);
  assert.ok(s.every((a) => a.n === 3));
  assert.equal(s[0].label, 'base');
  assert.ok(s.slice(1).every((a) => ['better', 'same', 'worse'].includes(a.label)));
  assert.ok(summarize(rows.slice(0, 5)).slice(1).every((a) => a.label === 'unresolved'));
});

test('pushTables writes a row per arm and per visit', () => {
  const rows = PUSH_ARMS.map((a, i) => ({ index: i, arm: a.id, durationS: 200, pushes: 10, nav: true, maxMorph: 1000, vals: [3000, 4000, 5000, 1, 1, 2, 3, 4] }));
  const arms = summarize(rows);
  const md = pushTables({ arms, visits: rows, notRun: [] });
  assert.match(md, /\| base \| 1 \|/);
  assert.equal(md.split('\n').filter((l) => l.startsWith('| ') && /^\| \d+ \|/.test(l)).length, rows.length);
});

test('nearEndJs scrolls to the end minus the gap', () => {
  assert.match(nearEndJs(100), /maxY - 100/);
});

test('the frames recorder reads data-fw-morph when the inline --morph is empty (morph.stage)', () => {
  assert.match(FRAMES_START_JS, /getPropertyValue\('--morph'\) \|\| n\.getAttribute\('data-fw-morph'\)/);
});

test('positionCheck: median over the arms of each position and of each round', () => {
  const rows = [];
  for (let i = 0; i < 16; i++) rows.push({ index: i, arm: PUSH_ARMS[i % 4].id, round: Math.floor(i / 4), position: i % 4, vals: [i, 0, 0, 0, 0, 0, 0, 0] });
  const c = positionCheck(rows);
  assert.equal(c.byPosition.length, 4);
  assert.equal(c.byRound.length, 4);
  assert.deepEqual(c.byPosition[1].metrics[PUSH_METRICS[0]].values, [1, 5, 9, 13]);
  assert.equal(c.byPosition[1].n, 4);
  assert.equal(c.byRound[2].metrics[PUSH_METRICS[0]].median, 10);
});

test('summarize adds the Lean cell verdicts per metric for each non-base arm', () => {
  const rows = [];
  for (let i = 0; i < 3; i++) for (const a of PUSH_ARMS) rows.push({ arm: a.id, vals: [a.id === 'base' ? 3000 : 1500, 0, 0, 0, 10, 10, 10, 10] });
  const s = summarize(rows);
  assert.equal(s[0].cells, null);
  assert.deepEqual(Object.keys(s[1].cells), PUSH_METRICS);
});
