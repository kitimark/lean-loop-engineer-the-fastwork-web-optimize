# Handoff: macos-pool-7 (lean-prover)

Branch `worktree-wf_15afb519-ea0-1`, worktree `.claude/worktrees/wf_15afb519-ea0-1`; `ci/macos-pool-7` pushed at b628840f, then 9c4b531e.

CI, all finished: GitHub webkit-sim 39734101098 success, lean 39734101026 and 39737132825 success, wktr 39734101164 and wktr-fixtures 39734101121 stopped stale at the tip re-check after the second push (their first jobs ran and passed). Codemagic 6ad9ad10c0a19be428a3fbc3 and 6ad9b3b25a4232c65cf47752 finished, 20 min each. CircleCI: none started; the route refused it (storage line).

Read first: `docs/team/tools/ci-pool.md` (three-tier section, live run), then `lean/Fw/Ci/PoolTier.lean`.

Verified
- Lean `Fw.Ci.PoolTier`: `github_first`, `codemagic_before_circleci`, `cap_7`, per-provider lines (`gh_line`, `cm_line`, `cm_refuses_over`, `cc_credits_line`, `cc_storage_line`, `bitrise_line`), `counted_relabel`, `result_counts_any_provider`; `Fw.Ci.Codemagic.poolOk_iff` and its refusals; `Fw.Ci.Overflow.classLeft_spec`, `storageClearAt_iff`. `sh lean/scripts/check.sh` green, axiom check 0 failing.
- Golden `packages/contracts/golden/ci/pool-tier.jsonl` (`lean/scripts/PoolGolden.lean`), replayed in `apps/runner/test/ci-pool-tier.test.ts`; apps/runner 2460 tests, measure-webkit 302, `scripts/codemagic.test.mjs` 24, ci-paths 54.
- Live: at 07:01:15Z six macOS jobs at once, five on GitHub (three ours) and Codemagic 6ad9b3b2. Both dispatches gave Codemagic one request and made the next wait (CircleCI storage 1297 > 1000).
- Pilot fixes on Codemagic: Node v24.22.0 (after the PATH fix; build 6ad9ad10 still ran v26.8.2), proxy from cached kegs in 4.1 s, `openurl` timeouts recovered by the retry in both builds. Class rows against the GitHub twin differ in 10 and 6 of 104, within the pilot's GitHub-vs-GitHub 11.

Open
- The seventh slot (CircleCI) needs the storage estimate under 1000: `scripts/circleci.mjs` counts every saved byte for 30 days, caches expire sooner. A measured storage figure or a cache retention per save is a follow-up (circleci.mjs is outside this task).
- No poller calls `fw ci pool dispatch` yet; the GitHub busy count was read by hand (`gh run view` job lists).

Conventions: `.local/` ledgers are per checkout; the lead copied this worktree's `.local/codemagic-ledger.json` (builds 1 to 5, 86 of 500 minutes in 2026-10) to the main checkout.

Round 2 (gate): merged main at graph r241 (check.sh and sim.mjs are task writes now), dry land rerun without --allow; `runs` holds the five GitHub ids, the Codemagic builds are named in the live-proof evidence.
