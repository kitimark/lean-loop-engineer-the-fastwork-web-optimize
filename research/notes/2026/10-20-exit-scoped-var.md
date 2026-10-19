# hero.exit:scoped: restyle only the readers of the exit properties

The exit driver writes `--exit-opacity` on the hero stage every scroll frame. Both exit properties are unregistered
custom properties and so inherited. Only 16 elements read them: the copy block, the cue and the 14 cards (10 orbit,
4 deck).

## Change (design 2 of the R1 record)

- In its effect, `hero.exit:scoped` registers both properties with `syntax: '*'` and `inherits: false`.
  `apps/site/src/parts/hero.exit/scope.ts` does this once per document.
- The stage carries `data-exit-scope`.
- 7 gated rules declare `--exit-opacity: inherit; --exit-scatter: inherit` on the classes between the stage and the
  readers: orbit, stage, stage3d, card, deck, copy and cue.
- The driver, the stage defaults (opacity 1, the scatter `calc`, reduced motion 0) and the REST plan are unchanged.

## Restyle model (CONFIRMED, source)

`Fw.Engine.Restyle` counts style resolutions per write on a tree whose nodes carry flags: `v` declares or references
a custom property, `s` is outside the Chromium clone path, `h` is `display: none`, `i` has the exit `inherit` rule,
`x` has another explicit `inherit`, `r` reads an exit property.

Chromium, unregistered (inherited) property:
- The written node resolves. Its diff is `kInherited` because variables changed
  (third_party/blink/renderer/core/style/computed_style.cc:470-475@f842f52), so every child is recalculated
  (third_party/blink/renderer/core/dom/element.cc:5618-5619@f842f52).
- A child without its own variables and outside the slow set gets a clone of its old style with the new inherited
  values (element.cc:5698-5702 and `PropagateInheritedProperties` element.cc:5554-5597@f842f52; the clone copies
  inherited variables, computed_style.cc:3146-3149@f842f52). It is not resolved, and its children follow the same rule.
- The slow set is what `PropagateInheritedProperties` refuses: pending recalc, animations or transitions, SVG custom
  style callbacks, variable references or declarations, links, applied text decorations.
- A `display: none` element resolves but stores no style, so its children are not visited
  (element.cc:5713,5734-5735@f842f52).

Chromium, registered with `inherits: false`: a non-inherited diff is `kInherited` only if a child declares `inherit`
for a non-inherited property (computed_style.cc:466-468@f842f52, set in
third_party/blink/renderer/core/css/resolver/style_builder.cc:114-117@f842f52); otherwise `kNonInherited` stops
(computed_style.cc:504@f842f52).

WebKit: inherited custom property changes resolve every child
(Source/WebCore/style/StyleTreeResolver.cpp:307-308@862f17d). There is no fast path for custom properties
(Source/WebCore/style/computed/StyleComputedStyle.cpp:212@862f17d, a FIXME). Registered non-inherited changes resolve
only children with explicit inheritance (StyleTreeResolver.cpp:310-311,1207-1209@862f17d; the flag is set in
Source/WebCore/style/StyleBuilder.cpp:576-577@862f17d). `display: none` stops the descent
(StyleTreeResolver.cpp:1387-1388@862f17d).

## Proved (Lean, `Fw.Engine.Restyle` and section Scoped of `Fw.Parts.HeroExitOpt`)

| theorem | statement |
|---|---|
| `crClone_of_vars`, `crClone_of_slow`, `crClone_of_hidden`, `crClone_fast` | one theorem per branch of the clone rule |
| `crFull_le_wkFull`, `crScoped_le_wkFull`, `wkScoped_le_crScoped` | Chromium ≤ WebKit unscoped; scoped WebKit ≤ scoped Chromium |
| `cr_units` | Chromium per write: narrow 99 faithful, 9 scoped; wide 172 and 17 |
| `wk_units` | WebKit per write: narrow 123 faithful, 9 scoped; wide 215 and 17 |
| `narrow_delta` | narrow Chromium faithful − scoped = 90 |
| `readers_exact`, `readers_in_tree`, `chain_covers` | the `r` nodes are exactly the reader list, each on an all-`i` path |
| `consumer_eq`, `consumer_eq_scoped` | every reader gets the stage value |
| `defaults` | before the first write the readers get opacity 1, registered or not (SSR, pre-hydration) |
| `reduced_scatter`, `scatter_eq` | reduced motion gives scatter 0; otherwise the scoped scatter equals the faithful one |
| `Fw.Site.Stage.exit_owner_never_written` | no `?only=` stage plan writes a rest value on hero.exit |

