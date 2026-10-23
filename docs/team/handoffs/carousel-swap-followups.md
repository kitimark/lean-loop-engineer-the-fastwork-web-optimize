branch: worktree-wf_b23d1ba6-96a-1 (CI branch ci/carousel-swap-followups)
worktree: .claude/worktrees/wf_b23d1ba6-96a-1
CI run: 39983630584 webkit-sim at 3bfca9339, jobs r1 r2 r3 all success (the 2nd of 2 dispatches). Earlier, not results: 39968418529 (no lane
token, skipped), 39968644601 (r1, r2 ok, r3 cancelled at the job limit).
read first: research/notes/2026/10-2x-carousel-swap-webkit.md, results/carousel-swap-webkit/people-carousel-crop.md

done:
- Cause of the every-third-window Layout/Paint pattern: the hero.accent draw cycle (stroke-dashoffset animations on both 900 ms draws, StyleDifference.cpp:161; width transition on draw-in, :404; cycle 1250+900+900 = 3050 ms against 3 carousel
  periods of 3060 ms). MEASURED timing match in 3 of 3 diagnostic captures; causal link INFERRED, confirmed by a capture with hero.accent frozen.
  WebKit: StyleDifference.cpp:404 and LocalFrameViewLayoutContext.cpp:223,335 at 862f17d. Faithful shows it in the rest windows, masked in swap windows.
- Lean SwapWindow: fewSamples (minFaithful 3), Bg/bgOf (busyMin 24), swapNeighbours, theorems and goldens; golden split in two constants (init-cost bound).
- swapreport prints the measured crop minimum next to the model line; per-sample job key; by-background tables; diagnostic section.
- Opt-in path [swap-lane] -> SWAP=--swap -> cli --swap confirmed (webkit-sim.yml:415, cli.mjs:24).

verified: lean/scripts/check.sh green, measure-webkit tests 470 pass, ci-paths 56 pass, runner land-inputs 56 pass, plan lint 0 errors.
open:
- Outside the task writes: packages/measure-webkit/src/lag/probe.mjs (swap pass before the cost passes).
- .github/workflows/webkit-sim.yml has no FW_JOB_ID, so the JSON holds <run>.<attempt>/<vm>/p<pass>, not the numeric job id (vm -> id in the note).
- Next measurement: freeze hero.accent in the swap lane to get quiet-background cells and the confirming test.
conventions: report built with `node src/lag/cli.mjs swap-report --files r1,r2,r3 ...` from packages/measure-webkit; never pool runs of different commits.
