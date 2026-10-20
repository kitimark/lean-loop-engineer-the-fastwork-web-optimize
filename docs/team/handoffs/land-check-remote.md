# Handoff: land-check-remote (round 2)

State: branch worktree-wf_7c5d2ef0-583-1, round-2 code commit (see report), then an empty `[ci:land]` probe commit for the dry lane run.
`sh lean/scripts/check.sh` green at the code commit. Runner (1581) tests incl. typecheck and `node --test scripts/ci-paths.test.mjs` (47, 0 skipped) pass.

Round 1 (kept)
- Lean `LandTier`: `checkShId` in `remoteIds` (8 ids); `check_sh_remote`; `gates_local` = install + reads-scan. Lean `LandLegs`: leg `checkSh`, `shardC`.
- land.yml matrix leg check-sh runs `fw checks --leg check-sh`.

Round 2
- #1 Lean `LandTier`: `fwcoreUsers`, `isCoreUser`, `Step`, `needsBuild built ids`, `localPlan`; theorems `needsBuild_of_user`, `no_build_when_built`,
  `no_build_without_user`, `core_user_has_build` (every local fwcore user has a build step before it unless one ran; no dependence on lean/** changing).
  Op `console.landTier` takes `built?`, returns `build`. Golden cases: golden-only change (measure-webkit local), build already ran, no user.
  `runTiered` (land-remote.ts) prepends `BUILD_ARGV` to the local list when `build`; `land.ts` passes `built: phase1Built`; `checkDeps` orders users after it.
  Tests: land.test.ts (remote, golden-only: build before measure-webkit; phase-1 build not repeated), checks.test.ts (build flag = FWCORE_USERS for local candidates).
- #5 `LandTier.summaryless`, `effectiveSkipped` + theorems; op `console.landLane` takes `check?` and returns `skipped`; TS `SUMMARYLESS` deleted.
- #6 `LandLegs.legs_cover` / `legs_nodup` now over `legs.flatMap (pickFor · sel)`; base theorems `suite_legs_cover` / `suite_legs_nodup`.
- Limit: `FWCORE_USERS` (TS) equals Lean `fwcoreUsers` only for local ids (checks.test.ts); the remote users are pinned by land-inputs.test.ts's scan.

Evidence (one pair, free runners vary; "lane wall time did not grow" is the only claim)
- Before: run 39458419744, a land-lane run of task land-queue-unreachable (main-based, branch ci/land-land-queue-unreachable-3aa12c0): 8m26; webkit 8m02.
  After (round 1): run 39461106516, 4m14, webkit 3m53, check-sh 2m09 (check.sh 31 s). The webkit gap is runner variance, not this change.
- Mac "local tier" spans, rule: the 12 most recent in .fw-console/timings.jsonl (seconds): 38.1, 140.2, 69.7, 57.1, 79.6, 138.7, 47.5, 51.9, 43.7, 54.9,
  0.08 (no checks), 46.8; median about 52. check.sh inside them: 26.3-92.9 s. The Mac still pays "fwcore build (phase 1)" (0.6-25.5 s, outside the span)
  on Lean changes, plus a build step for a golden-only change that selects a local fwcore user. After figure (tier minus check.sh) is INFERRED until a real land.

Dry lane run on head f49a0a5c (branch ci/land-check-remote-2): run 39464250113, land success (pass).
Read first: lean/Fw/Console/LandTier.lean (localPlan), lean/Fw/Console/LandLegs.lean.
