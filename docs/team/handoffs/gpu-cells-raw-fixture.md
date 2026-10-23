branch worktree-wf_462a1737-49a-1 | worktree .claude/worktrees/wf_462a1737-49a-1 | last code commit 9cc61db06 (merge of main; git log -1 for the handoff commit)
CI runs: none started (no new dispatch). Fixtures come from the existing complete A/A runs 39823047557, 39852684450, 39861846900 (artifact cells-gpu-chromium).
Verified (MEASURED, local, at 9cc61db06, after merging main): check.sh green; gate-breakpoints 649/649; runner 2852/2852; dry land VERDICT dry (needs --allow for the 4 hand-edited files outside the writes); contracts 11/11; ci-paths 54/54; Lean `--raw` and JS `raw` print equal lists (36 lines, all E) and agree on six scratch mutants (L/Q mix).
Open: WebKit raws (follow-up); non-E agreement is scratch-only.

# gpu-cells-raw-fixture handoff

## What exists
- `packages/contracts/fixtures/trajectory-gpu/raw-<runId>.json`: trimmed Chromium A/A raws (per run role, width; morph rows m/rep/nodes; pain layer/cls; carousel v; integers only). Made by `node packages/gate-breakpoints/src/trajectory/cells-gpu-cli.mjs trim --in <raw> --out <file>` from `gh run download <id> -n cells-gpu-chromium -D <empty dir>`.
  - 39823047557: 3 swaps, recordings open mid-swap, holds 2,2,0 both arms.
  - 39852684450: 4 swaps, holds 2,2,0,0 vs 1,1,0,0 (base vs cand); the 640 close opacity-kink run.
  - 39861846900: 4 swaps, hold 1,1,0,0 vs 2,2,0,0 at 640 (the other direction).
  - 39860085568, 39863586490, 39823476824, 39824100493 add no shape (equal holds); not committed (about 330 KB per run).
- `cells-gpu-cli.mjs`: `trim`, `raw <fixture json|dir>...` (line `<run> <width> <cell> <part> <grade> <reps> [lag=.. | swaps=.. holds=..]`), exports trimRaw, rawLines.
- `lean/scripts/TrajectoryGpuGolden.lean --raw <file>...`: Lean reader (JSON pick-out, cells in cellsOfRaw order) calling Fw.Gate.TrajectoryGpu matchedGrade/panelCell/carouselCell/painCell/worst.
- `lean/scripts/check.sh` job `trajectory-gpu raw cells`: `cmp` of the two outputs over the three literal fixture paths.
- `lean/Fw/Gate/TrajectoryGpu.lean`: panelCell_series_e, panelCell_no_lag, panelCell_long_lag_l, panelCell_unmatched_l (shiftedGrade_ne_e + panelGrade_no_match_l), panelCell_matched_q.
- `packages/gate-breakpoints/test/trajectory-gpu-raw.test.mjs`: fixture shape, trimRaw round trip, units per width, hold shapes, mutants leave E.

## Conventions and limits
- TS stand-ins: Lean reader dpr per width (<= 640 is 2), MIN_COVERED 8, pain layer rounding (exact decimal in Lean, float in JS; fixtures have layer null).
- All fixture grades are E; non-E agreement only on scratch mutants. Chromium raws only; trimmed.
- Outside the graph writes (declared reads and the theorems): lean/Fw/Gate/TrajectoryGpu.lean, lean/Fw/Ci/Trigger.lean, packages/contracts/golden/ci/triggers.jsonl, lean/Fw/Console/LandSpeed.lean, apps/runner/src/land-reads.gen.ts, apps/runner/src/land.ts, packages/contracts/golden/console/land-speed.jsonl.

## Read first
`lean/scripts/TrajectoryGpuGolden.lean`, then `cells-gpu-cli.mjs` rawLines.
