# Invisible paint: which repaints the user never sees (WKTR, original vs rewrite vs v2)

Task invisible-paint. Status: MEASURED (WKTR repaint rects, 3 jobs, one CI run), class rule PROVED in Lean, fix candidates INFERRED.
Run 40082809394 (ci/invisible-paint, sha 1d99c57a8, wktr.yml with `[repaint]`). Runs 40076565001 and 40078541948 are superseded.

## Answer first

- Between 45 and 72 percent of the repaint rects WebKit keeps during the swipe are not visible. MEASURED, pooled over 3 jobs, sum of part rows:

| arm | zone | frames per job | kept paints / 100 f | not visible / 100 f | share | wasted Mpx / 100 f |
|---|---|---|---|---|---|---|
| orig | hero | 177 | 1932 | 899 | 47% | 46.0 |
| orig | rest | 269-275 | 1934 | 1398 | 72% | 56.0 |
| orig | finish | 115 | 948 | 440 | 46% | 24.6 |
| rewrite | hero | 177 | 1276 | 715 | 56% | 23.1 |
| rewrite | rest | 275 | 1469 | 1029 | 70% | 27.3 |
| rewrite | finish | 115 | 954 | 432 | 45% | 23.3 |
| v2 | hero | 177 | 1355 | 728 | 54% | 24.8 |
| v2 | rest | 275 | 1365 | 918 | 67% | 26.1 |
| v2 | finish | 115 | 1071 | 552 | 52% | 26.4 |

- The rewrite already halves the wasted area in hero and rest against the original (46.0 to 23.1 and 56.0 to 27.3 Mpx per 100 frames), almost all of it in the people deck (vinyl). In finish the three arms are equal (23-26 Mpx).
- What is left is dominated by two groups: layers my harness could not name ("other", cause: the scroll offset changed) and the platform cards. Both are painted while outside the viewport and outside the tile coverage (class beyond-margin) or while hidden.
- Counts are noisy: per-job totals differ by up to 29 percent (v2 rest, not visible per 100 f: 773, 992, 994; rewrite rest 923, 1048, 1124) and once by 70 percent (v2 finish, one job at 763 against 448 and 450). paintRects, paintArea, wasteArea, trackedCalls, rects_beyond_margin and rects_visible classify quarantined in every arm and zone (kMax 4, tMax 24); only rects_clipped_out and rects_prepaint_margin are stable in some cells. A cell is an order of magnitude, not a result; the ranking below uses only gaps larger than the spread (orig against rewrite in hero people and in waste; part shares inside one arm).
- Classes covered and noop are never produced: they need a pixel diff that this lane does not run (follow-up). Their rows are 0 by construction, not measured zero.

## Definition (CONFIRMED, Lean)

lean/Fw/Engine/PaintVisible.lean `classify` asks in order: zero-area, hidden (layer or an ancestor has opacity 0 or contentsVisible 0), clipped-out (layer clips, rect lies outside its clip), covered, beyond-margin (misses viewport and tile coverage), prepaint-margin (misses viewport, hits coverage), noop (pixels equal), visible. One theorem per class: `zeroArea_iff`, `hidden_iff`, `clippedOut_iff`, `covered_iff`, `beyondMargin_iff`, `prepaintMargin_iff`, `noop_iff`, `visible_iff`; `tally_sum` (classes add up to all rects); `seen_add_waste` (seen + waste = rect area); `addDirty_*` for the engine's own dedupe. Goldens: packages/contracts/golden/measure/paint-visible.jsonl (37 lines), replayed by packages/measure-webkit/src/paintclip.mjs (7 tests). The reducer packages/measure-wktr/src/repaint.mjs only feeds facts and sums; it decides no class.

The count is of the dirty rects the engine keeps after `GraphicsLayerCA::setNeedsDisplayInRect` drops repeats (Source/WebCore/platform/graphics/ca/GraphicsLayerCA.cpp:1031-1043@862f17d; tracked calls per 100 f were 105481 / 79098 in orig hero / rest against 1935 kept). "waste" = rect area minus the part inside the viewport of a visible paint.

## Per part x zone x arm (run 40082809394)

