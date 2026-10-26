branch: worktree-wf_99fed9ac-b8f-1 (CI branch ci/push-cycle-separate)
worktree: .claude/worktrees/wf_99fed9ac-b8f-1 (under the repo root)
last commit: see `git log -1`
runs: 40284577163 (push 1, per-cycle xcodebuild design, sims 2 and 3 failed, 1 cancelled: evidence only); 40297879483 (push 2, FinishServer design, vm 3 failed, report job failed); 40315679172 (push 3, bundle-removal fix, all 6 sims and report green). No pushes left.
verified: Lean rule + golden (check.sh), TS twin and report tests, ci-paths, actionlint for the lane edit; report regenerated locally from artifacts and equal to the CI table
result: rewrite and user undecided (run 3 undecided:noRoom, stretch 2.39 put clock-matched cycle 5 at index 12 of a 12-cycle pass; run 2 inseparable / fewDwell). H4: layers and backing bytes flat per cycle in both arms.
open: later task: hold stretch near 2 or run 16 cycles, re-run; fix of the rise only after the cause is decided

What was built
- lean/Fw/Measure/PushCycle.lean: sepVerdict (theorem per branch), across/readCensus, restMs, golden packages/contracts/golden/measure/push-cycle.jsonl.
- packages/measure-webkit/src/throttle/push-cycle.mjs (twin; TS stand-ins periodMs, activeQuiet/activeCycles, sepArm, censusSeries have no Lean golden), push-cycle-pass.mjs (full, dwell), push-cycle-cli.mjs --separate, push-cycle-report.mjs.
- .github/workflows/toolbar-throttle.yml: tick uploads and the [throttle:push-cycle-separate] lane.

Read first: research/notes/2026/10-2x-push-cycle-separate.md, then lean/Fw/Measure/PushCycle.lean from `sepVerdict`.
Pre-existing, not ours: scripts/ci-steps-lint.test.mjs fails on `path-pix.yml: uncovered:sim-draw`.
