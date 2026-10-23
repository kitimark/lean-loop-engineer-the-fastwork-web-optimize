Branch: worktree-wf_38f9845b-370-1 (CI ci/morph-idle-none @540130e9f). Worktree: .claude/worktrees/wf_38f9845b-370-1
Round 2 done.
CI runs (branch ci/morph-idle-none): gate 39897800920; chromium-counts base 39897804079, flag 39897818039; webkit-sim base 39897814980, flag 39897807511; cost: base 39903977820 success, flag 39903974246 (marked failed by forced-exit after data upload; data complete). All complete.
Verified: layers lower in WebKit morph zones (idle 128->112); Paint/Composite per frame unresolved (noise 3x). Details: note 10-20-morph-idle-none.md, results/morph-idle-none/report.json webkitSim.morphCost.
CI runs (ci/morph-idle-none @540130e9f; all complete, success): gate 39897800920 (merge job re-run once after ECONNRESET); chromium-counts swipe-v1 x3 base 39897804079, flag 39897818039; webkit-sim base 39897814980, flag 39897807511. Dispatches used 5 of 6.
Verified: Lean MorphIdleNone (varRun_clock, varRun_present, restart_shifts, idleNone_visSame, tracks_layers_drop); site tests 123 files pass; gate passes both engines; Chromium layer-frames 28107 -> 24667, drawing 24904 -> 21464, layout +1, recalc +1; WebKit census layerCount and backing memory lower at y>=3000.
Open: WebKit cost counters (needs cost=on lag=true, no fw run input): gh workflow run webkit-sim.yml --ref ci/morph-idle-none -f target=rewrite -f lag=true -f cost=on -f fw=morph.columns:idle-none (and base without fw). Final check.sh and dry land: see the report.
Numbers: results/morph-idle-none/report.json; note research/notes/2026/10-20-morph-idle-none.md.

- Flag: `morph.columns:idle-none` (apps/site/src/parts/morph.columns/index.tsx, idle.ts, morph.module.css `data-fw-idle`).
- Same look: while the scene attribute is `paused` the tracks have `animation-name: none`; each animation's currentTime is kept at removal and set again on return in the MutationObserver callback (before paint). Lean: removal alone restarts the phase (`restart_shifts`); with the kept clock the variant equals the original (`varRun_clock`).
- Layers (model): `tracks_layers_drop` 5 layers with animated tracks, 1 without; INFERRED mapping to Chromium ActiveTransformAnimation (note 10-20-morph-layers.md).
- TS stand-in: IdleHold (DOM glue) has no golden; idleRemoved and idleStep are checked by idle.golden.test.ts against morph-idle-none.jsonl.
- Outside the task writes (dry land says VERDICT scope; the compose test needs the ledger row, so it needs --allow): apps/site/src/parts/morph.columns/idle.ts, idle.golden.test.ts, research/findings/ledger.json (row n 54), lean/Fw/Parts/FootprintRows.lean, packages/contracts/golden/parts/footprint-diff.gen.json, packages/contracts/golden/preset/v2-proved.decisions.jsonl.
- Read first: lean/Fw/Parts/MorphIdleNone.lean.
