branch: worktree-wf_a3f3d112-fbe-1 (ci branch ci/accent-nolayout-measure)
worktree: .claude/worktrees/wf_a3f3d112-fbe-1
last commit: a3bb8cd67 (ci/accent-nolayout-measure tip, dispatch 2)
CI runs: webkit-sim 40030735082 at 7e3e5fc96 success (3 jobs, 13 units each; report results/accent-draw-nolayout/accent-report-40030735082.md);
webkit-sim dispatch 2 at a3bb8cd67 (draw counter fix for hashed keyframe names): run 40035116432 running.
Never pool the two runs (different commits); the two are reported side by side.

State: items 1, 3-11 built; item 2 (path-pix draw window) is out of this round (pathpix-consensus-capture owns it).
- Lean `lean/Fw/Measure/SwapWindow.lean` (busyFrozen, busyWindows, perCaptureTenths, perFrameMilli, laneBudgetMin 24, unitFits, armOrder, laneUnits) + golden kinds in `packages/contracts/golden/measure/wkcost.jsonl`.
- `packages/measure-webkit/src/lag/`: `freeze.mjs` (`hero-accent-draw`), `freezesession.mjs`, `accentsession.mjs` (13 units/job), `accentreport.mjs`, `swapreport.mjs` (arm column from FW flag, pooled section, `--summary`), `cli.mjs` (`--accent`, `accent-report`), `zoneprobe.mjs`, `costmode.mjs`, `swap.mjs`.
- Workflow `.github/workflows/webkit-sim.yml`: `[swap-accent]` token (PASSES=1, `--accent`).
- Note `research/notes/2026/10-2x-accent-draw-nolayout.md`: item 9 engine cites and design written; results pending.

Verified locally (tests, not measurements): package test 555 pass; ci-paths 56; runner land-inputs 56; Lean golden `--check`.
Open: the CI run (3 jobs at one commit), reports into `results/accent-draw-nolayout/`, results in the note, final lean check, plan lint, dry land, review ready.
Convention: push only `ci/accent-nolayout-measure` with `[ci:webkit-sim] [swap-lane] [swap-accent]` in the head message; at most 2 dispatches; never pool jobs from different commits.
Read first: the note above, then `src/lag/accentsession.mjs` and `accentreport.mjs`.
