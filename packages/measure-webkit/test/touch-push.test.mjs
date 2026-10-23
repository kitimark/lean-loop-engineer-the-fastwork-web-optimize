import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readFileSync } from 'node:fs';
import { openDriver, touchWindow, TOUCH_PUSH, TOUCH_BUDGET, TOUCH_COUNT_JS, classifyWindow, doneInTime, laneAfter, spent, windowCap, timelinePlan, variantFor } from '../src/touch-push.mjs';
import { endTouchJs } from '../src/profile/recorder.mjs';

test('openDriver: no directory or an unbuilt one gives a reason without a home path, a built one gives the xctestrun', () => {
  assert.deepEqual(openDriver(undefined), { driver: null, why: 'no driver directory given' });
  const empty = mkdtempSync(join(tmpdir(), 'fw-touch-'));
  const r = openDriver(empty);
  assert.equal(r.driver, null);
  assert.match(r.why, /^driver not built/);
  const built = mkdtempSync(join(tmpdir(), 'fw-touch-'));
  mkdirSync(join(built, 'dd', 'Build', 'Products'), { recursive: true });
  writeFileSync(join(built, 'dd', 'Build', 'Products', 'FwThrottleDriver.xctestrun'), '');
  assert.equal(openDriver(built).driver.xctestrun, join(built, 'dd', 'Build', 'Products', 'FwThrottleDriver.xctestrun'));
});

test('endTouchJs is one parseable async expression that starts the recorder on the first touchstart', () => {
  assert.doesNotThrow(() => new Function(`return ${endTouchJs}`));
  assert.match(endTouchJs, /touchstart.*st\.start\(\)/s);
  assert.equal(TOUCH_PUSH.holdMs, 1000);
});

const pageTouch = (over = {}) => ({ begun: true, touch: { starts: 2, moves: 12, ends: 2, firstAt: Date.now(), lastEndAt: Date.now() + 3000, ...over } });

test('touchWindow: writes go-n with the variant, waits for done-n, returns the page value and the Lean observation', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'fw-touch-'));
  const server = { dir, next: 3, run: { state: { ended: false } } };
  const calls = [];
  const c = {
    evaluate: async (js) => { calls.push(js); return true; },
    runAsync: async () => { writeFileSync(join(dir, 'done-3'), 'ok 3100 3200'); return pageTouch(); },
  };
  const got = await touchWindow(c, { server, pageJs: '1', variant: 'safari' });
  assert.equal(readFileSync(join(dir, 'go-3'), 'utf8'), 'safari');
  assert.equal(got.pushed, true);
  assert.equal(got.outcome, 'ok');
  assert.deepEqual(got.presses, [3100, 3200]);
  assert.equal(got.obs.swipeAt, 3000);
  assert.equal(got.obs.moves, 12);
  assert.equal(got.obs.answered, true);
  assert.equal(server.next, 4);
  assert.equal(calls.length, 1);
});

test('touchWindow: a page that never ends is stopped at the deadline, a page that never answers is lost after answerMs, a dead server ends the wait', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'fw-touch-'));
  const budget = { ...TOUCH_BUDGET, beginMs: 20, swipeMs: 20, tailMs: 1, answerMs: 40, doneMs: 20 };
  const calls = [];
  const dead = { dir, next: 9, run: { state: { ended: true } } };
  const lost = await touchWindow({ evaluate: async (js) => { calls.push(js); return true; }, runAsync: () => new Promise(() => {}) }, { server: dead, pageJs: '1', budget });
  assert.equal(lost.pushed, false);
  assert.match(lost.error, /did not answer/);
  assert.equal(lost.outcome, 'pageLost');
  assert.ok(calls.some((js) => js.includes('__fwTouchStop = true')));
  const late = await touchWindow({ evaluate: async () => true, runAsync: async () => ({ begun: false, touch: null }) }, { server: { dir, next: 1, run: { state: { ended: true } } }, pageJs: '1', budget });
  assert.equal(late.outcome, 'beginLate');
  assert.equal(late.obs.beginAt, null);
});

test('touchCountJs is parseable and ends the window on the second touchend', () => {
  assert.doesNotThrow(() => new Function(TOUCH_COUNT_JS));
  assert.match(TOUCH_COUNT_JS, /\+\+w\.ends === 2/);
  assert.match(TOUCH_COUNT_JS, /600\)/);
});

test('variantFor cycles the list and refuses an unknown name', () => {
  assert.equal(variantFor(0, undefined), 'springboard');
  assert.deepEqual([0, 1, 2].map((i) => variantFor(i, 'safari, springboard')), ['safari', 'springboard', 'safari']);
  assert.throws(() => variantFor(0, 'finger'), /unknown touch variant/);
});

const golden = readFileSync(new URL('../../contracts/golden/measure/touch-push.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));

test('touch-push stand-ins replay the Lean golden', () => {
  const b = TOUCH_BUDGET;
  let n = 0;
  for (const g of golden) {
    if (g.op === 'constants') {
      for (const k of ['readyMs', 'beginMs', 'swipeMs', 'tailMs', 'answerMs', 'doneMs']) assert.equal(b[k], g[k], k);
      assert.equal(windowCap(b), g.windowCap);
    } else if (g.op === 'classify') {
      assert.equal(classifyWindow(b, g.obs), g.out, g.case);
      assert.equal(doneInTime(b, g.obs), g.doneInTime, g.case);
      assert.equal(laneAfter(b, true, g.obs), g.laneAfter, g.case);
      assert.equal(spent(b, g.obs), g.spent, g.case);
    } else if (g.op === 'lane') {
      let on = true;
      let time = 0;
      let failures = 0;
      for (const o of g.obs) {
        if (!on) break;
        time += spent(b, o) + b.doneMs;
        if (classifyWindow(b, o) !== 'ok') failures++;
        on = laneAfter(b, on, o);
      }
      assert.deepEqual({ time, failures }, { time: g.time, failures: g.failures }, g.case);
    } else if (g.op === 'timelinePlan') {
      const p = timelinePlan(g.touch, g.stopMs);
      assert.equal(p.kind === 'off' ? 'off' : `stopWithin ${p.ms}`, g.out);
    } else assert.fail(`unknown op ${g.op}`);
    n++;
  }
  assert.equal(n, golden.length);
  assert.ok(golden.some((g) => g.op === 'lane') && golden.some((g) => g.op === 'timelinePlan'));
});