Per 100 frames, pooled over 3 jobs. paints = kept dirty rects; area and waste in Mpx; hidden / clipped / beyond / prepaint are counts of invisible classes. top cause and element are the most frequent among the non-visible rects (count over 3 jobs in the full file); "anim:x" = a running animation of that name, "trans:p" = a transition of property p, "scroll" = nothing but the scroll offset changed in that frame. "(size match)" / "(1 of N same size)" = the layer had no probe name and was matched to elements of equal size (INFERRED). Parts with all zero rows are left out; A row with 0 paints has fewer than 1 paint per 100 frames (per100 rounds down); its area and waste are those few paints. Source: results/invisible-paint/table.md.

| arm | zone | part | paints | invisible | hidden | clipped | beyond | prepaint | area Mpx | waste Mpx | re-raster layers | top cause | top element |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | hero | nav | 100 | 0 | 0 | 0 | 0 | 0 | 1.8 | 0.0 | 0 | anim:svelte-1dcozpm-start-selling-nav-earn-unmask anim:svelte-1dcozpm-start-selling-nav-earn-sheen (4) | header.start-selling-top-nav.is-hero-pill.is-hero-chrome-ready (4) |
| orig | hero | hero | 6 | 2 | 2 | 0 | 0 | 0 | 0.6 | 0.6 | 0 | anim:svelte-1p2vpne-hero-cta-orbit (13) | svg.solar.solar-bell-linear.cta-icon (1 of 2 same size) (10) |
| orig | hero | people | 867 | 372 | 1 | 0 | 370 | 0 | 43.5 | 26.3 | 0 | anim:vinyl-spin (1708) | div.start-selling-profile-deck (1963) |
| orig | hero | platform | 93 | 93 | 0 | 0 | 93 | 0 | 0.0 | 0.0 | 0 | scroll (499) | - (499) |
| orig | hero | other | 866 | 432 | 231 | 0 | 200 | 0 | 37.1 | 19.1 | 18 | scroll (2294) | - (2294) |
| orig | rest | nav | 134 | 27 | 27 | 0 | 0 | 0 | 2.9 | 1.0 | 0 | scroll (225) | header.start-selling-top-nav.is-hero-pill.is-hero-chrome-ready (225) |
| orig | rest | hero | 11 | 11 | 6 | 0 | 5 | 0 | 4.3 | 4.3 | 0 | scroll (42) | div.hero-cta (37) |
| orig | rest | people | 633 | 501 | 0 | 0 | 501 | 0 | 31.3 | 29.0 | 0 | anim:vinyl-spin (3676) | div.start-selling-profile-deck (4075) |
| orig | rest | commission | 0 | 0 | 0 | 0 | 0 | 0 | 1.1 | 1.0 | 0 | anim:three-frame-zero (4) | svg.zero-frame.frame-0 (3) |
| orig | rest | platform | 337 | 313 | 0 | 0 | 279 | 33 | 3.8 | 3.4 | 0 | scroll (2530) | div.start-selling-platform-card (size match) (1372) |
| orig | rest | other | 819 | 546 | 130 | 0 | 408 | 7 | 40.2 | 17.4 | 3 | scroll (4440) | - (4440) |
| orig | finish | nav | 72 | 0 | 0 | 0 | 0 | 0 | 1.4 | 0.0 | 0 | - | - |
| orig | finish | hero | 0 | 0 | 0 | 0 | 0 | 0 | 0.9 | 0.9 | 0 | anim:svelte-1p2vpne-hero-cta-orbit (3) | div.hero-cta (3) |
| orig | finish | pain | 0 | 0 | 0 | 0 | 0 | 0 | 0.4 | 0.4 | 0 | scroll (3) | - (3) |
| orig | finish | platform | 428 | 221 | 0 | 0 | 155 | 65 | 2.1 | 1.0 | 0 | scroll (764) | div.start-selling-platform-card (size match) (454) |
| orig | finish | other | 448 | 219 | 2 | 0 | 215 | 0 | 24.4 | 22.4 | 0 | scroll (756) | - (756) |
| rewrite | hero | nav | 103 | 2 | 0 | 0 | 2 | 0 | 1.8 | 0.0 | 0 | anim:nav-module_earn-unmask_ZfvUeY anim:nav-module_earn-sheen_BJihYd (13) | header.nav-module_nav_fsb7in.is-hero-pill.is-hero-chrome-ready (13) |
| rewrite | hero | hero | 15 | 11 | 0 | 0 | 9 | 0 | 0.6 | 0.6 | 0 | scroll (56) | svg.hero-module_icon_V84s4Y (1 of 2 same size) (56) |
| rewrite | hero | people | 224 | 121 | 0 | 0 | 121 | 0 | 4.6 | 3.6 | 0 | trans:transform anim:deck-module_vinylSpin_k1msN- (389) | div.deck-module_deck_Cq95es (635) |
| rewrite | hero | commission | 0 | 0 | 0 | 0 | 0 | 0 | 0.0 | 0.0 | 1 | - | path (size match) 26x38->25x38 (4) |
| rewrite | hero | other | 934 | 581 | 198 | 95 | 287 | 0 | 36.0 | 18.9 | 58 | scroll (3090) | - (2584) |
| rewrite | rest | nav | 127 | 22 | 22 | 0 | 0 | 0 | 2.7 | 0.8 | 0 | scroll (183) | header.nav-module_nav_fsb7in.is-hero-pill.is-hero-chrome-ready (183) |
| rewrite | rest | hero | 4 | 4 | 0 | 0 | 4 | 0 | 1.7 | 1.7 | 0 | scroll (36) | - (8) |
| rewrite | rest | people | 180 | 105 | 0 | 0 | 105 | 0 | 3.1 | 2.5 | 0 | anim:deck-module_vinylSpin_k1msN- (717) | div.deck-module_deck_Cq95es (864) |
| rewrite | rest | commission | 0 | 0 | 0 | 0 | 0 | 0 | 0.7 | 0.7 | 0 | anim:commission-module_three-frame-zero_NB28ic (5) | - (3) |
| rewrite | rest | platform | 288 | 262 | 0 | 0 | 229 | 32 | 3.5 | 3.2 | 0 | scroll (2158) | div.platform-module_card_D3ykKA (1 of 2 same size) (2077) |
| rewrite | rest | other | 870 | 636 | 210 | 98 | 321 | 6 | 40.9 | 18.4 | 6 | scroll (5251) | - (4439) |
| rewrite | finish | nav | 72 | 0 | 0 | 0 | 0 | 0 | 1.4 | 0.0 | 0 | - | - |
| rewrite | finish | hero | 0 | 0 | 0 | 0 | 0 | 0 | 0.9 | 0.9 | 0 | anim:cue-module_scrollFloat_6RFPnC (3) | span.cue-module_float_g8PRFw (3) |
| rewrite | finish | pain | 0 | 0 | 0 | 0 | 0 | 0 | 0.4 | 0.4 | 0 | scroll (3) | - (3) |
| rewrite | finish | platform | 400 | 197 | 0 | 0 | 146 | 51 | 1.6 | 0.9 | 0 | scroll (680) | div.platform-module_card_D3ykKA (1 of 2 same size) (680) |
| rewrite | finish | other | 482 | 235 | 3 | 72 | 159 | 0 | 23.5 | 21.1 | 0 | scroll (814) | - (564) |
| v2 | hero | nav | 108 | 2 | 0 | 0 | 2 | 0 | 1.8 | 0.0 | 0 | anim:nav-module_earn-unmask_ZfvUeY anim:nav-module_earn-sheen_BJihYd (14) | header.nav-module_nav_fsb7in.is-hero-pill.is-hero-chrome-ready (14) |
| v2 | hero | hero | 12 | 8 | 1 | 0 | 6 | 0 | 0.6 | 0.6 | 0 | scroll (40) | svg.hero-module_icon_V84s4Y (1 of 2 same size) (32) |
| v2 | hero | people | 237 | 129 | 0 | 0 | 129 | 0 | 5.5 | 4.5 | 0 | trans:transform anim:deck-module_vinylSpin_k1msN- (349) | div.deck-module_deck_Cq95es (670) |
| v2 | hero | other | 998 | 589 | 233 | 95 | 260 | 0 | 37.4 | 19.7 | 46 | scroll (3131) | - (2623) |
| v2 | rest | nav | 129 | 24 | 24 | 0 | 0 | 0 | 2.8 | 0.9 | 0 | scroll (199) | header.nav-module_nav_fsb7in.is-hero-pill.is-hero-chrome-ready (199) |
| v2 | rest | hero | 7 | 7 | 2 | 0 | 5 | 0 | 1.2 | 1.2 | 0 | scroll (44) | button.cue-module_cue_AuR-MH (15) |
| v2 | rest | people | 183 | 107 | 0 | 0 | 107 | 0 | 3.1 | 2.6 | 0 | anim:deck-module_vinylSpin_k1msN- (744) | div.deck-module_deck_Cq95es (882) |
| v2 | rest | commission | 1 | 0 | 0 | 0 | 0 | 0 | 1.3 | 1.1 | 0 | scroll (3) | - (3) |
| v2 | rest | platform | 288 | 262 | 0 | 0 | 229 | 32 | 3.4 | 3.2 | 0 | scroll (2159) | div.platform-module_card_D3ykKA (1 of 2 same size) (2076) |
| v2 | rest | other | 757 | 518 | 109 | 98 | 301 | 9 | 40.0 | 17.2 | 5 | scroll (4277) | - (3463) |
| v2 | finish | nav | 93 | 15 | 15 | 0 | 0 | 0 | 1.8 | 0.4 | 0 | scroll (53) | header.nav-module_nav_fsb7in.is-hero-pill.is-hero-chrome-ready (53) |
| v2 | finish | hero | 4 | 4 | 2 | 0 | 1 | 0 | 1.7 | 1.7 | 0 | anim:cue-module_scrollFloat_6RFPnC (9) | button.cue-module_cue_AuR-MH (5) |
| v2 | finish | people | 12 | 12 | 0 | 0 | 12 | 0 | 0.4 | 0.4 | 0 | scroll (43) | div.deck-module_deck_Cq95es (42) |
| v2 | finish | pain | 0 | 0 | 0 | 0 | 0 | 0 | 0.4 | 0.4 | 0 | scroll (3) | - (3) |
| v2 | finish | platform | 405 | 199 | 0 | 0 | 147 | 51 | 2.5 | 1.4 | 0 | scroll (687) | div.platform-module_card_D3ykKA (1 of 2 same size) (687) |
| v2 | finish | other | 557 | 322 | 35 | 72 | 212 | 0 | 24.3 | 22.1 | 0 | scroll (1111) | - (860) |

