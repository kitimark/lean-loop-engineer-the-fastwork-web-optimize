branch: worktree-wf_bd6be3b9-683-1 (CI branch ci/cols-probe at the same commit)
worktree: .claude/worktrees/wf_bd6be3b9-683-1 (under the main checkout)
last commit: 74f5304bf (push 1)
CI runs: push 1: chromium-counts 40792572637 (queued), toolbar-throttle 40792572994 (queued), lean 40792572727 (queued)
Verified: Lean module builds (lake build Fw.Device.ColsProbe), golden cols-probe.jsonl up to date, measure-chromium cols-verdict test 9 pass, measure-webkit cols-report + morph-push + push-cycle tests 35 pass. check.sh and package tests through the slot are still to run.
Open: wait for push 1 (fw ci wait), reduce, up to 2 more Sim pushes if jobs are lost, note + ledger, merge main, revert the workflow token, dry land.

What it is: task cols-probe (P1 of research/notes/2026/10-27-end-columns-probe.md), CI lanes only. Lean Fw.Device.ColsProbe: arms
(base, base+off, timed-fixed, timed-fixed+off), search/wkArm/crLabel rows, pushLabel, flipValid (750 per mille), Cell.of (cost when every
off job is below the reference's lowest job; noCost when all inside its spread; few under 3 jobs), reading, fate of P2-P6.
TS twin packages/measure-chromium/src/cols-verdict.mjs (golden replay in test/cols-verdict.test.mjs). Chromium: run.mjs logs
takeLog (push/take with is-on-dark) into counts.json; src/cols-reduce.mjs <dir> reduces the chromium-counts-<label>-<run> tree.
WebKit Sim: push-cycle.mjs arms morph-base-off / morph-timed-off, push-cycle-pass.mjs logs takeLog, throttle/cols-report.mjs and
`push-cycle-cli.mjs cols --in <job files> --md --json`.

Conventions: commit message tokens drive the lanes: [counts profile=push-cycle-d1000 runs=3 target=rewrite arms=...] and
[throttle:push-cycle-morph:cols]. The cols token is a TEMPORARY edit of .github/workflows/toolbar-throttle.yml (not in the task's
writes); the patch is results/cols-probe/toolbar-throttle-cols-token.patch; revert it before the dry land and list it in the report.
WebKit layerCount/backingBytes are the census after the last cycle, Paint is milli-paints per push window. The counts lane has no
RasterTask ms and no render-pass key: report those as not delivered (follow-up: add them to trace.mjs).
Read first: lean/Fw/Device/ColsProbe.lean, then research/notes/2026/10-2x-phone-cols-probe.md.
