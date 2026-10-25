branch worktree-wf_d91e3108-16e-1; worktree .claude/worktrees/wf_d91e3108-16e-1; ci branch ci/cross-pool-pooling (1 of 3 pushes used)
last commit: 88795a001 (see git log for later ones)
CI runs: lean 40224630846 (queued at push), premise-tests 40224630870; webkit-sim 40224630867 skipped (a ci/* push does not dispatch it)
Codemagic: 0 builds, 0 minutes used by this task; month stays 166 of 500 (stop line 400). Reason: copying .local/codemagic.json and
.local/codemagic-ledger.json into the worktree was denied by the permission system, so no trigger was possible.

Verified (local): lean/scripts/check.sh green; @fw/runner tests 3608 pass (tsc + vitest); scripts/codemagic.test.mjs and ci-paths.test.mjs pass.
Delivered: Lean hardware key + k-pair row decision + budget + queued re-route (lean/Fw/Ci/PoolTier.lean, PoolTierWire.lean ops ci.poolRows
and ci.reroute, golden packages/contracts/golden/ci/pool-tier.jsonl); cm: ids in `fw ci state` (apps/runner/src/ci.ts, codemagic.mjs
`state --build`) and in review evidence (lean/Fw/Plan/ReviewReady.lean runIdOf); TS glue in apps/runner/src/ci-pool-tier.ts
(hwOf, classRowsOf, recordPair/readPairs, poolRows, rerouteQueued, pairRefused in place); webkit-sim.yml tools step prints hw.

Open:
- Pair evidence: with the config copied, per branch B in ci/cross-pool-pooling, -b, -c: dispatch webkit-sim (1 VM, original) on B and run
  `node scripts/codemagic.mjs trigger --pool --branch B --vars ...` (FW_TARGET original, FW_VM v1); ~20 min each, reserves 40 each
  (166 + 120 = 286 <= 400). Then `fw run` places the pair; ci-pairs/ holds the records; ci.poolRows decides each row (needs 3 agreeing pairs).
- Poller call site for rerouteQueued is not wired (glue + Lean decision exist); packages/gh-budget/src/poller.ts untouched.
- Merge main, run `pnpm -s fw plan lint docs/team/work-graph.json`, then the dry land.
Read first: docs/team/tools/ci-pool.md section "Cross-pool pooling".
