## Invisible paint, WKTR repaint rects per frame (MEASURED, macOS WebKit in the iOS 26.5 Simulator; counts, not time)

### orig (3 runs, frames hero 531, rest 813, finish 345)

| zone | part | paints/100f | invisible/100f | waste px/100f | zero-area | hidden | clipped | beyond | prepaint | re-raster layers/100f | re-raster px/100f | causes (non-visible) | elements (non-visible) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| hero | nav | 100 | 0 | 3010 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | anim:svelte-1dcozpm-start-selling-nav-earn-unmask anim:svelte-1dcozpm-start-selling-nav-earn-sheen (4) | header.start-selling-top-nav.is-hero-pill.is-hero-chrome-ready (4) |
| hero | hero | 6 | 2 | 588634 | 0 | 2 | 0 | 0 | 0 | 0 | 515 | anim:svelte-1p2vpne-hero-cta-orbit (13) | svg.solar.solar-bell-linear.cta-icon (1 of 2 same size) (10); div.hero-cta (3); svg.solar.solar-bell-linear.cta-icon (1 of 2 same size) 20x20->37x37 (2) |
| hero | people | 867 | 372 | 26303801 | 0 | 1 | 0 | 370 | 0 | 0 | 0 | anim:vinyl-spin (1708); trans:filter anim:vinyl-spin (117); trans:transform anim:vinyl-spin (72) | div.start-selling-profile-deck (1963); div.body (14) |
| hero | platform | 93 | 93 | 125 | 0 | 0 | 0 | 93 | 0 | 0 | 0 | scroll (499) | - (499) |
| hero | other | 866 | 432 | 19119052 | 0 | 231 | 0 | 200 | 0 | 18 | 313669 | scroll (2294) | - (2294); - 14x33->2x33 (4); - 9x33->2x33 (4) |
| rest | nav | 134 | 27 | 1017221 | 0 | 27 | 0 | 0 | 0 | 0 | 0 | scroll (225) | header.start-selling-top-nav.is-hero-pill.is-hero-chrome-ready (225) |
| rest | hero | 11 | 11 | 4325460 | 0 | 6 | 0 | 5 | 0 | 0 | 0 | scroll (42); anim:svelte-1p2vpne-hero-cta-orbit (37); anim:svelte-1p2vpne-scroll-float (15) | div.hero-cta (37); button.scroll-cue (15); - (14) |
| rest | people | 633 | 501 | 28958769 | 0 | 0 | 0 | 501 | 0 | 0 | 0 | anim:vinyl-spin (3676); scroll (403) | div.start-selling-profile-deck (4075); div.body (4) |
| rest | commission | 0 | 0 | 965195 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | anim:three-frame-zero (4) | svg.zero-frame.frame-0 (3); svg.underline-frame.frame-0 (1) |
| rest | platform | 337 | 313 | 3376780 | 0 | 0 | 0 | 279 | 33 | 0 | 0 | scroll (2530); anim:start-selling-platform-i-doc-sweep (15) | div.start-selling-platform-card (size match) (1372); div.start-selling-platform-card (1 of 2 same size) (697); - (461) |
| rest | other | 819 | 546 | 17351416 | 0 | 130 | 0 | 408 | 7 | 3 | 365 | scroll (4440) | - (4440); - 12x33->2x33 (5); - 11x33->2x33 (2) |
| finish | nav | 72 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | - | - |
| finish | hero | 0 | 0 | 859930 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | anim:svelte-1p2vpne-hero-cta-orbit (3) | div.hero-cta (3) |
| finish | pain | 0 | 0 | 420526 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | scroll (3) | - (3) |
| finish | platform | 428 | 221 | 986731 | 0 | 0 | 0 | 155 | 65 | 0 | 0 | scroll (764) | div.start-selling-platform-card (size match) (454); div.start-selling-platform-card (1 of 2 same size) (227); - (83) |
| finish | other | 448 | 219 | 22354760 | 0 | 2 | 0 | 215 | 0 | 0 | 0 | scroll (756) | - (756) |

Tracked repaint calls per 100 frames and the dirty rects the engine keeps (Lean `dirty`): hero 105481 calls -> 1935 kept, rest 79098 calls -> 1938 kept, finish 1564 calls -> 951 kept

Count-type classes over the 3 runs (kMax 4, tMax 24):

