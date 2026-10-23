branch: worktree-wf_379d0376-a33-1 (CI branch ci/carousel-swap-webkit-lane)
worktree: .claude/worktrees/wf_379d0376-a33-1 (in the main checkout)
last commit: 48142c753 (pushed to ci/carousel-swap-webkit-lane; message tokens [ci:webkit-sim] [swap-lane])
CI runs:
- 39932917436 webkit-sim (push, target rewrite fw people.carousel:crop, vms 3, lag cost only via [swap-lane]): in_progress
verified: Lean SwapWindow builds (no sorry), wkcost.jsonl regenerated and --check ok, measure-webkit tests 432 pass, ci-paths 54 pass, ci-steps-lint ok.
open: CI result of 39932917436; analysis into results/carousel-swap-webkit/ and research/notes/2026/10-2x-carousel-swap-webkit.md; lean check.sh; land dry; review ready.

State
- Lean: lean/Fw/Measure/SwapWindow.lean (schedule, phase, counts, validity, cell verdict); golden appended to packages/contracts/golden/measure/wkcost.jsonl through lean/Fw/Measure/WkCost.lean.
- TS: packages/measure-webkit/src/lag/{swap,swapprobe,swapreport}.mjs; hooks in probe.mjs (swap option, 5th cost pass) and cli.mjs (run builds crop+faithful arms when --cost on|only and --search; new command swap-report).
- Workflow: .github/workflows/webkit-sim.yml reads [swap-lane] in the head commit message on a push (rewrite, people.carousel:crop, 3 VMs, lag, cost only).
- Tests: packages/measure-webkit/test/lag-swap{,-report,-probe}.test.mjs.

Conventions
- One capture = fresh load of an arm, scroll to maxY, MutationObserver marks swap on/off (5 vs 4 avatars); Timeline rows counted per observed window; pass = faithful-a, crop-a, faithful-b, crop-b (flipped on odd passes).
- Cell verdict per (window, kind): win/loss/unresolved(drift|noSamples|floorBroken|overlap); never pooled.
- Read first: lean/Fw/Measure/SwapWindow.lean, packages/measure-webkit/src/lag/swapprobe.mjs.
- No local Simulator run was made (the sim slot was held by another agent).
