---
id: 2026-10-20-hero-relayout-boundary
kind: note
title: "contain: size layout on the sticky hero scopes its own layout passes (hero.exit:contain)"
status: draft
created: 2026-10-26
topics: [layout, containment, hero, accent, chromium, webkit]
---

**Answer.** With `contain: size layout` the sticky `.hero` becomes a relayout boundary in both engines. A frame whose
dirty objects all sit inside the hero (accent width transition, countdown digits) then lays out only the hero
subtree. A frame with any dirty source outside the hero (people cards, the fixed nav) or on the hero box itself stays
a full layout, in either order. The hero's box does not change at any of the 124 breakpoint probes. Chromium swipe-touch-v1
(3 runs per arm, same commit): Layout totalObjects in the hero-exit window 108,446 to 70,122 (-35.3%), whole run
456,706 to 357,812 (-21.7%), with the same number of Layout passes. WebKit is source-only (see WebKit). Lean:
`Fw.Parts.HeroContainOpt`; golden `packages/contracts/golden/parts/hero-contain.jsonl`.

## Why the hero becomes a boundary (CONFIRMED from source)

Chromium `ObjectIsRelayoutBoundary`, third_party/blink/renderer/core/layout/layout_object.cc:1439-1560@f842f52:
- guards in order: a LayoutBox with a cached layout result (:1441-1450); the fragment is not destroyed or moved, has
  no break token, no propagated layout objects, no out-of-flow descendants and no child anchors (:1455-1477); a
  formatting-context root (:1484); a self-painting layer or an SVG root (:1491-1494); not a table part (:1498); not an
  out-of-flow box with auto insets (:1508-1512); not a flex item (:1517); containing block not a grid (:1525); not inner
  MathML (:1531);
- then layout plus size containment returns true (:1535-1538). Without containment the hero fails the fixed-size
  tail: its width is auto (:1550).
- The hero passes every guard: its parent `.track` is a block box, so it is not a flex item; sticky with `z-index: 2`
  gives it a self-painting layer (layout_box.cc:554-562); it is a flex container (formatting-context root); it has no
  sticky, fixed, anchor or snap descendant, and every absolute descendant has a containing block inside the
  positioned hero. Lean `hero_cr_base`, `hero_cr_flag`.

WebKit `isLayoutBoundary`, Source/WebCore/rendering/RenderObject.cpp:516-556@862f17d: the view (:519-520), a text
control outside flex and grid (:523-528), layout plus size containment (:530-531, no flex-item exclusion), an SVG
root (:533-534); overflow visible returns false (:536-539), which is the base hero. Lean `hero_wk_base`,
`hero_wk_flag`, `flexItem_engines_differ`.

## Which passes stay inside the hero (CONFIRMED from source, Lean)

- Both engines start the marking walk at the dirty object's container and test the boundary on ancestors only
  (layout_object.cc:1656-1734; RenderObject.cpp:593-655). A dirty hero box therefore roots at the view
  (`outside_view`, from `NavOofRoot.layoutRoot_skips_self`).
- Chromium keeps a list of subtree roots (local_frame_view.cc:1706-1723); a walk that reaches the view schedules a
  full layout and clears the list (:1676-1694). Lean `crStep`, `cr_outside_full`, `cr_inside_root`.
- WebKit keeps one subtree root (Source/WebCore/page/LocalFrameViewLayoutContext.cpp:701-753): the same or a nested
  root keeps it, an enclosing root re-roots, two disjoint roots or a pending full layout give a full layout
  (:663-664, :727-731, :749-752). Lean `wkStep`, `wk_outside_full`, `wk_reroot`, `wk_disjoint`.
- Instances (`drawIn_flag_hero`, `drawIn_outside_full`, `drawOut_wk_same`): accent width plus countdown digit roots at
  the hero in both engines; the WebKit draw-out frame (dash offset only) already roots at the accent's SVG root in the
  base, so the flag does not change it; the dash offset is no layout in Chromium
  (`Fw.Engine.StyleDiffAccent.dashoffset_cr_nolayout`). Any frame that also dirties the nav, a people card or the hero
  box is a full layout.
- INFERRED: on iOS a subtree layout turns full only when `fetchCustomFixedPositionLayoutRect` is true
  (LocalFrameViewLayoutContext.cpp:233-236); its default is false (Source/WebCore/page/ChromeClient.h:391) and the
  WebKit2 client does not override it.

## Same box (Lean, CSS restated)

- Size containment sizes a box as if it were empty. The hero's height is definite (`100svh`, `min-height: 680px`, or
  `100svh` at `<= 600` px) and its auto width fills the block `.track`, so its box is the same at every probe
  (`hero_same_box`, `hero_height_stage`); an auto-height box would collapse (`height_auto_differs`).
- Layout containment also makes a stacking context, an absolute containing block and an independent formatting
  context; the sticky, positioned, flex hero is all three already (`effects_same`), and it has no fixed descendant
  (`no_fixed_descendant`).
- Layout containment turns the hero's content overflow into ink overflow, so it no longer adds to the page's
  scrollable overflow. Its reach below the track is under one viewport and at most 453.2 px (`excess_lt_vh`,
  `excess_lt_454`, `desk-rm-601`). The page extent is unchanged when the content after the track is at least that tall
  (`extent_same`); `page-root` clips x. The breakpoint gate checks the premise (`scroll-height`).

## Measurements (MEASURED)

Chromium `chromium-counts`, profile swipe-touch-v1, sha 0537be1 (ref `ci/hero-relayout-boundary`), 3 runs per arm:
base run 40268899311, flag run 40268902395 (`--fw hero.exit:contain`). Hero-exit window = zones y00000 and y00500
(scrollY 0 to 1000; the exit runs over 0 to 932). Means over r1-r3; per-run values in
`results/hero-relayout-boundary/chromium.json` (extractor `extract-chromium.mjs`).

| scope | arm | Layout passes | totalObjects | dirtyObjects | partial | UpdateLayoutTree |
|---|---|---|---|---|---|---|
| hero-exit window | base | 122.3 | 108,446 | 1,466 | 25.7 | 405 |
| hero-exit window | flag | 121.7 | 70,122 | 1,112 | 76.3 | 405 |
| whole run | base | 474.7 | 456,706 | 6,483 | 122.0 | 2,389 |
| whole run | flag | 473.7 | 357,812 | 5,775 | 223.3 | 2,391 |

- The pass count stays the same: the flag makes passes smaller, it does not remove them. In the window 76 of 122 passes
  are partial with the flag; the other 46 are full, as the dirty-source condition predicts for frames with a source
  outside the hero.
- Zones y01500 and y02000 also drop (49,784 to 33,014, 74,933 to 36,724 in r1): the countdown keeps ticking after the
  hero leaves the viewport, and those frames now lay out the hero only. Zones y02500 and later are unchanged.
- dirtyObjects falls too (-24% in the window): a partial pass counts only the hero subtree's dirty objects
  (local_frame_view.cc:685-698), INFERRED.

## WebKit

Source-only. When the counts ran, the macOS queue was full (two webkit-sim runs of `ci/platform-sweep-layer` and a
toolbar-throttle run in progress), so no WebKit Simulator counts were dispatched. The source shows the same
boundary (RenderObject.cpp:530-531) and single-root scheduling, so the draw-in frames with only hero sources would
root at the hero; that is INFERRED until counted.

## Limits

- CI only, no phone pass. WebKit source-only.
- The gain needs frames without outside sources; frames with the people reveal or the nav stay full.
- Preset promotion is a later task.
