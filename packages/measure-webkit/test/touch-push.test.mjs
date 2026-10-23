import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openDriver, TOUCH_PUSH } from '../src/touch-push.mjs';
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
  assert.equal(TOUCH_PUSH.cycles, 1);
});
