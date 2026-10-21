// The zone-binned Timeline profile (src/profile/reduce.mjs) against the Lean golden (lean/Fw/Measure/WebKitProfile.lean).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  KINDS, WORK, TIMED, DRIFT_TOL, nestedOf, driftOk, meanOffset, profile, medianNat, zoneVerdict, armsOf, perFrameUs,
  flattenTimeline, markTimes, profileWindow, profileFromRaw, rawOf, unionLen, span, ZONES,
} from '../src/profile/reduce.mjs';

const G = readFileSync(new URL('../../contracts/golden/measure/webkit-profile.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l));
const of = (kind) => G.filter((l) => l.kind === kind);

test('kinds, work kinds, timed kinds and drift tolerance are Lean\'s', () => {
  const k = of('kinds')[0];
  assert.deepEqual(KINDS, k.kinds);
  assert.deepEqual(WORK, k.work);
  assert.deepEqual(TIMED, k.timed);
  assert.ok(!WORK.includes('Composite') && !TIMED.includes('Composite'));
  assert.equal(DRIFT_TOL, k.driftTol);
});

test('nested: a record is nested when a work record encloses it', () => {
  for (const c of of('nested')) assert.equal(nestedOf(c.ancestors), c.nested, JSON.stringify(c.ancestors));
});

test('drift: kept within the tolerance, refused beyond, the mean offset', () => {
  for (const c of of('drift')) {
    assert.equal(driftOk(c.a, c.b), c.ok, `${c.a} ${c.b}`);
    assert.equal(meanOffset(c.a, c.b), c.mean, `${c.a} ${c.b}`);
  }
});

test('profile: records binned to the zone of their frame, per kind counts and durations, render work per frame, span', () => {
  for (const c of of('profile')) {
    const recs = c.recs.map(([kind, t, dur, nested]) => ({ kind, t, dur, nested }));
    for (const z of ['hero', 'finish', 'rest']) assert.deepEqual(profile(c.vh10, c.maxY10, c.frames, c.off, c.ws, z, recs), c.zones[z], z);
    const total = ['hero', 'finish', 'rest'].map((z) => profile(c.vh10, c.maxY10, c.frames, c.off, c.ws, z, recs).cells.reduce((s, x) => s + x[1], 0));
    assert.equal(total.reduce((a, b) => a + b, 0), recs.filter((r) => c.ws.some((w) => w[0] <= r.t - c.off && r.t - c.off < w[1]) && KINDS.includes(r.kind)).length);
  }
});

test('median, per-frame value, verdict, arms', () => {
  for (const c of of('median')) assert.equal(medianNat(c.values), c.median, JSON.stringify(c.values));
  for (const c of of('verdict')) assert.equal(zoneVerdict(c.a, c.b, c.aa1, c.aa2), c.verdict, JSON.stringify(c));
  for (const c of of('perFrame')) for (const [w, n, v] of c.cases) assert.equal(perFrameUs(w, n), v);
  for (const c of of('arms')) {
    const names = ['rewrite', 'v2', 'look'];
    assert.deepEqual(armsOf(c.flags.map((f, i) => [names[i], f])), c.kept);
  }
});

test('flattenTimeline: seconds to hundredths of ms, nested under a render ancestor, TimeStamp marks by name', () => {
  const recs = [
    { type: 'TimeStamp', startTime: 10, endTime: 10, data: { message: 'wk:a' } },
    { type: 'RecalculateStyles', startTime: 10.5, endTime: 10.502, children: [{ type: 'Layout', startTime: 10.5005, endTime: 10.501 }] },
    { type: 'FunctionCall', startTime: 10.6, endTime: 10.6004, children: [{ type: 'Paint', startTime: 10.6001, endTime: 10.6002 }] },
  ];
  const flat = flattenTimeline(recs);
  assert.deepEqual(flat.map((r) => [r.kind, r.nested]), [['TimeStamp', false], ['RecalculateStyles', false], ['Layout', true], ['FunctionCall', false], ['Paint', false]]);
  assert.equal(flat[1].t, 1050000);
  assert.equal(flat[1].dur, 200);
  assert.equal(markTimes(recs).get('wk:a'), 1000000);
});

test('profileWindow: refuses a window whose clock offsets drift, bins a steady one', () => {
  const mk = (bTs) => [
    { type: 'TimeStamp', startTime: 10, endTime: 10, data: { message: 'wk:a' } },
    { type: 'Layout', startTime: 10.01, endTime: 10.011 },
    { type: 'TimeStamp', startTime: bTs, endTime: bTs, data: { message: 'wk:b' } },
  ];
  const page = { frames: [[100000, 0], [101000, 500]], vh10: 8440, maxY10: 21000, w0: 100000, w1: 102000, marks: { a: 100000, b: 102000 } };
  const steady = profileWindow(page, mk(10.02));
  assert.equal(steady.ok, true);
  assert.equal(steady.profiles.hero.cells.find((c) => c[0] === 'Layout')[1], 1);
  const drifted = profileWindow(page, mk(10.03));
  assert.equal(drifted.ok, false);
  assert.equal(drifted.reason, 'drift');
  assert.equal(profileWindow(page, [mk(10.02)[1]]).reason, 'marks-missing');
});

test('union: overlap, duplicate and nesting count once; the sweep is order free', () => {
  assert.equal(unionLen(0, [[5, 15], [0, 10], [20, 25], [21, 22]]), 20);
  assert.equal(unionLen(0, [[0, 10], [0, 10]]), 10);
  assert.equal(unionLen(0, []), 0);
});

test('every time is bounded by the window span and Composite is a count (Lean profile_work_le_span, profile_cells_le_span, cell_composite_time)', () => {
  for (const c of of('profile')) {
    const recs = c.recs.map(([kind, t, dur, nested]) => ({ kind, t, dur, nested }));
    for (const z of ZONES) {
      const p = profile(c.vh10, c.maxY10, c.frames, c.off, c.ws, z, recs);
      assert.equal(p.span, span(c.ws));
      assert.ok(p.work <= p.span, `${z} work`);
      for (const [k, n, t] of p.cells) { assert.ok(t <= p.span, `${z} ${k}`); if (k === 'Composite') assert.equal(t, 0); assert.ok(n >= 0); }
    }
  }
  // a Composite record far longer than the window adds count and no time
  const long = [{ kind: 'Composite', t: 100, dur: 9e6, nested: false }, { kind: 'Layout', t: 100, dur: 9e6, nested: false }];
  const p = profile(8440, 21000, [[0, 0]], 0, [[0, 1000]], 'hero', long);
  assert.equal(p.cells.find((x) => x[0] === 'Composite').join(), 'Composite,1,0');
  assert.equal(p.work, 900);
});

test('profileFromRaw gives back the profile of profileWindow (the raw input re-reduces)', () => {
  const recs = [
    { type: 'TimeStamp', startTime: 10, endTime: 10, data: { message: 'wk:a' } },
    { type: 'Layout', startTime: 10.01, endTime: 10.011 },
    { type: 'Composite', startTime: 10.012, endTime: 10.9 },
    { type: 'TimeStamp', startTime: 10.02, endTime: 10.02, data: { message: 'wk:b' } },
  ];
  const page = { frames: [[100000, 0], [101000, 500]], vh10: 8440, maxY10: 21000, w0: 100000, w1: 102000, marks: { a: 100000, b: 102000 } };
  const w = profileWindow(page, recs);
  assert.deepEqual(JSON.parse(JSON.stringify(profileFromRaw(JSON.parse(JSON.stringify(w.raw))))), JSON.parse(JSON.stringify({ ok: w.ok, off: w.off, offA: w.offA, offB: w.offB, profiles: w.profiles })));
  assert.deepEqual(rawOf(page, recs), w.raw);
  assert.equal(w.profiles.hero.cells.find((c) => c[0] === 'Composite')[2], 0);
});
