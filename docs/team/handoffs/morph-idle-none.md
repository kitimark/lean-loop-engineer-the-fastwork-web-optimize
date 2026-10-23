Branch: worktree-wf_38f9845b-370-1 (CI ci/morph-idle-none @540130e9f). Worktree: .claude/worktrees/wf_38f9845b-370-1
Round 2 done.
CI runs (branch ci/morph-idle-none): gate 39897800920; chromium-counts base 39897804079, flag 39897818039; webkit-sim base 39897814980, flag 39897807511; cost: base 39903977820 success, flag 39903974246 (Determinism sessions step hit its 35-minute timeout 4 s after r1-lag.json was written; data complete). All complete.
Verified: layers lower in WebKit morph zones (idle 128->112); Paint/Composite per frame unresolved (noise 3x). Details: note 10-20-morph-idle-none.md, results/morph-idle-none/report.json webkitSim.morphCost.
Numbers: results/morph-idle-none/report.json; note research/notes/2026/10-20-morph-idle-none.md.

- Flag: `morph.columns:idle-none` (apps/site/src/parts/morph.columns/index.tsx, idle.ts, morph.module.css `data-fw-idle`).
- Same look: while the scene attribute is `paused` the tracks have `animation-name: none`; each animation's currentTime is kept at removal and set again on return in the MutationObserver callback (before paint). Lean: removal alone restarts the phase (`restart_shifts`); with the kept clock the variant equals the original (`varRun_clock`).
- Layers (model): `tracks_layers_drop` 5 layers with animated tracks, 1 without; INFERRED mapping to Chromium ActiveTransformAnimation (note 10-20-morph-layers.md).
- TS stand-in: IdleHold (DOM glue) has no golden; idleRemoved and idleStep are checked by idle.golden.test.ts against morph-idle-none.jsonl.
- Writes widened in graph r317; dry land prints VERDICT dry morph-idle-none without --allow.
- Read first: lean/Fw/Parts/MorphIdleNone.lean.
