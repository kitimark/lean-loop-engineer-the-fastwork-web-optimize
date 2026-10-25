branch worktree-wf_d91e3108-16e-1; worktree .claude/worktrees/wf_d91e3108-16e-1; round 2 (no new CI push or dispatch)
CI runs (round 1): lean 40224630846; k=3 pairs GitHub 40225058193, 40226715252, 40229095163 (success) with cm:6ade550f28f7ff171ac1a5a9, cm:6ade59e62261fc70401bb883, cm:6ade60fa118a2ae26ddd9238 (219 of 500 minutes, stop line 400)
Result (MEASURED): hardware differs (3 vs 8 cpu), merged=false; ci.poolRows over 104 rows: 65 paired, 39 refused (36 differ in class, 3 in fewer than 3 pairs).

Round 2 fixes
- B pair identity: lean/Fw/Ci/PoolTier.lean Obs (ghRun, cmBuild, ghSha, cmSha), Obs.holds, rowPooled, theorems pooled_dup_gh_refused, pooled_dup_cm_refused, pooled_sha_mismatch_refused (+ pooled_empty_sha_refused); PoolTierWire obsOf; TS PairRecord ghSha/cmSha, no fallback (apps/runner/src/ci-pool-tier.ts pairRefused, headShaOf); golden rows in lean/scripts/PoolGolden.lean
- F1 toolchain in Lean: sameToolchain in rowUse, theorems rowUse_{xcode,macos,runtime}_not_paired; TS `same` deleted
- F2 opReroute rows carry i; rerouteQueued uses jobs[row.i]; test with a young job ahead
- F3 ci-pool.md sentence, F4 ghHw docstring, F5 place test (ci-pool-tier-route.test.ts, "same toolchain, other hardware")
- Pair records rebuilt via realRoute.place over the downloaded cells (driver scratchpad/cpp/tool2/place.ts, real gh headSha): 3 records in scratchpad/cpp/console/ci-pairs, ghSha = cmSha = 3ead519e11ec..., 65 paired / 39 refused again.

Open / follow-ups
- cancel-after-trigger idempotence (record moved run id before cancel); QueuedRun to QueuedJob with runCells (poller.ts vs ci-pool-tier.ts); production env.reroute caller.
- packages/contracts/golden/plan/review-ready.jsonl not regenerated (accepted limit). Pair records are not committed.
Read first: docs/team/tools/ci-pool.md "Cross-pool pooling".