Narrow is ≤ 600 px (orbit hidden), wide is above (deck hidden).

Golden: `packages/contracts/golden/parts/hero.exit.scoped.json` holds:
- the reader list, the inherit rules and the stage defaults;
- both flagged trees and the units per tree and engine;
- the per-frame write set and the zone totals (94 frames, narrow Chromium 9306 faithful, 846 scoped).

`apps/site/src/parts/hero.exit/scoped.test.ts` derives the flags from the CSS. It runs the cascade (layers, media,
specificity, inline style) over the SSR DOM at 15 widths and checks:
- that the result equals one of the two Lean trees;
- that its own recurrences give the golden units;
- that the reading nodes are the reader list;
- that the scope rules are the golden inherit rules, with no other scope or exit declaration;
- the stage defaults against the `.hero` rule and the reduced-motion rule.

Reader coverage and allowlist identity come from this test, not from a Lean hypothesis.

## Measured

All values below are MEASURED. Setup:
- Workflow chromium-counts on `ci/exit-scoped-var` at fad89503, target rewrite, 3 runs per arm.
- One image, reused from run 39049264131.
- The variant was read from `meta.rewrite.config.variants` (`hero.exit: scoped`, every other part faithful).

The counter is `UpdateLayoutTree.elementCount` summed over frames 10-103:

| profile | base run | base zone | scoped run | scoped zone | Δ | per-frame median base → scoped |
|---|---|---|---|---|---|---|
| swipe-v1 | 39314368756 | 13145 (r1-r3) | 39314340270 | 4730 (r1-r3) | -8415 (-64%) | 136 → 45 |
| swipe-touch-v1 | 39314380116 | 12035-12036 | 39314355168 | 4328 (r1-r3) | -7707 (-64%) | 136 → 45 |

Per frame (swipe, both arms):
- Frames 0-9 are equal in both arms.
- Frame 10 is 122 in both arms.
- Frames 13-23: 136 → 46 (Δ 90).
- Frames 27 on: 136 → 45 (Δ 91).

Model against measurement (phone width, narrow tree):

| quantity | value | status |
|---|---|---|
| Δ per frame | model 90, measured 90-91 | PROVED vs MEASURED |
| scoped frame: exit writer | 9 | PROVED (model) |
| scoped frame: other writers | 45 − 9 = 36 | MEASURED difference |
| faithful frame | model 99 + 36 = 135, measured 136 | PROVED + MEASURED |

The per-writer split assumes that the other writers' share is the same in both arms. The harness has no per-pass
trace dump, so that share is not measured on its own.

Other counters:
- Whole-run elementCount drops by the same amount: swipe 44128-44182 → 35776-35790, touch 48526-48528 →
  40109-40133.
- `UpdateLayoutTree` passes (391 swipe, 365 touch) and zone `Layout.dirtyObjects` stay the same within 2.

Breakpoint gate:
- Run 39314391342 (`fw=hero.exit:scoped`) passes every hero.exit cell in Chromium and WebKit.
- The run's verdict is fail (Chromium) and incomplete (WebKit) because of two cells unrelated to this flag:
  - commission in `sweep:pain-1440-600-1440`;
  - WebKit matchMedia NC in `sweep:phone-rotation`.
- Both cells fail the same way on `ci/countdown-one-chain` (run 39313815482), so they come from main, not from this
  flag.

## Limits

- `UpdateLayoutTree.elementCount` is a quarantined counter. On the admitted counters the win is proved-unmeasured
  unless the lead admits the zone-restricted count.
- The WebKit win is source-only (`wk_units`); no WebKit lane counts restyled elements.
- The flags come from the SSR DOM and its CSS. Runtime state is not modelled:
  - a running animation sets `s` at run time;
  - the test's specificity is an approximation of the cascade.
- The split between exit and other writers is inferred (see above).
- A future reader outside the chain classes would see the guaranteed-invalid value. `scoped.test.ts` fails on it.
