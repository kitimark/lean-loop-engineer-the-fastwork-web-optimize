branch: worktree-wf_5bf9b435-920-1 (no CI branch: no new CI)
worktree: .claude/worktrees/wf_5bf9b435-920-1
last commit: see `git log -1` (merged main; fix round after review 1: stall index, 9 retry slots, lane wording)
CI runs: none dispatched; analysed smoothness 41391781282, 41402584809, 41422536168, 41436626306, 41460411752, 41475879793, 41503168296
verified: Lean WindowLoss builds (sum, side, rank theorems), 43 golden lines, check.sh golden job wired, ci triggers.jsonl regenerated (`lake test -- --write-ci-trigger-golden`); window-loss.test.mjs 8/8; lint-wallclock ok
open: recommended follow-up change (retry a refused noOpen/tooShort window in place) not made; noOpen cause not isolated; tests, check.sh, dry land, review ready results are in the final report

Result: of 2016 planned windows 558 are kept; restartFailed 408, noOpen 248, noArtifact 144, inspectorDead 133, walkDeadline 121, planShort 100, driverNotReady 96, tooShort 75, evaluateTimeout 73, jobCut 38. Sides: ok 558, harness 726, simulator 732.
Here ok is a status-ok window with refusal none (Lean rowClass). The lane verdict (touchlock.mjs:177-183) also keeps a swipeLate or beginLate row that has frames and no refusal: 5 of the 9 such rows, so the artifacts' summary.arms.*.accepted sum to 563; this note counts those 5 as lost (swipeLate/beginLate). Sufficient jobs are the same either way (2 and 16 of 84).
After the stalled window itself 501 windows were lost, 13 ran ok (planShort excluded); stall chain 501 > refusals 323.
Sufficient jobs (every arm at minKept kept): 2 of 84; status-ok: 15 of 84 -> jobsFor 23; WalkBudget jobsNeeded 10 is far short.
Read first: research/notes/2026/11-03-touch-window-loss.md, then results/touch-window-loss/window-loss.md.
Lean: lean/Fw/Measure/WindowLoss.lean (Class, rowClass, endClass, jobWindows, tally, jobCounts_total, runCounts_total, side_partition, rank_sorted, jobsImplied). Golden packages/contracts/golden/measure/window-loss.jsonl, generator lean/scripts/WindowLossGolden.lean.
TS: packages/measure-webkit/src/window-loss.mjs (replays the golden), window-loss-cli.mjs (reads <root>/<run>/smoothness-webkit-sim-<n>[-retry]/{touch-lock.json,sim.log}; data only).
TS stand-ins (no golden; firstStall returns after: done - 1, planShort excluded from the stall chain): logFacts, restartTally, firstStall, jobOf, the CLI and its lever / first-stall / noOpen-by-rep tables.
Conventions: a `-retry` artifact replaces its slot; missing slot = noArtifact; the INCOMPLETE reason in sim.log wins over the artifact's "walk not finished".
Scratch (local, not committed): scratchpad/touch-window-loss/ (artifact downloads per run id, scripts).
