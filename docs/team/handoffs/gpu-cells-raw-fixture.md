branch worktree-wf_462a1737-49a-1 | worktree .claude/worktrees/wf_462a1737-49a-1 | last code commit: git log -1 (WIP 1c25327cb)
CI runs: none started (no new dispatch; the fixtures come from the existing A/A runs 39823047557, 39852684450, 39861846900, artifact cells-gpu-chromium, all complete).
Verified so far (MEASURED, local): Lean `--raw` and JS `raw` print equal grade lists (36 lines, 3 runs x 2 widths x 6 units, all E); the same holds on six mutated copies of 39852684450 (blur 0, stale panel, nav shift, pain flip, truncated carousel: L/Q/E mix). Lean `lake build Fw.Gate.TrajectoryGpu` green with the new panelCell theorems. gate-breakpoints trajectory-gpu-raw test 5/5.
Open: check.sh, package tests, dry land (see the report); WebKit raws (follow-up).

# gpu-cells-raw-fixture handoff

## What exists
- `packages/contracts/fixtures/trajectory-gpu/raw-<runId>.json`: trimmed Chromium A/A raws (fields cellsOfRaw reads: per run role, width, morph rows m/rep/nodes, pain layer/cls, carousel v; integers only). Made by `node packages/gate-breakpoints/src/trajectory/cells-gpu-cli.mjs trim --in <raw-chromium.json> --out <file>` from `gh run download <id> -n cells-gpu-chromium -D <empty dir>`.
  - 39823047557: 3 swaps, recordings open mid-swap, holds 2,2,0 both arms.
  - 39852684450: 4 swaps, holds 2,2,0,0 vs 1,1,0,0 (base vs cand); the 640 close opacity-kink run.
  - 39861846900: 4 swaps, hold 1,1,0,0 vs 2,2,0,0 at 640 (the other direction).
  - 39860085568 and 39863586490 add no shape beyond these (holds equal), so they are not committed; the older 39823476824 and 39824100493 likewise (size: about 330 KB per run).
- `cells-gpu-cli.mjs`: `trim`, `raw --in <dir|file>` (one line per unit: `<run> <width> <cell> <part> <grade> <reps> [lag=.. | swaps=.. holds=..]`), exports trimRaw, rawLines.
- `lean/scripts/TrajectoryGpuGolden.lean --raw <file>...`: the Lean reader (JSON field pick-out, cells assembled in cellsOfRaw order) calling Fw.Gate.TrajectoryGpu matchedGrade/panelCell/carouselCell/painCell/worst. Same output text.
- `lean/scripts/check.sh` job `trajectory-gpu raw cells`: `cmp` of the two outputs.
- `lean/Fw/Gate/TrajectoryGpu.lean`: panelCell_series_e, panelCell_no_lag, panelCell_long_lag_l, panelCell_unmatched_l (shiftedGrade_ne_e + panelGrade_no_match_l), panelCell_matched_q.
- `packages/gate-breakpoints/test/trajectory-gpu-raw.test.mjs`: fixture shape, trimRaw round trip, units per width, hold shapes, mutants leave E.

## Conventions and limits
- TS stand-ins: the Lean reader's dpr per width (<= 640 is 2, else 1; registry envFor), MIN_COVERED 8, pain layer rounding (exact decimal in Lean, float in JS; fixtures have layer null).
- All fixture grades are E; non-E agreement is shown only on mutants (scratch, not in check.sh).
- Chromium raws only; trimmed, not the full artifact.
- Outside the task's graph writes: lean/Fw/Gate/TrajectoryGpu.lean (the theorems).

## Read first
`lean/scripts/TrajectoryGpuGolden.lean`, then `cells-gpu-cli.mjs` rawLines.
