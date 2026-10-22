# Handoff: macos-pool-7 (lean-prover)

Branch `worktree-wf_15afb519-ea0-1`, worktree `.claude/worktrees/wf_15afb519-ea0-1`; pushed `ci/macos-pool-7` at b628840f.

CI (push 2026-10-22T06:28Z): GitHub runs webkit-sim 39734101098, wktr 39734101164, wktr-fixtures 39734101121, smoothness 39734101135, lean 39734101026 (running at write time). Codemagic build 6ad9ad10c0a19be428a3fbc3 (`fw ci pool dispatch --go`, triggered 06:28:32Z). CircleCI: none; the route refused (storage stop rule, see below).

Read first: `docs/team/tools/ci-pool.md` (three-tier section), then `lean/Fw/Ci/PoolTier.lean`.

Verified
- Lean `Fw.Ci.PoolTier`: `github_first`, `codemagic_before_circleci`, `cap_7`, per-provider lines (`gh_line`, `cm_line`, `cm_refuses_over`, `cc_credits_line`, `cc_storage_line`, `bitrise_line`), `counted_relabel`, `result_counts_any_provider`; `Fw.Ci.Codemagic.poolOk_iff` and refusals; `Fw.Ci.Overflow.classLeft_spec`, `storageClearAt_iff`.
- Golden `packages/contracts/golden/ci/pool-tier.jsonl` (`lean/scripts/PoolGolden.lean`), replayed in `apps/runner/test/ci-pool-tier.test.ts`; `scripts/codemagic.test.mjs` 24/24 (pool golden, `trigger --pool`, yaml pins).
- Live dispatch: state GitHub 5 of 5 busy (the push's macOS jobs), Codemagic 46 min used, CircleCI 3575 credits, storage 1297 thousandths of a GB-month (ledger, 30-day retention bound). The route gave Codemagic to rep 5 and `wait` to rep 6: CircleCI storage is over the 1000 line (`cc_storage_line`).

Open
- Fetch the Codemagic build (`node scripts/codemagic.mjs wait --build 6ad9ad10c0a19be428a3fbc3 --out <dir>`) and read the GitHub job times for the overlap.
- CircleCI's 7th slot needs the storage estimate under 1000: the ledger counts every saved byte for 30 days (caches expire sooner); a measured storage figure is a follow-up.

Conventions: `.local/` ledgers are per checkout (copied from the main checkout for this run); the Codemagic ledger here has the three pilot builds plus this one.
