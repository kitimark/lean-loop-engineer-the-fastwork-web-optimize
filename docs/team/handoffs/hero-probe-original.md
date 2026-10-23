branch worktree-wf_21345e1b-595-1, CI branch ci/hero-probe-original, run 39926829451 (sha f733e2083, success, CLEAN)
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
- Run 39926829451 (MEASURED, summary-chromium.md): CLEAN, 72 arms, 14416 units: pass 10342, fail 0, skip 4074, coverage
  failures 0; rels ok 14373, cleared 43, new 0. origEmpty 42 (candidate), baseOrigEmpty 0, all at width 640 open@1.
- Same raw-chromium.json re-reduced offline with main's old reduce.mjs: RED, new=42, all fail:coverage at width 640 open@1
  (a dev check, not a result). Open@1 sampled passes of 5 (orig/base/cand): 390 1/1/1, 640 0/1/0, 641 1/0/2, 1280 5/5/4.
## Open
- Ledger row hero.scenePause stays partly-proved (lead): CLEAN in run 39926829451 rests on open@1 sampling jitter at 640/641; follow-up trajectory-first-coverage.
- Outside the task writes: docs/team/tools/trajectory-probe.md (First frame paragraph); land with --allow docs/team/tools/trajectory-probe.md.
- Other arms not re-reduced: which arms' open@1 units turn from fail:coverage to skip:origEmpty is unknown until each arm's trajectory raw is re-reduced with byMFirst (accepted limit).
- Rule excuses only open@1; close@1 and other buckets keep fail:coverage. An original with one sampled pass keeps the rule off.
- No workflow trigger or CI table change needed (`node --test scripts/ci-paths.test.mjs` passes).
## Read first
- `lean/Fw/Gate/Trajectory.lean` (section FirstFrame), `docs/team/tools/trajectory-probe.md` (First frame paragraph).
