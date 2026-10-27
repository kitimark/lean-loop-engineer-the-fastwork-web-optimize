Cells: median [min-max] over the visits of the arm. p95, p99 and max are frame intervals in ms inside the push spans; over50 is frames over 50 ms; over50Rate is frames over 50 ms per 1000 intervals of the visit (a tenth of it per 100 intervals);
style, layout, paint and rAF are Timeline records between each push and its morph end (RecalculateStyles, Layout, Paint, FireAnimationFrame), summed over the 10 pushes of a visit.
Label: the Lean rule `pushLabel` against the base (better, worse, same, unresolved); unresolved when either side has fewer than 3 visits.

| arm | n | p95 | p99 | max | over50 | RecalculateStyles | Layout | Paint | FireAnimationFrame | over50Rate | label |
|---|---|---|---|---|---|---|---|---|---|---|---|
| base | 6 | 58.0 [57.0-85.0] | 72.0 [68.0-106.0] | 92.0 [82.0-198.0] | 52 [42-57] | 1237 [983-1308] | 1047 [844-1096] | 12613 [8994-13251] | 262 [186-292] | 91 [72-127] | base |
| morph.geom:on | 5 | 62.0 [56.0-65.0] | 92.0 [90.0-96.0] | 109.0 [103.0-138.0] | 36 [26-38] | 834 [810-884] | 565 [553-607] | 3210 [3151-3229] | 275 [272-312] | 113 [80-119] | better |
| morph.tween:geom-timed | 5 | 69.0 [68.0-98.0] | 108.0 [107.0-137.0] | 134.0 [114.0-160.0] | 53 [52-74] | 1102 [966-1160] | 868 [752-894] | 4566 [4172-4680] | 94 [58-136] | 106 [104-172] | better |

### Lean cell verdicts against the base

| arm | p95 | p99 | max | over50 | RecalculateStyles | Layout | Paint | FireAnimationFrame | over50Rate |
|---|---|---|---|---|---|---|---|---|---|
| morph.geom:on | same | same | same | same | same | same | beats | same | same |
| morph.tween:geom-timed | same | same | same | same | same | same | beats | same | same |

### Median over the arms by position in the round

| position | n | p95 | p99 | max | over50 | RecalculateStyles | Layout | Paint | FireAnimationFrame | over50Rate |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 6 | 68.0 [59.0-98.0] | 106.0 [74.0-137.0] | 134.0 [82.0-198.0] | 53 [36-74] | 983 [816-1232] | 844 [563-1030] | 4389 [3151-11958] | 255 [58-298] | 119 [86-172] |
| 1 | 5 | 62.0 [57.0-71.0] | 90.0 [68.0-107.0] | 109.0 [89.0-138.0] | 42 [27-52] | 1120 [810-1237] | 885 [553-1047] | 4680 [3210-12613] | 262 [91-312] | 91 [74-117] |
| 2 | 5 | 58.0 [56.0-69.0] | 91.0 [68.0-117.0] | 103.0 [82.0-151.0] | 53 [26-59] | 1160 [834-1308] | 894 [565-1096] | 4605 [3185-13251] | 275 [110-292] | 94 [72-121] |

### Median over the arms by round

| round | n | p95 | p99 | max | over50 | RecalculateStyles | Layout | Paint | FireAnimationFrame | over50Rate |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 3 | 68.0 [62.0-85.0] | 106.0 [90.0-108.0] | 131.0 [109.0-198.0] | 53 [27-57] | 983 [884-1160] | 844 [607-894] | 4605 [3210-8994] | 186 [136-312] | 106 [82-127] |
| 1 | 3 | 61.0 [57.0-71.0] | 92.0 [68.0-107.0] | 105.0 [92.0-114.0] | 42 [38-52] | 1120 [816-1308] | 885 [563-1096] | 4680 [3229-13251] | 275 [91-292] | 104 [72-119] |
| 2 | 3 | 58.0 [56.0-68.0] | 91.0 [72.0-108.0] | 105.0 [103.0-134.0] | 52 [26-53] | 966 [834-1237] | 752 [565-1047] | 4172 [3185-12150] | 256 [94-275] | 91 [80-106] |
| 3 | 3 | 65.0 [58.0-98.0] | 96.0 [70.0-137.0] | 138.0 [82.0-160.0] | 54 [37-74] | 1045 [810-1301] | 868 [553-1091] | 4389 [3214-12710] | 272 [58-280] | 117 [94-172] |
| 4 | 3 | 64.0 [57.0-69.0] | 92.0 [68.0-117.0] | 112.0 [89.0-151.0] | 42 [36-59] | 1102 [848-1229] | 863 [577-1037] | 4566 [3151-12613] | 262 [110-298] | 113 [74-121] |
| 5 | 1 | 59.0 [59.0-59.0] | 74.0 [74.0-74.0] | 82.0 [82.0-82.0] | 49 [49-49] | 1232 [1232-1232] | 1030 [1030-1030] | 11958 [11958-11958] | 255 [255-255] | 86 [86-86] |