- hero: quarantined: paintArea, paintRects, reRasterArea, rects_beyond_margin, rects_hidden, rects_visible, resizedLayers, trackedCalls, wasteArea | deterministic: rects_clipped_out, rects_covered, rects_noop, rects_prepaint_margin, rects_zero_area
- rest: quarantined: paintArea, paintRects, reRasterArea, rects_beyond_margin, rects_hidden, rects_prepaint_margin, rects_visible, resizedLayers, trackedCalls, wasteArea | deterministic: rects_clipped_out, rects_covered, rects_noop, rects_zero_area
- finish: quarantined: paintArea, paintRects, rects_beyond_margin, rects_hidden, rects_prepaint_margin, rects_visible, trackedCalls, wasteArea | deterministic: reRasterArea, rects_clipped_out, rects_covered, rects_noop, rects_zero_area, resizedLayers

### rewrite (3 runs, frames hero 531, rest 825, finish 345)

| zone | part | paints/100f | invisible/100f | waste px/100f | zero-area | hidden | clipped | beyond | prepaint | re-raster layers/100f | re-raster px/100f | causes (non-visible) | elements (non-visible) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| hero | nav | 103 | 2 | 9783 | 0 | 0 | 0 | 2 | 0 | 0 | 1776 | anim:nav-module_earn-unmask_ZfvUeY anim:nav-module_earn-sheen_BJihYd (13) | header.nav-module_nav_fsb7in.is-hero-pill.is-hero-chrome-ready (13); header.nav-module_nav_fsb7in.is-hero-pill.is-hero-chrome-ready 73x36->188x36 (1); header.nav-module_nav_fsb7in.is-hero-pill.is-hero-chrome-ready 73x36->74x36 (1) |
| hero | hero | 15 | 11 | 593538 | 0 | 0 | 0 | 9 | 0 | 0 | 0 | scroll (56); anim:cue-module_scrollFloat_6RFPnC (3) | svg.hero-module_icon_V84s4Y (1 of 2 same size) (56); span.cue-module_float_g8PRFw (3) |
| hero | people | 224 | 121 | 3637367 | 0 | 0 | 0 | 121 | 0 | 0 | 0 | trans:transform anim:deck-module_vinylSpin_k1msN- (389); anim:deck-module_vinylSpin_k1msN- (219); trans:filter anim:deck-module_vinylSpin_k1msN- (15) | div.deck-module_deck_Cq95es (635); div.deck-module_feedBody_Q-ZMcn (9) |
| hero | commission | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 2147 | - | path (size match) 26x38->25x38 (4); path (1 of 2 same size) 26x37->25x37 (2); strong.typing-module_percent_StHZIE (size match) 74x38->64x38 (2) |
| hero | other | 934 | 581 | 18856564 | 0 | 198 | 95 | 287 | 0 | 58 | 594646 | scroll (3090) | - (2584); body > nav.site-locale-links (506); - 29x38->28x38 (6) |
| rest | nav | 127 | 22 | 772474 | 0 | 22 | 0 | 0 | 0 | 0 | 0 | scroll (183) | header.nav-module_nav_fsb7in.is-hero-pill.is-hero-chrome-ready (183) |
| rest | hero | 4 | 4 | 1745063 | 0 | 0 | 0 | 4 | 0 | 0 | 0 | scroll (36); anim:accent-module_strokeOut_SDdGZt (2); anim:cue-module_scrollFloat_6RFPnC (2) | - (8); article.card-module_card_E1pJca.deck-module_a_2TcmWu (7); article.card-module_card_E1pJca.deck-module_b_PzVqgG (7) |
| rest | people | 180 | 105 | 2502368 | 0 | 0 | 0 | 105 | 0 | 0 | 0 | anim:deck-module_vinylSpin_k1msN- (717); scroll (138); trans:transform anim:deck-module_vinylSpin_k1msN- (12) | div.deck-module_deck_Cq95es (864); div.deck-module_feedBody_Q-ZMcn (3) |
| rest | commission | 0 | 0 | 670292 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | anim:commission-module_three-frame-zero_NB28ic (5); scroll (3) | - (3); svg.commission-module_zeroFrame_3hN6xy.commission-module_frame0_ErKjUF (3); svg.commission-module_underlineFrame_gOs8-C.commission-module_frame0_E (2) |
| rest | platform | 288 | 262 | 3244275 | 0 | 0 | 0 | 229 | 32 | 0 | 0 | scroll (2158); anim:sweep-module_sweepDoc_zGc1tE (3); anim:visuals-module_marqueeLeft_14it1n (2) | div.platform-module_card_D3ykKA (1 of 2 same size) (2077); - (81); span.platform-module_word_p8Lg-4.sweep-module_sweep_6bRkbr (3) |
| rest | other | 870 | 636 | 18371348 | 0 | 210 | 98 | 321 | 6 | 6 | 1908 | scroll (5251) | - (4439); body > nav.site-locale-links (812); - 3x33->2x33 (5) |
| finish | nav | 72 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | - | - |
| finish | hero | 0 | 0 | 859930 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | anim:cue-module_scrollFloat_6RFPnC (3) | span.cue-module_float_g8PRFw (3) |
| finish | pain | 0 | 0 | 420526 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | scroll (3) | - (3) |
| finish | platform | 400 | 197 | 915194 | 0 | 0 | 0 | 146 | 51 | 0 | 0 | scroll (680) | div.platform-module_card_D3ykKA (1 of 2 same size) (680) |
| finish | other | 482 | 235 | 21149062 | 0 | 3 | 72 | 159 | 0 | 0 | 0 | scroll (814) | - (564); body > nav.site-locale-links (250) |

