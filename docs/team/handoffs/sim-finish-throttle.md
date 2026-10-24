branch: worktree-wf_b6d72e95-643-1 (CI branch ci/sim-finish-throttle)
worktree: .claude/worktrees/wf_b6d72e95-643-1
last commit: 07fd978e1 (trigger commit with [ci:toolbar-throttle] [throttle:finish])
CI runs: 40076091168 toolbar-throttle (dispatch 1 of 3 allowed) in_progress; the other workflows on the push were skipped
verified: lake build Fw.Device.FinishRuns; golden --check up to date (46 lines); check.sh green; @fw/measure-webkit tests 606 pass; scripts/ci-paths.test.mjs 56 pass; apps/runner land-inputs 60 pass; driver compiles (swift build)
open: CI table, research note, results/sim-finish-throttle, plan lint, dry land, review ready

State
- Lean: lean/Fw/Device/FinishRuns.lean (imports StillRuns, does not edit it), lean/scripts/FinishRunsGolden.lean, packages/contracts/golden/device/finishruns.jsonl.
- TS twin: packages/measure-webkit/src/throttle/finish.mjs (golden replay test/throttle-finish.test.mjs). Glue: finish-page.mjs (recorder JS), finish-probe.mjs, finish-report.mjs (table), cli.mjs --mode finish, driver.mjs mode/target, DragTests.swift testFinish.
- Workflow: toolbar-throttle.yml reads [throttle:finish] from the head commit message to pick --mode finish.
- Lead adds at land: lean/Fw.lean `import Fw.Device.FinishRuns` (next to Fw.Device.StillRuns);
  lean/scripts/check.sh job line: `job "device-finishruns golden check" lake env lean --run scripts/FinishRunsGolden.lean --check ../packages/contracts/golden/device/finishruns.jsonl` after the device-stillruns job.
- Trigger.lean lists stillruns.jsonl but not finishruns.jsonl for toolbar-throttle.yml; the workflow report job must not read the finish golden.

Conventions: one local debug run only (done, not a result); scratch in scratchpad/sft/; waits via `pnpm -s fw ci wait --branch ci/sim-finish-throttle`.
Read first: this file, then research/notes/2026/10-2x-sim-finish-throttle.md once written.
