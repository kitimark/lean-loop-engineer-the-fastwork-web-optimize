import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { GOLDEN, analyseFlipProbe, colorDist, installFlipProbe, judgeKept, judgeQuiet, judgeTrace, leaveCovered, loadVerify, MUTATION_OWNER, MUTATION_RUN, pushChance, retryJudged } from '../src/flip-verify.mjs';

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
  assert.ok(of('verifyTrace').length >= 10);
  for (const l of of('verifyTrace')) assert.equal(judgeTrace(l.in.events, l.in.chances), l.out, JSON.stringify(l.in));
});

test('every verifyCovered golden line is replayed by leaveCovered', () => {
  assert.ok(of('verifyCovered').length >= 6);
  for (const l of of('verifyCovered')) assert.equal(leaveCovered(l.in.leave, l.in.last, l.in.window), l.out, JSON.stringify(l.in));
});

test('every verifyRetry golden line is replayed by retryJudged', () => {
  assert.ok(of('verifyRetry').length >= 7);
  for (const l of of('verifyRetry')) assert.equal(retryJudged(l.in.pushes), l.out, JSON.stringify(l.in));
});

test('a push is a chance when the nav was dark at it or a later frame followed the first dark one', () => {
  assert.equal(pushChance(true, false), true);
  assert.equal(pushChance(false, true), true);
  assert.equal(pushChance(false, false), false);
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
const fr = (ts, o = {}) => ({ ts, flip: false, w: 984, bg: 'x', dark: true, tr: [], anims: [{ key: 'nav:up', t: ts, paused: false }], ...o });
const quiet = [];
for (let i = 0; i < 80; i++) quiet.push(fr(i * 16.7, { flip: i >= 2 && i < 20 }));
const trace = [{ kind: 'push', at: 0 }, { kind: 'take', el: 30 }, { kind: 'push', at: 700 }, { kind: 'take', el: 20 }];

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
  const r = analyseFlipProbe({ frames: quiet, trace: [{ kind: 'push', at: 0 }, { kind: 'take', el: 1 }, { kind: 'push', at: 700 }] }, { baseWidth: 984, verify });
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

test('a push the guard never opened for is not judged, and any number may be excused while one push is taken', () => {
  const four = [{ kind: 'push', at: 0 }, { kind: 'take', el: 1 }, { kind: 'push', at: 700 }, { kind: 'take', el: 1 }, { kind: 'push', at: 1400 }, { kind: 'take', el: 1 }, { kind: 'push', at: 2100 }];
  const frames = Array.from({ length: 200 }, (_, i) => fr(i * 16.7));
  const none = frames.map((f) => (f.ts >= 2100 ? { ...f, dark: false } : f));
  const r = analyseFlipProbe({ frames: none, trace: four }, { baseWidth: 984, verify });
  assert.deepEqual(r.a5.chances, [true, true, true, false]);
  assert.equal(r.a5.ok, true);
  assert.equal(r.a5.unjudged, 1);
  const opened = analyseFlipProbe({ frames, trace: four }, { baseWidth: 984, verify });
  assert.equal(opened.a5.ok, false, 'the guard was open with a later frame in the window and the push was not taken');
  const two = [{ kind: 'push', at: 0 }, { kind: 'take', el: 1 }, { kind: 'push', at: 700 }, { kind: 'take', el: 1 }, { kind: 'push', at: 1400 }, { kind: 'push', at: 2100 }];
  const late = frames.map((f) => (f.ts >= 1400 ? { ...f, dark: false } : f));
  assert.equal(analyseFlipProbe({ frames: late, trace: two }, { baseWidth: 984, verify }).a5.ok, true);
  const dead = [{ kind: 'push', at: 0 }, { kind: 'push', at: 700 }];
  assert.equal(analyseFlipProbe({ frames: late, trace: dead }, { baseWidth: 984, verify }).a5.ok, false, 'no push taken: the guard is dead');
});

test('a band whose open pushes start light on a starved runner passes on its taken closes, as in run 41198892838', () => {
  const light = 'is-hero-chrome-ready';
  const dark = 'is-hero-chrome-ready is-on-dark';
  const trace = [
    { kind: 'push', at: 300, nav: light },
    { kind: 'push', at: 11000, nav: dark },
    { kind: 'take', el: 25 },
    { kind: 'push', at: 13000, nav: light },
    { kind: 'push', at: 23700, nav: dark },
    { kind: 'take', el: 27 },
  ];
  const frames = Array.from({ length: 40 }, (_, i) => fr(300 + i * 600, { dark: false }));
  const r = analyseFlipProbe({ frames, trace }, { baseWidth: 984, verify, expectedPushes: 4 });
  assert.deepEqual(r.a5.chances, [false, true, false, true]);
  assert.equal(r.a5.ok, true);
  assert.deepEqual(r.a5.obs.map((o) => o.light), [true, false, true, false]);
  assert.equal(retryJudged(r.a5.obs), false, 'no light-start push was judged: the run must not pass on the retry');
});

test('a push the nav was dark at, left untaken on a one-frame runner, is a lost chance', () => {
  const trace = [{ kind: 'push', at: 0, nav: 'is-on-dark' }, { kind: 'push', at: 700, nav: 'is-on-dark' }, { kind: 'take', el: 2 }];
  const frames = [fr(0, { dark: true }), fr(2000, { dark: true })];
  const r = analyseFlipProbe({ frames, trace }, { baseWidth: 984, verify });
  assert.deepEqual(r.a5.chances, [true, true]);
  assert.equal(r.a5.ok, false);
});

test('the probe says a leave is covered only after a frame windowMs past it', () => {
  const g = globalThis;
  const saved = { window: g.window, document: g.document, requestAnimationFrame: g.requestAnimationFrame };
  let flip = false;
  let frame = null;
  g.window = { scrollY: 0 };
  g.document = {
    documentElement: { classList: { contains: () => flip } },
    querySelector: () => null,
  };
  g.requestAnimationFrame = (cb) => {
    frame = cb;
  };
  try {
    installFlipProbe();
    const p = g.window.__fwFlipProbe;
    p.start();
    const tick = (ts) => {
      const cb = frame;
      frame = null;
      cb(ts);
    };
    assert.equal(p.leaveReady(800), true, 'no flip seen: nothing to wait for');
    flip = true;
    tick(0);
    assert.equal(p.leaveReady(800), false, 'flip on and not yet left');
    flip = false;
    assert.equal(p.leaveReady(800), false, 'the page left but no frame saw it');
    tick(100);
    assert.equal(p.leaveReady(800), false, 'the leave frame alone does not cover the window');
    tick(899);
    assert.equal(p.leaveReady(800), false);
    tick(900);
    assert.equal(p.leaveReady(800), true);
  } finally {
    Object.assign(g, saved);
  }
});

test('a dark frame that is the last one in the window leaves no tick to retry on', () => {
  const frames = Array.from({ length: 80 }, (_, i) => fr(i * 100, { dark: i === 6 }));
  const r = analyseFlipProbe({ frames, trace: [{ kind: 'push', at: 0 }] }, { baseWidth: 984, verify });
  assert.deepEqual(r.a5.chances, [false]);
});

test('taken pushes on a runner too slow to show the guard open still pass', () => {
  const four = [{ kind: 'push', at: 0 }, { kind: 'take', el: 1 }, { kind: 'push', at: 700 }, { kind: 'take', el: 1 }, { kind: 'push', at: 1400 }, { kind: 'take', el: 1 }, { kind: 'push', at: 2100 }, { kind: 'take', el: 1 }];
  const frames = Array.from({ length: 40 }, (_, i) => fr(i * 700, { dark: false }));
  const r = analyseFlipProbe({ frames, trace: four }, { baseWidth: 984, verify });
  assert.deepEqual(r.a5.chances, [false, false, false, false]);
  assert.equal(r.a5.ok, true);
});
