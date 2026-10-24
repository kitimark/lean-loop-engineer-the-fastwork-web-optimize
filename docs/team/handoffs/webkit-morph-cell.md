# webkit-morph-cell handoff

- Branch: `worktree-wf_a29b6a9d-e3d-1`; CI branch `ci/webkit-morph-cell`; worktree `.claude/worktrees/wf_a29b6a9d-e3d-1`.
- Last commit when written: `2e8054195` (trigger commit; the Lean/TS work is `8dae67ead`).
- CI runs: trajectory-probe 40097658094 (push, preset=v2-proved, Chromium+Linux WebKit) success; trajectory-probe 40099056290 (dispatch, Linux+Mac WebKit) success; lean 40097658170 success. Mac morph pass in 40099056290.
- Cause (CONFIRMED, run 40080296257): the probe emulates a fine pointer at 641 and 1280, so `engine.scroll:unthrottle` (all rules
  behind `(pointer: coarse)`) is inactive there; all 127 new Mac morph units sit at those two widths; the pooled repeat rule then
  gives "no verdict: coverage".
- Done: Lean `Fw.Gate.Trajectory` per-width `Basis` (`basisAt`, `Group.measured`, `outcome` over measured widths), a theorem per
  branch, `inactive_unthrottle_same`; golden ops `cellEnv` and `cell`; TS twin in `plan.mjs` (`cellOutcome`), replayed by
  `test/trajectory.test.mjs` (722 tests pass); `Gen.run` regenerated: v2-proved = `engine.scroll:unthrottle`.
- Note: `research/notes/2026/10-2x-webkit-morph-cell.md` (Results section filled after the run).
- Open: breakpoint gate on preset=v2-proved both engines (lead dispatch: pnpm -s fw run --gate --engines both --preset v2-proved --ref ci/webkit-morph-cell); land dry and review ready.
- Follow-up (named): `webkit-morph-walk-noise`, Mac morph coverage noise for flags active at every width.
- Conventions: regenerate with `cd lean && lake env lean --run scripts/TrajectoryGolden.lean` and
  `printf 'import Fw.Preset.Gen\n#eval Fw.Preset.Gen.run []\n' | lake env lean --stdin`; never hand-edit the outputs.
- Read first: the note, then `lean/Fw/Gate/Trajectory.lean` (`basisAt`, `outcome`), `plan.mjs` (`cellOutcome`).