Tracked repaint calls per 100 frames and the dirty rects the engine keeps (Lean `dirty`): hero 2615 calls -> 1276 kept, rest 2706 calls -> 1472 kept, finish 1558 calls -> 957 kept

Count-type classes over the 3 runs (kMax 4, tMax 24):

- hero: quarantined: paintArea, paintRects, reRasterArea, rects_beyond_margin, rects_clipped_out, rects_hidden, rects_visible, resizedLayers, trackedCalls, wasteArea | deterministic: rects_covered, rects_noop, rects_zero_area | stable: rects_prepaint_margin(k1,t1)
- rest: quarantined: paintArea, paintRects, reRasterArea, rects_beyond_margin, rects_hidden, rects_prepaint_margin, rects_visible, resizedLayers, trackedCalls, wasteArea | stable: rects_clipped_out(k4,t1) | deterministic: rects_covered, rects_noop, rects_zero_area
- finish: quarantined: paintArea, paintRects, rects_beyond_margin, rects_visible, trackedCalls, wasteArea | deterministic: reRasterArea, rects_covered, rects_noop, rects_zero_area, resizedLayers | stable: rects_clipped_out(k1,t1), rects_hidden(k3,t1), rects_prepaint_margin(k1,t1)

### v2 (3 runs, frames hero 531, rest 825, finish 345)

