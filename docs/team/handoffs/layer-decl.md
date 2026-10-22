branch: worktree-wf_60d9b4aa-522-1 (CI branch ci/layer-decl)
worktree: .claude/worktrees/wf_60d9b4aa-522-1
last commit pushed to CI: 6de942c2 (ci request commit on top of the merge of main)
CI runs: breakpoint-gate 39732883815 complete, success (chromium j0-j2 and playwright-webkit j0-j3 all green, merge green); lean 39732883734 complete, success

Verified locally (not results): site package test 5724 pass; runner test 2426 pass; site typecheck; scripts/ci-paths.test.mjs 54 pass; lean/scripts/check.sh green.
Open: dry land and review ready only.

What was built (task layer-decl, attributes only, no behaviour change)
- part.json of hero, hero.cue, hero.orbit, hero.deck, hero.countdown, nav, morph.panel: `layers` [{id, label, text}] and per-variant `files`.
  `files` = non-test source files of the part folder the variant runs; shared files appear in several variants' lists; the
  extractor (compose-layers-lean) derives variant-only code as the difference. hero.countdown:hidden-pause adds hidden.ts, hero:scene-pause adds scene.ts.
- data-fw-layer on the boxes: hero_copy, hero.cue_cue, hero.orbit_card, hero.deck_article, hero.countdown_face, hero.countdown_strip,
  nav_bar, nav_earn, morph.panel_panel. Roots carry both data-fw and data-fw-layer.
- hero.countdown_strip is added because the strip variant has no face box. The morph.countdown instance of HeroCountdown carries no layer attribute (layer={fwId === 'hero-countdown'}).
- Registry types: LayerDef, PartDef.layers?, VariantDef.files? (apps/site/src/registry/types.ts).
- Test: apps/site/src/parts/hero/layers.component.test.ts (schema: unique ids, okChar parsed from lean/Fw/Console/BuildsOpen.lean, files exist and cover the folder; DOM: every data-fw-layer declared, every layer found, text flag).

Writes outside the task list (lead adds to graph writes)
- lean/Fw/Parts/FootprintData.lean and packages/contracts/golden/parts/footprint.gen.json (regenerated with part-footprint.mjs --write; line numbers moved).
- apps/runner/src/land.ts: "apps/site" read list gains lean/Fw/Console/BuildsOpen.lean (land-inputs test asked for it).
- That is three files; footprint.gen.json is already admitted by a graph glob, so two (FootprintData.lean, land.ts) needed --allow until the graph names them.
