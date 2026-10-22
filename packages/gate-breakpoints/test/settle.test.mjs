import test from 'node:test';
import assert from 'node:assert/strict';
import { prepareInPage, settleInPage, waitReady } from '../src/page.mjs';
import { GATE_POLICY, idlePolicy, waitTrace } from '../src/settle.mjs';

class FakeDocumentTimeline {}
class FakeScrollTimeline {}
const docTimeline = new FakeDocumentTimeline();

function fakeAnimation(iterations = 1, timeline = docTimeline) {
  let done;
  const finished = new Promise((r) => { done = r; });
  const a = {
    playState: 'running',
    timeline,
    effect: { getComputedTiming: () => ({ iterations }) },
    finished,
    finish() { a.playState = 'finished'; done(a); },
  };
  return a;
}

function withDom(animations) {
  const saved = { document: globalThis.document, window: globalThis.window, requestAnimationFrame: globalThis.requestAnimationFrame, DocumentTimeline: globalThis.DocumentTimeline };
  globalThis.DocumentTimeline = FakeDocumentTimeline;
  globalThis.document = {
    fonts: { ready: Promise.resolve() },
    querySelector: () => ({}),
    getAnimations: () => animations.filter((a) => a.playState !== 'finished'),
  };
  globalThis.window = { __fw: { hydrated: true, mode: 'test', hydrationErrors: [] } };
  globalThis.requestAnimationFrame = (cb) => setTimeout(cb, 1);
  return () => {
    Object.assign(globalThis, saved);
    if (saved.DocumentTimeline === undefined) delete globalThis.DocumentTimeline;
  };
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

test('the mount idle wait stops after maxFrames real frames and Lean decides its outcome', async () => {
  const stuck = fakeAnimation(1);
  const restore = withDom([stuck]);
  globalThis.window.scrollTo = () => {};
  globalThis.window.scrollY = 0;
  globalThis.window.innerHeight = 900;
  try {
    const r = await prepareInPage({ stage: 'ready', steps: [], capMs: 20000, maxFrames: 5 });
    assert.deepEqual(r.found, []);
    const last = r.idle[r.idle.length - 1];
    assert.equal(last.frames, 6, 'stops at the first observation past the budget');
    assert.equal(waitTrace(idlePolicy({ ...GATE_POLICY, maxFrames: 5 }, 20000), r.idle), 'unsettled');
    stuck.finish();
    const ok = await prepareInPage({ stage: 'ready', steps: [], capMs: 20000, maxFrames: 5 });
    assert.equal(waitTrace(idlePolicy(GATE_POLICY, 20000), ok.idle), 'settled@0');
  } finally { restore(); }
});

test('the idle wait does not wait for a scroll-driven finite animation, and still waits for a document one', async () => {
  const scroll = fakeAnimation(1, new FakeScrollTimeline());
  const tail = fakeAnimation(1);
  const restore = withDom([scroll, tail]);
  try {
    setTimeout(() => tail.finish(), 300);
    const r = await waitReady({ site: 'rewrite', capMs: 5000 });
    assert.equal(tail.playState, 'finished');
    assert.equal(scroll.playState, 'running', 'the scroll-driven animation is untouched');
    assert.equal(r.animations.awaited, 1, 'only the document animation was awaited');
    assert.equal(r.animations.left, 0);
    assert.ok(r.animations.waitedMs < 4000, `waited ${r.animations.waitedMs} ms, not the cap`);
  } finally { restore(); }
});

function probe(animations) {
  const el = { getAnimations: () => animations, getBoundingClientRect: () => ({ x: 1, y: 2, width: 30, height: 40 }), matches: () => false };
  const saved = { document: globalThis.document, window: globalThis.window, getComputedStyle: globalThis.getComputedStyle, requestAnimationFrame: globalThis.requestAnimationFrame, DocumentTimeline: globalThis.DocumentTimeline };
  globalThis.DocumentTimeline = FakeDocumentTimeline;
  globalThis.document = { querySelectorAll: () => [el] };
  globalThis.window = { innerWidth: 390, innerHeight: 800 };
  globalThis.getComputedStyle = () => ({ transform: 'none', opacity: '1' });
  globalThis.requestAnimationFrame = (cb) => setTimeout(cb, 1);
  return () => {
    Object.assign(globalThis, saved);
    if (saved.DocumentTimeline === undefined) delete globalThis.DocumentTimeline;
  };
}

const ARG = { policy: GATE_POLICY, roots: ['.x'], hoverCapable: false };

test('the settle probe: a scroll-driven animation at a fixed offset leaves the sample settled', async () => {
  const restore = probe([fakeAnimation(1, new FakeScrollTimeline()), fakeAnimation(1, new FakeScrollTimeline())]);
  try {
    const { trace } = await settleInPage(ARG);
    assert.ok(trace.every((o) => o.running === 0), 'no scroll-driven animation is counted');
    assert.equal(waitTrace(GATE_POLICY, trace), 'settled@' + (trace.length - 1));
  } finally { restore(); }
});

test('the settle probe: a running document animation still blocks, beside scroll-driven ones', async () => {
  const doc = fakeAnimation(1);
  const restore = probe([fakeAnimation(1, new FakeScrollTimeline()), doc]);
  try {
    setTimeout(() => doc.finish(), 15);
    const { trace } = await settleInPage(ARG);
    assert.equal(trace[0].running, 1, 'the document animation is counted while it runs');
    const last = trace[trace.length - 1];
    assert.equal(last.running, 0);
    assert.equal(waitTrace(GATE_POLICY, trace), 'settled@' + (trace.length - 1));
  } finally { restore(); }
});
