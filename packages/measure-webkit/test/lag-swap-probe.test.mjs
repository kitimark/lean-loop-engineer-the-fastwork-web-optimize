import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { WATCH_JS, FIND_JS, DIAG_JS, ORDER, FLIPPED, bucketRows, jobMeta } from '../src/lag/swapprobe.mjs';

async function watch(periods, children, script, deadlineMs = 50) {
  const marks = [];
  let callback = null;
  const el = { childElementCount: children, getAttribute: () => 'crop' };
  const fire = (n) => { el.childElementCount = n; callback?.(); };
  const sandbox = {
    document: { querySelector: () => el },
    MutationObserver: class { constructor(cb) { callback = cb; } observe() {} disconnect() { callback = null; } },
    performance: { mark: (m) => marks.push(m) },
    setTimeout, clearTimeout,
  };
  const done = vm.runInNewContext(WATCH_JS(periods, deadlineMs), sandbox);
  await new Promise((r) => setImmediate(r));
  script(fire);
  return { res: await done, marks };
}

test('every swap is marked on and off, and the watcher stops after the asked number of windows', async () => {
  const { res, marks } = await watch(2, 4, (fire) => { fire(5); fire(4); fire(5); fire(4); });
  assert.deepEqual(marks, ['wk:begin', 'wk:on0', 'wk:off0', 'wk:on1', 'wk:off1', 'wk:end']);
  assert.deepEqual([res.why, res.closed, res.open, res.variant], ['full', 2, false, 'crop']);
});

test('a swap already running when the watcher starts is not counted, a window left open at the deadline is reported open', async () => {
  const { res, marks } = await watch(3, 5, (fire) => { fire(5); fire(4); fire(5); }, 30);
  assert.deepEqual(marks, ['wk:begin', 'wk:on0', 'wk:end']);
  assert.deepEqual([res.why, res.closed, res.open], ['deadline', 0, true]);
});

test('the pass order has the two faithful captures as slots a and b, the flipped order the same captures crop first', () => {
  assert.deepEqual(ORDER.map(([a, s]) => `${a}-${s}`), ['faithful-a', 'crop-a', 'faithful-b', 'crop-b']);
  assert.deepEqual(FLIPPED.map(([a, s]) => `${a}-${s}`), ['crop-a', 'faithful-a', 'crop-b', 'faithful-b']);
});

function find(maxY, { reduced = false, docTop = 1000 } = {}) {
  let y = 0;
  const el = { childElementCount: 4, getBoundingClientRect: () => ({ top: docTop - y, bottom: docTop - y + 32, width: 120 }) };
  const sandbox = {
    document: { querySelector: () => el },
    matchMedia: () => ({ matches: reduced }),
    innerHeight: 800,
    requestAnimationFrame: (cb) => setImmediate(() => cb(0)),
    scrollTo: ({ top }) => { y = top; },
    get scrollY() { return y; },
  };
  return vm.runInNewContext(FIND_JS(maxY), sandbox);
}

test('the scroll search stops at the first scroll position that shows the whole carousel', async () => {
  const r = await find(5000);
  assert.ok(r.y > 0 && r.top >= 0 && r.bottom <= 800, JSON.stringify(r));
  assert.equal(r.reduced, false);
});

test('the scroll search reports a carousel that never comes into view, and reduced motion', async () => {
  const r = await find(500, { reduced: true, docTop: 3000 });
  assert.match(r.error, /never/);
  assert.equal(r.reduced, true);
});

test('Timeline rows are counted per bucket from the page mark, rows outside the span are dropped', () => {
  const rows = [['Layout', 10.0], ['Layout', 10.05], ['Layout', 10.12], ['Paint', 10.12], ['Layout', 9.9], ['Layout', 10.4], ['Layout', 'x']];
  assert.deepEqual(bucketRows(rows, 'Layout', 10, 100, 3), [2, 1, 0]);
  assert.deepEqual(bucketRows(rows, 'Paint', 10, 100, 3), [0, 1, 0]);
});

test('a sample knows its CI job from the default GitHub variables and the matrix cell', () => {
  assert.deepEqual(jobMeta({ GITHUB_RUN_ID: '9', GITHUB_RUN_ATTEMPT: '1', GITHUB_JOB: 'sim', VM: 'r2', GITHUB_SHA: 'abc' }),
    { run: '9', attempt: '1', job: 'sim', vm: 'r2', jobId: null, sha: 'abc' });
  assert.equal(jobMeta({ FW_JOB_ID: '123' }).jobId, '123');
});

test('the diagnostic watch counts mutations per owner and bucket and lists the running animations', async () => {
  let callback = null, now = 0;
  const owned = (name) => ({ nodeType: 1, closest: () => ({ getAttribute: () => name }), tagName: 'DIV' });
  const anim = { animationName: 'spin', constructor: { name: 'CSSAnimation' }, playState: 'running', effect: { target: owned('deck'), getKeyframes: () => [{ offset: 0, transform: 'a' }, { offset: 1, transform: 'b' }], getComputedTiming: () => ({ duration: 4000, iterations: Infinity }) } };
  const marks = [];
  const sandbox = {
    document: { documentElement: {}, getAnimations: () => [anim, anim] },
    MutationObserver: class { constructor(cb) { callback = cb; } observe() {} disconnect() { callback = null; } },
    performance: { mark: (m) => marks.push(m), now: () => now },
    setTimeout: (f, ms) => setTimeout(f, 20),
  };
  const done = vm.runInNewContext(DIAG_JS(300, 100), sandbox);
  await new Promise((r) => setImmediate(r));
  now = 150;
  callback([{ target: owned('pain'), type: 'attributes', attributeName: 'style' }, { target: owned('pain'), type: 'attributes', attributeName: 'style' }, { target: owned('people-carousel'), type: 'childList' }]);
  const res = JSON.parse(JSON.stringify(await done));
  assert.deepEqual(marks, ['wk:dbegin', 'wk:dend']);
  assert.deepEqual(res.owners, { 'pain:style': [0, 2, 0], 'people-carousel:childList': [0, 1, 0] });
  assert.deepEqual(res.before, { 'deck|spin|CSSAnimation|running|4000|Infinity|transform': 2 });
  assert.equal(res.buckets, 3);
});
