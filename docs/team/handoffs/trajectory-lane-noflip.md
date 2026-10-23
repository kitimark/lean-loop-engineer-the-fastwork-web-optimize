# trajectory-lane-noflip (lean-prover)

- Branch `worktree-wf_03888c75-8c3-1`, worktree `.claude/worktrees/wf_03888c75-8c3-1`, code commit af7e459a4.
- CI runs: none started (no probe needed); evidence runs 39926829451 and 39557718020 re-reduced offline (dev check).
- Verified: `lean/scripts/check.sh` green (axioms standard, trajectory golden 342 lines up to date); `@fw/gate-breakpoints`
  tests 692/692; `scripts/ci-paths.test.mjs` 54/54; runner `land-inputs` 56/56.
- Open: ledger row `hero.scenePause` in `docs/report/v2-report.md` (lead). WebKit cadence still unmodelled.

## What changed
- `rel`: a faithful `skip:firstOpen` is `undecided` against any failing candidate (coverage or content), and a candidate
  `skip:firstOpen` is `undecided` against every non-failing base (also `skip:firstOpen`). Content is included because
  `rel (fail apart) (fail coverage) = unmeasured` would otherwise go to `new` when the faithful arm steps missing -> undecided.
- Lane theorem `laneOf_extra` (section FirstFrame): units `FirstUnit` with arms `Arm.fixed v | Arm.cover nw`, shared original
  `(no, k)`, `k <= no`; one extra original pass per unit (hit or miss) never moves `laneOf` red <-> clean. Unit step
  `unit_extra` from finite tables `flip_both`, `flip_base`, `flip_cand` and `jump_extra` (from `firstCover_extra`).
- Counterexample guards `openAt`, `openLane` on `passesWith 5 3` vs cand 5 / faithful 4 passes: UNDECIDED before and after.
- Timing link `lateRate_delays`: the original's late rate is the share of passes at least 2 vsyncs late (`sampled_iff`);
  the same-distribution assumption is stated in `docs/team/tools/trajectory-probe.md` (First frame).
- Golden: rel rows `first open both` (now undecided), `first open base coverage`, `first open base content`; op `laneStep`
  (3 rows). JS twin `rel` in `reduce.mjs`; `cli.mjs` summary prints `red.lane.toUpperCase()` and an `undecided` row.

## Offline re-reduction (this branch)
| run | lane | new | undecided | open@1 skip:first units |
|---|---|---|---|---|
| 39926829451 (?fw=hero:scene-pause) | CLEAN | 0 | 0 | 42 firstLate vs pass, 42 pass vs firstLate |
| 39557718020 (default) | CLEAN | 0 | 0 | none |
Read first: section FirstFrame in `lean/Fw/Gate/Trajectory.lean` (from `laneOf_red_iff`).
