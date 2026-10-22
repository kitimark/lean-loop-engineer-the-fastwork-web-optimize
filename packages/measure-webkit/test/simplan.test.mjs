// Glue of the webkit-sim plan (src/simplan.mjs) against the Lean goldens of measure.simPlan
// (lean/Fw/Measure/SimPlan.lean): the request it builds is the shape Lean reads, the outputs it writes are Lean's reply, and
// a refused request throws with Lean's problems. Needs lean/.lake/build/bin/fwcore; FW_CORE_BIN overrides the path.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { planRequest, outputsOf, simPlan } from '../src/simplan.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const GOLDEN = join(HERE, '../../contracts/golden/measure/measure.simPlan.jsonl');
const BIN = process.env.FW_CORE_BIN ?? resolve(HERE, '../../../lean/.lake/build/bin/fwcore');
const load = () => readFileSync(GOLDEN, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const envOf = (q) => ({ TARGET: q.target, VMS: q.vms, SESSIONS: q.sessions, PRESET: q.preset, FW: q.fw, EXPERIMENT: q.experiment, SHA: q.sha });

function fwcore(cases) {
  assert.ok(existsSync(BIN), `fwcore not found at ${BIN}; build it with: cd lean && lake build`);
  const input = cases.map((c, i) => JSON.stringify({ ...c.request, id: i })).join('\n') + '\n';
  const r = spawnSync(BIN, [], { input, env: { ...process.env, LEAN_ABORT_ON_PANIC: '1' }, maxBuffer: 1 << 28 });
  assert.equal(r.status, 0, `fwcore exit: ${r.stderr}`);
  assert.equal(r.stderr.length, 0, `fwcore stderr: ${r.stderr}`);
  return r.stdout.toString().trim().split('\n').map((l, i) => { const { id, ...rest } = JSON.parse(l); assert.equal(id, i); return rest; });
}

test('measure.simPlan: fwcore reproduces every golden line', () => {
  const cases = load();
  assert.ok(cases.length > 0);
  const got = fwcore(cases);
  cases.forEach((c, i) => assert.deepStrictEqual(got[i], c.response, c.name));
});

test('the request built from the environment is the golden request', () => {
  for (const c of load()) {
    const { id, ...q } = planRequest(envOf(c.request));
    assert.deepStrictEqual(q, c.request, c.name);
  }
});

test("outputs are Lean's reply; a refusal throws with the problems", async () => {
  for (const c of load()) {
    const call = async () => [c.response];
    if (c.response.problems.length) {
      await assert.rejects(simPlan(envOf(c.request), call), (e) => c.response.problems.every((p) => e.message.includes(p)), c.name);
    } else {
      const o = await simPlan(envOf(c.request), call);
      assert.deepStrictEqual(JSON.parse(o.matrix).include, c.response.matrix, c.name);
      assert.equal(o.search, c.response.search);
      assert.equal(o.both, String(c.response.both));
      assert.equal(o.step_min, String(c.response.stepTimeoutMin));
      assert.equal(o.job_min, String(c.response.jobTimeoutMin));
      assert.equal(o.stall_ms, String(c.response.stallMs));
      assert.equal(o.watchdog_min, String(c.response.watchdogMin));
      assert.equal(o.term_grace_ms, String(c.response.termGraceMs));
    }
  }
  assert.deepStrictEqual(outputsOf({ matrix: [], search: '', original: true, rewrite: false, both: false, stepTimeoutMin: 35, jobTimeoutMin: 45, stallMs: 720000, watchdogMin: 33, termGraceMs: 20000 }),
    { matrix: '{"include":[]}', search: '', original: 'true', rewrite: 'false', both: 'false', step_min: '35', job_min: '45', stall_ms: '720000', watchdog_min: '33', term_grace_ms: '20000' });
});
