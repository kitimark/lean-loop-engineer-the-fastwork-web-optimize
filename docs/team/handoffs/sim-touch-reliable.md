# sim-touch-reliable handoff

- Branch `worktree-wf_b60a7b2e-e1c-1`, worktree `.claude/worktrees/wf_b60a7b2e-e1c-1`, last commit: see `git log -1` (updated at the end).
- CI runs started by this task: none. Evidence used: runs `39901005729` and `39909042070` (read-only).
- Verified: Lean `Fw.Measure.TouchPush` compiles with its theorems and golden (`packages/contracts/golden/measure/touch-push.jsonl`);
  `test/touch-push.test.mjs` replays the golden; two short local debug runs (debug evidence, not results) show a push in 4.6 s on a quiet
  Mac with both variants reaching the page.
- Cause (note `research/notes/2026/10-2x-sim-touch-reliable.md`): XCUITest post-event wait for Safari idle (CI log tail), Timeline of a
  minutes-long touch window (no Timeline now). Bound: one failing touch window per job, at most 145,600 ms per window.

## Open
- Dispatch for the lead: push `ci/sim-touch-reliable` and run the smoothness workflow on it (3 sim jobs); the touch rows log
  `touch push n (variant): outcome, begin, swipe, done, presses`. Compare with `FW_TOUCH_VARIANTS=safari` if the workflow can set env.
- Follow-ups outside this task's writes: `report.mjs` Timeline label for rows with `timeline:false`; `smoothness.yml` env pass-through for
  `FW_TOUCH_VARIANTS`; Simulator hero windows are starved (2 to 40 frames in 7 s).
- Files outside the task writes: `lean/Fw/Measure/TouchPush.lean`, `lean/scripts/TouchPushGolden.lean`, `lean/Fw.lean`, `lean/scripts/check.sh`,
  `packages/contracts/golden/measure/touch-push.jsonl`.

## Read first
`research/notes/2026/10-2x-sim-touch-reliable.md`, then `packages/measure-webkit/src/touch-push.mjs` (`touchWindow`, stand-ins), `lean/Fw/Measure/TouchPush.lean`.
