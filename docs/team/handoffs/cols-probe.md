branch: worktree-wf_bd6be3b9-683-1 (CI branch ci/cols-probe, pushed at 74f5304bf then at the push-2 commit)
worktree: .claude/worktrees/wf_bd6be3b9-683-1 (under the main checkout)
last commit: see git log (data complete; the temporary workflow token is reverted in the last commit)
CI runs (all success): chromium-counts 40792572637 (unusable, wrong profile), 40802455145, 40812007208 (swipe-touch-v1, 12 jobs each); toolbar-throttle 40792572994, 40802455303, 40812007170 (Sim, 9 job files pooled)
Verified: check.sh green; Lean module, golden, measure-chromium cols-verdict + measure-webkit cols-report tests pass. Verdicts: Chromium pictures cost (both contrasts), WebKit Sim mixed (both), phone undecided; P2-P4 independent, P5 and P6 keep by the rule (P6 rests on Chromium alone).
Open: merge main, dry land, review ready; follow-up: RasterTask ms and render passes in trace.mjs; the earlier Chromium push-cycle proxy may not have reached the page end.

What it is: task cols-probe (P1 of research/notes/2026/10-27-end-columns-probe.md), CI lanes only. Lean Fw.Device.ColsProbe: arms
(base, base+off, timed-fixed, timed-fixed+off), search/wkArm/crLabel rows, pushLabel, flipValid (750 per mille), Cell.of (cost when every
off job is below the reference's lowest job; noCost when all inside its spread; few under 3 jobs), reading, fate of P2-P6.
TS twin packages/measure-chromium/src/cols-verdict.mjs (golden replay in test/cols-verdict.test.mjs). Chromium: run.mjs logs
takeLog (push/take with is-on-dark) into counts.json; src/cols-reduce.mjs <dir> reduces the chromium-counts-<label>-<run> tree.
WebKit Sim: push-cycle.mjs arms morph-base-off / morph-timed-off, push-cycle-pass.mjs logs takeLog, throttle/cols-report.mjs and
`push-cycle-cli.mjs cols --in <job files> --md --json`.

Findings so far (MEASURED, run 40792572994): Sim layerCount 128 and backing 122557120 B are the same in all arms (probe-off changes neither);
Paint base 57400 vs base+off 131666 per 1000 pushes (1 job each); timed-fixed pushes 12/12 took, 0/12 on-dark at push; Sim jobs lose passes
("push server: no ready file after 420 s", "Timeline.stop timed out"): 4 arms per job does not fit, so push 2 uses two arms per job.
Conventions: commit message tokens drive the lanes. The cols tokens are a TEMPORARY edit of .github/workflows/toolbar-throttle.yml (not in
the task's writes); patch results/cols-probe/toolbar-throttle-cols-token.patch; revert it before the dry land and list it in the report.
WebKit layerCount/backingBytes are the census after the last cycle, Paint is milli-paints per push window. The counts lane has no
RasterTask ms and no render-pass key: report those as not delivered (follow-up: add them to trace.mjs).
Read first: lean/Fw/Device/ColsProbe.lean, then research/notes/2026/10-2x-phone-cols-probe.md.
