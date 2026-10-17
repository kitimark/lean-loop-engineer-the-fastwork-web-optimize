// Conformance: the measure.* golden vectors (generated from Lean, packages/contracts/golden/measure/) through the fwcore
// binary. Since fwcore matched them (and the stored zones of three real 503-frame runs), the TS zoneSums is gone: zones
// and classes come from fwcore only (src/fwcore.mjs). Needs lean/.lake/build/bin/fwcore (cd lean && lake build).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { fwcoreBin, zoneSums } from '../src/fwcore.mjs';

const GOLDEN = join(dirname(fileURLToPath(import.meta.url)), '../../contracts/golden/measure');
const load = (op) => readFileSync(join(GOLDEN, `${op}.jsonl`), 'utf8').trim().split('\n').map((l) => JSON.parse(l));

/** All requests of one file in one fwcore process; replies without ids. */
function replies(cases) {
  const input = cases.map((c, i) => JSON.stringify({ ...c.request, id: i })).join('\n') + '\n';
  const r = spawnSync(fwcoreBin(), [], { input, env: { ...process.env, LEAN_ABORT_ON_PANIC: '1' }, maxBuffer: 1 << 28 });
  assert.equal(r.status, 0, `fwcore exit: ${r.stderr}`);
  assert.equal(r.stderr.length, 0, `fwcore stderr: ${r.stderr}`);
  return r.stdout.toString().trim().split('\n').map((l, i) => { const { id, ...rest } = JSON.parse(l); assert.equal(id, i); return rest; });
}

for (const op of ['measure.zoneSums', 'measure.classify', 'measure.noMoreWork']) {
  test(`${op}: fwcore reproduces every golden line`, () => {
    const cases = load(op);
    assert.ok(cases.length > 0);
    const got = replies(cases);
    cases.forEach((c, i) => assert.deepStrictEqual(got[i], c.response, c.name));
  });
}

test('zoneSums through the client: the pure.test.mjs seed vector', () => {
  const frames = [
    { n: 0, phase: 'rest', scrollY: 0, counts: { a: 1, b: 2 } },
    { n: 1, phase: 'swipe', scrollY: 10, counts: { a: 1, b: 0 } },
    { n: 2, phase: 'swipe', scrollY: 490, counts: { a: 2, b: 1 } },
    { n: 3, phase: 'swipe', scrollY: 500, counts: { a: 4, b: 1 } },
    { n: 4, phase: 'tail', scrollY: 500, counts: { a: 0, b: 7 } },
  ];
  const z = zoneSums(frames, 500);
  assert.deepEqual(z.map((x) => x.id), ['rest', 'y00000', 'y00500', 'tail']);
  assert.deepEqual(z.map((x) => x.frames), [1, 2, 1, 1]);
  assert.deepEqual(z.map((x) => x.scrolledPx), [0, 490, 10, 0]);
  assert.deepEqual(z[1].sums, { a: 3, b: 1 });
  assert.equal(z.reduce((s, x) => s + x.sums.a, 0), 8);
});
