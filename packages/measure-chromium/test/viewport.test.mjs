// Conformance of the viewport guard: Lean Fw.Measure.Viewport goldens (packages/contracts/golden/measure/measure.viewport.jsonl)
// through fwcore, through the container twin src/viewport.mjs, and the wiring in src/run.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { fwcoreBin } from '../src/fwcore.mjs';
import { viewportFaithful } from '../src/viewport.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const cases = readFileSync(join(HERE, '../../contracts/golden/measure/measure.viewport.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));

test('viewportFaithful (viewport.mjs) equals every golden of measure.viewport', () => {
  assert.ok(cases.length >= 5);
  for (const c of cases) assert.equal(viewportFaithful(c.request.profile, c.request.observed), c.response.faithful, c.name);
});

test('fwcore answers every measure.viewport golden', () => {
  const input = cases.map((c, i) => JSON.stringify({ ...c.request, id: i })).join('\n') + '\n';
  const r = spawnSync(fwcoreBin(), [], { input, env: { ...process.env, LEAN_ABORT_ON_PANIC: '1' }, maxBuffer: 1 << 24 });
  assert.equal(r.status, 0, `fwcore exit: ${r.stderr}`);
  const got = r.stdout.toString().trim().split('\n').map((l) => { const { id, ...rest } = JSON.parse(l); return rest; });
  assert.deepStrictEqual(got, cases.map((c) => c.response));
});

test('run.mjs calls the guard after the geometry read and records the viewport in meta', () => {
  const src = readFileSync(join(HERE, '../src/run.mjs'), 'utf8');
  const geo = src.indexOf('const geo = await ev(');
  const guard = src.indexOf('viewportGate(SEARCH');
  assert.ok(geo > 0 && guard > geo, 'guard after the geometry read');
  for (const k of ['innerWidthPx', 'innerHeightPx', 'scrollWidthPx', 'visualViewportScale']) assert.ok(src.includes(k + ':'), k);
});
