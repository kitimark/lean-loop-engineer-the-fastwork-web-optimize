branch: worktree-wf_1014fee6-cdd-1 (CI branch ci/hero-accent-frozen-confirm)
worktree: .claude/worktrees/wf_1014fee6-cdd-1
CI runs: dispatch 1 = run 39996415429 webkit-sim at 9997926ab: FAILED as a set (r1 job 120562437169 failure: Simulator died in the zone captures, no json; r2 job 120562437268 cancelled: slow boot, diag capture timed out, Safari relaunch failed, json with no pass; r3 job 120580412344 success, 2 passes). Runner load averages were 366 to 893 in the host dumps.
dispatch 2 of 2 (the last): run 40006432997 webkit-sim at f2dec2e2b (ci branch tip, do not push later commits), in progress; hardened (see below). Never pool jobs of different commits (r3 of dispatch 1 stays a single-job pilot).
read first: research/notes/2026/10-2x-carousel-swap-webkit.md (section on the freeze), results/carousel-swap-webkit/hero-accent-frozen.md
done (code, committed):
- freeze.mjs (harness-side hero.accent freeze, inert when --freeze is unset), zoneprobe.mjs (hero-exit zone Layout/Paint, aligned = scroll starts in a draw), freezesession.mjs, freezereport.mjs, cli.mjs `--freeze hero-accent` and `freeze-report`
- hardening after dispatch 1: the session saves --out after every capture/zone unit (swapPass onStart/onUnit), the report reads partial jobs, one pass per job under [swap-freeze] (PASSES in webkit-sim.yml), the state order shifts by VM number
- Lean (outside the task writes): SwapWindow.lean longRuns, median2, frozenCell (a theorem per branch), sharePct, zoneVerdict; golden kinds swapFreezeConst/swapRuns/swapMedian2/swapFrozen/swapShare/swapZone in wkcost.jsonl
- job key <job id>/p<pass>/<slot a|b|diag|aligned|natural>; webkit-sim.yml has FW_JOB_ID, FREEZE, PASSES
verified: lean/scripts/check.sh green; lag tests pass; ci-paths 56. Playwright WebKit on this Mac (functional only): after the sheet 0 hero-accent animations over a 7 s draw cycle, unfrozen up to 4.
pilot (log lines of r3, not pooled): frozen crop windows 2-4 Layout rows vs unfrozen busy 13-16; frozen faithful stays 8-16 (the carousel itself); zone free 72-80 vs frozen 47-54 Layout.
open: result of dispatch 2; report `node src/lag/cli.mjs freeze-report --files a,b,c --sources "run <id> ..." --out ../../results/carousel-swap-webkit/hero-accent-frozen.md --json ...` from packages/measure-webkit; note section; dry land; review ready
conventions: 3 jobs at one commit; do not edit lag/probe.mjs or lag/report.mjs; the ci branch tip must stay the token commit while its run is open
pilot report of r3 (single job, commit 9997926ab, not pooled): results/carousel-swap-webkit/hero-accent-frozen-pilot.{md,json}
open: result of dispatch 2; report `node src/lag/cli.mjs freeze-report --files a,b,c --sources "run 40006432997 ..." --out ../../results/carousel-swap-webkit/hero-accent-frozen.md --json ...` from packages/measure-webkit; note section; dry land; review ready
conventions: 3 jobs at one commit; do not edit lag/probe.mjs or lag/report.mjs
