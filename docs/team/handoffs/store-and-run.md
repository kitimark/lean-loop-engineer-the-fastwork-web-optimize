# Handoff: store-and-run (console-builder)

State: branch `worktree-agent-a44f38a8082229230`; `sh lean/scripts/check.sh` green (includes fwtest, mathview 0 failing),
`pnpm --filter ./apps/runner test` green (94 tests). `tsc` of runner shows 2 older errors in test/spawn-guard.test.ts (`kinds`), not ours.

What exists
- Lean `lean/Fw/Store/`: `Reduce.lean` (store.reduce: classify base runs, union of types, verdict; proofs reduceOk_iff/sound, overall_iff),
  `Layout.lean` (Engine, objectPath + objectPath_inj, Manifest.problems, keyPairs + keyPairs_inj, Request/plan/blocked,
  cache hit/miss, workflow inputs table), `Golden.lean` (namespace Fw.Wire.Store.Golden: the mathview lint skips Fw.Wire.*).
- Wire ops `store.plan|manifest|objectPath|reduce` in `lean/Fw/Wire/Store.lean`; goldens in `packages/contracts/golden/store/*.jsonl`
  (regenerate: `cd lean && lake env lean --run scripts/StoreGolden.lean`; lake test checks them).
- Contracts `packages/contracts/src/artifacts.ts` (exported from index.ts).
- `fw run` in `apps/runner/src/run.ts` (+ `fw.ts` dispatch): `--dry` prints the plan; otherwise gh dispatch -> watch -> headSha check ->
  download -> ingest into `.fw-console/store/` (objects/<2>/<62>, runs/<sha256 of key JSON>/manifest.json).

Decisions
- Blocked, not guessed: chromium-counts.yml has inputs {profile, runs}; webkit-sim.yml {vms, sessions, fresh_boot}. Neither takes `preset` or
  `fw`, so a non-default preset/fw/profile job is reported BLOCKED (exit 2) until the workflow gains the input (Lean table
  `workflowInputs` in Layout.lean). `--from-run engine=<id>` ingests an existing run without dispatch.
- Run key = sha256(JSON of Lean `keyPairs`); the hash is TS (assumption: no collisions).

TS stand-ins: sha256 + file copy/walk, gh process calls, polling for the new run id. No decision logic in TS.
Open: add `preset`/`fw` workflow_dispatch inputs; call `store.reduce` from the console verdict path (reduceArms exists in run.ts, unused by CLI);
swap the 2 untouched lines in `lean/Fw.lean`, `Wire.lean`, `FwTestMain.lean`, `contracts/src/index.ts` if they conflict on merge (import + op-list lines).
Read first: lean/Fw/Store/Layout.lean docstring, apps/runner/src/run.ts.
