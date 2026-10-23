branch: worktree-wf_1014fee6-cdd-1 (CI branch ci/hero-accent-frozen-confirm)
worktree: .claude/worktrees/wf_1014fee6-cdd-1
last commit: 9997926ab (token commit [ci:webkit-sim] [swap-lane] [swap-freeze])
CI runs: 39996415429 webkit-sim at 9997926ab, queued (dispatch 1 of 2; the other workflows of the push are skipped, lean is the push check)
read first: research/notes/2026/10-2x-carousel-swap-webkit.md (section on the freeze, once written), results/carousel-swap-webkit/hero-accent-frozen.md

done (code, committed):
- freeze.mjs: harness-side hero.accent freeze (adopted style sheet, scoped to [data-fw="hero-accent"], inert when --freeze is unset)
- zoneprobe.mjs (hero-exit zone scroll-A Layout/Paint, aligned = scroll starts inside a draw), freezesession.mjs (per pass: swap pass unfrozen and frozen, both arms, diag on both arms, zone captures), freezereport.mjs, cli.mjs `--freeze hero-accent` and `freeze-report`
- Lean (outside the task writes): SwapWindow.lean longRuns, median2, frozenCell (one theorem per branch), sharePct, zoneVerdict; golden kinds swapFreezeConst, swapRuns, swapMedian2, swapFrozen, swapShare, swapZone in wkcost.jsonl; TS twins in lag/swap.mjs
- job key is <job id>/p<pass>/<slot a|b|diag|aligned|natural>; webkit-sim.yml has FW_JOB_ID and FREEZE (token [swap-freeze] next to [swap-lane])
verified: lean/scripts/check.sh green, measure-webkit lag tests 122 pass, ci-paths 56 pass. Premise (functional only, Playwright WebKit on this Mac, not a result): after the sheet 0 hero-accent animations over a 7 s draw cycle, unfrozen 4 (strokeIn, strokeOut, width, idle frames).
open: CI result of run 39996415429; report to build with `node src/lag/cli.mjs freeze-report --files r1,r2,r3 --sources "run 39996415429 ..." --out results/carousel-swap-webkit/hero-accent-frozen.md --json ...` from packages/measure-webkit; note section; dry land; review ready
conventions: never pool runs of different commits; 3 jobs at one commit; do not edit lag/probe.mjs or lag/report.mjs
