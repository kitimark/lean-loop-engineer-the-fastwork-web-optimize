branch: worktree-wf_21345e1b-595-1 (CI branch ci/hero-probe-original)
worktree: .claude/worktrees/wf_21345e1b-595-1 (under the repo root)
last commit: see `git log -1` (the commit carrying [ci:trajectory-probe])
CI runs: run 1 (trajectory-probe, fw=hero:scene-pause engines=chromium, all widths): pending, id filled in below

# hero-probe-original handoff

## State
- Lean `Fw.Gate.Trajectory` section FirstFrame: `byMFirst` = `byMRule` plus `firstVerdict`. Open@1 (bucket 1 of phase 0, push)
  empty in the rewrite AND absent from the original (all passes of the width) is `skip:origEmpty` (new `Skip.origEmpty`), not
  `fail:coverage`. Applies to every arm, so the faithful arm too; `rel` then compares the adjusted verdicts.
- Theorems: `firstVerdict_both_empty`, `_orig_sampled`, `_rew_sampled`, `_not_first`, `_content`, `_cases`, `byMFirst_mem`,
  `rel_origEmpty_not_new`, `rel_first_frame_before_after` (new before, ok after), `laneRed_origEmpty`, concrete `first_*`,
  `second_neither`, `close_neither`.
- Golden: 10 `byMFirst` lines in `packages/contracts/golden/gate/trajectory.jsonl` (regenerate: `cd lean && lake env lean --run
  scripts/TrajectoryGolden.lean`). TS twin: `byMFirst` in `packages/gate-breakpoints/src/trajectory/reduce.mjs`, used by
  `reduceWidth`; `verdictLines` adds a `FIRSTFRAME` line. `run.mjs` needed no change (it only calls `runCheck`).
- Premise MEASURED in control 39557718020 (390, Chromium): original open@1 in 0/5 passes, faithful 3/5, no-flag candidate 3/5.

## Verified
- `sh lean/scripts/check.sh` green; `pnpm --filter @fw/gate-breakpoints test` 663 pass; both through `fw slot`.

## Open
- CI run result for hero:scene-pause; ledger row hero.scenePause (docs/report/v2-report.md L43/L45 area) is the lead's.
- Other arms' verdict changes are listed, not re-run (accepted limit).
- Rule excuses only open@1; close@1 and other buckets keep fail:coverage. An original with one sampled pass keeps the rule off.

## Read first
- `lean/Fw/Gate/Trajectory.lean` (section FirstFrame), `docs/team/tools/trajectory-probe.md` (First frame paragraph).
