import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { GOLDEN, analyseFlipProbe, colorDist, judgeKept, judgeQuiet, judgeTrace, loadVerify, MUTATION_OWNER, MUTATION_RUN } from '../src/flip-verify.mjs';

const lines = readFileSync(GOLDEN, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (fn) => lines.filter((l) => l.fn === fn);

test('every verifyQuiet golden line is replayed by judgeQuiet', () => {
  assert.ok(of('verifyQuiet').length >= 6);
  for (const l of of('verifyQuiet')) assert.equal(judgeQuiet(l.in.base, l.in.tol, l.in.frames), l.out, JSON.stringify(l.in));
});

test('every verifyKept golden line is replayed by judgeKept', () => {
  assert.ok(of('verifyKept').length >= 3);
  for (const l of of('verifyKept')) assert.equal(judgeKept(l.in.frame, l.in.lost, l.in.pairs), l.out, JSON.stringify(l.in));
});

test('every verifyTrace golden line is replayed by judgeTrace', () => {
  assert.ok(of('verifyTrace').length >= 4);
  for (const l of of('verifyTrace')) assert.equal(judgeTrace(l.in.events), l.out, JSON.stringify(l.in));
});

test('the golden names the six mutations and the window', () => {
  const v = loadVerify();
  assert.deepEqual(v.mutations.map((m) => m.id), ['A1', 'A3b', 'A3c', 'A4', 'A3a', 'A5']);
  assert.equal(v.windowMs, 800);
  assert.deepEqual(Object.keys(MUTATION_RUN).sort(), v.mutations.map((m) => m.id).sort());
});

test('cell mutation owners match only their own reading', () => {
  assert.ok(MUTATION_OWNER.A1('column1: not beside column0 (left 0.0, previous 0.0)'));
  assert.ok(MUTATION_OWNER.A3b('earn: edges differ by 8.00 px (> 1)'));
  assert.ok(MUTATION_OWNER.A3c('lang: edges differ by 6.00 px (> 1)'));
  assert.ok(!MUTATION_OWNER.A3b('lang: edges differ by 6.00 px (> 1)'));
});

const verify = loadVerify();
const fr = (ts, o = {}) => ({ ts, flip: false, w: 984, bg: 'x', tr: [], anims: [{ key: 'nav:up', t: ts, paused: false }], ...o });
const quiet = [];
for (let i = 0; i < 80; i++) quiet.push(fr(i * 16.7, { flip: i >= 2 && i < 20 }));
const trace = [{ kind: 'push' }, { kind: 'take', el: 30 }, { kind: 'push' }, { kind: 'take', el: 20 }];

test('quiet frames, kept time and a taken trace pass', () => {
  const r = analyseFlipProbe({ frames: quiet, trace }, { baseWidth: 984, verify, expectedPushes: 2 });
  assert.equal(r.a3a.ok, true);
  assert.equal(r.a4.ok, true);
  assert.equal(r.a5.ok, true);
});

test('a width transition after the leave fails A4', () => {
  const frames = quiet.map((f, i) => (i > 22 && i < 30 ? { ...f, tr: ['width'], w: 990 } : f));
  const r = analyseFlipProbe({ frames, trace }, { baseWidth: 984, verify });
  assert.equal(r.a4.ok, false);
});

test('a restarted animation across the re-parent fails A3a', () => {
  const frames = quiet.map((f, i) => (i >= 20 ? { ...f, anims: [{ key: 'nav:up', t: (i - 20) * 16.7, paused: false }] } : f));
  const r = analyseFlipProbe({ frames, trace }, { baseWidth: 984, verify });
  assert.equal(r.a3a.ok, false);
});

test('an untaken push fails A5', () => {
  const r = analyseFlipProbe({ frames: quiet, trace: [{ kind: 'push' }, { kind: 'take', el: 1 }, { kind: 'push' }] }, { baseWidth: 984, verify });
  assert.equal(r.a5.ok, false);
});

test('a window not covered by frames fails A4 instead of passing vacuously', () => {
  const r = analyseFlipProbe({ frames: quiet.slice(0, 30), trace }, { baseWidth: 984, verify });
  assert.equal(r.a4.ok, false);
});

test('colours of all three serialisations compare in sRGB', () => {
  assert.ok(colorDist('rgba(255, 255, 255, 0.1)', 'color(srgb 1 1 1 / 0.1)') < 1e-9);
  assert.ok(colorDist('color(srgb 1 1 1 / 0.101961)', 'oklab(0.999 0.00004 0.000005 / 0.1021)') < 0.01);
  assert.ok(colorDist('rgba(0, 0, 0, 0)', 'color(srgb 1 1 1 / 0.1)') > 0.05);
});

test('a visible background transition fails A4, the base nav residue does not', () => {
  const bgOff = quiet.map((f, i) => (i > 22 && i < 40 ? { ...f, tr: ['background-color'], bg: 'rgba(0, 0, 0, 0)' } : { ...f, bg: 'color(srgb 1 1 1 / 0.101961)' }));
  assert.equal(analyseFlipProbe({ frames: bgOff, trace }, { baseWidth: 984, verify }).a4.ok, false);
  const residue = quiet.map((f, i) => (i > 22 && i < 40 ? { ...f, tr: ['background-color', 'width'], w: 984.2, bg: 'oklab(0.994 0.00002 -0.00009 / 0.1027)' } : { ...f, bg: 'color(srgb 1 1 1 / 0.101961)' }));
  assert.equal(analyseFlipProbe({ frames: residue, trace }, { baseWidth: 984, verify }).a4.ok, true);
});

test('a one-frame stall in a slow frame is within that frame, a restart is not', () => {
  const stall = quiet.map((f, i) => (i >= 20 ? { ...f, ts: f.ts + 8, anims: [{ key: 'nav:up', t: Math.max(0, (i - 1) * 16.7), paused: false }] } : f));
  assert.equal(analyseFlipProbe({ frames: stall, trace }, { baseWidth: 984, verify }).a3a.ok, true);
});
