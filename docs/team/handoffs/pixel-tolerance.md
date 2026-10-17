# Handoff: pixel-tolerance

**State.** Done on branch `worktree-agent-a0d87fe8c3a459e2c` (one commit on top of ff55f4e). `sh lean/scripts/check.sh`
and `pnpm --filter ./packages/measure-chromium test` green.

**What changed.**
- `lean/Fw/Measure/Classes.lean`, section "Pixel-area types": `TypeUnit`, `unitOf` (name ends in `AreaPx` -> px),
  `PxTol` (default `pxTolDefault = 1/1000`), `minAbsTotal`, `tBound` (count: tMax; px: max(tMax, floor(num * min|total| / den))),
  `policyFor`, `classifyU`, `classifyAllU`. Proved: `classifyU_count` (counts unchanged), `classifyAllU_eq_of_counts`,
  `tMax_le_tBound`, `le_tBound_px_iff`, `classify_policy_mono`, `classifyU_le_classify`, `classifyU_sound`,
  `classifyU_strictest`, `classifyU_quarantined_iff`, `tBound_anti`, `classifyU_mono` (runs), `classifyU_tol_mono`,
  `classifyAllU_types` (one row per key: total), `classifyAllU_row`, `classifyAllU_sound`.
- Why the smallest total: adding runs only lowers it, so `classifyU_mono` holds like `classify_mono`.
- `Wire.lean` `measure.classify` frames: uses `classifyAllU`; optional `pxRel {num, den >= 1}`; px rows add `unit`,
  `tBound`; count rows are byte-identical to before (existing goldens unchanged). 5 new goldens in
  `packages/contracts/golden/measure/measure.classify.jsonl` (via `Golden.lean`), one client test in `fwcore.test.mjs`.
- No TS change needed: CI's `src/classify.mjs` already calls fwcore `measure.classify` with kMax/tMax only, so the
  Lean default applies. `src/classes.mjs` is the SelfCheck classifier (already relative 0.2 % / 2 %), left unchanged.
- Part 2: 14 r7a docstring fixes in `SelfCheck.lean` (8) and `Snapshot.lean` (6), math only.

**Re-class of the spk-i CI runs (MEASURED, fwcore on downloaded counts.json, no new measurement).**

| Run | old det/stable/quar | new |
|---|---|---|
| 39029423874 | 33/20/9 | 33/22/7 |
| 39031884554 | 31/21/10 | 31/23/8 |
| 39033771018 | 27/25/10 | 27/27/8 |

census.activeTileAreaPx and census.drawingAreaPx leave quarantine in all 3 runs (max gap 382 ppm of the smallest
total, run 39033771018); no count type changes class.

**Open.** `lean/README.md` op row for `measure.classify` does not mention `pxRel`/`unit`/`tBound` (outside my write
scope). spk-i.md / class-policy.md numbers not updated (lead). Math view regeneration for the new entries (page-writer).

**Read first.** The section header comment in `Classes.lean` (after `classifyAll_sound`).
