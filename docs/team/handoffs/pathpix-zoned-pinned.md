# pathpix-zoned-pinned (lean-prover)

- Branch `worktree-wf_60350621-05c-1`; worktree `.claude/worktrees/wf_60350621-05c-1`; last commit: `git log -1` (main merged).
- CI runs: none started (no dispatch, no push). Run read: 40037992429 (complete), through its committed results under
  `results/accent-draw-nolayout-pixels/run-40037992429/`.

## Built
- Lean `lean/Fw/Gate/PathPix.lean`: `zonedPinned` with `zonedPinned_of_ok` (equals `zoned` when `rowsOk` of the checked rows),
  `zonedPinned_of_not_ok` (`.graded .invalid`), `zonedPinned_eq`; `drawFrames`, `drawIdle`, `drawBase`, `aboveBase` with
  `drawBase_some_iff`, one `none` theorem per failing condition, `aboveBase_restores`, `aboveBase_head`, `aboveBase_const`.
- Golden kinds `zonedPinned` (zoned cases x 4 row sets) and `drawBase` (6 measured lanes of run 40037992429 + 5 negatives);
  `#guard`s pin the F lanes to the note's column.
- `pathpix-exit.mjs`: `zonedPinned` (production call for the consensus verdict), `drawBase`, `aboveBase`; replayed by
  `test/pathpix.test.mjs`.
- Note: item-5 column now cites `aboveBase`; new section "Pinned zoned reading and draw baseline" with the open items.

## Open
- Chromium draw frames (needs native sampling and a CI run); 192513-20 signature rule (one value, needs recurrence);
  first mixed cell (next path-pix run reports it).
- Follow-up outside the task writes: `pathpix-exit-draw-zones.mjs` could print the `aboveBase` column into `zones.md`.

## Conventions
- Golden: `lake build Fw.Gate.PathPix`, then `lake env lean --run scripts/PathPixGolden.lean > ../packages/contracts/golden/gate/path-pix.jsonl` from `lean/`; `--check` must pass.
- Read first: the note section above and `zonedPinned` / `drawBase` in `PathPix.lean`.
