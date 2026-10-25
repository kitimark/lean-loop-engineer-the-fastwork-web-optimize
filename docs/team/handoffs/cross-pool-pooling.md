branch worktree-wf_d91e3108-16e-1; worktree .claude/worktrees/wf_d91e3108-16e-1; ci branches ci/cross-pool-pooling, -b, -c (pushed at 3ead519e1)
CI runs: lean 40224630846 (first push); k=3 pairs: GitHub webkit-sim 40225058193, 40226715252, 40229095163 (all success) with Codemagic
  cm:6ade550f28f7ff171ac1a5a9, cm:6ade59e62261fc70401bb883, cm:6ade60fa118a2ae26ddd9238 (all finished; 16 + 19 + 18 = 53 minutes; 219 of 500, stop line 400)
Result (MEASURED): hardware differs (3 cpu vs 8 cpu) so merged=false; ci.poolRows over 104 rows: 65 paired, 39 refused, 0 direct. See docs/team/tools/ci-pool.md "Pinned pairs".

Delivered
- Lean hardware key, k-pair row decision, budget, re-route: lean/Fw/Ci/PoolTier.lean, PoolTierWire.lean (ops ci.poolRows, ci.reroute), golden packages/contracts/golden/ci/pool-tier.jsonl
- cm: ids in fw ci state and review evidence (lean/Fw/Plan/ReviewReady.lean runIdOf; scripts/codemagic.mjs state --build)
- TS glue apps/runner/src/ci-pool-tier.ts (hwOf, classRowsOf, recordPair/readPairs, poolRows, rerouteQueued); webkit-sim.yml tools step prints hw
- Poller call site: packages/gh-budget/src/poller.ts rerouteTick + RerouteEnv.reroute hook (same file); test packages/gh-budget/test/reroute-tick.test.ts
- Bug fixed: classRowsOf read the five-column merged table as zero rows (apps/runner/src/ci-pool-tier.ts, scripts/codemagic.mjs; test added)

Verified: @fw/gh-budget 93 pass; @fw/runner 3609 pass (tsc + vitest); ci-paths and codemagic node tests pass; plan lint shows no cross-pool-pooling lines.
Open / follow-ups
- The runner does not set Env.reroute in production (the poller call site exists; the job request builder is a follow-up).
- Pair records were written by a scratch script (scratchpad/cpp/tool/pair.ts, not committed), not by `fw run place`; same commit and settings for all three pairs.
- packages/contracts/golden/plan/review-ready.jsonl not regenerated (accepted limit).
Read first: docs/team/tools/ci-pool.md section "Cross-pool pooling".
