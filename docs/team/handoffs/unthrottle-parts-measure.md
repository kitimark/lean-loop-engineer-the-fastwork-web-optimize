Branch: worktree-wf_3b6992a9-795-1
Worktree: .claude/worktrees/wf_3b6992a9-795-1 (under the repo root)
Last commit: c56f0ef81afcc496e57d1d04d73cdd9cba5c71b1 (round 3 note fix; this handoff is the next commit)
CI runs (toolbar-throttle lane; the lane yml on this branch now equals the ci-only commit bd492dcf3):
- 40098348176 on ci/unthrottle-parts-measure-drags (dispatch 1 of 3): success, 6/6 usable passes per arm, hero lifted
- 40101695202 on ci/unthrottle-parts-measure-finish (dispatch 2 of 3): attempt 1 failed, rerun (attempt 2) failed; jobs 2 and 3 gave 1 pass each (original, lift), job 1 stalled at start; no unthrottle pass
- 40101702393 on ci/unthrottle-parts-measure-rest (dispatch 3 of 3): attempt 1 failed, rerun success; 3 jobs, 6 usable passes per arm, platform anchor not found on all jobs
Verified: Lean check.sh green (before the last main merge; rerun after it, see report); @fw/measure-webkit test 665 pass; ci-paths test 56 pass; ci-paths --check ok; land-inputs test 60 pass; throttle-parts golden --check up to date (319 lines).
Open (follow-ups, not refusal grounds): Lean `judge` cadence domain (own lower bound on K, per pass or pooled, new golden vectors and TS replay); reducer `medianGapMs` over exercised passes only (midMoving > 0); commission Lean class (chase predicted pulses, measured stills) to revisit; platform anchor; partVerdict that ignores the original arm; permanent lane yml is on this branch (lands with it).

## State
- Lean: ThrottleParts.lean has Match, judge, PartVerdict, partVerdict, bandFor, one theorem per branch; golden has 240 judge, 40 partVerdict, 6 bandFor lines.
- parts.mjs: judge/partVerdict/bandFor are twins replayed in test/throttle-parts.test.mjs; judgeArm, partOf, why texts, noDataReason, captureRow are TS reporting.
- results/unthrottle-parts/: drags, finish (attempt 1, job 1), finish-...-rerun (jobs 2, 3), rest (3 jobs).

## Read first
research/notes/2026/10-2x-unthrottle-parts-measure.md (answer, tables), then 10-2x-unthrottle-parts.md (Lean predictions).
