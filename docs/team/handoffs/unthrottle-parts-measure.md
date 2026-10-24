Branch: worktree-wf_3b6992a9-795-1
Worktree: .claude/worktrees/wf_3b6992a9-795-1 (under the repo root)
Last commit: ea1ece49c (round 2: Lean judge, partVerdict, bandFor + golden replay at 81bd93cc2; lane yml at the commit after it; note denominators at ea1ece49c)
CI runs (toolbar-throttle lane, ci-only commit bd492dcf3 = yml edit, now also on this branch):
- 40098348176 on ci/unthrottle-parts-measure-drags (dispatch 1 of 3): success, 6/6 usable passes per arm, hero verdict lifted
- 40101695202 on ci/unthrottle-parts-measure-finish (dispatch 2 of 3): attempt 1 failed (VM 1 original+rewrite only); attempt 2 (gh run rerun --failed by the lead): sim jobs queued/in_progress at 2026-10-24 ~16:20 UTC
- 40101702393 on ci/unthrottle-parts-measure-rest (dispatch 3 of 3): attempt 1 failed (VM 1 gave 8 usable passes); attempt 2 (rerun --failed): VM 2 and 3 queued
Verified: Lean check.sh green at ea1ece49c; @fw/measure-webkit test 665 pass; ci-paths test 56 pass; ci-paths --check ok; throttle-parts golden --check ok (319 lines).
Open: reruns of finish and rest not finished (data not yet in the tables); apps/runner land-inputs test; fw plan lint; dry land; fw review ready.

## State
- Lean: ThrottleParts.lean has Match, judge, PartVerdict, partVerdict, bandFor with one theorem per branch; golden has 240 judge, 40 partVerdict, 6 bandFor lines.
- src/throttle/parts.mjs: judge/partVerdict/bandFor are twins replayed on the golden; judgeArm/partOf/why texts/noDataReason/captureRow are TS reporting.
- Lane yml now reproduces the runs (parts-cli, four arms, [throttle:rest], ROUNDS, timeouts 75/58).
- results/unthrottle-parts/ holds the three summaries from the first attempts; rerun data is added when the runs finish.

## Read first
research/notes/2026/10-2x-unthrottle-parts-measure.md (answer, tables), then 10-2x-unthrottle-parts.md (Lean predictions).
