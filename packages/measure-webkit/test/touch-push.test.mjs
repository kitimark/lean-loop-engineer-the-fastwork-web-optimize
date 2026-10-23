import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openDriver, touchWindow, TOUCH_PUSH } from '../src/touch-push.mjs';
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

test('touchWindow: asks the server for push n, waits for done-n, stops the page loop and returns the page value', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'fw-touch-'));
  const server = { dir, next: 3, run: { state: { ended: false } } };
  const calls = [];
  const c = {
    evaluate: async (js) => { calls.push(js); if (js.includes('__fwTouchStop = true')) writeFileSync(join(dir, 'seen-stop'), ''); return true; },
    runAsync: async () => { writeFileSync(join(dir, 'done-3'), ''); return { begun: true }; },
  };
  const got = await touchWindow(c, { server, pageJs: '1', tailMs: 1, lostMs: 1000 });
  assert.deepEqual(got, { pushed: true, result: { begun: true } });
  assert.equal(server.next, 4);
  assert.equal(calls.length, 2);
  const dead = { dir, next: 9, run: { state: { ended: true } } };
  const lost = await touchWindow({ evaluate: async () => true, runAsync: () => new Promise(() => {}) }, { server: dead, pageJs: '1', tailMs: 1, lostMs: 20 });
  assert.equal(lost.pushed, false);
  assert.match(lost.error, /did not answer/);
});
