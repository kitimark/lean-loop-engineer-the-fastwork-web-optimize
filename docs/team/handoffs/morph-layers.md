# morph-layers handoff (branch worktree-wf_f4cccc1d-568-2)

State: variant `morph.mount:shift-dormant` built, measured and noted. CI ran on ci/morph-layers at d5a219cc. Later
commits add only the note, `animStart_eq_mountStart` and the regenerated preset decisions row (`no-link`).

Verified:
- Attribution of the 9 Chromium layers (probe ci/morph-layers-probe, 1f7ef2d6, never landed): 3 tracks
  [ActiveTransformAnimation], panel [FixedPosition], backdrop, 2 column + center + nav bar [Overlap]. WebKit sim
  run 39309416016 (`shift`, y=0): 11 panel layers + nav bar, all hung on the 3 animated tracks.
- `lean/Fw/Parts/MorphMountDormant.lean`: `dormant` (+ `#guard`s), `animated_eq_mountO`,
  `animStart_eq_mountStart`, `visSame_dormant` (from HiddenBefore), `layerize` model with `layers_dormant_eq` and
  `census_dormant_eq` under the `Absorbed` premise (INFERRED). Golden `morph.mount.dormant.jsonl` and its TS replay
  test; no TS stand-in.
- chromium-counts, 3 runs per arm: dormant drawingLayers/layers equal faithful per frame (swipe and touch);
  the +1053 / +1134 of `shift` is gone. Recalc: dormant equals faithful on swipe and is -1 on touch; `shift`'s
  trigger-frame recalc win is given back. Layout keeps -3 of `shift`'s -4.
- `sh lean/scripts/check.sh` green at the final commit; apps/site tests, ci-paths and land-inputs tests pass.

Open:
- Breakpoint gate run 39312308450 (`fw=morph.mount:shift-dormant`). Attempt 1 failed only on the known commission
  margin-inline flake (desktop-1512, pain-1440); every morph.* part passes. Attempt 2 is running; read it with
  `gh run view 39312308450 --attempt 2 --log-failed` (`fw ci wait` still reports attempt 1).
- Whether to put `shift-dormant` into v2-proved instead of `shift` is a lead decision (layers vs one recalc).
  It needs a findings-ledger row.
- WebKit census of the dormant build was not run (accepted limit: source-only).

Conventions: arms are told apart by `meta.search` in each counts.json. Per-frame diffs came from a scratch reducer
(sum and run-length diff of `frames[].counts`), which is not committed.
Read first: the note research/notes/2026/10-20-morph-layers.md (Answer, Measurements), then MorphMountDormant.lean.