## Ranked same-look fix candidates, one per source (INFERRED, none shipped)

Rank = (not visible per 100 f summed over hero and rest) x (waste Mpx per 100 f summed over hero and rest), rewrite arm: other 1217 x 37.3, people 226 x 6.1, platform 262 x 3.2, nav 22 x 0.8. Candidates 5 (re-raster, not an invisible-paint class) and 6 (no area) are listed after the ranked ones, unranked. "Same look" is the test to run before any flag: a pixel diff of the viewport per frame, with and without the change. Tiled layers skip raster for a repaint rect outside the coverage and only mark the tile stale (Source/WebCore/platform/graphics/ca/TileGrid.cpp:140-170 and 206-214@862f17d), so beyond-margin rects cost the call, not the raster, on tiled layers. Non-tiled layers hand every kept rect to the CALayer (GraphicsLayerCA.cpp:3767-3783) and nothing in `setNeedsDisplayInRect` looks at hidden or visible state; it also returns early without drawsContent, on m_needsFullRepaint and on an empty rect (GraphicsLayerCA.cpp:1016-1028). Whether CoreAnimation then rasters an off-screen non-tiled rect is not in the source we pin: not measured here.

1. Unnamed layers repainted by the scroll offset ("other"). Rewrite: 581 (hero) and 636 (rest) not visible per 100 f, 18.9 and 18.4 Mpx wasted, two thirds to four fifths of all waste in those zones; orig is alike (432 / 546), so the rewrite did not change it. In one rewrite job (rest) the non-tiled layers behind it are: a 393x462 layer that is hidden and receives 17 repaint calls per frame over 60 frames, a hidden 18x37 layer (2 calls per frame, 160 frames), and 402x922, 402x1204, 402x1268 layers that get a viewport-sized rect each frame (visible, so partly wasted by area). Candidate: first name them (the Inspector `data.clip` lane or a probe by layer id; follow-up), then stop the per-scroll style write that dirties them or move the pre-reveal state of hidden blocks to `visibility: hidden`, which removes the layer's contents from painting. Source: GraphicsLayerCA.cpp:1014-1046.
2. People deck, vinyl spin. Original 372 (hero) / 501 (rest) not visible, 26.3 / 29.0 Mpx; rewrite 121 / 105, 3.6 / 2.5 Mpx; v2 129 / 107. The rewrite is already about 7 times lower in hero waste. Cause: `anim:vinylSpin` (a 4 s `transform: rotate` loop, apps/site/src/parts/people.deck/deck.module.css:479-486) and `trans:transform|filter|opacity`. A rotate animation on its own layer is composited and needs no repaint, so repaints of the deck during the loop mean the spinning record shares a layer with painted content. Candidate: find which layer gets the deck repaints. .record is already composited by its running transform animation (RenderLayerCompositor.cpp:3842-3864), and the deck already pauses when not near (data-fw-scene=paused, people.deck/index.tsx:86), so the repaints come from deck content painted next to the record or from the near-but-off-screen band. Next step: a probe by layer id, then narrow the near margin of the deck scene. INFERRED. Source: Source/WebCore/rendering/RenderLayerCompositor.cpp:3842-3864 (running accelerated animation or an animated transform/filter forces a layer).
3. Platform cards, scroll cause, beyond the coverage. Rewrite rest 262 not visible (229 beyond, 32 prepaint), 3.2 Mpx; finish 197 (146 beyond, 51 prepaint), 0.9 Mpx; v2 the same; the original is higher in rest (313). Elements: `div.platform-module_card` by size match, plus marquee and sweep animations (`anim:marqueeLeft`, `anim:sweepDoc`, a few). The rects are small, so cost is call volume. Candidate: find the scroll-dependent style write that dirties the cards (the top cause is the scroll offset, not an animation; the section already pauses its animations when not near, platform.module.css:22-25) and stop it while the cards are outside the coverage. Pausing animations covers only the few anim:* rows. INFERRED. This overlaps the candidates of research/notes/2026/10-2x-end-gpu-map.md. Source: TileGrid.cpp:206-214.
4. Nav header while hidden (rest). 22-24 not visible per 100 f, all hidden class, 0.8 Mpx; `header.nav-module_nav` repainted by the scroll offset while its contents are hidden. Small. Candidate: do not change the nav's scroll-dependent style while it is off its shown state. Source: GraphicsLayerCA.cpp:1016.
5. Layer resizes that re-raster whole layers (hero). Rewrite 58 and v2 46 resized non-tiled layers per 100 f (0.6 and 0.7 Mpx), original 18 (0.3 Mpx): the rewrite resizes about three times more layers. Elements: `header.nav-module_nav` 73x36 to 188x36 (earn pill unmask), `strong.typing-module_percent` 74x38 to 64x38, commission `path` glyphs 26x38 to 25x38. The Lean rule `rerasterArea` counts the full new size of a non-tiled layer whose size changed. Candidate: animate those with `transform: scale` or `clip-path` on a fixed-size layer (the look must be re-checked: width changes reflow text). Source: GraphicsLayerCA.cpp:641-648 (a size change is a GeometryChanged commit; the re-raster itself is CoreAnimation behaviour, INFERRED).
6. `body > nav.site-locale-links` clipped-out. 95-98 per 100 f in hero and rest (rewrite, v2), 72 in finish, but each rect is 2 px (540 px for 270 rects in one job): the count is high, the cost is nothing. No fix.

## Limits (accepted)

- WKTR is iOS-simulator WebKit (WKTR r324039) on a macOS runner, not the phone: tile sizes and the toolbar differ. Transfer to the phone is INFERRED.
- Paints for tiles that are created while scrolling never reach WKTR's tracked repaint rects, so new-tile raster is not in these numbers.
- covered and noop need a pixel diff; none was run (candidate sample: 20 frames per arm, follow-up). Their rows are 0 by construction.
- The page script replays the swipe-touch-v1 schedule with `scrollTo` in native requestAnimationFrame: counts per frame, never time.
- 13 of 105 candidate layers were named by the probe; the rest are named by size match or left as "other" (candidate 1 depends on closing this).
- Inspector Paint `data.clip` lane (clip per paint record, real phone-engine data) is a follow-up; it needs an xcode job in webkit-sim.yml.

## Where things are

- Lean: lean/Fw/Engine/PaintVisible.lean, lean/scripts/PaintVisibleGolden.lean, golden packages/contracts/golden/measure/paint-visible.jsonl.
- Lane: packages/measure-wktr/src/repaint*.mjs, wktr.yml inputs `repaint` / token `[repaint]`.
- Results: results/invisible-paint/ (summary.json, summary.md, table.md, run.txt).
