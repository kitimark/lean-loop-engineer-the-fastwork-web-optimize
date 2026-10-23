branch: worktree-wf_379d0376-a33-1 (CI branch ci/carousel-swap-webkit-lane)
worktree: .claude/worktrees/wf_379d0376-a33-1
state: round-2 fixes 748ff0cbd, handoff 13702dafe, main 7e4722c7d (graph r345) merged at 4350feb62, polish f4c9e4682, final-round texts in the commit that lands this line; last CI push commit: 8dc944f90 on ci/carousel-swap-webkit-lane; no CI run since.
CI runs:
- 39932917436 webkit-sim at 48142c753: ci state complete, 0 swap windows (probe scrolled to page end); superseded
- 39937838325 webkit-sim at 58b1df271 (scroll search): ci state failed (r3 cancelled at the job limit, no log); r1, r2 success (8 windows per capture, 16 captures)
- 39947916723 webkit-sim at 8dc944f90: ci state failed (r1, r2 lost the inspector in layersScroll); r3 success (2 passes)
- counted: 39937838325 r1, r2 + 39947916723 r3 (6 passes, 12 captures per arm); report in results/carousel-swap-webkit/; note research/notes/2026/10-2x-carousel-swap-webkit.md
verified: Lean SwapWindow builds (no sorry), wkcost.jsonl regenerated and --check ok, measure-webkit tests 444 pass, ci-paths 54 pass, ci-steps-lint ok.
open: land; follow-ups in graph task carousel-swap-followups (every-third-window Layout and Paint in the crop, minimum-n, model line, one-run [swap-lane] CI run of the opt-in path, job id per sample).

State
- Lean: lean/Fw/Measure/SwapWindow.lean (schedule, phase, counts, validity, cell verdict); golden appended to packages/contracts/golden/measure/wkcost.jsonl through lean/Fw/Measure/WkCost.lean.
- TS: packages/measure-webkit/src/lag/{swap,swapprobe,swapreport}.mjs; hooks in probe.mjs (swap option, 5th cost pass) and cli.mjs (run builds crop+faithful arms when --swap with --cost on|only and --search; new command swap-report).
- Workflow: .github/workflows/webkit-sim.yml reads [swap-lane] in the head commit message on a push (rewrite, people.carousel:crop, 3 VMs, lag, cost only, --swap).
- Tests: packages/measure-webkit/test/lag-swap{,-report,-probe,-optin}.test.mjs.

Conventions
- One capture = fresh load of an arm, scroll until the carousel is in the viewport, MutationObserver marks swap on/off (5 vs 4 avatars); Timeline rows counted per observed window; pass = faithful-a, crop-a, faithful-b, crop-b (flipped on odd passes).
- Cell verdict per (window, kind): win/loss/unresolved(drift|noSamples|floorBroken|overlap); never pooled.
- Read first: lean/Fw/Measure/SwapWindow.lean, packages/measure-webkit/src/lag/swapprobe.mjs.
- No local Simulator run was made.
Round 2: --swap opt-in (cli.mjs via costmode.swapSetup, test lag-swap-optin), SWAP env in webkit-sim.yml, note Question line, run states from fw ci state. Dry land at main 7e4722c7d: VERDICT dry carousel-swap-webkit-lane (writes widened in graph r345).
