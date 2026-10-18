// Conformance: the faithful.verdict golden vectors (generated from Lean, packages/contracts/golden/faithful/) through the
// fwcore binary, and the region helper of src/faithful.mjs. Needs lean/.lake/build/bin/fwcore (cd lean && lake build).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { fwcoreBin } from '../src/fwcore.mjs';
import { REGION, regionOf, summarize } from '../src/faithful.mjs';

const GOLDEN = join(dirname(fileURLToPath(import.meta.url)), '../../contracts/golden/faithful');
const cases = readFileSync(join(GOLDEN, 'faithful.verdict.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));

function replies() {
  const input = cases.map((c, i) => JSON.stringify({ ...c.request, id: i })).join('\n') + '\n';
  const r = spawnSync(fwcoreBin(), [], { input, env: { ...process.env, LEAN_ABORT_ON_PANIC: '1' }, maxBuffer: 1 << 28 });
  assert.equal(r.status, 0, `fwcore exit: ${r.stderr}`);
  assert.equal(r.stderr.length, 0, `fwcore stderr: ${r.stderr}`);
  return r.stdout.toString().trim().split('\n').map((l, i) => { const { id, ...rest } = JSON.parse(l); assert.equal(id, i); return rest; });
}

test('every faithful.verdict golden equals the fwcore reply', () => {
  assert.ok(cases.length >= 10);
  const got = replies();
  cases.forEach((c, i) => assert.deepStrictEqual(got[i], c.response, c.name));
});

test('the goldens pin both outcomes and the refusal', () => {
  const pass = cases.filter((c) => c.response.pass === true).length;
  const fail = cases.filter((c) => c.response.pass === false).length;
  const err = cases.filter((c) => c.response.error !== undefined).length;
  assert.ok(pass >= 2 && fail >= 5 && err === 1, `pass ${pass} fail ${fail} error ${err}`);
});

test('regionOf keeps exactly the region zones, in file order', () => {
  const zones = ['rest', 'y03500', 'tail', 'y04000', 'y04500'].map((id) => ({ id }));
  assert.deepStrictEqual(regionOf({ zones }).map((z) => z.id), ['tail', 'y04000', 'y04500']);
  assert.deepStrictEqual(REGION, ['y04000', 'y04500', 'tail']);
});

test('summarize lists failed cells and unbanded differences only', () => {
  const v = { pass: false, failedZones: ['tail'], zones: [{ id: 'tail', present: true, shape: true, pass: false, framesA: 3, framesR: 3,
    pxA: 0, pxR: 0, tally: {}, failed: ['x'], cells: { x: { family: 'exact', status: 'fail', lo: 1, hi: 1, a: 1, r: 2 },
      y: { family: 'unbanded', status: 'unbanded', lo: 1, hi: 1, a: 1, r: 1 }, z: { family: 'unbanded', status: 'unbanded', lo: 1, hi: 1, a: 1, r: 4 },
      p: { family: 'exact', status: 'pass', lo: 1, hi: 1, a: 1, r: 1 } } }] };
  const s = summarize(v).zones[0];
  assert.deepStrictEqual(s.offBand.map((c) => c.type), ['x']);
  assert.deepStrictEqual(s.unbandedDiffs, [{ type: 'z', a: 1, r: 4 }]);
});
