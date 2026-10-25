branch: worktree-wf_1025224f-bba-1 (CI branch ci/morph-end-remeasure, 3 pushes used of 3; no more pushes)
worktree: .claude/worktrees/wf_1025224f-bba-1
last commit: see git log (round 2 commit "morph-end-remeasure r2", then this handoff and the merge of main)
CI runs (all finished, pooled): toolbar-throttle 40158609202 (failed, 4 six-arm jobs lost), 40167641467 (job 2 failed, job 9 cancelled, artifact kept), 40193540518 (sim 1, 3, 10 lost runners, sim 2 exit 130); touch-lock lane: smoothness 40158609210 success; lean 40158609183 (fixed), 40167641470, 40193540707 success.
round 2 (review 1 refused: 2 blockers, 2 fix-before-land):
- blocker 1: verdicts now run Lean verdictOf on first-stretch pairs (perStretch, one open start per pass on both sides) against same-job faithful passes; the earlier whole-pass win is stated in the note as an exposure effect (1 open start against 4).
- blocker 2: brickVerdict/verdictOf take stillWorse (stillWorseOf: per job, every brick pass above every faithful pass of the job, at least one comparable job); theorems brickVerdict_trade_still, brickVerdict_win_iff, stillWorseOf_iff, verdictOf_still_worse, rates_perStretch; golden regenerated (57 lines), TS twin replays it.
- result: clamp no-win, flip no-win, release TRADE (fights 0 v 2.25, still runs 34.8 v 23.0, worse in all 4 jobs), all win, all+unthrottle win (first stretch only).
- fix-before-land: drift sentence (MEASURED: release-type page drops to scrollY 3513-4067 px after the first close; I count 19 passes with a record and 4953 px elsewhere, reviewer said 20 and 4932; cause untested; added to phone questions); stored pin 5183-5279.
verified: lean/scripts/check.sh green; measure-webkit 842, ci-paths 56, runner 3575 pass; fw plan lint: no writesClosure line for this task.
caveats: fight reading matters: spring-back fights (Lean unit) are lower; pin turns (TouchLock) overlap, which would make all three no-win. Both stated in the note. Pooling of rev/fight across jobs, only still runs per job.
TS stand-ins: firstStretch selection, same-job grouping (brickRow), report glue.
scratch: scratchpad/mer/ (pool3 data, jobs.mjs, drift.mjs, first.mjs); regenerate the pooled md with `node packages/measure-webkit/src/throttle/cli.mjs report --in <pool3 files> --md <out>`.
open: lead lands; phone step (re-open on second drag, drift, still runs); macos-vm-evidence owns lost-VM evidence; follow-up: push frame in the recorder to test the open-frame lag.
read first: lean/Fw/Measure/MorphEndCount.lean (verdict section), research/notes/2026/10-2x-morph-end-remeasure.md
