// The WebKit live resize keeps the device width (Lean Fw.Gate.WebkitScreen, golden/gate/webkit-screen.jsonl).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { webkitEmulatedSize } from '../src/engines.mjs';
import { loadGen, sweepDefs } from '../src/spec.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/gate/webkit-screen.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const pin = lines.find((l) => l.kind === 'pin');
const stops = lines.filter((l) => l.kind === 'stop');

test('every stop after the first of every sweep has a golden line, with the sizes of spec.mjs', () => {
  const sweeps = sweepDefs(loadGen().gen);
  const want = sweeps.flatMap((s) => s.stops.slice(1).map((e, i) => ({ sweep: s.id, stop: i + 1, e })));
  assert.equal(stops.length, want.length);
  for (const [i, w] of want.entries()) {
    const g = stops[i];
    assert.deepEqual([g.sweep, g.stop], [w.sweep, w.stop]);
    assert.deepEqual([g.width, g.height, g.deviceWidth, g.deviceHeight], [w.e.width, w.e.height, w.e.deviceWidth, w.e.deviceHeight]);
  }
});

test('the harness resize sets the viewport to the stop and the screen to its device size', () => {
  for (const g of stops) {
    const env = { width: g.width, height: g.height, deviceWidth: g.deviceWidth, deviceHeight: g.deviceHeight };
    const size = webkitEmulatedSize(env);
    assert.deepEqual([size.viewport.width, size.viewport.height], [g.width, g.height]);
    assert.deepEqual([size.screen.width, size.screen.height], g.keptScreen);
    assert.equal(g.keptMet, true);
  }
});

test('a plain resize leaves the device width unmet at exactly the two landscape phone stops', () => {
  const unmet = stops.filter((g) => !g.plainMet).map((g) => `${g.sweep}#${g.stop}`);
  assert.deepEqual(unmet, ['phone-rotation#1', 'phone-rotation#3']);
  for (const g of stops) assert.deepEqual(g.plainScreen, [g.width, g.height]);
});

test('playwright-core 1.64.1 still does what the golden pins', () => {
  const dir = dirname(createRequire(import.meta.url).resolve('playwright-core/package.json'));
  const version = JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8')).version;
  assert.equal(`playwright-core@${version}`, pin.package);
  const src = readFileSync(join(dir, pin.file), 'utf8');
  assert.ok(src.includes(`this._setEmulatedSize({ viewport: { ...viewportSize }, ${pin.plainResize} });`), 'page.setViewportSize no longer resets the screen to the viewport');
  assert.ok(src.includes(`${pin.keptResize}(emulatedSize) {`));
  assert.ok(src.includes(`async ${pin.apply}() {`));
  assert.ok(src.includes('screen: emulatedSize.screen') || src.includes('emulatedSize.screen.width'), 'the engine no longer reads the emulated screen');
});