### Visits

| visit | arm | round | position | seconds | pushes | nav | max morph (per mille) | p95 | p99 | max | over50 | RecalculateStyles | Layout | Paint | FireAnimationFrame | over50Rate |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | base | 0 | 0 | 215 | 10 | yes | 1000 | 85.0 | 106.0 | 198.0 | 57 | 983 | 844 | 8994 | 186 | 127 |
| 1 | morph.geom:on | 0 | 1 | 194 | 10 | yes | 1000 | 62.0 | 90.0 | 109.0 | 27 | 884 | 607 | 3210 | 312 | 82 |
| 2 | morph.tween:geom-timed | 0 | 2 | 185 | 10 | yes | 1000 | 68.0 | 108.0 | 131.0 | 53 | 1160 | 894 | 4605 | 136 | 106 |
| 3 | morph.geom:on | 1 | 0 | 186 | 10 | yes | 1000 | 61.0 | 92.0 | 105.0 | 38 | 816 | 563 | 3229 | 275 | 119 |
| 4 | morph.tween:geom-timed | 1 | 1 | 188 | 10 | yes | 1000 | 71.0 | 107.0 | 114.0 | 52 | 1120 | 885 | 4680 | 91 | 104 |
| 5 | base | 1 | 2 | 196 | 10 | yes | 1000 | 57.0 | 68.0 | 92.0 | 42 | 1308 | 1096 | 13251 | 292 | 72 |
| 6 | morph.tween:geom-timed | 2 | 0 | 184 | 10 | yes | 1000 | 68.0 | 108.0 | 134.0 | 53 | 966 | 752 | 4172 | 94 | 106 |
| 7 | base | 2 | 1 | 187 | 10 | yes | 1000 | 58.0 | 72.0 | 105.0 | 52 | 1237 | 1047 | 12150 | 256 | 91 |
| 8 | morph.geom:on | 2 | 2 | 185 | 10 | yes | 1000 | 56.0 | 91.0 | 103.0 | 26 | 834 | 565 | 3185 | 275 | 80 |
| 9 | morph.tween:geom-timed | 3 | 0 | 186 | 10 | yes | 1000 | 98.0 | 137.0 | 160.0 | 74 | 1045 | 868 | 4389 | 58 | 172 |
| 10 | morph.geom:on | 3 | 1 | 185 | 10 | yes | 1000 | 65.0 | 96.0 | 138.0 | 37 | 810 | 553 | 3214 | 272 | 117 |
| 11 | base | 3 | 2 | 301 | 10 | yes | 1000 | 58.0 | 70.0 | 82.0 | 54 | 1301 | 1091 | 12710 | 280 | 94 |
| 12 | morph.geom:on | 4 | 0 | 186 | 10 | yes | 1000 | 64.0 | 92.0 | 112.0 | 36 | 848 | 577 | 3151 | 298 | 113 |
| 13 | base | 4 | 1 | 189 | 10 | yes | 1000 | 57.0 | 68.0 | 89.0 | 42 | 1229 | 1037 | 12613 | 262 | 74 |
| 14 | morph.tween:geom-timed | 4 | 2 | 187 | 10 | yes | 1000 | 69.0 | 117.0 | 151.0 | 59 | 1102 | 863 | 4566 | 110 | 121 |
| 15 | base | 5 | 0 | 240 | 10 | yes | 1000 | 59.0 | 74.0 | 82.0 | 49 | 1232 | 1030 | 11958 | 255 | 86 |

### Not run

- visit 16 (morph.tween:geom-timed): refused, 0 attempts, faults none

## Frame attribution (tl lane: Timeline on, frames cut by the rAF times, work by the innermost record)

Main-thread busy = script, style, layout, paint. `commitWait` is the WebKit `Composite` span (CA commit and flush; it ends after an off-main flush, so it is not main-thread busy). A frame under half busy is `commitWait` when that span fills half of it, else `idle`.

