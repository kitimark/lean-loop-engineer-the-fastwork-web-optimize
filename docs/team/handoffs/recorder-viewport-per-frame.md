# Handoff: recorder-viewport-per-frame

- Branch `worktree-wf_b2dcdd3f-850-1`, worktree `.claude/worktrees/wf_b2dcdd3f-850-1`. Last code commit: `git log -1` on the branch
  (the commit that adds this file). CI runs: none (no CI run or phone pass in this task).
- Done (round 1): the recorder stores `vv.height` (`vh`) and `vv.offsetTop` (`vt`) per rAF frame (`device-record.mjs`); Lean splits frames
  into toolbar-moving and toolbar-still (`Session.lean` "The toolbar class of a frame": `moveWin` 30, `moveMin` 1) with partition
  theorems; per-class pass reduction and comparison (`reduceClass`, `compareClass`); per-class run counts (`StillRuns.lean` `armOf`, `runsC`).
- Done (round 2, review findings): the still class is decided per height group (`StillRuns.lean` "The still class, one height at a time":
  `Pass.stillHeights`, `Pass.csAt`, `armAt`, `verdictAt`, `groupOf`, `verdictByHeight`). A height only one arm has is `not-comparable`.
  Theorems: `verdictByHeight_const` / `_noField` (constant height or old recording = one group = `verdictToday`),
  `verdictByHeight_ne_confounded` (a toggling pass is never confounded by pooling), `groupOf_absent_base|lift|present`, `Pass.csAt_still_iff`.
  The old pooled `verdictClass` is gone (the moving class is `verdictMoving`). Golden `cverdict` now has `groups` and cases with a 31/60-frame
  collapse (> `moveWin`) and both arms toggling 7750/8150; regenerated from `StillRunsGolden.lean`. Twin `throttle/stillruns.mjs`
  (`verdictByHeight`, `armAt`, `passClassesAt`) and its test replay them. Doc "Toolbar class" text corrected (finding 3); finding 5 cite added
  in the doc and `device-record.mjs`.
- Finding (round 1): the premise "visualViewport reads do not flush layout" is false (`VisualViewport.cpp:72-76,87-94,123-130,132-141`
  @862f17d); `height`/`offsetTop` add no layout work because `scale` and `scrollY` already flush each frame.
- Verified: `lean/scripts/check.sh` green, `pnpm --filter @fw/measure-webkit test` (607 pass), `scripts/ci-paths.test.mjs`, runner
  `land-inputs.test.ts`, plan lint, dry land (see the report for the lines).
- Open: finding 4 (zone boundaries of `reduceClass` and `compareClass` by height group; `Session.lean`, `device-session.mjs`, `session.jsonl`) is a
  follow-up, not done; `device-cli.mjs` subcommand to print the table; `vt` unused; throttle probe `report.mjs` does not call
  `verdictByHeight`; a phone pass with the new recorder has not run; TS stand-ins move to `fwcore` later.
- Conventions: goldens come from Lean (`cd lean && lake env lean --run scripts/StillRunsGolden.lean > ...`; `lake build Fw.Device.Session`
  first); never hand-edit. Keep case lists functions of `Unit` (init-cost lint bound 10000).
- Read first: `lean/Fw/Device/StillRuns.lean` section "The still class, one height at a time", then the doc section "Toolbar class".
