branch: worktree-wf_31e4b9d2-d88-1 (CI branches ci/touch-lock-windows, ci/touch-lock-windows-2)
worktree: .claude/worktrees/wf_31e4b9d2-d88-1
last commit: see `git log -1` (CI heads: bec2feaf9 dispatch 1, fbe5e9861 dispatch 2; later commits are notes only)
CI runs: smoothness 40071802991 success (dispatch 1, 12 windows, restart failed "no ready file after 276 s", lane ended); smoothness 40074062290 success (dispatch 2, 18 windows, 6 reps, no restart); lean 40071803039 on dispatch 1
verified: lean/scripts/check.sh green at 45e615849 (golden 40 lines); @fw/measure-webkit test 603 pass; ci-paths 56; runner land-inputs 60; fw plan lint: no writesClosure error for this task
open: lock window still fights (4 of 5 accepted windows); 11 of 30 windows never open the morph; restart cannot heal a dead Simulator page; across-job verdict is sim-touch-verdict-jobs; look class stays change for the user review

# touch-lock-windows

- Read first: `research/notes/2026/10-2x-touch-lock-page-end.md` (Answer, first bullets), `lean/Fw/Measure/TouchLock.lean`, `packages/measure-webkit/src/touchlock*.mjs`.
- Change: `Run.calls` (the site's instant scrollTo calls while recording: target in tenths, morph open at the call; hook in `touchlock-page.mjs`);
  `lockOf r` = first open call target (`storedLock`); no call means no lock and no fights (`fights_zero_of_unrestored`); open calls that disagree refuse the
  window `lockMoved`; `serveTag` (`serve`, `serve-r<n>`) names the push server result bundle; markdown has the push failure reasons column, a stored lock column and a per-window table.
- Results: `results/touch-lock-page-end/run-40071802991/`, `run-40074062290/` (touch-lock.json, touch-lock.md); combine with `node packages/measure-webkit/src/touchlock-cli.mjs report <json> <json>`.
- Lane: head commit tags `[ci:smoothness] [webkit-cadence] [sim-only] [touch-lock]`; artifact `smoothness-webkit-sim-1`. Both dispatches used.