| zone | part | paints/100f | invisible/100f | waste px/100f | zero-area | hidden | clipped | beyond | prepaint | re-raster layers/100f | re-raster px/100f | causes (non-visible) | elements (non-visible) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| hero | nav | 108 | 2 | 11701 | 0 | 0 | 0 | 2 | 0 | 0 | 0 | anim:nav-module_earn-unmask_ZfvUeY anim:nav-module_earn-sheen_BJihYd (14) | header.nav-module_nav_fsb7in.is-hero-pill.is-hero-chrome-ready (14) |
| hero | hero | 12 | 8 | 606201 | 0 | 1 | 0 | 6 | 0 | 0 | 257 | scroll (40); anim:cue-module_scrollFloat_6RFPnC (3) | svg.hero-module_icon_V84s4Y (1 of 2 same size) (32); span.cue-module_float_g8PRFw (3); article.card-module_card_E1pJca.deck-module_a_2TcmWu (2) |
| hero | people | 237 | 129 | 4478064 | 0 | 0 | 0 | 129 | 0 | 0 | 0 | trans:transform anim:deck-module_vinylSpin_k1msN- (349); anim:deck-module_vinylSpin_k1msN- (260); trans:filter trans:opacity trans:transform anim:deck-module_vinylSpin_k1msN- (35) | div.deck-module_deck_Cq95es (670); div.deck-module_feedBody_Q-ZMcn (15) |
| hero | commission | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 532 | - | path (size match) 26x38->25x38 (2); path (1 of 2 same size) 26x37->25x37 (1) |
| hero | platform | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 2056 | - | img (1 of 2 same size) 89x59->91x60 (2) |
| hero | other | 998 | 589 | 19706141 | 0 | 233 | 95 | 260 | 0 | 46 | 718291 | scroll (3131) | - (2623); body > nav.site-locale-links (508); - 37x36->37x37 (6) |
| rest | nav | 129 | 24 | 853098 | 0 | 24 | 0 | 0 | 0 | 0 | 0 | scroll (199) | header.nav-module_nav_fsb7in.is-hero-pill.is-hero-chrome-ready (199) |
| rest | hero | 7 | 7 | 1175233 | 0 | 2 | 0 | 5 | 0 | 0 | 0 | scroll (44); anim:cue-module_scrollFloat_6RFPnC (15); anim:accent-module_idle0_t7SI92 (2) | button.cue-module_cue_AuR-MH (15); article.card-module_card_E1pJca.deck-module_a_2TcmWu (9); article.card-module_card_E1pJca.deck-module_b_PzVqgG (9) |
| rest | people | 183 | 107 | 2550535 | 0 | 0 | 0 | 107 | 0 | 0 | 0 | anim:deck-module_vinylSpin_k1msN- (744); scroll (142) | div.deck-module_deck_Cq95es (882); div.deck-module_feedBody_Q-ZMcn (4) |
| rest | commission | 1 | 0 | 1140900 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | scroll (3); anim:commission-module_three-frame-zero_NB28ic (2) | - (3); svg.commission-module_zeroFrame_3hN6xy.commission-module_frame0_ErKjUF (2) |
| rest | platform | 288 | 262 | 3211794 | 0 | 0 | 0 | 229 | 32 | 0 | 0 | scroll (2159); anim:sweep-module_sweepDoc_zGc1tE (3) | div.platform-module_card_D3ykKA (1 of 2 same size) (2076); - (82); span.platform-module_word_p8Lg-4.sweep-module_sweep_6bRkbr (3) |
| rest | other | 757 | 518 | 17151461 | 0 | 109 | 98 | 301 | 9 | 5 | 1588 | scroll (4277) | - (3463); body > nav.site-locale-links (814); - 4x33->2x33 (3) |
| finish | nav | 93 | 15 | 415723 | 0 | 15 | 0 | 0 | 0 | 0 | 0 | scroll (53) | header.nav-module_nav_fsb7in.is-hero-pill.is-hero-chrome-ready (53) |
| finish | hero | 4 | 4 | 1685603 | 0 | 2 | 0 | 1 | 0 | 0 | 0 | anim:cue-module_scrollFloat_6RFPnC (9); scroll (5) | button.cue-module_cue_AuR-MH (5); span.cue-module_float_g8PRFw (4); - (1) |
| finish | people | 12 | 12 | 386484 | 0 | 0 | 0 | 12 | 0 | 0 | 0 | scroll (43) | div.deck-module_deck_Cq95es (42); div.deck-module_feedBody_Q-ZMcn (1) |
| finish | pain | 0 | 0 | 420526 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | scroll (3) | - (3) |
| finish | platform | 405 | 199 | 1380559 | 0 | 0 | 0 | 147 | 51 | 0 | 0 | scroll (687) | div.platform-module_card_D3ykKA (1 of 2 same size) (687) |
| finish | other | 557 | 322 | 22146430 | 0 | 35 | 72 | 212 | 0 | 0 | 0 | scroll (1111) | - (860); body > nav.site-locale-links (251) |

Tracked repaint calls per 100 frames and the dirty rects the engine keeps (Lean `dirty`): hero 2781 calls -> 1357 kept, rest 2473 calls -> 1367 kept, finish 1838 calls -> 1073 kept

Count-type classes over the 3 runs (kMax 4, tMax 24):

- hero: quarantined: paintArea, paintRects, reRasterArea, rects_beyond_margin, rects_clipped_out, rects_hidden, rects_visible, resizedLayers, trackedCalls, wasteArea | deterministic: rects_covered, rects_noop, rects_zero_area | stable: rects_prepaint_margin(k1,t1)
- rest: quarantined: paintArea, paintRects, reRasterArea, rects_beyond_margin, rects_hidden, rects_prepaint_margin, rects_visible, resizedLayers, trackedCalls, wasteArea | stable: rects_clipped_out(k3,t3) | deterministic: rects_covered, rects_noop, rects_zero_area
- finish: quarantined: paintArea, paintRects, rects_beyond_margin, rects_hidden, rects_visible, trackedCalls, wasteArea | deterministic: reRasterArea, rects_covered, rects_noop, rects_zero_area, resizedLayers | stable: rects_clipped_out(k2,t2), rects_prepaint_margin(k2,t2)
