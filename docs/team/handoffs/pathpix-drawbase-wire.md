# pathpix-drawbase-wire (measure-engineer)

- Branch `worktree-wf_2b2f2269-4a9-1`; worktree `.claude/worktrees/wf_2b2f2269-4a9-1`; last commit: `git log -1` (main merged).
- CI runs: none (no dispatch, no push). Fixtures: the committed `results/accent-draw-nolayout-pixels/run-40037992429/job-{1,2,3}/cells.json`.

## Built
- Test (`packages/measure-webkit/test/pathpix.test.mjs`): the six lanes (jobs 1-3, arms N and F, `rest.changed` of the 14 frames) equal
  the golden `drawBase` rows `run 40037992429 job-N X` (lane, base, above); a second test sends them and the golden negatives
  through fwcore; a third checks the committed `zones.md` equals what the script prints. The fwcore tests skip when the binary is not built.
- Script (`packages/measure-webkit/src/pathpix-exit-draw-zones.mjs`): `outsideLane`, `withAbove` (fwcore `gate.pathpixDrawBase`),
  `aboveTable`; `zoneTable` appends the table when every job carries `above`. Formatting only.
- `zones.md` regenerated: `node src/pathpix-exit-draw-zones.mjs d1=<job-1/cells.json> d2=... d3=...` from `packages/measure-webkit`.
  The old tables are unchanged; the new one has baselines 100/1965/17 (N) and 35751/101/100 (F), and the F column 0 x7, 17622, 16871, 12709, 8584, 2092, 0, 0.

## Writes outside the task (needed: fwcore had no op for drawBase)
- `apps/runner/src/land.ts`: one read glob (`results/accent-draw-nolayout-pixels/run-40037992429/**`) for packages/measure-webkit, asked by land-inputs.
- New `lean/Fw/Gate/PathPixWire.lean` (op `gate.pathpixDrawBase`, theorems `laneJson_pinned`, `laneJson_unpinned`), registered in
  `lean/Fw/Wire.lean` (import, `ops`, dispatch) and `lean/Fw.lean` (import).

## Open
- No golden file for the wire op itself (the test replays the PathPix golden rows through it); Chromium draw frames and the
  192513-20 rule stay open as in `pathpix-zoned-pinned.md`.
- Read first: `pathpix-exit-draw-zones.mjs`, `Fw/Gate/PathPixWire.lean`.
