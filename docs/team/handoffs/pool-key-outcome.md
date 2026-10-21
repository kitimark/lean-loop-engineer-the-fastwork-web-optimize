# pool-key-outcome (lean-prover)

**State:** branch `worktree-wf_27cbc28d-204-1`; module `lean/Fw/Ci/Pool/Key.lean` (`Fw.Ci.Pool.Key`), imported in
`lean/Fw.lean`; golden `packages/contracts/golden/ci/pool-key.jsonl` from `lean/scripts/PoolKeyGolden.lean`
(`--check` row in `lean/scripts/check.sh`). `Fw.Ci.Provider` untouched (its `Provider` is imported).

**Verified (Lean, no sorry):**
- `Key := (sha, lane, cfg, rep)`, `Key.valid` (sha 40 hex, cfg 64 hex = full sha256, lane `[a-z0-9-]+`);
  `keysOf` reps `0..n-1`, `keysOf_nodup`.
- `Art := (item = (key, leg), attempt, provider)`; `Art.name` =
  `mres-<sha>-<cfg>-r<rep>-l<leg>-a<attempt>-<github|circleci>-<lane>`; `name_inj`: valid keys, equal names imply
  equal artifacts (provider included).
- `Outcome := result | failed | stale | skipped | notRun | waiting`; `terminal` (all but waiting), `delivered`
  (what a job writes), `fails` (failed, notRun).
- `reduce plan recs`: one row per planned unit (`exactly_one_row`, `no_row_unplanned`, `reduce_terminal`); the row
  is the delivered record with the latest attempt (ties: github, then first), from any provider
  (`rowOf_of_delivered`, `delivered_counted`), else `notRun` (`rowOf_notRun_of_none`, `rowOf_notRun_iff`).
- `fastPath` (in-job `if: always()` step) writes only notRun rows and covers the job's units (`fastPath_covers`);
  `fast_path_only`: the reduce output is the same with or without them.
- `runFails_iff`: a run fails iff some row is failed or notRun.

**Open / follow-ups:** workflow wiring and the reduce job (pool-shadow), routing and `waiting` resolution
(pool-fallback, ci-route); `portOf` lane ports (design §3, needed by pool-wktr-device) are not here; adding a
`bitrise` provider means extending `providerTag`, `providerRank` and the golden `format` row in Key.lean.

**Conventions:** a planned unit is (key, leg); `notRun` records in artifacts are never read back, so a lost runner and
the fast path give the same row. Name length is about 140 chars (GitHub artifact name limit not checked, INFERRED ok).

**Read first:** `lean/Fw/Ci/Pool/Key.lean` (theorems above), research/notes/2026/10-20-macos-pool-v2.md §3.
