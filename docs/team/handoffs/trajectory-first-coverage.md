# trajectory-first-coverage (lean-prover)

- Branch `worktree-wf_c8ba7449-951-1`, worktree `.claude/worktrees/wf_c8ba7449-951-1`, last code commit 5133cca8f (then a merge of main and this note).
- CI runs: none new; evidence stays runs 39926829451 and 39557718020 (both completed, CLEAN).
- Verified: `lean/scripts/check.sh` green (axioms standard, golden 337 lines up to date); `test/trajectory.test.mjs` 372/372;
  `scripts/ci-paths.test.mjs` 54/54. Other gate-breakpoints test files fail only on `playwright-core` not installed in this worktree.
- Open: `src/trajectory/cli.mjs` summary header still prints `red.red ? 'RED' : 'CLEAN'` and has no `undecided` row (outside
  this task's writes; use `red.lane`). WebKit cadence (only Chromium's 17 ms is modelled). Ledger row `hero.scenePause` in
  `docs/report/v2-report.md` is the lead's.

## What changed
- Lean `Fw/Gate/Trajectory.lean` section FirstFrame: `mAt`, `mAt_first_iff` (bucket 1 = elapsed 12-35 ms), `slots_cadence`,
  `sampled_iff`; `firstCover no k nw` (missing / late / undecided at `alpha` 1/20), `coverVerdict`, new `firstVerdict`;
  no-flip theorems `firstCover_extra` (one more original pass, hit or not), `firstCover_step`, `firstCover_more`,
  `firstCover_fewer`; concrete `first_five`, `first_extra_pass`. `Skip.origEmpty` is gone: `skip:firstLate`, `skip:firstOpen`.
  `Rel.undecided` (candidate `skip:firstOpen` where the faithful arm's is not), `laneOf` (red / undecided / clean).
- Golden ops `firstCover` (table no 0-6, k 0-7, nw 0-6) and `lane`; JS twin in `reduce.mjs` (`firstCover` by BigInt cross
  multiplication, `laneOf`, `red.lane`, VERDICT word RED/UNDECIDED/CLEAN, FIRSTFRAME counts).

## Offline re-reduction (dev check, main's reducer vs this branch)
| run | width | open@1 before | open@1 after | lane before / after |
|---|---|---|---|---|
| 39926829451 | 390, 641, 1280 cand | pass | pass | CLEAN / CLEAN |
| 39926829451 | 640 cand | skip:origEmpty | skip:firstLate | |
| 39926829451 | 641 faithful | fail:coverage (cleared) | skip:firstLate (ok) | cleared 43 to 1 |
| 39557718020 | 390 | pass | pass | CLEAN / CLEAN |

Read first: `docs/team/tools/trajectory-probe.md` (First frame paragraph), then FirstFrame in `Trajectory.lean`.
