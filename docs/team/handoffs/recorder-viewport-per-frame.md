# Handoff: recorder-viewport-per-frame

- Branch `worktree-wf_b2dcdd3f-850-1`, worktree `.claude/worktrees/wf_b2dcdd3f-850-1`. Last code commit: see `git log -1` on the branch
  (the commit that adds this file). CI runs: none (no CI run or phone pass in this task).
- Done: the recorder stores `vv.height` (`vh`) and `vv.offsetTop` (`vt`) per rAF frame (`device-record.mjs`); Lean splits frames into
  toolbar-moving and toolbar-still (`Session.lean` "The toolbar class of a frame": `moveWin` 30 frames, `moveMin` 1 tenth px) with
  partition theorems; per-class pass reduction and comparison (`reduceClass`, `compareClass`); per-class still-run verdict
  (`StillRuns.lean` `verdictClass`, `Pass`, `runsC`); old recordings without the field keep today's verdict (`*_noField`, `_const`).
- Goldens (regenerated from Lean, old lines unchanged, new ones inserted before the Stats lines in `session.jsonl`, appended in
  `stillruns.jsonl`): `class.consts`, `class`, `class.report`, `class.compare`; `cruns`, `cverdict`.
- TS twins: `device-session.mjs` (`classes`, `reduceClass`, `classVals`, `compareClass`, `compareClasses`, `normalize`/`denormalize` carry
  `vh`), `throttle/stillruns.mjs` (`runsC`, `armOf`, `verdictClass`, `verdictByClass`). Twin tests replay every new golden kind.
- Finding: the premise "the visualViewport reads do not flush layout" is false. WebKit `VisualViewport.cpp:72-76,87-94,123-130,132-141`
  @862f17d call `updateFrameLayout`; the recorder already read `scale` and `scrollY` every frame, so `height`/`offsetTop` add no layout
  work. Doc corrected (`docs/team/tools/device-lag-recorder.md`).
- Verified: Lean check (`lean/scripts/check.sh`), measure-webkit tests incl. typecheck, ci-paths and land-inputs tests, plan lint,
  dry land; see the report for the exact lines.
- Open: `device-cli.mjs` subcommand to print the per-class table (not in this task's writes); `vt` not used by the class; still frames
  at two heights stay `confounded`; the throttle probe (`throttle/report.mjs`) does not call `verdictByClass` yet; TS stand-ins move
  to `fwcore` later; a phone pass with the new recorder has not run.
- Conventions: new goldens come from Lean (`cd lean && lake env lean --run scripts/DeviceSessionGolden.lean > ...`, same for
  `StillRunsGolden.lean`; run `lake build Fw.Device.Session` first so StillRuns sees changes); never hand-edit them.
- Read first: `lean/Fw/Device/Session.lean` section "The toolbar class of a frame", `lean/Fw/Device/StillRuns.lean` section "The verdict
  by toolbar class", then the doc section "Toolbar class".
