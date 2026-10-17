// Differential runner: fast-check inputs -> TS function and fwcore -> equal outputs, or a shrunk golden-row candidate.
//
// Phase 1 (detect): sample `numRuns` inputs with the fixed seed, send them to fwcore in ONE batch, compare each reply
// with the TS output. Phase 2 (only on a mismatch): rerun the same seed as an async fast-check property against the
// same child, which shrinks the failing input, then write the minimal case as a golden-row candidate
// (`{name, request, response}`, the shape of packages/contracts/golden/**/<op>.jsonl) and fail the test.
//
// Refusals: fwcore answers `{"error":…}` for an input it does not accept ("Lean refuses inputs on which JS would throw or
// misbehave"). Those are skipped, but at least `minAccepted` of the runs must be accepted, so a generator that drifted
// out of the valid domain cannot pass vacuously.
import fc from 'fast-check';
import assert from 'node:assert/strict';
import { appendFileSync, mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { REPO } from './fwcore.mjs';

export const SEED = Number(process.env.DIFFTEST_SEED ?? 20261018);
export const RUNS = Number(process.env.DIFFTEST_RUNS ?? 300);
export const OUT = process.env.DIFFTEST_OUT ?? resolve(REPO, 'packages/difftest/candidates');

/** JSON with sorted keys; -0 and undefined fields vanish as they do on the wire. */
export function canon(v) {
  const norm = (x) => {
    if (Array.isArray(x)) return x.map(norm);
    if (x !== null && typeof x === 'object') return Object.fromEntries(Object.keys(x).sort().filter((k) => x[k] !== undefined).map((k) => [k, norm(x[k])]));
    return x;
  };
  return JSON.stringify(norm(v));
}

/** Project a Lean reply onto the fields the TS function returns (for ops whose Lean reply is richer). */
export const sameKeys = (reply, tsOut) => Object.fromEntries(Object.keys(tsOut ?? {}).map((k) => [k, reply[k]]));

function judge(input, reply, ts, project, compareErrors = false) {
  if (reply.error !== undefined && !compareErrors) return { refused: true };
  let out;
  try { out = ts(structuredClone(input)); } catch (e) { return { ok: false, got: `TS threw: ${e.message}`, want: canon(reply) }; }
  const want = canon(project(reply, out));
  const got = canon(out);
  return { ok: got === want, got, want };
}

/**
 * @param {object} spec
 * @param {string} spec.op wire op
 * @param {import('fast-check').Arbitrary<object>} spec.arb request fields (without `op`)
 * @param {(input: object) => unknown} spec.ts the TS function, as a reply object
 * @param {(reply: object, tsOut: unknown) => unknown} [spec.project] Lean reply -> compared part
 * @param {string} [spec.label] candidate name prefix (default: op)
 * @param {number} [spec.minAccepted] fraction of runs that must be accepted by Lean
 * @param {boolean} [spec.compareErrors] a Lean refusal is compared with the TS output too (the TS returns `{error}`)
 */
export async function differential(core, { op, arb, ts, project = (r) => r, label = op, minAccepted = 0.5, compareErrors = false, numRuns = RUNS, seed = SEED }) {
  const inputs = fc.sample(arb, { numRuns, seed });
  const replies = await core.batch(inputs.map((i) => ({ op, ...i })));
  let accepted = 0;
  let bad = -1;
  for (let i = 0; i < inputs.length; i++) {
    const j = judge(inputs[i], replies[i], ts, project, compareErrors);
    if (j.refused) continue;
    accepted++;
    if (!j.ok && bad < 0) bad = i;
  }
  if (bad >= 0) {
    // Phase 2: shrink. The same seed and run count reproduce the failing sample, then fast-check shrinks it.
    const r = await fc.check(fc.asyncProperty(arb, async (input) => {
      const reply = await core.call({ op, ...input });
      const j = judge(input, reply, ts, project, compareErrors);
      return j.refused || j.ok;
    }), { numRuns, seed });
    const input = r.failed ? r.counterexample[0] : inputs[bad];
    const reply = await core.call({ op, ...input });
    const j = judge(input, reply, ts, project, compareErrors);
    const row = { name: `difftest ${label}: TS and Lean differ (seed ${seed}, TS gives ${j.got}, Lean gives ${j.want})`, request: { op, ...input }, response: reply };
    mkdirSync(OUT, { recursive: true });
    appendFileSync(join(OUT, `${op}.jsonl`), JSON.stringify(row) + '\n');
    assert.fail(`${op}: TS differs from fwcore (seed ${seed}, shrunk).\n  request: ${JSON.stringify(row.request)}\n  TS:      ${j.got}\n  Lean:    ${j.want}\n  candidate golden row appended to ${join(OUT, `${op}.jsonl`)}`);
  }
  assert.ok(accepted >= Math.ceil(numRuns * minAccepted), `${op}: only ${accepted}/${numRuns} generated inputs were accepted by fwcore; the generator left the valid domain`);
  const stat = { op, runs: numRuns, accepted, refused: numRuns - accepted, seed };
  console.log(`difftest ${JSON.stringify(stat)}`);
  return stat;
}
