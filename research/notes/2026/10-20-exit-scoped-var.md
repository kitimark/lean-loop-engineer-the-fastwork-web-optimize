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
- The counter: a resolution is counted by `IncStyleForElementCount`
  (third_party/blink/renderer/core/css/resolver/style_resolver.cc:1362-1364 via :1442@f842f52), and
  `UpdateLayoutTree.elementCount` is that count after the pass minus before it
  (third_party/blink/renderer/core/dom/document.cc:2822,2856-2857@f842f52). The clone path (element.cc:5698-5702@f842f52)
  never reaches it, so `crFull` counts resolutions, not clones.

Restyle units are validated only as between-arm deltas. No task may cite an absolute Restyle unit (`crFull`,
`crScoped`, `wkFull`, `wkScoped`) as measured elementCount until the per-pass follow-up (chromium-per-pass-elementcount)
lands.

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
- the per-frame write set and a model `zone`: the swipe-v1 frame window 10-103 (94 frames, 93 of them exit-write
  frames). Its totals (narrow Chromium 9306 faithful, 846 scoped) are model products; no measured sum is compared with
  them.

`apps/site/src/parts/hero.exit/scoped.test.ts` derives the flags from the CSS. It runs the cascade (layers, media,
specificity, inline style) over the SSR DOM at 15 widths and checks:
- that the result equals one of the two Lean trees;
- that its own recurrences give the golden units;
- that the reading nodes are the reader list;
- that the scope rules are the golden inherit rules, with no other scope or exit declaration;
- the stage defaults against the `.hero` rule and the reduced-motion rule.

Reader coverage and allowlist identity come from this test, not from a Lean hypothesis.

## Measured

Values below are MEASURED unless a row or sentence says INFERRED. Setup:
- Workflow chromium-counts on `ci/exit-scoped-var` at fad89503, target rewrite, 3 runs per arm.
- One image, reused from run 39049264131.
- The variant was read from `meta.rewrite.config.variants` (`hero.exit: scoped`, every other part faithful).

The counter is `UpdateLayoutTree.elementCount` per frame. `counts.json` holds per-frame sums over the frame's passes
(packages/measure-chromium/src/trace.mjs:21), so no artifact splits a frame by pass or by writer.

The exit range is defined by scrollY, not by frame index:
- The last exit-write frame is swipe n=103 (scrollY 940) and touch n=111 (scrollY 939). From scrollY ≈ 950 on
  (swipe n=104 at 950, touch n=112 at 949) the written value no longer changes: Δ is 0 in every run over swipe n 104-131 and touch n 112-139; later frames
  show other-writer noise of |Δ| ≤ 4.
- Exit-write frames (Δ ≠ 0): 93 per run, swipe n 11-103 and touch n 14-90 and 96-111.
- Δ is 0 in the first frame of each scroll segment (swipe n=10, touch n=13 and n=95) and in the touch frames that hold
  scrollY 774 (n 91-94). The faithful driver writes in the part's own rAF, one frame after the scroll
  (`mountExit` in apps/site/src/parts/hero.exit/driver.ts); the lag is INFERRED from that code and these frames.

Sums over the exit range (first scroll frame to the last frame below scrollY 950), MEASURED, all 3 runs per arm:

| profile | base run | scoped run | window | base sum | scoped sum | Δ | median per write frame |
|---|---|---|---|---|---|---|---|
| swipe-v1 | 39314368756 | 39314340270 | n 10-103 | 13145 | 4730 | 8415 (-64.0%) | 136 → 45 |
| swipe-touch-v1 | 39314380116 | 39314355168 | n 13-111 | 13218-13219 | 4825 | 8393-8394 (-63.5%) | 136 → 46 |

The earlier window n 10-103 truncates the touch exit range: it leaves out the 8 write frames n 104-111 (touch sums
12035-12036 → 4328). Whole-run Δ is 8395-8417 on touch and 8338-8406 on swipe. These sums are not set against the
golden `zone` totals (see Proved).

Model against measurement (phone width, narrow tree):

| quantity | value | status |
|---|---|---|
| Δ per exit-write frame | model 90 (`narrow_delta`). Measured 90-91 in every write frame except one per profile at scrollY ≈ 890 (swipe n=98, touch n=106, Δ 56 in all runs) and touch r2 n=79 (Δ 92: base 138, where r1 and r3 give 137). Frames without a write (touch 91-95) have Δ 0 | PROVED vs MEASURED |
| other writers, exit silent | swipe n 104-131 (scrollY 950-1220): median 43 in both arms; touch n 112-139 (scrollY 949-1219): median 44 in both arms; 3 `UpdateLayoutTree` passes per frame against 4 in the exit range | MEASURED |
| other writers, later windows | frames 132-200: median 130 (swipe base, touch both arms) and 131 (swipe scoped), range 43-137 with the exit writer silent, so the other writers vary by window | MEASURED |
| per-writer split of a write frame | not measured, INFERRED bounds only: the other writers' share is 36 if the model's 9 is the exit share (scoped median 45 minus 9), or 43/44 if they cost in the exit range what they cost in the silent window | INFERRED |

