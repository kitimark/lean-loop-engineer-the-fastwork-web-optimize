# Handoff: store-cirun (lean-prover)

State: worktree branch, one commit with trailer `Task: store-cirun`. `lean/scripts/check.sh` green, runner 134 tests green.

What exists
- `lean/Fw/Store/Ci.lean`: spec of `store.ciRun` (run selection, shard jobs `counts (<target>, r<n>)`, refusals,
  shards-agree check, rewrite query -> preset/flags, key inputs `ciReq : Req` per target). Theorems: `ciRun_refused`
  (refused => no store key), `ciRun_accepted_run`, `ciRun_accepted_got`, `ciRun_accepted_req`, `ciRun_targets_nodup`,
  `ciRun_shard_target`, `ciRun_req_target`, `ciRun_key_ne` (shards of different targets => different keyPairs, via
  `keyPairs_target_ne`), `ciRun_keys_nodup`.
- Wire op in `lean/Fw/Wire/Store.lean` (`opCiRun`, table row in the header). Two calls: without `artifacts` = check
  before the download; with `artifacts` [{name, profile, image, search?, target?}] + `classes` = full check plus
  `meta` (ingest fields) and `key` per target. Goldens: `packages/contracts/golden/store/ciRun.jsonl` (14 cases).
- `apps/runner/src/ci.ts`: stand-ins `selectCiRun`, `searchConfig` and the TS shards-agree check deleted; it calls
  `ciRun(call, run, got?)`. Tests in `apps/runner/test/ci.test.ts` run the old table through fwcore.

Behaviour changes vs the stand-in
- A shard whose `meta.target` differs from the target in its name is refused (was: only shards compared to each other).
- Rewrite flags are sorted by part (canonical key); query not percent-decoded (the workflow writes it raw).

Open
- No zod schema for `store.ciRun` in `packages/contracts/src/artifacts.ts` and no entry in
  `apps/runner/test/run-golden.test.ts` (files outside this task); types are local in ci.ts.
- `docs/team/tools/fw-ci.md` still names the TS stand-ins (not in this task's files).
- WebKit: a `webkit-sim` analogue of `store.ciRun` once webkit-green passes.
Read first: the module doc of `lean/Fw/Store/Ci.lean`, then `ciMain` in ci.ts.