| arm | n | intervals | over 50 ms | script | style | layout | paint | commitWait | idle | not main-busy (commitWait + idle) | main-thread busy share of the over-50 time |
|---|---|---|---|---|---|---|---|---|---|---|---|
| base | 6 | 2706 | 424 | 0 (0%) | 0 (0%) | 0 (0%) | 0 (0%) | 407 (96%) | 17 (4%) | 424 of 424 | 21% |
| morph.geom:on | 5 | 1354 | 311 | 3 (1%) | 203 (65%) | 0 (0%) | 0 (0%) | 24 (8%) | 81 (26%) | 105 of 311 | 62% |
| morph.tween:geom-timed | 5 | 2312 | 396 | 2 (1%) | 348 (88%) | 0 (0%) | 0 (0%) | 39 (10%) | 7 (2%) | 46 of 396 | 69% |

Tail (frames at or over the visit p95 of the tl lane):

| arm | frames | script | style | layout | paint | commitWait | idle |
|---|---|---|---|---|---|---|---|
| base | 149 | 0 (0%) | 0 (0%) | 0 (0%) | 0 (0%) | 149 (100%) | 0 (0%) |
| morph.geom:on | 76 | 2 (3%) | 35 (46%) | 0 (0%) | 0 (0%) | 2 (3%) | 37 (49%) |
| morph.tween:geom-timed | 125 | 0 (0%) | 116 (93%) | 0 (0%) | 0 (0%) | 2 (2%) | 7 (6%) |

Lead records of the over-50 frames (dominant work: record):

- base: commitWait: Composite x407; idle: - x17
- morph.geom:on: style: RecalculateStyles x203; idle: - x81; commitWait: Composite x24; script: FunctionCall entry-client-DN21yM_l.js:47:46699 x2; script: FunctionCall entry-client-DN21yM_l.js:9:96013 x1
- morph.tween:geom-timed: style: RecalculateStyles x348; commitWait: Composite x39; idle: - x7; script: FunctionCall entry-client-DN21yM_l.js:47:14476 x2

Style invalidations in the main-busy long frames (ScheduleStyleRecalculation records inside the interval; caller = top script frame of its stack; the Timeline names no element for them):

- base: 0 records; none
- morph.geom:on: 482 records; setProperty [native code]:0 x211; no script stack x209; oh entry-client-DN21yM_l.js:47 x47; add [native code]:0 x5; Jh entry-client-DN21yM_l.js:47 x5
- morph.tween:geom-timed: 796 records; no script stack x364; setProperty [native code]:0 x249; Jh entry-client-DN21yM_l.js:47 x43; oh entry-client-DN21yM_l.js:47 x42; cancel [native code]:0 x26

Running animations at the start of the pushes (first visit with a snapshot):

