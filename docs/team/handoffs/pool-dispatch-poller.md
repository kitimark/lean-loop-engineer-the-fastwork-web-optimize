# Handoff: pool-dispatch-poller (console-builder)

Branch `worktree-wf_2de28e7d-882-1`, worktree `.claude/worktrees/wf_2de28e7d-882-1`, ci branch `ci/pool-dispatch-poller`. Last commit: see `git log -1` (merge of main on top of e15c56c43).

CI runs: lean 40194602056 (queued at checkpoint 1), webkit-sim push run 40194602049 (success; guard skip, no sim ran). No newer push after e15c56c43 yet; no GitHub twin or Codemagic run exists.
Codemagic: NOT triggered. The worktree has no `.local/codemagic.json` or ledger; the sandbox denied copying them from the main checkout.

Verified (local, via slot): apps/runner 113 files / 3549 tests green incl. typecheck; `node --test scripts/ci-paths.test.mjs scripts/codemagic.test.mjs` 82 pass; `sh lean/scripts/check.sh` green; `fw plan lint` 0 errors, no writesClosure line for this task.
Dry land: `VERDICT scope pool-dispatch-poller`: `scripts/codemagic.mjs` and `scripts/codemagic.test.mjs` are outside the task's writes (the trigger `--vars` and the ledger build times live there). The lead adds them to the graph row (not edited here), then reruns the dry.

Done: Lean cell theorems (PoolTier.lean); `codemagic.yaml` takes the cell as variables; `fw run` routes a webkit-sim count job through `ci.poolTier` (`realRoute` in `apps/runner/src/ci-pool-tier.ts`, hook `RunDeps.route` in `run.ts`), triggers the Codemagic cells, awaits them with the GitHub run, files them, merges classes locally; events in `<console dir>/ci-route.jsonl`; `--no-route`; docs in `docs/team/tools/ci-pool.md`.
Open: paired run. From a checkout with the app id: copy `.local/codemagic.json` and the ledger; GitHub twin `pnpm fw run --target original --engines webkit --runs 1 --ref ci/pool-dispatch-poller --no-route`; Codemagic cell `node scripts/codemagic.mjs trigger --pool --branch ci/pool-dispatch-poller --vars '{"FW_TARGET":"original","FW_PRESET":"original","FW_FW":"","FW_VM":"v1","FW_SESSIONS":"1"}'`, `wait --build <id> --out <dir>` (>= 120 s), then `node scripts/codemagic.mjs compare`.
Follow-ups: re-route of already queued GitHub jobs (no re-route step in the Lean route); rewrite arm on Codemagic (needs the site build); spool `ci-route.jsonl` into console events.
Read first: docs/team/tools/ci-pool.md (section "Dispatch-time route"), then `realRoute` in ci-pool-tier.ts.

## Round 2 checkpoint (commit ec606c602)
Branch `worktree-wf_2de28e7d-882-1`, worktree `.claude/worktrees/wf_2de28e7d-882-1`, last commit ec606c602, ci branch `ci/pool-dispatch-poller` pushed at ec606c602.
Codemagic paired cell: build 6addffe5e4d133ded52e64b3 (rewrite, vm r1), running. GitHub twin: `fw run --target rewrite --engines webkit --runs 1 --no-route` started in the background (log scratchpad/pdp/gh.log). CI push run: not read yet.
Done: Lean `ci.poolCell` (routable targets, rewrite filed only with equal non-empty site digests, theorems in PoolTier.lean), rewrite lane in pool7.cmAllow, codemagic.yaml builds the site (pinned elan, frozen pnpm install, @fw/site build, `codemagic.mjs site-digest`), `fw run` routes rewrite cells and checks the digest in `place`.
Outside the task writes (lead to widen): lean/Fw/Ci/PoolTierWire.lean, lean/scripts/PoolGolden.lean.

## Round 2 checkpoint 4 (commit 2f847f8a3, pushed to ci/pool-dispatch-poller)
Branch `worktree-wf_2de28e7d-882-1`, worktree `.claude/worktrees/wf_2de28e7d-882-1`, last commit 2f847f8a3.
Runs: GitHub twin 40196504411 (rewrite, r1+r2, --no-route, at ec606c602) queued/in progress waiting for macOS slots. Codemagic r1: 6ade005d9ff25140a255e015 (9 min, digest mismatch, cause below), 6ade07e480382cf4e724c435 (8 min, finished). Month used 104 of 400 min line.
Digest finding: first mismatch was our digest, not the site. upload-artifact drops hidden `.vite/manifest.json`; `build-info.json` holds build `ms` times. siteDigest now skips hidden paths and drops `ms`. With that the GitHub site-dist and the Codemagic build both give ca7745e4f918...d, 243 files.
Verified: runner 3563 tests, ci-paths 56, codemagic 33, check.sh green.
Open: count-artifact compare of webkit-sim-r1 once the twin finishes; CI on 2f847f8a3; dry land; review ready.

## Round 2 checkpoint 5 (paired run result)
CI: lean 40199047016 success at 2f847f8a3. GitHub twin 40196504411: success on attempt 2 (attempt 1 r1 stalled in the Safari inspector; `gh run rerun --failed`).
Paired rewrite cell r1 (MEASURED): site digests equal, ca7745e4f918...d, 243 files (Lean `ci.poolCell` files the cell). Count classes NOT equal: 18 of 104 rows differ (GitHub stable 26 / deterministic 55 / quarantined 23; Codemagic 13 / 55 / 36), e.g. scroll RecalculateStyles total 1 vs 39. Cause (INFERRED from tools.txt): the images differ, GitHub macOS 27.0.1 + Xcode 27.1, Codemagic macOS 27.0 + Xcode 27.0 and an extra iOS 26.5 runtime. One session each, so one cell proves one pair only.
Codemagic minutes: 1 (failed yaml) + 9 (digest mismatch build 6ade005d) + 8 (build 6ade07e4) = 18; month used 104 of the 400 line.
Follow-up: Lean should require a matching toolchain (macOS/Xcode/runtime) before a cell's counts are merged, or pin Codemagic to the GitHub Xcode.

## Round 3 checkpoint 1 (commit f438f8623, pushed to ci/pool-dispatch-poller)
Branch `worktree-wf_2de28e7d-882-1`, worktree `.claude/worktrees/wf_2de28e7d-882-1`, last commit f438f8623.
Done: Lean PlatformKey/cellMerged + theorems + wire op ci.cellMerged + golden (PoolTier.lean, PoolTierWire.lean, PoolGolden.lean); codemagic.yaml xcode 27.1; ci-pool-tier.ts parse/ask/event/aside/missing-sha; tests green (runner ci-pool-tier*).
Open: CI runs on f438f8623, paired rewrite run (Codemagic + GitHub twin), check.sh, dry land, review ready.

## Round 3 checkpoint 2
Branch `worktree-wf_2de28e7d-882-1`, worktree `.claude/worktrees/wf_2de28e7d-882-1`, last commit see git log. check.sh green at f438f8623.
GitHub twin: webkit-sim dispatch run 40211928946 (rewrite, r1+r2, --no-route) queued at checkpoint time. Lean/CI push run on f438f8623: not read yet.
Codemagic (prose): build 6ade2733 timed out at 41 min (determinism step hung, no artifacts; harness stall like the GitHub attempt-1 stall); retry build 6ade316d finished in 21 min, key macOS 26A434 / Xcode 27A9275 / runtime 24A434, equal to GitHub r1 tools.txt (round 2). Month used 166 of the 400 line.
Open: twin finish, place/compare (node scripts/codemagic.mjs compare), CI run, dry land, review ready.
