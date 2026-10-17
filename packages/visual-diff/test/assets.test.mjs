// The TS asset rules must answer every Lean golden case as Lean does (lean/Fw/Gate/Pixel.lean, assetLines).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { fontsLoaded, imagesLoaded } from '../src/assets.mjs';
import { GATE_POLICY, fontsBoth, imagesBoth, presentAny, settled, settledBoth, waitTrace } from '../src/settle-adapter.mjs';

const GOLDEN = resolve(dirname(fileURLToPath(import.meta.url)), '../../contracts/golden/gate/pixel-assets.jsonl');
const cases = readFileSync(GOLDEN, 'utf8').trim().split('\n').map((l) => JSON.parse(l));

test('golden: every Lean asset case', () => {
  assert.ok(cases.length >= 20);
  for (const c of cases) {
    if (c.kind === 'settle') {
      assert.equal(settledBoth(c.a, c.b), c.settled, c.name);
      assert.equal(presentAny(c.a, c.b), c.present, c.name);
      assert.equal(fontsBoth(c.a, c.b), c.fontsLoaded, c.name);
      assert.equal(imagesBoth(c.a, c.b), c.imagesLoaded, c.name);
    } else {
      const got = c.kind === 'images' ? imagesLoaded(c.images) : fontsLoaded(c.families, c.faces);
      assert.equal(got, c.loaded, c.name);
    }
  }
});

test('golden: the arm rule has settled and unsettled, present and absent cases', () => {
  const s = cases.filter((c) => c.kind === 'settle');
  assert.deepEqual([...new Set(s.map((c) => c.settled))].sort(), [false, true]);
  assert.deepEqual([...new Set(s.map((c) => c.present))].sort(), [false, true]);
});

test('settle adapter: the gate predicate and the wait over a trace', () => {
  const p = GATE_POLICY;
  const ok = { running: 0, frames: 2, stable: 3, hoverInside: false, t: 100 };
  assert.equal(settled(p, ok), true);
  assert.equal(settled(p, { ...ok, running: 1 }), false);
  assert.equal(settled(p, { ...ok, frames: 1 }), false);
  assert.equal(settled(p, { ...ok, stable: 2 }), false);
  assert.equal(settled(p, { ...ok, hoverInside: true }), false);
  assert.equal(waitTrace(p, [{ ...ok, running: 1, t: 0 }, ok]), 'settled@1');
  assert.equal(waitTrace(p, [{ ...ok, running: 1, t: 0 }, { ...ok, running: 1, t: 4000 }]), 'unsettled');
  assert.equal(waitTrace(p, []), 'unsettled');
});

test('golden: both outcomes occur for both rules', () => {
  for (const kind of ['images', 'fonts']) {
    assert.deepEqual([...new Set(cases.filter((c) => c.kind === kind).map((c) => c.loaded))].sort(), [false, true], kind);
  }
});
