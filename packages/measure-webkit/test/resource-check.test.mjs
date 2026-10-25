import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { measuredSign, slowWalk, check, verdict, memFit, footprints } from '../src/resource-check.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const GOLDEN = join(HERE, '../../contracts/golden/engine/resource.jsonl');
const rows = readFileSync(GOLDEN, 'utf8').trim().split('\n').map((l) => JSON.parse(l));

test('every check row: measured sign and check equal Lean', () => {
  const checks = rows.filter((r) => r.kind === 'check');
  assert.ok(checks.length > 0);
  for (const r of checks) {
    const m = measuredSign(r.base, r.arm, r.tol);
    assert.equal(m, r.measured, `${r.flag} ${r.engine} ${r.resource}`);
    assert.equal(check(r.resource, r.slow, r.predicted, m), r.check, `${r.flag} ${r.engine} ${r.resource}`);
  }
});

test('every footprint: verdict equals Lean', () => {
  const fps = footprints(rows);
  assert.equal(fps.length, 18);
  for (const fp of fps) {
    assert.equal(Object.keys(fp.signs).length, 10, fp.flag);
    assert.equal(verdict(fp.signs, fp.budget, fp.peak), fp.verdict, `${fp.flag} ${fp.engine}`);
  }
});

test('every check row cites a footprint sign', () => {
  const fps = new Map(footprints(rows).map((f) => [`${f.flag}|${f.engine}`, f]));
  for (const r of rows.filter((x) => x.kind === 'check')) {
    assert.equal(fps.get(`${r.flag}|${r.engine}`)?.signs[r.resource] ?? 'unknown', r.predicted);
  }
});

test('every bound: its check rows share its unit and change by at most it', () => {
  const bounded = rows.filter((r) => r.kind === 'predict' && r.bound !== null);
  assert.equal(bounded.length, 4);
  for (const b of bounded) {
    for (const c of rows.filter((x) => x.kind === 'check' && x.flag === b.flag && x.engine === b.engine && x.resource === b.resource)) {
      assert.equal(c.unit, b.unit, `${b.flag} ${b.engine} ${b.resource}`);
      assert.ok(Math.max(c.arm.hi - c.base.lo, c.base.hi - c.arm.lo) <= b.bound, `${b.flag} ${b.engine} ${b.resource}`);
    }
  }
});

test('decision examples', () => {
  assert.equal(slowWalk(4077, 6791), true);
  assert.equal(slowWalk(4077, 3646), false);
  assert.equal(memFit(10, 'up', 11), false);
  assert.equal(memFit(10, 'up', null), null);
  const base = { style: 'down', gpuMemory: 'same', layout: 'same', paintRecords: 'same', script: 'same',
    eventDispatch: 'same', repaintArea: 'same', framesRequested: 'same' };
  assert.equal(verdict(base, 10, null), 'win');
  assert.equal(verdict({ ...base, gpuMemory: 'up' }, 10, 11), 'overBudget');
  assert.equal(verdict({ ...base, repaintArea: 'up' }, 10, null), 'trade');
  assert.equal(verdict({ ...base, style: 'same', layers: 'up' }, 10, null), 'neutral');
});
