import test from 'node:test';
import assert from 'node:assert/strict';
import { accelHarnessSource, parseAccel } from '../src/accel-page.mjs';
import { MODES } from '../src/accel-cli.mjs';

test('the harness is one parseable script per mode and carries the shared probe', () => {
  for (const mode of ['scrubbed', 'timed']) {
    const js = accelHarnessSource({ mode });
    assert.doesNotThrow(() => new Function(js));
    assert.match(js, /window\.__fwx/);
    assert.match(js, new RegExp(`"mode":"${mode}"`));
    assert.match(js, /acceleratedAnimationsForElement/);
  }
  assert.throws(() => accelHarnessSource({ mode: 'other' }), /mode/);
});

test('both modes name flag sets the build prerenders (the Chromium half uses the same two)', () => {
  assert.deepEqual(Object.keys(MODES), ['scrubbed', 'timed', 'mid', 'mid-thr-off', 'sweep-thr-off']);
  assert.equal(MODES.scrubbed, 'morph.geom:on');
  assert.equal(MODES.timed, 'morph.geom:on,morph.tween:geom-timed');
});

test('parseAccel reads the report, the error and the done marker', () => {
  const text = ['noise', 'FWWKTR accel {"rows":[1]}', 'FWWKTR done {}'].join('\n');
  assert.deepEqual(parseAccel(text), { report: { rows: [1] }, error: null, done: true });
  const bad = parseAccel('FWWKTR error {"message":"x"}\nFWWKTR done {}');
  assert.equal(bad.report, null);
  assert.equal(bad.error.message, 'x');
});
