import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { binOf, classOf, effOf, frameSummary, midSummary, normName, oracleTicks, prefOf, readsAccelCls, tickOf, ticksContinuously, ticksMain } from '../src/midflip.mjs';
import { accelHarnessSource } from '../src/accel-page.mjs';
import { headerOf, isMid, MID_ARMS, MID_AT, THREADED_OFF } from '../src/accel-cli.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(HERE, '../../contracts/golden/parts/morph-track-accel.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));

test('the tick rule agrees with the Lean golden on all 256 effect states', () => {
  const rows = lines.filter((l) => l.fn === 'tick');
  assert.equal(rows.length, 256);
  for (const r of rows) {
    assert.equal(ticksContinuously(r.in), r.out.continuous, JSON.stringify(r.in));
    assert.equal(ticksMain(r.in), r.out.main, JSON.stringify(r.in));
    assert.equal(tickOf(r.in), r.out.kind, JSON.stringify(r.in));
  }
});

test('the bins and the name rule agree with the Lean golden', () => {
  const bins = lines.filter((l) => l.fn === 'bin');
  assert.equal(bins.length, 12);
  for (const r of bins) assert.equal(binOf(r.in.permille), r.out, String(r.in.permille));
  for (const r of lines.filter((l) => l.fn === 'name')) assert.equal(normName(r.in.a) === normName(r.in.b), r.out);
});

test('the class rule agrees with the Lean golden', () => {
  const rows = lines.filter((l) => l.fn === 'cls');
  assert.equal(rows.length, 8);
  for (const r of rows) assert.equal(readsAccelCls(r.in.prop, r.in.reported, r.in.tracks), r.out, JSON.stringify(r.in));
  assert.equal(classOf('scale'), classOf('transform'));
});

test('effOf reads a readout row into the Lean inputs', () => {
  const eff = effOf({ p: 0, s: 'running', a: 1 }, 500, true, true);
  assert.deepEqual(eff, { pending: false, running: true, active: true, rendered: true, complete: true, accel: true, threaded: true, disallowed: false });
  assert.equal(ticksMain(eff), false);
  assert.equal(ticksMain(effOf({ p: 1, s: 'running', a: 1 }, 500, true, true)), true);
  assert.equal(ticksMain(effOf({ p: 0, s: 'running', a: 0 }, 500, true, false)), true);
  assert.equal(ticksMain(effOf({ p: 0, s: 'idle', a: 0 }, 1500, true, false)), false);
});

test('the oracle reads timeToNextAnimationTick against the animation interval', () => {
  assert.equal(oracleTicks('inf', 0.0166), false);
  assert.equal(oracleTicks(0, 0.0166), true);
  assert.equal(oracleTicks(300, 0.0166), false);
  assert.equal(oracleTicks(undefined, 0.0166), null);
  assert.equal(oracleTicks(0, undefined), null);
});

const report = () => ({
  tags: [{ id: 'a', mg: 'column', prop: 'translate', idx: 0 }, { id: 'b', mg: 'image', prop: 'transform', idx: 1 }],
  rows: [
    {
      arm: 'all',
      stages: [{ stage: 'flip', frames: 10, ms: 400, recalc: 20 }],
      rendered: [true, false],
      frames: [{ n: 1, dt: 40, ph: 400, rc: 2, upd: 30, inv: 5 }, { n: 2, dt: 80, ph: 500, rc: 5, upd: 40, inv: 8 }],
      samples: [
        { why: 'p50', ph: 520, dt: 300, env: { itv: 0.0166 }, rows: [{ id: 'a', s: 'running', p: 0, a: 1, th: true, t: 'inf' }, { id: 'b', s: 'running', p: 0, a: 0, th: null, t: 0 }] },
        { why: 'end', ph: 1500, dt: 700, env: { itv: 0.0166 }, rows: [{ id: 'a', s: 'idle', p: 0, a: 0, th: null, t: 'inf' }, { id: 'b', s: 'idle', p: 0, a: 0, th: null, t: 'inf' }] },
      ],
    },
  ],
});

test('midSummary counts tracks per group and checks the Lean rule against the engine answer', () => {
  const out = midSummary(report());
  assert.equal(out.length, 2);
  assert.equal(out[0].bin, 50);
  assert.equal(out[0].groups['translate'].accel, 1);
  assert.equal(out[0].groups['translate'].oracleQuiet, 1);
  assert.equal(out[0].groups['translate'].agree, 1);
  assert.equal(out[0].groups['transform'].unrendered, 1);
  assert.equal(out[0].groups['transform'].oracleTicks, 1);
  assert.equal(out[0].groups['transform'].leanTicks, 0);
  assert.equal(out[0].groups['transform'].agree, 0);
  assert.equal(out[1].bin, 'end');
  assert.equal(prefOf(report()), true);
});

test('midSummary reads the flush steps before the frames and the class entries of an element', () => {
  const rep = report();
  rep.rows[0].pre = [{ why: 'f-style', ph: 300, ms: 4.5, err: null, env: { itv: 0.015 }, rows: [{ id: 'a', s: 'running', p: 0, a: 0, th: null, t: 0, e: ['transform'], tc: 1 }, { id: 'b', s: 'running', p: 1, a: 0, th: null, t: 0, e: [], tc: 1 }] }];
  const [first] = midSummary(rep);
  assert.equal(first.bin, 'f-style');
  assert.equal(first.ms, 4.5);
  assert.equal(first.groups.translate.accelCls, 1);
  assert.equal(first.groups.translate.leanTicks, 0);
  assert.equal(first.groups.transform.pending, 1);
  assert.equal(first.groups.transform.leanTicks, 1);
});

test('frameSummary differences the cumulative recalc count', () => {
  const [f] = frameSummary(report());
  assert.equal(f.recalcPerFrame, 2);
  assert.equal(f.rcMax, 3);
  assert.equal(f.invDelta, 3);
  assert.equal(f.updMax, 40);
});

test('the mid mode reads the three phases, the preference off arm adds its header key', () => {
  assert.deepEqual(MID_AT, [0.3, 0.5, 0.8]);
  for (const a of ['all', 'idle', 'no-translate', 'no-transform', 'none']) assert.ok(MID_ARMS.includes(a), a);
  assert.ok(isMid('mid') && isMid('mid-thr-off') && !isMid('timed'));
  assert.equal(headerOf('mid', 'useFlexibleViewport=true'), 'useFlexibleViewport=true');
  assert.equal(headerOf('mid-thr-off', 'useFlexibleViewport=true'), `useFlexibleViewport=true ${THREADED_OFF}`);
  const js = accelHarnessSource({ mode: 'timed', mid: MID_AT });
  assert.doesNotThrow(() => new Function(js));
  assert.match(js, /"mid":\[0\.3,0\.5,0\.8\]/);
  assert.match(js, /timeToNextAnimationTick/);
  assert.throws(() => accelHarnessSource({ mode: 'scrubbed', mid: MID_AT }), /timed/);
});
