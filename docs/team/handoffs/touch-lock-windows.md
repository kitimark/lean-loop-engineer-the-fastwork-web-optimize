branch: worktree-wf_31e4b9d2-d88-1 (CI branch ci/touch-lock-windows)
worktree: .claude/worktrees/wf_31e4b9d2-d88-1
last commit: bec2feaf9 (CI head of dispatch 1; later commits are notes only)
CI runs: smoothness 40071802991 success (dispatch 1 of 2, head bec2feaf9): 12 windows, all three arms counted (base 2 open, lock 3, orig 3; 4 noOpen), restart of the push server FAILED with "no ready file after 276 s" (not the old xcresult name error), lane ended after window 12; dispatch 2 on ci/touch-lock-windows-2 (see below)
results: results/touch-lock-page-end/run-40071802991/ (touch-lock.json, touch-lock.md)
verified: lean/scripts/check.sh green at 45e615849; measure-webkit touchlock test 18 pass; golden 40 lines
open: dispatch 1 result; lock and orig windows; restart fix measured only if a restart happens

# touch-lock-windows

- Read first: `research/notes/2026/10-2x-touch-lock-page-end.md`, `lean/Fw/Measure/TouchLock.lean`, `packages/measure-webkit/src/touchlock*.mjs`.
- Change: `Run.calls` (the site's instant scrollTo calls while recording: target in tenths, morph open at the call, hook in `touchlock-page.mjs`);
  `lockOf r` = first open call target (`storedLock`); no call means no lock, no fights (`fights_zero_of_unrestored`); open calls that disagree refuse the
  window `lockMoved`; `serveTag` (`serve`, `serve-r<n>`) for the restart bundle name; markdown has the push failure reasons column and a per-window table.
- Lane: head commit tags `[ci:smoothness] [webkit-cadence] [sim-only] [touch-lock]`; artifact `smoothness-webkit-sim-1`; at most 2 dispatches.
