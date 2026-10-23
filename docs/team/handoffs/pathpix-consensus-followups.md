# pathpix-consensus-followups (measure-engineer)

- Branch `worktree-wf_9aacdd20-f29-1`; CI branch `ci/pathpix-consensus-followups`; worktree `.claude/worktrees/wf_9aacdd20-f29-1`.
- Last measured commit `f69f8cb29` (code = `0612ef447` + merge of main; the tip commit is empty and carries `[ci:path-pix]`).
- CI runs: 40037992429 (path-pix, in progress at this checkpoint; jobs sim x3, sim-draw x3, chromium x3, report).

## Built (committed)
- Lean `lean/Fw/Gate/PathPix.lean`: `MZone`, `zoned` (per-zone grade, varied zones dropped in mixed cells), `Verdict.listed`, draw pieces (`drawTimes`, `Draw`, `drawOf`, `Draw.worst`). Golden kinds `zoned`, `drawTimes`, `draw`, `drawWorst` in `packages/contracts/golden/gate/path-pix.jsonl` (regenerated, `--check` clean).
- TS `pathpix-exit.mjs` / `pathpix-exit-report.mjs`: consensus now zoned, `lookList` shows verdict next to grade and leaves varied cells out, hero summary has verdict columns.
- Chromium A3 arm: `packages/measure-chromium/src/pathpix.mjs` arm list `A, A2, A3, P`.
- Draw window (WebKit only, seeking is never done in Chromium): `pathpix-exit-draw-webkit.mjs` (lane), `pathpix-exit-draw-page.mjs` (page expressions), `pathpix-exit-draw.mjs` (pure analysis), `pathpix-cli.mjs --mode draw`, workflow job `sim-draw`.
- Local debug run (sim lease, under 5 min, not a result): all 4 arms captured, 0 unstable frames, A/A floor 0 at every frame.

## Open
- Wait for run 40037992429, fetch with `pnpm fw ci 40037992429`, run `pathpix-exit-report.mjs` and `pathpix-cli.mjs --analyze-only`, write the note sections in `research/notes/2026/10-2x-hero-copy-floor.md` and `results/accent-draw-nolayout-pixels/`.
- Class the hero_copy 192513-20 raster from the new run (majority reference); nav-earn 4478-2 may stay open if it does not recur.
- Dry land, `fw review ready`, final report. Chromium draw frames (native sampling, no seeking) is a follow-up.

## Conventions
- Never hand-edit the golden; regenerate with `lake env lean --run scripts/PathPixGolden.lean` after `lake build Fw.Gate.PathPix`.
- Read first: the note section "Consensus capture" and `lean/Fw/Gate/PathPix.lean` (`zoned`, `drawOf`).