- base: 39 animations; CSSAnimation visuals-module_secureNetworkFlagIn_aRoy3y on span.visuals-module_flag_iB99gw.visuals-module_flagBordered_FJGe1F [transform,opacity] finished x5; CSSAnimation visuals-module_invoiceIRowIn_3lnIkg on li.visuals-module_order_WtwPir [transform,opacity] finished x4; CSSAnimation sweep-module_sweepDoc_zGc1tE on span.platform-module_word_p8Lg-4.sweep-module_sweep_6bRkbr [backgroundPositionY,backgroundPositionX] running x3; CSSAnimation morph-module_up_d0Qv2N on div.morph-module_track_CO8LmY [transform] paused x2; CSSAnimation deck-module_profileFade_bvnD7G on div.deck-module_body_KfX5hf [transform,opacity] paused x2; CSSAnimation nav-module_earn-unmask_ZfvUeY on button.nav-module_btn_iwM4wZ.nav-module_earn_opGnJj[data-fw=nav-earn] [webkitMaskPositionY,webkitMaskPositionX] finished x1; CSSAnimation nav-module_earn-sheen_BJihYd on button.nav-module_btn_iwM4wZ.nav-module_earn_opGnJj[data-fw=nav-earn] [transform] finished x1; CSSAnimation morph-module_down_PJRywW on div.morph-module_track_CO8LmY [transform] paused x1; CSSAnimation accent-module_idle0_t7SI92 on svg [opacity] running x1; CSSAnimation accent-module_idle1_a3NQoa on svg [opacity] running x1; CSSAnimation accent-module_idle2_Q1MyP3 on svg [opacity] running x1; CSSAnimation cue-module_copyIn_j26lO8 on button.cue-module_cue_AuR-MH[data-fw=hero-cue] [] finished x1
- morph.geom:on: 39 animations; CSSAnimation visuals-module_secureNetworkFlagIn_aRoy3y on span.visuals-module_flag_iB99gw.visuals-module_flagBordered_FJGe1F [transform,opacity] finished x5; CSSAnimation visuals-module_invoiceIRowIn_3lnIkg on li.visuals-module_order_WtwPir [transform,opacity] finished x4; CSSAnimation sweep-module_sweepDoc_zGc1tE on span.platform-module_word_p8Lg-4.sweep-module_sweep_6bRkbr [backgroundPositionY,backgroundPositionX] running x3; CSSAnimation morph-module_up_d0Qv2N on div.morph-module_track_CO8LmY [transform] paused x2; CSSAnimation deck-module_profileFade_bvnD7G on div.deck-module_body_KfX5hf [transform,opacity] paused x2; CSSAnimation nav-module_earn-unmask_ZfvUeY on button.nav-module_btn_iwM4wZ.nav-module_earn_opGnJj[data-fw=nav-earn] [webkitMaskPositionY,webkitMaskPositionX] finished x1; CSSAnimation nav-module_earn-sheen_BJihYd on button.nav-module_btn_iwM4wZ.nav-module_earn_opGnJj[data-fw=nav-earn] [transform] finished x1; CSSAnimation morph-module_down_PJRywW on div.morph-module_track_CO8LmY [transform] paused x1; CSSAnimation accent-module_idle0_t7SI92 on svg [opacity] running x1; CSSAnimation accent-module_idle1_a3NQoa on svg [opacity] running x1; CSSAnimation accent-module_idle2_Q1MyP3 on svg [opacity] running x1; CSSAnimation cue-module_copyIn_j26lO8 on button.cue-module_cue_AuR-MH[data-fw=hero-cue] [] finished x1
- morph.tween:geom-timed: 39 animations; CSSAnimation visuals-module_secureNetworkFlagIn_aRoy3y on span.visuals-module_flag_iB99gw.visuals-module_flagBordered_FJGe1F [transform,opacity] finished x5; CSSAnimation visuals-module_invoiceIRowIn_3lnIkg on li.visuals-module_order_WtwPir [transform,opacity] finished x4; CSSAnimation sweep-module_sweepDoc_zGc1tE on span.platform-module_word_p8Lg-4.sweep-module_sweep_6bRkbr [backgroundPositionY,backgroundPositionX] running x3; CSSAnimation morph-module_up_d0Qv2N on div.morph-module_track_CO8LmY [transform] paused x2; CSSAnimation deck-module_profileFade_bvnD7G on div.deck-module_body_KfX5hf [transform,opacity] paused x2; CSSAnimation nav-module_earn-unmask_ZfvUeY on button.nav-module_btn_iwM4wZ.nav-module_earn_opGnJj[data-fw=nav-earn] [webkitMaskPositionY,webkitMaskPositionX] finished x1; CSSAnimation nav-module_earn-sheen_BJihYd on button.nav-module_btn_iwM4wZ.nav-module_earn_opGnJj[data-fw=nav-earn] [transform] finished x1; CSSAnimation morph-module_down_PJRywW on div.morph-module_track_CO8LmY [transform] paused x1; CSSAnimation accent-module_idle0_t7SI92 on svg [opacity] running x1; CSSAnimation accent-module_idle1_a3NQoa on svg [opacity] running x1; CSSAnimation accent-module_idle2_Q1MyP3 on svg [opacity] running x1; CSSAnimation cue-module_copyIn_j26lO8 on button.cue-module_cue_AuR-MH[data-fw=hero-cue] [] finished x1

Long frames (over 50 ms) by time since the touch start, long / all intervals of the tl lane:

| arm | 0-0.5 s | 0.5-1 s | 1-1.5 s | later |
|---|---|---|---|---|
| base | 272 / 746 | 151 / 708 | 0 / 898 | 1 / 354 |
| morph.geom:on | 208 / 652 | 97 / 276 | 6 / 125 | 0 / 301 |
| morph.tween:geom-timed | 234 / 544 | 162 / 516 | 0 / 893 | 0 / 359 |

Mean per interval of records overlapping it (record time in ms is the sum of the record lengths clipped to the interval, nested records counted in full):

| arm | frames | n | style n | style ms | layout n | paint n | composite ms | touch+pointer events | transition events | animation events |
|---|---|---|---|---|---|---|---|---|---|---|
| base | over 50 ms | 424 | 4.9 | 10.0 | 4.9 | 90.8 | 48.4 | 21.6 | 6.7 | 0.6 |
| base | other | 2282 | 2.7 | 3.2 | 2.3 | 13.5 | 14.7 | 1.8 | 1.8 | 0.3 |
| morph.geom:on | over 50 ms | 311 | 4.2 | 35.6 | 3.2 | 30.2 | 18.9 | 12.7 | 3.7 | 1.9 |
| morph.geom:on | other | 1043 | 3.1 | 12.1 | 1.6 | 4.6 | 9.3 | 3.2 | 0.4 | 0.3 |
| morph.tween:geom-timed | over 50 ms | 396 | 3.6 | 45.4 | 3.1 | 33.2 | 25.5 | 13.7 | 4.6 | 1.8 |
| morph.tween:geom-timed | other | 1916 | 2.5 | 3.8 | 1.9 | 5.1 | 10.2 | 0.8 | 0.7 | 0.4 |

