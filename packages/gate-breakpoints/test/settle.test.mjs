// waitReady compares end states: it awaits every finite animation or transition, including one that starts after the first
// quiet moment (the original's people card mounts after hydration; WebKit run 39059296556 read blur(0.002685px) in its tail).
import test from 'node:test';
import assert from 'node:assert/strict';
import { prepareInPage, waitReady } from '../src/page.mjs';
import { GATE_POLICY, idlePolicy, waitTrace } from '../src/settle.mjs';

/** A fake animation that is running until `finish()` and exposes the `finished` promise like the Web Animations API. */
function fakeAnimation(iterations = 1) {
  let done;
  const finished = new Promise((r) => { done = r; });
  const a = {
    playState: 'running',
    effect: { getComputedTiming: () => ({ iterations }) },
    finished,
    finish() { a.playState = 'finished'; done(a); },
  };
  return a;
}

function withDom(animations) {
  const saved = { document: globalThis.document, window: globalThis.window, requestAnimationFrame: globalThis.requestAnimationFrame };
  globalThis.document = {
    fonts: { ready: Promise.resolve() },
    querySelector: () => ({}),
    getAnimations: () => animations.filter((a) => a.playState !== 'finished'),
  };
  globalThis.window = { __fw: { hydrated: true, mode: 'test', hydrationErrors: [] } };
  globalThis.requestAnimationFrame = (cb) => setTimeout(cb, 1);
  return () => Object.assign(globalThis, saved);
}

test('a running finite transition is awaited and counted; an infinite animation is ignored', async () => {
  const tail = fakeAnimation(1);
  const orbit = fakeAnimation(Infinity);
  const restore = withDom([tail, orbit]);
  try {
    setTimeout(() => tail.finish(), 400);
    const r = await waitReady({ site: 'rewrite', capMs: 5000 });
    assert.equal(tail.playState, 'finished', 'the end state was reached before waitReady returned');
    assert.equal(orbit.playState, 'running', 'infinite animations are not waited for');
    assert.equal(r.animations.awaited, 1);
    assert.equal(r.animations.left, 0);
    assert.ok(r.animations.waitedMs >= 400, `waited ${r.animations.waitedMs} ms`);
  } finally { restore(); }
});

test('a transition that starts after the first quiet moment is awaited too (late mount)', async () => {
  const animations = [];
  const restore = withDom(animations);
  try {
    let late;
    setTimeout(() => { late = fakeAnimation(1); animations.push(late); setTimeout(() => late.finish(), 300); }, 150);
    const r = await waitReady({ site: 'rewrite', capMs: 8000 });
    assert.ok(late, 'the late transition started');
    assert.equal(late.playState, 'finished');
    assert.equal(r.animations.left, 0);
    assert.equal(r.animations.awaited, 1);
    assert.ok(r.animations.passes >= 2, 'a second pass saw the quiet page');
  } finally { restore(); }
});

test('the wait is bounded by capMs and reports what was left', async () => {
  const stuck = fakeAnimation(1);
  const restore = withDom([stuck]);
  try {
    const r = await waitReady({ site: 'rewrite', capMs: 600 });
    assert.equal(stuck.playState, 'running');
    assert.equal(r.animations.left, 1);
  } finally { restore(); }
});

// gate-shard-balance: the mount stage's idle wait is bounded by the frame budget, not only by the 20 s cap, and its trace is
// decided by Lean's wait under idlePolicy (an animation a timer keeps restarting ends the wait unsettled after maxFrames frames).
test('the mount idle wait stops after maxFrames real frames and Lean decides its outcome', async () => {
  const stuck = fakeAnimation(1);
  const restore = withDom([stuck]);
  globalThis.window.scrollTo = () => {};
  globalThis.window.scrollY = 0;
  globalThis.window.innerHeight = 900;
  try {
    const t0 = Date.now();
    const r = await prepareInPage({ stage: 'ready', steps: [], capMs: 20000, maxFrames: 5 });
    assert.deepEqual(r.found, []);
    const last = r.idle[r.idle.length - 1];
    assert.equal(last.frames, 6, 'stops at the first observation past the budget');
    assert.ok(Date.now() - t0 < 5000, 'far below the 20 s cap');
    assert.equal(waitTrace(idlePolicy({ ...GATE_POLICY, maxFrames: 5 }, 20000), r.idle), 'unsettled');
    stuck.finish();
    const ok = await prepareInPage({ stage: 'ready', steps: [], capMs: 20000, maxFrames: 5 });
    assert.equal(waitTrace(idlePolicy(GATE_POLICY, 20000), ok.idle), 'settled@0');
  } finally { restore(); }
});
