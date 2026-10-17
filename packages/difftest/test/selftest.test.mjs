// Negative control: a TS function that is wrong on purpose must be caught, shrunk and written as a golden-row candidate.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import fc from 'fast-check';
import { FwCore } from '../src/fwcore.mjs';

let core;
before(() => { core = new FwCore(); });
after(() => core.close());

test('a wrong symDiff (ignores multiplicity) is caught and shrunk to a minimal candidate', async () => {
  const wrong = ({ a, b }) => ({ symDiff: new Set([...a.filter((x) => !b.includes(x)), ...b.filter((x) => !a.includes(x))]).size });
  const out = mkdtempSync(join(tmpdir(), 'difftest-'));
  process.env.DIFFTEST_OUT = out; // diff.mjs reads it at import time: a fresh instance of the module
  const { differential } = await import(`../src/diff.mjs?out=${encodeURIComponent(out)}`);
  await assert.rejects(differential(core, {
    op: 'measure.symDiff',
    arb: fc.record({ a: fc.array(fc.constantFrom('a', 'b'), { maxLength: 6 }), b: fc.array(fc.constantFrom('a', 'b'), { maxLength: 6 }) }),
    ts: wrong,
  }), /TS differs from fwcore/);
  const row = JSON.parse(readFileSync(join(out, 'measure.symDiff.jsonl'), 'utf8').trim().split('\n')[0]);
  assert.equal(row.request.op, 'measure.symDiff');
  assert.ok(row.request.a.length + row.request.b.length <= 3, `not minimal: ${JSON.stringify(row.request)}`);
  assert.ok(row.response.symDiff !== undefined);
});
