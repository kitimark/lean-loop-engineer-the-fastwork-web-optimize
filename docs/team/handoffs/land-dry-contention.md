# land-dry-contention handoff

- Branch `worktree-wf_ce64bd7a-546-1`, worktree `.claude/worktrees/wf_ce64bd7a-546-1`; round 2 (findings applied), main merged.
- CI runs: none (accepted limit "no CI run").

## State
- Lean `Fw.Obs.Timing`: `landDryLoad = 4`, `Params.dryLandMax`, `Sample.dryLand` (tool `fw land`, step `dry*`),
  `contended` has two branches, each a theorem: `contended_of_load`, `contended_of_dryLand`; also `contended_cases`,
  `contended_between`, `landDry_three_contended` (the three 2026-10-24 samples: contended; same durations at load 4: slow).
  `not_contended_of_load_le`, `slow_at_normal_load`, `ceiling_at_normal_load` take `dryLand = true -> load <= dryLandMax`.
- Golden `packages/contracts/golden/obs/timing.jsonl`: 5 new rows (3 samples, load-4 contrast, non-dry `fw land` step),
  regenerated with `scripts/TimingGolden.lean`.
- Evidence and decision: `research/notes/2026/10-2x-land-dry-contention.md`. Finding: the extra load was outside the
  slot (locks.jsonl shows only the land's own hold), so serialization would not help; the improvement is the contended verdict.
- No TS verdict logic exists (fwcore decides), so no TS stand-in.

## Round 2
- Note: per-sample co-runner table (only 8f040f0 has a named co-runner; bf9aa85 and c4f662a rest on the load floor; cause unexplained), calm median definition, replay old 44 -> new 41 slow of 520 exit-0 rows.
- Lean: landDryLoad doc, theorem/case names no longer claim 'hides no regression', `dryLandMax` in params encoder and Wire paramsOf (golden row pins it), Health headline.

## Verified
- `lean/scripts/check.sh` green; @fw/runner 3300 tests, @fw/contracts 11, ci-paths 56; dry land VERDICT dry land-dry-contention; plan lint: no writesClosure error for this task.

## Open
- Writes outside the task: `lean/Fw/Obs/Health.lean` (`sysContended_iff_sample` gains `s.dryLand = false`),
  `lean/Fw/Plan/WritesClosure.lean` (`calm_iff` simp set). Both followed from changing `contended`.
- Effect (100 of 495 dry samples, 20 percent, leave the windows) is checked on later dry lands.
- The load cut 4 is INFERRED (the land's own load); revisit with more samples.

## Read first
- `lean/Fw/Obs/Timing.lean` `landDryLoad`, `contended`; the research note.
