// Conformance of src/reduce.mjs with its Lean spec (lean/Fw/Measure/WebKit.lean). The golden vectors in
// packages/contracts/golden/measure/ are generated from Lean; every line is checked twice:
//   1. the fwcore binary (Lean) reproduces the golden reply, and
//   2. the TS function in src/reduce.mjs gives the same value (error cases are Lean-only refusals and skipped here).
// Needs lean/.lake/build/bin/fwcore (cd lean && lake build); FW_CORE_BIN overrides the path.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { quietReply } from '../src/quietsteps.mjs';
import { tally, reduceSteps, zones, classify, symDiff, summarize } from '../src/reduce.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const GOLDEN = join(HERE, '../../contracts/golden/measure');
const BIN = process.env.FW_CORE_BIN ?? resolve(HERE, '../../../lean/.lake/build/bin/fwcore');
const load = (op) => readFileSync(join(GOLDEN, `${op}.jsonl`), 'utf8').trim().split('\n').map((l) => JSON.parse(l));

function fwcore(cases) {
  assert.ok(existsSync(BIN), `fwcore not found at ${BIN}; build it with: cd lean && lake build`);
  const input = cases.map((c, i) => JSON.stringify({ ...c.request, id: i })).join('\n') + '\n';
  const r = spawnSync(BIN, [], { input, env: { ...process.env, LEAN_ABORT_ON_PANIC: '1' }, maxBuffer: 1 << 28 });
  assert.equal(r.status, 0, `fwcore exit: ${r.stderr}`);
  assert.equal(r.stderr.length, 0, `fwcore stderr: ${r.stderr}`);
  return r.stdout.toString().trim().split('\n').map((l, i) => { const { id, ...rest } = JSON.parse(l); assert.equal(id, i); return rest; });
}

// op -> TS function of the request, giving the reply object (or undefined to skip)
const TS = {
  'measure.webkit.tally': (q) => tally(q.rows),
  'measure.webkit.reduceSteps': (q) => reduceSteps(q.rows, q.marks, q.endTime),
  'measure.webkit.zones': (q) => ({ zones: q.zonePx === undefined ? zones(q.ys, q.perStep, q.perStepPaintArea) : zones(q.ys, q.perStep, q.perStepPaintArea, q.zonePx) }),
  'measure.symDiff': (q) => ({ symDiff: symDiff(q.a, q.b) }),
  'measure.summarize': (q) => ({ summary: summarize(q.rows.map((r) => ({ ...r }))).map(({ family, metric, levels, worst }) => ({ family, metric, levels, worst })) }),
  'measure.quietSteps': (q) => quietReply(q),
  'measure.classify': (q) => (q.mode === 'cells' ? classify(q.runs, q.tol) : undefined),
};

for (const op of Object.keys(TS)) {
  test(`${op}: fwcore reproduces every golden line`, () => {
    const cases = load(op);
    assert.ok(cases.length > 0);
    const got = fwcore(cases);
    cases.forEach((c, i) => assert.deepStrictEqual(got[i], c.response, c.name));
  });
  test(`${op}: src/reduce.mjs agrees with the Lean goldens`, () => {
    let n = 0;
    for (const c of load(op)) {
      if (c.response.error !== undefined) continue; // Lean refuses inputs on which JS would throw or misbehave
      const ts = TS[op](c.request);
      if (ts === undefined) continue;
      // cell mode: Lean also reports the frame-sense maxima k, t (not in JS)
      const want = op === 'measure.classify' ? Object.fromEntries(Object.keys(ts).map((k) => [k, c.response[k]])) : c.response;
      assert.deepStrictEqual(ts, want, c.name);
      n++;
    }
    assert.ok(n > 0);
  });
}
