branch: worktree-wf_789d4038-d56-1
worktree: .claude/worktrees/wf_789d4038-d56-1
last commit: see `git log -1` (code commit 79b5478c6, then the handoff)
CI runs: none (accepted limit: no CI run for this task)
verified: lean/scripts/check.sh, `@fw/runner` test, `@fw/contracts` test, ci-paths test, plan lint (results in the report)
open: none; the report lists writes outside the graph (none expected)

What changed
- (1) `Fw.Obs.Timing.ownOfPhases` (+ theorems `ownOfPhases_some`, `_not_done`, `_no_upd`, `_after_end`, #guards). `Fw.Wire.Obs.Timing.ownOfJson`
  decodes raw `startMs`/`durMs`/`phases{how,updMs}` in `sampleOf`; the `ownMs` JSON key is no longer read. `sampleJson` writes the raw
  form, so golden/obs/timing.jsonl round-trips (#guard in Wire/Obs.lean). TS `ownOf` is gone; `rawOf` (timing.ts) forwards well-formed facts.
- (2) `fw polish commit` that keeps nothing now notes `checks = {0, []}` (class light, `NO_CHECKS`); the remaining unkeyed writer
  (fwcore gave no command list) is intentional and documented on `stagedSpan` and `unkeyedLate`.
- (3) `Fw.Obs.Next.alertsFrom` (+ `alertsFrom_map`: its subjects are `slowLatestFrom`); `obs.slow` `details` come from the last alert
  verdict of the subject, named `<host> sample (startMs N, commit C)` via `SampleVerdict.detailWith`. `Sample` gained `startMs`, `commit`.
- (4) `verdictsOf_ciWait_not_slow` (whole output); Next.lean docstrings and `slowOf` now use `verdictsOf`.
- (5) land-dry.test.ts lake case: `rmSync` in `finally`, step derived with fw-main's `lastDryStep` replace.

Conventions: regenerate with `cd lean && lake env lean --run scripts/TimingGolden.lean` (`--check`); never hand-edit goldens.
Read first: `ownOfPhases`, `verdictsOf_ciWait_not_slow` in lean/Fw/Obs/Timing.lean; `ownOfJson`, `alertLine` in lean/Fw/Wire/Obs.lean.
