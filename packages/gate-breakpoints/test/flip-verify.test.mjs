import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { GOLDEN, analyseFlipProbe, judgeKept, judgeQuiet, judgeTrace, loadVerify, MUTATION_OWNER, MUTATION_RUN } from '../src/flip-verify.mjs';

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
