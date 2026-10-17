import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { stepVectors, compositeGapsNs, fwcoreBin, fwcoreCall } from '../src/handoff.mjs';
import { COUNT_TYPES } from '../src/reduce.mjs';
import { loadStamp } from '../src/load.mjs';

const j = (t) => COUNT_TYPES.indexOf(t);
const row = (o) => COUNT_TYPES.map((t) => o[t] || 0);
const scroll = {
  ys: [0, 300, 600, 900],
  reduced: { perStep: [row({ Layout: 1, Composite: 2 }), row({ Layout: 2 }), row({ Layout: 3, Composite: 1 }), row({ Layout: 4 })], perStepPaintArea: [0, 0, 0, 0] },
  records: [['Composite', 1.0, 1.001, null], ['Composite', 1.0166, 1.018, null], ['Composite', 1.05, null, null], ['Layout', 1.06, 1.07, null]],
  marks: [0.9, 1.1], endTime: 1.2,
};

test('stepVectors: step / zone / total and column selection', () => {
  assert.equal(stepVectors(scroll, 'step').length, 4);
  assert.equal(stepVectors(scroll, 'step')[0].length, COUNT_TYPES.length);
  const z = stepVectors(scroll, 'zone'); // 500 px zones: steps at 0,300 | 600,900(zone 1) -> two zones
  assert.equal(z.length, 2);
  assert.equal(z[0][j('Layout')], 3);
  assert.equal(z[1][j('Layout')], 7);
  assert.deepEqual(stepVectors(scroll, 'total', ['Layout', 'Composite']), [[10, 3]]);
  assert.throws(() => stepVectors(scroll, 'step', ['Nope']), /unknown count type/);
});

test('compositeGapsNs: start-to-start gaps in integer ns', () => {
  const s = { ...scroll, marks: [0.9], endTime: 1.2 };
  assert.deepEqual(compositeGapsNs(s), [16600000, 33400000]);
});

test('loadStamp has the fields the lane records', () => {
  const s = loadStamp();
  assert.ok(typeof s.ts === 'string' && typeof s.load1 === 'number' && s.cpus > 0);
  assert.ok(s.idle === null || (s.idle >= 0 && s.idle <= 100));
});

test('fwcore screen and ticks round trip (skipped when the binary is not built)', async (t) => {
  let bin;
  try { bin = fwcoreBin(); } catch { return t.skip('fwcore not built'); }
  if (!existsSync(bin)) return t.skip('fwcore not built');
  const r = await fwcoreCall([
    { id: 1, op: 'screen', base: [[3, 10], [2, 10]], var: [[1, 10], [2, 10]] },
    { id: 2, op: 'screen', base: [[1]], var: [[1], [2]] },
    { id: 3, op: 'ticks', hz: 60, dtNs: [16666667, 33333334] },
  ], bin);
  assert.equal(r[0].screen, 'dominates');
  assert.match(r[1].error, /not aligned/);
  assert.deepEqual(r[2].ticks, [1, 2]);
});
