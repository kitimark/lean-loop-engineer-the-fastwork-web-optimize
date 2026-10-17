// The committed WebKit zone baseline (results/baselines/webkit) is what Lean's measure.zoneBaseline gives for the committed
// zones file and the committed class table, and the gateable types do not drift. Needs fwcore (cd lean && lake build; FWCORE overrides).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { fwcoreCall } from '../src/handoff.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const read = (p) => readFileSync(join(ROOT, p));
const zonesText = read('results/baselines/webkit/original.zones.json');
const zf = JSON.parse(zonesText);
const bf = JSON.parse(read('results/baselines/webkit/original.baseline.json'));
const classText = read(bf.classTable.file);
const table = JSON.parse(classText);
const frozen = (level) => Object.fromEntries(Object.keys(table.byLevel[level]).map((t) => [t, { class: table.byLevel[level][t].class, k: 0, t: 0 }]));

test('baseline file = Lean zoneBaseline of the committed zones file and class table', async () => {
  assert.equal(createHash('sha256').update(zonesText).digest('hex'), bf.source.zonesSha256);
  assert.equal(createHash('sha256').update(classText).digest('hex'), bf.classTable.sha256);
  const [zb, tb] = await fwcoreCall([
    { id: 0, op: 'measure.zoneBaseline', classes: frozen('zone'), runs: zf.runs },
    { id: 1, op: 'measure.zoneBaseline', classes: frozen('total'), runs: zf.runs },
  ]);
  assert.deepEqual(zb.zones, bf.zones);
  assert.deepEqual(zb.detDrift, bf.detDrift);
  assert.deepEqual(tb.totals, bf.totals);
  assert.deepEqual(tb.detDriftTotals, bf.detDriftTotals);
});

test('at least 3 independent VMs; no deterministic cell drifts; gateable zone types are exactly the D/S ones', () => {
  assert.ok(new Set(zf.sessions.map((s) => s.name)).size >= 3);
  assert.deepEqual(bf.detDrift, []);
  assert.deepEqual(bf.detDriftTotals, []);
  const gate = Object.entries(bf.zones[0].types).filter(([, c]) => c.class !== 'quarantined').map(([t]) => t).sort();
  assert.deepEqual(gate, ['Composite', 'EventDispatch', 'RenderingFrame']);
});