The Δ 56 frame. Each profile's Δ 56 frame is the first frame past the driver's `pointer-events: none` threshold:
- The driver sets the hero's `pointer-events` to `none` once opacity < 0.05 (`POINTER_OFF_BELOW` in
  apps/site/src/parts/hero.exit/logic.ts, written at driver.ts:25).
- With the 932 px exit range that is scrollY > 885.4. The frames before it are at 880 (swipe) and 879 (touch); the Δ 56
  frames are at 890 and 889.
- `pointer-events` is an independent inherited property
  (third_party/blink/renderer/core/css/css_properties.json5:5316-5320@f842f52).
- In the faithful arm the frame is 142 (swipe) and 141 (touch), the same as its neighbours: the change rides in the
  pass the exit write already runs. In the scoped arm it is 86 and 85 against 51 in its neighbours, 34-35 more.
- The timing is INFERRED: the Δ 56 frame is the threshold crossing if the write lags one frame and the track top
  sits about 6-12 px above scrollY 0 (this fits n=10/13 with Δ 0 and the last write at n=103/111); the 932 px range
  and the offset are not measured. The mechanism (a one-time inherited write on the stage that
  the scoped arm pays for and the faithful arm absorbs) is INFERRED. The extra 34-35 is not derived: a walk of the
  narrow tree under the `Fw.Engine.Restyle` clone rule gives 75 resolutions for an independent-inherited change, not 44.
  This frame is an accepted limit (see Limits).

Pseudo-style premise. apps/site/src/styles/reset.css:52-54 (`*, *::before, *::after`) matches every element, hero
elements included. Whether Chromium resolves, and so counts, a `::before`/`::after` style with `content: normal` for
them is not source-checked. The measured Δ of 90 (one count per modelled element) suggests that no pseudo resolutions
are counted (INFERRED).

Other counters:
- Whole-run elementCount drops by about the exit-range amount: swipe 44128-44182 → 35776-35790 (Δ 8338-8406), touch
  48526-48528 → 40109-40133 (Δ 8395-8417).
- Over the exit range, `UpdateLayoutTree` passes (391 swipe, 398 touch) are equal in both arms and
  `Layout.dirtyObjects` (3576-3578 swipe, 3717-3719 touch) stays the same within 2.

Breakpoint gate:
- Run 39314391342 (`fw=hero.exit:scoped`) passes every hero.exit cell in Chromium and WebKit.
- The run's verdict is fail (Chromium) and incomplete (WebKit) because of two cells unrelated to this flag:
  - commission in `sweep:pain-1440-600-1440`;
  - WebKit matchMedia NC in `sweep:phone-rotation`.
- Both cells fail the same way on `ci/countdown-one-chain` (run 39313815482), so they come from main, not from this
  flag.

## Limits

- `UpdateLayoutTree.elementCount` is a quarantined counter. On the admitted counters the win is proved-unmeasured
  unless the lead admits the exit-range count.
- The WebKit win is source-only (`wk_units`); no WebKit lane counts restyled elements.
- The flags come from the SSR DOM and its CSS. Runtime state is not modelled:
  - a running animation sets `s` at run time;
  - the test's specificity is an approximation of the cascade.
- The per-writer split needs a per-pass elementCount dump; `counts.json` holds per-frame sums
  (packages/measure-chromium/src/trace.mjs:21). The split is therefore not measured; the table gives INFERRED bounds
  only. Under the 43/44 bound the exit share would be about 2 (scoped) and 93 (faithful) against the model's 9 and 99.
  That about 7 nodes sit in the other writers (a pass shared with the exit write, or a writer that costs less while
  the hero is on screen) is an INFERRED hypothesis only. The per-pass dump and this 7-node question are the follow-up
  task chromium-per-pass-elementcount.
- Restyle units are validated only as between-arm deltas; no per-arm share is measured on this harness.
- One frame per profile at scrollY ≈ 890 (swipe n=98, touch n=106) has Δ 56. Its timing matches the one-time
  `pointer-events: none` write; the scoped arm's extra 34-35 there is not derived from the model.
- The pseudo-style path is not source-checked (see Pseudo-style premise).
- A future reader outside the chain classes would see the guaranteed-invalid value. `scoped.test.ts` fails on it.
