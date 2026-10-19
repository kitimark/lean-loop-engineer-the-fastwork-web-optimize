# Handoff integrate-wave-1 (lead-owned, run by a measure agent)

State: branch `integrate-wave-1` (from main 4283c5a1), CI branch `ci/integrate-wave-1` (at 4283c5a1; never pushed again, so no `stale:` abort).
Read first: research/notes/2026/10-19-integrate-wave-1.md.

Verified (MEASURED on CI, free runners)
- Gate default arm, run 39184687325: Chromium pass (7056 readings, 0 bad, 7 excused, was 64), WebKit incomplete (2 bad = the same two
  phone-rotation not-comparable cells as main's 39142015714). No new failing cell. The 57 commission live-resize readings now pass.
- Counts, 6 workflow runs (swipe-v1 39184638066 39186469962 39186477379; swipe-touch-v1 39184646781 39186485136 39187013275), target both,
  image pinned `image_run=39049264131`. PaintImage/DecodeImage/ImageDecodeTask rise as expected (note table).
- Faithful verdict on run 1 of each profile: all six region zones FAIL (Lean), control passes; touch tail 15 to 10 off-band cells.
- Refreeze class table accepted by `freeze.mjs` (Lean): R now 30/22/18 and 27/26/17 det/stable/quar over 70 types; baselines under it have detDrift 0, 0 unlisted.

Not done / open
- v2-proved gate: impossible with `breakpoint-gate.yml` (fw input becomes `?fw=...`; run 39185920522 died at start, 0 readings). Needs a `preset`
  input (FW_SEARCH=`?preset=<name>`) or a prerendered eight-flag `?fw=` key. Workflow is outside the writes of this task.
- To adopt the refreeze: `results/refreeze-wave-1/classes.proposed.json` is the exact `freeze.mjs --out` output; copy it to
  `packages/measure-chromium/classes.frozen.json`, then `zone-baseline.mjs baseline --out results/baselines/chromium --profile p --target rewrite`
  (needs the zones files from `zone-baseline.mjs --store ... --run`), then `faithful.mjs verdict` and `faithful.mjs lean` (Measured.lean is stale: DIFFERS).
  results/baselines/chromium/*/rewrite.* stay the early rewrite (385/409 frames) until then; the new R fails their test invariants under the old table.
- Drop the unused `commissionResizeStops`/`resizeExemption` entries in `Fw.Gate.Exit` (Lean change; their own note says so).
- Per-part cause of the R class changes (rAF, EventDispatch, FunctionCall quarantined) and of the newly off-band `raster.invalidatedLayers` is INFERRED, not diagnosed.

Conventions: `pnpm install --offline --frozen-lockfile` in the worktree flips apps/runner/src/fw.ts to mode 755 (do not commit it). Store is the main
checkout's `.fw-console/store`; `fw ci` refuses a second run with the same key (use `gh run download -R <repo> --pattern 'chromium-c*'` for freeze inputs).
`gh run download` outside a git dir needs `-R kitimark/lean-loop-engineer-the-fastwork-web-optimize`.
