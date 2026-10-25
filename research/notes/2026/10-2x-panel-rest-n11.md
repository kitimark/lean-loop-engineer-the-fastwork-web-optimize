# panel-rest-n11: ledger row n 11 shipped as the flag `morph.panel:rest`

Answer first.
* The flag exists: the platform section drops `filter` (`blur(0px)` to `none`) while `--morph-fade` is 1 and keeps the same blur otherwise. CONFIRMED in code (`apps/site/src/parts/morph.panel/rest.logic.ts`, `morph.tween/driver.ts` `updateFade`, `platform.module.css` `.section[data-fw-rest]`).
* RG10 holds on the rewrite DOM. MEASURED (local debug run, Chromium, 10 widths 320 to 1440): 54 absolutely positioned descendants of the section and 0 fixed; every one has a positioned or transformed ancestor below the section, so none uses the section as its containing block. The section is `position: static`, `z-index: auto`.
* The scenes are not pixel-equal everywhere. MEASURED (Chromium, 70 viewport clips of the section at 9 widths, flag vs base; base vs base noise floor 0 to 77 px per clip): all clips are inside the noise except width 721, where three clips differ by 720 to 734 px, one full 721 px row at the section's fractional bottom edge (section top 4320.47, height 1482.16). INFERRED mechanism: the filter group is rastered into a snapped layer, so the edge row of a fractional box is covered differently. So `rest_visSame_E` needs a third premise (no fractional section edge), or the class is Q at that row. Follow-up, not a blocker: a Lean premise and a gate row for fractional edges.
* No timing claim yet. The counts come from the lead's runs (commands in the report items).

## Mechanism (CONFIRMED at the cited lines)
* Chromium@f842f52: `blur(0)` still appends a blur op (`third_party/blink/renderer/core/paint/filter_effect_builder.cc:465-470`); `NeedsFilter` is true for any layer with `HasFilter` (`core/paint/paint_property_tree_builder.cc:2629-2651`), so an effect node and a `SaveLayer` exist at rest.
* WebKit@862f17d: `hasFilter` is `!filter.isNone()` (`Source/WebCore/rendering/RenderElementStyleInlines.h:40`), so `blur(0)` keeps a group and a RenderLayer although nothing is painted.

## What was added in Lean (reuse of `Fw.Parts.MorphPanelOpt`)
`Fw.Parts.MorphPanelRest`: `kindOf` (the per-frame decision, `off` iff `filterV (fade r)` is empty), `kindOf_rest`, `kindOf_fade`, `kindOf_off_iff` (one theorem per branch), `toggles` (rest-fade flips of a run) with `toggles_cross`, `toggles_fade`, `toggles_rest`, `toggles_all_rest`, `toggles_all_fade`. Golden `packages/contracts/golden/parts/morph.panel.rest.jsonl` (17 rows) is replayed by `apps/site/src/parts/morph.panel/rest.golden.test.ts`; `morph.tween/rest.driver.test.ts` runs the real driver through rest, fade and back.

## Registration
`morph.panel:rest` is `optimized` in `part.json`; it conflicts with the WAAPI tween and the threaded fade (they own the fade write). `Fw.Preset.Gen` lists it as a curated exclusion (ledger n 11: Chromium trade) so v2-proved is unchanged; the decisions golden has the new row.

## Open (the lead's runs decide)
Per-engine counts on the rest to fade toggle frames (WebKit `wk_toggle_eqv` is modelled, never measured; Chromium `cr_toggle_not_le`). If Chromium pays layout on the toggle, the follow-up is the Lean decision to toggle only in a frame that already pays layout. The Chromium run-level mixed theorem (row `missingWhy`) stays a follow-up unless the counts need it.
