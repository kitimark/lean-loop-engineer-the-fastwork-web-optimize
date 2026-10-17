# proof-countdown-strip (CD-W, hero.countdown + morph.countdown `strip`)
**State:** done on this worktree branch (commit in the report). `lake build` green, mathview 0 failing, standard axioms only.
**Module:** `lean/Fw/Parts/HeroCountdownOpt.lean`. Golden: `packages/contracts/golden/engine/countdown-strip.jsonl` (from `goldenJsonl`;
regenerate with a scratch `def main` writing it, run by `lake env lean --run` from `lean/`).
**Proved:** `strip_visSame` (VisSame E, every env/width/instant, from `strip_shows_same`); `strip_passes_eq` (passes `=o`),
`strip_units` (faces cost 9|D| more units per stage), `strip_claim` + `cr_strip`/`wk_strip` (Core label: rolling run ->
dominates if resident ≤ else trade; still run -> noClaim; a resident-only win with equal Work is noClaim in Core).
**Resident:** `hero_layers`: 80 -> 8 per 8-digit clock (spec: 1 strip per digit, `index.tsx:24-50`), 8 ≤ 16. 80 and 16 are the
`layerBudget`s in part.json (PLAN.md:696-697); 16 is v1's strip-rw backed count, not v2's layer count.
`strip_backing_gt` + `strip_label_fullLayer`: strip backs 12 cells per digit vs 10 (full-layer rule, INFERRED) -> **trade**.
**WebKit:** `wk_owns`: layers exist only via will-change under Normal (translateY never composites, `static2D_not_own`);
Conservative and the paused morph panel: 0 = 0 layers (`wk_conservative_same`, `paused_same`); Normal: 80 -> 8 (`wk_normal_layers`).
**Golden rows:** Chromium census.layers `<o`, stage comp, swipe-v1 / swipe-touch-v1, base `rewrite` (deterministic arm, so
frame-exact `<o` is usable; vs `original`, stable t 3, `<o` would be unusable). Per-frame det rows withheld: strip also moves
the clock to a shared-loop subscriber (index.tsx:103-108), which shifts roll frames; not modelled.
**Open:** `variantKeys` (engine-check.ts:69-74) lets a `+search` run also answer to `rewrite`; keep strip runs out of the
base series (separate run dir) or the base mixes both arms. Backing rule for small layers is INFERRED, not CONFIRMED.
**Read first:** the module doc of HeroCountdownOpt.lean, then design note §4.2 rank 5.
