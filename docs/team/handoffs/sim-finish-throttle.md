branch: worktree-wf_b6d72e95-643-1 (CI branch ci/sim-finish-throttle)
worktree: .claude/worktrees/wf_b6d72e95-643-1
last commit: 07fd978e1 (trigger commit with [ci:toolbar-throttle] [throttle:finish])
CI runs: 40076091168 toolbar-throttle (dispatch 1) success: no band-run signature in any arm; runs of 1-9 frames: rewrite 184, original 226, lift 8 (jobs 1,2); job 3 lost its lift passes to touch-driver timeouts.
         40079501230 toolbar-throttle (dispatch 2, commit 6d992b20c) failure (sim 1 hit the step limit on touch-driver timeouts; its partial json counted): same picture, no band, runs of 1-9: rewrite 236, original 140, lift 17. Dispatch 3 unused.
result: pinned verdict no-signature (band 5-6); exploratory 1-9 runs per 1000 frames 27.7 original, 29.1 rewrite, 2.3 lift (note: research/notes/2026/10-2x-sim-finish-throttle.md; tables: results/sim-finish-throttle/)
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
