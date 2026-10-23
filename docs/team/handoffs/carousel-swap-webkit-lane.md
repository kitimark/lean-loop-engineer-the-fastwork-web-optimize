branch: worktree-wf_379d0376-a33-1 (CI branch ci/carousel-swap-webkit-lane)
worktree: .claude/worktrees/wf_379d0376-a33-1 (in the main checkout)
last commit: 8dc944f90 (pushed to ci/carousel-swap-webkit-lane; tokens [ci:webkit-sim] [swap-lane])
CI runs:
- 39932917436 webkit-sim at 48142c753: probe scrolled to page end, 0 swap windows in r1 (carousel loop idle there); superseded
- 39937838325 webkit-sim at 58b1df271 (scroll search): r1, r2 success (8 windows per capture, all 16 captures); r3 cancelled at the job limit (no log); 2 VMs only
- 39947916723 webkit-sim at 8dc944f90: r3 success (2 passes); r1, r2 failed in cost layersScroll (inspector lost, no lag file)
- counted: 39937838325 r1, r2 + 39947916723 r3 (6 passes, 12 captures per arm); report in results/carousel-swap-webkit/; note research/notes/2026/10-2x-carousel-swap-webkit.md
verified: Lean SwapWindow builds (no sorry), wkcost.jsonl regenerated and --check ok, measure-webkit tests 434 pass, ci-paths 54 pass, ci-steps-lint ok.
open: land dry, review ready; follow-ups in the note (every-third-window Layout in the crop, more passes per job).

State
- Lean: lean/Fw/Measure/SwapWindow.lean (schedule, phase, counts, validity, cell verdict); golden appended to packages/contracts/golden/measure/wkcost.jsonl through lean/Fw/Measure/WkCost.lean.
- TS: packages/measure-webkit/src/lag/{swap,swapprobe,swapreport}.mjs; hooks in probe.mjs (swap option, 5th cost pass) and cli.mjs (run builds crop+faithful arms when --cost on|only and --search; new command swap-report).
- Workflow: .github/workflows/webkit-sim.yml reads [swap-lane] in the head commit message on a push (rewrite, people.carousel:crop, 3 VMs, lag, cost only).
- Tests: packages/measure-webkit/test/lag-swap{,-report,-probe}.test.mjs.

Conventions
- One capture = fresh load of an arm, scroll until the carousel is in the viewport, MutationObserver marks swap on/off (5 vs 4 avatars); Timeline rows counted per observed window; pass = faithful-a, crop-a, faithful-b, crop-b (flipped on odd passes).
- Cell verdict per (window, kind): win/loss/unresolved(drift|noSamples|floorBroken|overlap); never pooled.
- Read first: lean/Fw/Measure/SwapWindow.lean, packages/measure-webkit/src/lag/swapprobe.mjs.
- No local Simulator run was made (the sim slot was held by another agent).
