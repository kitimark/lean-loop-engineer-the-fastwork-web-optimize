# sim-touch-reliable handoff

- Branch `worktree-wf_b60a7b2e-e1c-1`, worktree `.claude/worktrees/wf_b60a7b2e-e1c-1`, last code commit `ace249c13` (this handoff commit follows it).
- CI: pushed `ci/sim-touch-reliable` at `610d43d70` (smoothness, `[webkit-cadence] [earn-bound] [sim-only]`, default variant springboard); run id pending
  (`pnpm -s fw ci wait --branch ci/sim-touch-reliable --workflow smoothness`). Evidence read-only: runs `39901005729` and `39909042070`.
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
  `lean/Fw/Ci/Trigger.lean` (one input), `packages/contracts/golden/ci/triggers.jsonl` (regenerated), `packages/contracts/golden/measure/touch-push.jsonl`.
  Dry land without `--allow` ends `VERDICT scope sim-touch-reliable` (4 files); with `--allow` for them it ends `VERDICT dry sim-touch-reliable`.
- Green: `sh lean/scripts/check.sh`, measure-webkit tests (419), ci-paths test (54), apps/runner test (2914 incl. tsc).

## Read first
`research/notes/2026/10-2x-sim-touch-reliable.md`, then `packages/measure-webkit/src/touch-push.mjs` (`touchWindow`, stand-ins), `lean/Fw/Measure/TouchPush.lean`.