Paint clip rectangles by the animated element box (snapshot of document.getAnimations() at the start of the pushes; morph tracks left out) that holds the clip centre; top five, share of all clips:

- base, over 50 ms (38478 clips): 36% visuals-module_secureNetworkRingsIn; 26% no animated box; 11% visuals-module_invoiceIRowIn; 6% visuals-module_secureNetworkRingsIn+visuals-module_secureNetworkShieldIn; 5% visuals-module_invoiceCardIn
- base, other (30842 clips): 25% visuals-module_secureNetworkRingsIn; 18% no animated box; 14% visuals-module_secureNetworkDashIn+visuals-module_secureNetworkRingsIn; 10% visuals-module_invoiceIRowIn; 10% sweep-module_sweepDoc
- morph.geom:on, over 50 ms (9388 clips): 38% visuals-module_secureNetworkRingsIn; 27% no animated box; 6% visuals-module_secureNetworkDashIn+visuals-module_secureNetworkRingsIn; 5% visuals-module_invoiceCardIn; 5% sweep-module_sweepDoc
- morph.geom:on, other (4746 clips): 43% sweep-module_sweepDoc; 42% visuals-module_secureNetworkDashIn+visuals-module_secureNetworkRingsIn; 6% visuals-module_secureNetworkRingsIn; 5% no animated box; 2% visuals-module_invoiceCardIn
- morph.tween:geom-timed, over 50 ms (13141 clips): 36% visuals-module_secureNetworkRingsIn; 28% no animated box; 9% visuals-module_invoiceIRowIn; 5% visuals-module_secureNetworkDashIn+visuals-module_secureNetworkRingsIn; 4% sweep-module_sweepDoc
- morph.tween:geom-timed, other (9689 clips): 37% visuals-module_secureNetworkDashIn+visuals-module_secureNetworkRingsIn; 26% sweep-module_sweepDoc; 19% visuals-module_secureNetworkRingsIn; 14% visuals-module_secureNetworkRingsIn+visuals-module_secureNetworkShieldIn; 2% visuals-module_invoiceCardIn

Frames lane (the r2-comparable one), all visits of the arm pooled: frame intervals inside the push spans, those over 50 ms, and the worst interval:

| arm | visits | intervals | over 50 ms | per 100 intervals | worst interval (ms) | Lean label against the base |
|---|---|---|---|---|---|---|
| base | 6 | 3294 | 296 | 9.0 | 198.0 | base |
| morph.geom:on | 5 | 1601 | 164 | 10.2 | 138.0 | better |
| morph.tween:geom-timed | 5 | 2414 | 291 | 12.1 | 160.0 | better |

Frames lane (no Timeline) against the tl lane (Timeline on), median over the visits of the arm; ms:

| arm | frames lane p95 | tl lane p95 | frames lane over 50 ms | tl lane over 50 ms | tl lane max |
|---|---|---|---|---|---|
| base | 58 | 73.0 | 52 | 72 | 133.0 |
| morph.geom:on | 62 | 77.0 | 36 | 69 | 144.0 |
| morph.tween:geom-timed | 69 | 81.0 | 53 | 81 | 175.0 |

Worst five over-50 frames per arm (ms; dominant work; lead record):

- base: 184.0 commitWait (Composite, visit 0); 169.0 commitWait (Composite, visit 0); 159.0 commitWait (Composite, visit 0); 150.0 commitWait (Composite, visit 0); 137.0 commitWait (Composite, visit 0)
- morph.geom:on: 159.0 style (RecalculateStyles, visit 10); 147.0 style (RecalculateStyles, visit 3); 144.0 style (RecalculateStyles, visit 1); 130.0 script (FunctionCall entry-client-DN21yM_l.js:47:46699, visit 8); 129.0 script (FunctionCall entry-client-DN21yM_l.js:47:46699, visit 12)
- morph.tween:geom-timed: 211.0 style (RecalculateStyles, visit 14); 191.0 style (RecalculateStyles, visit 2); 175.0 style (RecalculateStyles, visit 9); 172.0 style (RecalculateStyles, visit 6); 170.0 style (RecalculateStyles, visit 6)
