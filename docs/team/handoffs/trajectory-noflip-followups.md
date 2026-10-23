# trajectory-noflip-followups

- Branch `worktree-wf_85b609fd-a1c-1`, worktree `.claude/worktrees/wf_85b609fd-a1c-1`; work commits 74ba4abfa, 072402f55, merged main.
- No CI run made; offline re-reduction of runs 39926829451 and 39557718020 (dev check).

## Verified
- Lean `section Stable` in `lean/Fw/Gate/Trajectory.lean`: `family`, `stableRel`, `stableOf`, `laneOf_stable_extra`
  (no RED/CLEAN flip on one extra original pass, any unit verdict), `mem_family_extra`, `family_one`; counterexamples
  `contentRel`/`bumpPass` #guards show the plain `rel` flips both ways; `laneExit` (strict UNDECIDED exits 3), `exitJoin`.
- `slow_cadence_phases`: at 141 ms frames, 24 of 141 vsync phases reach open@1 (WebKit timing link is phase, not delay).
- JS twin in `src/trajectory/reduce.mjs` (`family`, `stableRel`, `unitRel`, `byMFam`, `laneExit`, `exitJoin`), checked by
  golden ops `stable` and `exit`; reduceRaw and CLI `--strict` tests in `test/trajectory.test.mjs`.
- Offline: 39926829451 CLEAN (14416 units, leave-one-out 0); 39557718020 CLEAN (3604 units).

## Open
- Golden `packages/contracts/golden/gate/trajectory.jsonl` changed (+9 rows, exit join table): CI golden.
- Cost: jackknife re-reduces the morph path once per original pass (run A 8.7 s to about 40 s offline).
- CLI `summary` with no raw file still exits 1, the same code as strict RED (pre-existing).

## Conventions
- Golden: `cd lean && lake env lean --run scripts/TrajectoryGolden.lean` (`--check` to verify); never hand-edit.

## Read first
- `docs/team/tools/trajectory-probe.md` check 2 (Leave-one-out band, WebKit cadence) and check 3 (Exit codes).
