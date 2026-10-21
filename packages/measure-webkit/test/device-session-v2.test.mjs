import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as S from '../src/device-session.mjs';

const lines = readFileSync(new URL('../../contracts/golden/device/session.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);
const ivsOfDts = (dts) => S.ivs(dts.reduce((acc, d) => [...acc, acc[acc.length - 1] + d], [0]).map((t) => [t, t, []]));
const frames3 = (fs) => fs.map(([t, y, p]) => [t, y, p]);

test('every v2 golden kind has lines', () => {
  for (const k of ['v2.consts', 'v2.slot', 'v2.counterexample', 'v2.ivs', 'v2.stat', 'v2.band', 'v2.marks', 'v2.touch', 'v2.session']) assert.ok(of(k).length > 0, k);
});

test('slots match Lean', () => {
  for (const c of of('v2.slot')) assert.equal(S.slotOf(c.t0, c.t), c.slot, JSON.stringify(c));
});

test('the counterexample: an interval over 25 ms without a skipped slot', () => {
  const [c] = of('v2.counterexample');
  const vs = S.ivs(frames3(c.frames));
  assert.deepEqual(vs, c.ivs);
  assert.deepEqual(vs.map((v) => S.CONST2.miss < v[2]), c.miss);
  assert.deepEqual(vs.map(S.skip), c.skip);
  assert.ok(c.miss.some((m, i) => m && !c.skip[i]));
});

test('intervals and their stats match Lean', () => {
  for (const c of of('v2.ivs')) {
    const vs = S.ivs(frames3(c.frames));
    assert.deepEqual(vs, c.ivs, JSON.stringify(c.frames));
    assert.equal(S.expected(vs), c.expected);
    assert.deepEqual(S.stat2(c.expected, vs), c.stat);
  }
  for (const c of of('v2.stat')) assert.deepEqual(S.stat2(c.expected, ivsOfDts(c.dts)), c.stat, JSON.stringify(c.dts));
});

test('every Lean stat keeps over50 <= over34 <= over25 and run30 <= skips', () => {
  const stats = [...of('v2.ivs'), ...of('v2.stat')].map((c) => c.stat);
  for (const s of stats) {
    assert.ok(s.over50 <= s.over34 && s.over34 <= s.over25, JSON.stringify(s));
    assert.ok(s.run30 <= s.skips && s.median <= s.p95 && s.p95 <= s.longest, JSON.stringify(s));
  }
});

test('bands match Lean', () => {
  for (const c of of('v2.band')) assert.equal(S.bandOf(c.hitch), c.band, String(c.hitch));
});

test('felt marks with the first-tap start match Lean', () => {
  for (const c of of('v2.marks')) {
    const tp = c.taps.map(([s, t, x, y]) => [s, [t, x, y]]);
    assert.deepEqual(S.marksW(tp).map(([s, [t, x, y]]) => [s, t, x, y]), c.marks);
  }
});

test('touch latency and finger offset match Lean', () => {
  for (const c of of('v2.touch')) {
    const ds = S.drags(c.touches);
    assert.equal(ds.length, c.drags);
    assert.deepEqual(ds.map((s) => S.startLatency(c.frames, s)).filter((d) => d !== null), c.starts, JSON.stringify(c.touches));
    assert.deepEqual(ds.map((s) => S.offsetMax(c.maxY10, c.frames, s)).filter((d) => d !== null), c.offsets, JSON.stringify(c.touches));
  }
});

test('the synthetic pass reduces as in Lean', () => {
  const [c] = of('v2.session');
  assert.deepEqual(S.reduceV2(c.record), c.report);
});

test('the summary holds no times or touch values and keeps one felt mark per first-reduction mark', () => {
  const [c] = of('v2.session');
  const s = S.summarizeV2('2000-01-01', [{ arm: 'original', pass: 1, record: c.record }, { arm: 'original', pass: 2, record: c.record }, { arm: 'look', pass: 1, record: c.record }]);
  const text = JSON.stringify(s);
  for (const k of ['"t"', '"touches"', '"starts":[', '"y":']) assert.ok(!text.includes(k), k);
  assert.equal(s.passes[0].felt.length, S.reducePass(c.record).felt.length);
  assert.equal(s.felt.find((f) => f.arm === 'original').marks, 2 * c.report.felt.length);
  const md = S.summaryV2Md(s);
  assert.match(md, /\| whole \| look \| 1 \|/);
  assert.ok(s.compare.every((x) => x.arms.every((a) => a.verdict === 'same')));
});
