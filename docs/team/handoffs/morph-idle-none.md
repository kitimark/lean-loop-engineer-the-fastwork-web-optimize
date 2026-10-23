Branch: worktree-wf_38f9845b-370-1 (CI branch ci/morph-idle-none, pushed at 540130e9f). Worktree: .claude/worktrees/wf_38f9845b-370-1
Last commit: see git log (FootprintRows regen after 540130e9f). Dispatches used: 5 of 6.
CI runs (all dispatched on ci/morph-idle-none @540130e9f, state running): gate 39897800920; chromium-counts swipe-v1 x3: 39897804079, 39897818039 (one flag, one base; mapping set when fw run prints); webkit-sim: 39897807511, 39897814980 (one flag, one base).
Verified: Lean MorphIdleNone builds (varRun_clock, varRun_present, restart_shifts, shownV_eq, idleNone_visSame, tracks_layers_drop); site tests 123 files pass; check.sh failed only on the footprint rows (regenerated, rerun pending).
Open: read the five runs (layers.json reduction on swipe frames; webkit-sim cost-report on the morph zone), note, ledger row n, final check.sh, dry land.

- Flag: `morph.columns:idle-none` (apps/site/src/parts/morph.columns/index.tsx, idle.ts, morph.module.css `data-fw-idle`).
- Same look: while the scene attribute is `paused` the tracks have `animation-name: none`; each animation's currentTime is kept at removal and set again on return in the MutationObserver callback (before paint). Lean: removal alone restarts the phase (`restart_shifts`); with the kept clock the variant equals the original (`varRun_clock`).
- Layers (model): `tracks_layers_drop` 5 layers with animated tracks, 1 without; INFERRED mapping to Chromium ActiveTransformAnimation (note 10-20-morph-layers.md).
- TS stand-ins: IdleHold (DOM glue, no golden); idleStep and idleRemoved are checked against packages/contracts/golden/parts/morph-idle-none.jsonl.
- Outside the task writes: lean/Fw/Parts/FootprintRows.lean, packages/contracts/golden/parts/footprint-diff.gen.json, packages/contracts/golden/preset/v2-proved.decisions.jsonl, research/findings/ledger.json (row), lean/scripts/MorphIdleNoneGolden.lean is under lean/scripts/*Golden.lean (in writes).
- Read first: lean/Fw/Parts/MorphIdleNone.lean.
