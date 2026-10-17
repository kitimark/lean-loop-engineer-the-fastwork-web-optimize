// Conformance of the WebKit A/R alignment with its Lean spec (lean/Fw/Measure/StepAlign.lean, op measure.webkit.align):
//   1. the fwcore binary reproduces every golden line;
//   2. src/align.mjs (glue) sends the request shape Lean expects and prints what Lean replied (no decisions in JS).
// Needs lean/.lake/build/bin/fwcore (cd lean && lake build); FW_CORE_BIN overrides the path.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { runOf, scrollsOf, alignPasses, zoneTable, coverageLine } from '../src/align.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const GOLDEN = join(HERE, '../../contracts/golden/measure/measure.webkit.align.jsonl');
const BIN = process.env.FW_CORE_BIN ?? resolve(HERE, '../../../lean/.lake/build/bin/fwcore');
const load = () => readFileSync(GOLDEN, 'utf8').trim().split('\n').map((l) => JSON.parse(l));

function fwcore(cases) {
  assert.ok(existsSync(BIN), `fwcore not found at ${BIN}; build it with: cd lean && lake build`);
  const input = cases.map((c, i) => JSON.stringify({ ...c.request, id: i })).join('\n') + '\n';
  const r = spawnSync(BIN, [], { input, env: { ...process.env, LEAN_ABORT_ON_PANIC: '1' }, maxBuffer: 1 << 28 });
  assert.equal(r.status, 0, `fwcore exit: ${r.stderr}`);
  assert.equal(r.stderr.length, 0, `fwcore stderr: ${r.stderr}`);
  return r.stdout.toString().trim().split('\n').map((l, i) => { const { id, ...rest } = JSON.parse(l); assert.equal(id, i); return rest; });
}

test('measure.webkit.align: fwcore reproduces every golden line', () => {
  const cases = load();
  assert.ok(cases.length > 0);
  const got = fwcore(cases);
  cases.forEach((c, i) => assert.deepStrictEqual(got[i], c.response, c.name));
});

const scroll = (ys, rows, areas) => ({ ys, reduced: { perStep: rows, perStepPaintArea: areas } });

test('runOf keeps only what the Lean request reads', () => {
  const s = scroll([0, 50], [[1, 2], [3, 4]], [5, 6]);
  assert.deepEqual(runOf(s), { ys: [0, 50], perStep: [[1, 2], [3, 4]], perStepPaintArea: [5, 6] });
});

test('scrollsOf reads determinism passes and perstep entries of one mode', () => {
  const a = scroll([0], [[1]], [0]), b = scroll([0], [[2]], [0]);
  assert.deepEqual(scrollsOf({ passes: [{ scroll: a }, { scroll: b }] }), [a, b]);
  assert.deepEqual(scrollsOf({ entries: [{ mode: 'base', scroll: a }, { mode: 'x', scroll: b }] }, 'x'), [b]);
});

test('alignPasses: pass i of A against pass i of R through fwcore; the longer run keeps unpaired zones', async () => {
  const A = scroll([0, 50, 100, 150, 200, 250], [[1], [2], [3], [4], [5], [6]], [0, 0, 0, 0, 0, 0]);
  const R = scroll([0, 50, 100, 150], [[1], [2], [3], [4]], [0, 0, 0, 0]);
  const res = await alignPasses([A, A], [R, R], 100);
  assert.equal(res.passes, 2);
  assert.equal(res.pairs.length, 2);
  assert.deepEqual(res.pairs[0], res.pairs[1]);
  assert.ok(res.pairs[0].zones.length >= 2);
  // the first zone (y 0..99) holds steps 0 and 50 on both sides, with the same neighbours; R's last step has no next offset
  assert.equal(res.pairs[0].zones[0].full, true);
  assert.equal(res.pairs[0].zones[1].full, false);
});

test('alignPasses refuses an empty side', async () => {
  await assert.rejects(() => alignPasses([], [scroll([0], [[1]], [0])]), /at least one/);
});

test('zoneTable and coverageLine print the reply as it is', () => {
  const pair = {
    zones: [{ y0: 0, stepsA: 2, stepsB: 2, pairedA: 2, full: true, countsA: { Layout: 3 }, countsB: { Layout: 1 }, delta: { Layout: 2 } }],
    paired: { steps: 2 }, full: { zones: 1, steps: 2 },
  };
  assert.equal(zoneTable([pair], 'Layout').split('\n')[2], '| 0 | 2 / 2 | 2 | yes | 3 | 1 | 2 |');
  assert.throws(() => zoneTable([pair], 'Nope'), /unknown count type/);
  assert.match(coverageLine(pair, 2, 2), /zones 1, full 1; paired steps 2 of A 2 \/ R 2; steps in full zones 2/);
});
