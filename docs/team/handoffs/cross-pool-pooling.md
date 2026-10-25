branch worktree-wf_d91e3108-16e-1; worktree .claude/worktrees/wf_d91e3108-16e-1; ci branches ci/cross-pool-pooling, -b, -c (pushed at 3ead519e1)
CI runs: pair 1 GitHub webkit-sim 40225058193 success + cm:6ade550f28f7ff171ac1a5a9 finished; pair 2 GitHub 40226715252 success + cm:6ade59e62261fc70401bb883 finished; pair 3 GitHub 40229095163 (running) + cm:6ade60fa118a2ae26ddd9238 (running)
Codemagic minutes: 166 before; 3 builds reserve 40 each (<= 286 of stop line 400); actual minutes in the ledger (scripts/codemagic.mjs facts). Pair records: scratchpad/cpp/tool/pair.ts (not committed). Fixed classRowsOf (5-column merged table was read as zero rows).
Poller call site done: packages/gh-budget/src/poller.ts rerouteTick + env.reroute hook, test packages/gh-budget/test/reroute-tick.test.ts (runner does not set the hook in production: follow-up).
Pair procedure: dispatch `gh workflow run webkit-sim.yml --ref B -f vms=1 -f target=original`, `node scripts/codemagic.mjs trigger --pool --branch B --vars '{"FW_TARGET":"original","FW_VM":"v1"}'`; then record with recordPair (apps/runner/src/ci-pool-tier.ts) and run poolRows.
Rule: if GitHub keeps a twin queued > 3 h, report the k reached; decision stays 'not pooled'.

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
