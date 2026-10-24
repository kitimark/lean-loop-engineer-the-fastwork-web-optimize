---
id: 2026-10-2x-throttle-lift-ship
kind: note
title: "engine.scroll:unthrottle: the throttle-lift diagnostic as a shippable variant, with its WebKit condition, same-look proof, per-frame cost and a gate on both engines"
status: review
created: 2026-10-24
topics: [lag, webkit, ios-toolbar, scroll-driven, engine.scroll, unthrottle, lean, gate, counts]
---

# engine.scroll:unthrottle

Task `throttle-lift-ship`. The user's phone pass of `?fw=engine.scroll:throttle-lift` ("looks the same and hero-exit is a lot
of improve, no laggy on hero exit") and the Simulator count (163 band runs to 0, run `39667548341`, note
`10-2x-toolbar-throttle.md`) made the diagnostic worth shipping. `engine.scroll:unthrottle` is the same element with its style
text generated from Lean and guarded by `@supports (animation-timeline: scroll())`. `throttle-lift` stays the diagnostic.

## Answer

- **The condition is a Lean decision with a theorem per branch (PROVED, CONFIRMED by source).** Mobile Safari holds
  visible-rect updates to 100 ms while the toolbar collapses unless the page reports a main-thread scroll-driven animation;
  an animation of a custom property on the root scroll timeline is one. It lifts only on iOS WebKit with
  `animation-timeline` supported, and changes nothing on Chromium or without that support.
- **Same look (PROVED in the visual model; MEASURED by the gate).** The element paints nothing, takes no layout, no hit and no
  accessibility content (Lean). The breakpoint gate passes on Chromium and Playwright WebKit with the flag, every cell, no
  failing item (run `40068858697`).
- **Its cost (PROVED bound; MEASURED on Chromium and the Simulator).** One element restyled per scroll frame and no layout. Chromium
  counts, 535 swipe frames in each of 3 runs: +1 element restyled in 95.5 %, 98.1 % and 99.1 % of the frames, no extra
  layout, no extra style-recalc event in at least 532 of 535 frames. It also adds 2 compositor layers (one drawing layer)
  in about 530 frames: the bound does not cover this, it is the measured price (below).
- **Phone (felt, one person, preview):** recorded in the toolbar-throttle note and the ledger. A recorded phone session
  is a separate lead step.
- **Preset (item 5):** proposed here; the follow-up task `unthrottle-preset` (section 6) set the row `proved`, ran the trajectory probe and moved the element to `position: absolute` behind `(pointer: coarse)`. Membership in `v2-proved` waits on one cell (WebKit morph).

## 1. The WebKit condition chain (Lean `Fw.Parts.EngineScrollUnthrottle`)

Pinned source: WebKit tag `WebKit-7625.1.29.10.29`, `.cache/upstream/WebKit@862f17d`.

| step | source | Lean |
|---|---|---|
| toolbar collapse under a finger waits 100 ms between visible-rect updates, unless the page reports main-thread scroll-driven animations | `Source/WebKit/UIProcess/API/ios/WKWebViewIOS.mm:3256-3268` (delay constant `:143`) | `throttled i p = i && !p.reported` |
| the web process reports `document->hasProgressBasedScrollDrivenAnimation()` | `Source/WebKit/WebProcess/WebPage/Cocoa/WebPageCocoa.mm:2357` | `Page.reported` |
| true iff a progress-based timeline holds an animation whose effect is not completely accelerated | `Source/WebCore/animation/AnimationTimelinesController.cpp:267-279` | `hasProgressBasedScrollDriven`, `reported_iff` |
| completely accelerated needs properties and all of them accelerated | `Source/WebCore/animation/KeyframeEffect.cpp:1736-1769` | `accState`, `complete_iff` |
| a custom property is never accelerated | `Source/WebCore/style/StyleInterpolation.cpp:256-266` | `custom_not_accelerated`, `liftAnim_not_complete` |

One theorem per branch:

| claim | theorem |
|---|---|
| lifted iff a progress-based, not completely accelerated animation exists (and the timeline is supported) | `reported_iff` |
| with `animation-timeline` supported the element lifts the throttle, whatever else the page has | `lifted_when_supported` |
| without that support the element changes nothing | `no_effect_without_support` |
| no toolbar collapse, no throttle | `no_throttle_when_idle` |
| pages with only compositable or time-based animations stay throttled | `compositable_does_not_lift` |
| Chromium has no such throttle | `chromium_never_throttled` (the engine model; INFERRED from the absence of the handshake) |
| on any engine, supported timeline: not throttled | `lift_effect` |

History of the throttle, from `gh search commits` on WebKit/WebKit (CONFIRMED): bug 307463, commit `de6e12d23e`
(2026-02-25), "up to 2 % power as measured by an iOS browsing power benchmark"; its first attempt `c45540108d` (bug 307463,
2026-02-12) was reverted by `cab43568d0` (bug 307858) because fixed elements froze; bug 315320 fixed the fixed-element flicker
in the throttled path; bug 319523, commit `b07ce30ae0` (2026-07-17), "REGRESSION(308209@main): okaymay.be scroll-driven
animation is jittery", added the exemption this variant uses. The exemption exists because unaccelerated scroll-driven
animations need the update every frame; the throttle is a power saving (up to 2 %), so the variant trades that for smoothness
on pages that already run such an animation. That trade is the cost to name on a battery budget; it is not measured here.

## 2. Same look

Lean (visual model `Fw.Engine.Visual`, element as typed style `flag`):

| claim | theorem |
|---|---|
| the visible scene with the element equals the page's own, for every viewport and scene | `visible_withFlag` |
| any renderer of the visible scene gives the same result; the gate relation Q holds | `render_withFlag`, `Q_withFlag` |
| no in-flow box, no hit target, no accessible content added | `same_layout_hit_a11y` |
| the keyframes animate the custom property only; no style reads it | `flag_animates_custom_only`, `flag_value_unread` |

The element has `position: fixed`, 1 px by 1 px, `opacity: 0`, `pointer-events: none` and `aria-hidden="true"`. The style text
and attributes are generated by Lean (`css`, `attrs`) into `packages/contracts/golden/parts/engine.scroll.unthrottle.jsonl`;
`unthrottle.ts` is checked against it (`unthrottle.test.ts`).

Gate (MEASURED), run `40068858697` at `5fe2545ed`, `fw=engine.scroll:unthrottle`, engines both:

| engine | cells | engine.scroll row | failing items |
|---|---|---|---|
| Chromium 156.0.8078.4 | 14 | pass in 14 of 14 | 0 |
| Playwright WebKit 27.2 | 14 | pass in 12 of 14; 2 `UNREACHABLE 4` (hover-pointer-cross, fractional-gaps: cells this engine port cannot build, Lean reach rule), the same two cells for every part row, an engine-port limit, not this flag | 0 |

On Playwright WebKit the sweep hysteresis reads orig 5/8082 and rewrite 5/8082 items differing on the desktop sweep (equal),
and the margin cells number 1960 with 0 differing computed styles; the failing-items table is empty on both engines.

## 3. Its own cost

Lean bound (`restyled_flag`, `laidOut_flag`, `extraRecalc_le`, `extraRecalc_idle`, `extraRecalc_scroll`): the registered
property does not inherit and no declaration reads it, so a tick restyles exactly one element, lays out nothing, and costs
nothing in a frame where the scroll offset did not move; a run of `n` frames costs at most `n` restyles.

Chromium counts (MEASURED), profile `swipe-v1`, 3 runs on separate VMs, same sha `5fe2545ed`. Arm A is the faithful rewrite
(push run `40068835905`), arm B the flag (dispatch run `40068851412`). Frame by frame over the 535 swipe frames:

| count | run 1 | run 2 | run 3 |
|---|---|---|---|
| frames where elements restyled differ by exactly +1 (`trace.UpdateLayoutTree.elementCount`) | 511 | 525 | 530 |
| sum of the difference over moved frames | +539 | +435 | +617 |
| frames with the same `metric.RecalcStyleCount` | 532 | 534 | 534 |
| `metric.LayoutCount` over the profile, A and B | 378, 378 | 378, 378 | 378, 378 |
| `trace.Paint` over the profile, A minus B | 1 | 1 | -1 |
| frames with +2 `census.layers` (and +1 `census.drawingLayers`) | 530 | 528 | 530 |

The sums exceed 535 in runs 1 and 3: run 1 has 10 frames at +11 against 9 at -9 (other restyles moved by one frame), run 3 one frame at +88. The bound is about the element itself and is matched by the per-frame mode (+1 in 511/525/530 frames); the summed difference is not a check of it.

Reading: the page already recalculates style every frame, so the element adds no recalc event, only one element to each
one (the Lean bound, MEASURED at 0.99 per frame); layout and paint are unchanged. The surprise is the layers: Chromium
composites the fixed 1 px element, 2 layers more in every scroll frame. They are 1 px layers (the drawing area difference is
10 px of 6,333,730), so the raster and memory cost is negligible; the compositor walks two more layers per frame. This is not
in the Lean bound. `position: absolute` would likely avoid the layer, but it is not the element the user tested; it is a
follow-up (a dispatch for it would be a fourth).

WebKit Simulator (MEASURED): the dispatch `40068853873` (`webkit-sim`, target rewrite, `fw=engine.scroll:unthrottle`, iPhone 430x775, 107-step scroll,
2 passes) against four earlier flag-free rewrite runs of the same lane (8 passes: `39897814980`, `39864122924`, `39856782689`,
`39775866606`, at other shas: the push run of this branch was skipped as unchanged, so no same-sha baseline exists). The
lane counts timeline events, not elements, so the "one element" half of the bound cannot be read; the event counts can:

| events over the scroll | flag, pass 1 | flag, pass 2 | 8 baseline passes (min to max) |
|---|---|---|---|
| RecalculateStyles | 676 | 678 | 645 to 693 |
| Layout | 634 | 619 | 604 to 661 |
| Composite | 213 | 211 | 213 (all 8) |
| Paint | 1261 | 1414 | 1224 to 1400 |
| FireAnimationFrame | 679 | 671 | 671 to 681 |
| layers with reason positionFixed, every state | 1 | 1 | 1 |

The flag's counts sit inside the spread of the baseline passes (the slow baseline passes, wall 10 to 19 s, reach 693 style
recalcs), so no extra style or layout event shows. The fixed element gets no layer of its own on WebKit (`positionFixed` is 1
in every state with and without the flag; layer totals 108 to 143 are within the baseline spread of up to 6): the 2 extra layers
are Chromium's. Limit: a one-event effect cannot be told from the lane's noise; this is "no resolvable cost", not "zero".
Pass 1 of the flag run was slow (wall 11.7 s; slow baseline passes of 10 to 19 s exist too).

## 4. The device observation

Written in `10-2x-toolbar-throttle.md` (section "Phone pass") and in the ledger rows `engine.scroll.throttleLift` (updated)
and `engine.scroll.unthrottle` (new). The felt pass is one person, preview, the diagnostic flag. The lead's recorded phone
session of the same day (`results/phone/2026-10-24-throttle-lift/summary.md`, MEASURED on the real iPhone, one person, one
session, landed on main after this task's CI runs) counts the same stepping on the device: at viewport height 775, hero-exit
band runs of 5 to 6 frames are 90 in 1200 exit frames for the faithful rewrite and 2 in 1318 for the diagnostic flag (Lean verdict
`lifted`); the original has 29 and 27. Neither says anything about the shipped text, which differs by `@supports` and the
custom property name: its still runs are not measured on any device.

## 5. Preset proposal

`Fw.Preset.V2Proved.ok` admits a flag iff it is registered `optimized`, its ledger link is `proved`, its trajectory cells
(Chromium and WebKit, hero and morph walks) pass, and it is no look change. State at this commit:

| condition | state |
|---|---|
| registered `optimized` | yes (`part.json` variant `unthrottle`) |
| look class | none declared (the scene proof gives `E`); the generator reads no look change |
| ledger row `proved` | `partly-proved`: the phone pass is felt and the layers are outside the bound |
| trajectory cells | all four pending: no `[ci:trajectory-probe]` run of this flag exists |

Proposal: after a trajectory probe with `fw=engine.scroll:unthrottle` (a push, not a dispatch) and a decision on the 2 extra
layers, set the row to `proved` and regenerate the preset with `Fw.Preset.Gen.run []`. Not done here: the pinned unit says
the preset waits for items 1 to 3 to pass, and the trajectory cells are a push this task did not spend.
`packages/contracts/golden/preset/v2-proved.decisions.jsonl` now lists the flag as registered, not a member.

## Limits and stand-ins

- Phone evidence is one person: a felt preview and one recorded session, both of the diagnostic; the CI Simulator is not the phone.
- Chromium baseline and flag ran at the same sha; the WebKit baseline did not (the push run was skipped as unchanged), see section 3.
- TS stand-ins: `installUnthrottle` (DOM glue, no decision logic). The style text is Lean-generated and golden-checked.
- The 100 ms throttle saves power (up to 2 % on WebKit's benchmark); the variant gives that up while scrolling.
- Sections 1 to 5 describe the first text (`position: fixed`, every device). Section 6 supersedes it: absolute, guarded by `(pointer: coarse)`.

## 6. unthrottle-preset: guard, position, trajectory, lane (task `unthrottle-preset`, branch ci/unthrottle-preset)

The shipped text now is Lean's `css`: the `@property` and `@keyframes` rules, then `@supports (animation-timeline: scroll())` holding
`@media (pointer: coarse)` holding the element rule with `position: absolute` (golden `engine.scroll.unthrottle.jsonl`, 39 lines).

**Guard (PROVED, premise CONFIRMED by source).** An iPhone reports a coarse primary pointer: `WebPageIOS.mm:4243-4246` returns `Coarse`
unless the mouse is primary (Mac Catalyst only, `:4201-4208`); `MediaQueryFeatures.cpp:527-538` reads it; only a site named in
`Quirks.cpp:3194-3203` (disneyplus.com) hides it. Lean `Env`, `Env.valid` (premise), `iphone_valid`: `guard_keeps_ios` (the guarded page
is the unguarded lifted page on iOS), `guard_keeps_ios_throttle`, `guard_lifts_ios` (supported timeline: not throttled), `guard_fine_noop`
and `guard_fine_throttle` (a fine pointer gives the page without the element), `guard_fine_cost` (0 elements restyled), `guard_coarse_cost` (1).
So the iPhone path is unchanged by the guard and a desktop pays nothing. Limit: an iPad with a mouse reports `fine` as primary; the
throttle stays there (it is a power saving; stays INFERRED harmless).

**Position (decision: absolute; PROVED look and condition, MEASURED layers).** Lean `lift_anim_position_free` (the lifting animation
depends on the animated properties only), `same_layout_out_of_flow` (any out-of-flow position adds no in-flow box, hit target or
accessible content), `fixed_same_look`. Chromium counts, dispatch 1 of 3, run `40078781031`, `swipe-v1` x 3, `?fw=engine.scroll:unthrottle`, against
push run `40068835905` (older sha `5fe2545`, the same page apart from this part; no same-sha baseline):

| count over 575 frames | run 1 | run 2 | run 3 |
|---|---|---|---|
| frames with the same `census.layers` (and `census.drawingLayers`) | 575 | 573 | 572 |
| frames with +1 element restyled (`trace.UpdateLayoutTree.elementCount`) | 532 | 514 | 531 |
| frames with the same `metric.RecalcStyleCount` | 575 | 572 | 575 |
| frames with the same `metric.LayoutCount` | 575 | 573 | 571 |

The +2 layers of `position: fixed` are gone; the element is restyled in about 93 % of frames (so the guard is on in the counts' touch
emulation) and nothing else moves. Run 2 shows 9 frames at -9 elements and one frame at -1 layer, +2 layers: other restyles shifted by a frame, as
in the first note.

**Trajectory (MEASURED), push `40078755889` and dispatch 2 of 3 `40080296257`** at `c113d5eca` (inputs read back from artifact `trajectory-inputs`:
`fw=engine.scroll:unthrottle`, `engines=both`, no widths, not diagnostic). Stored with the recorder:

| cell | result |
|---|---|
| Chromium hero | pass (both runs) |
| Chromium morph | pass (both runs) |
| WebKit hero | pass (Linux in both runs, Mac in `40080296257`) |
| WebKit morph | Linux no verdict (the probe cannot decide it); Mac no verdict: coverage |

The Mac morph units that differ are coverage units at width 641 (steps open@4, close@8) and 1280 (open@3), 127 new units against 172 failing in both
arms; widths 390 and 640 are clean. Those are the widths where a desktop Safari reports `pointer: fine`, so the element is inactive
(`guard_fine_noop`): the misses are the probe's, INFERRED (the probe's pointer setting per width was not read). No flag has ever passed this cell
(`v2-proved.decisions.jsonl`: every flag with a Mac morph run carries fail or no verdict: coverage on that cell). So `engine.scroll:unthrottle` is `proved` in the
ledger and stays `pending: trajectory` in the preset; `v2-proved` has no member.

**Toolbar-throttle lane (MEASURED), push run `40078755847`** (Simulator iPhone, viewport height 775 in every usable pass; arms rewrite,
unthrottle, original; job 1 failed on its VM):

| arm | usable passes | exit frames | band runs (5 to 6 frames) | per 1000 |
|---|---|---|---|---|
| rewrite | 1 of 3 (two passes: touch driver failed) | 1600 | 19 | 11.9 |
| original | 4 | 3846 | 15 | 3.9 |
| unthrottle (shipped text) | 4 | 6330 | 0 | 0 |

Lean verdict (`Fw.Device.StillRuns`) for the pooled jobs: `lifted`; job 2 `lifted`; job 3 `no-data` (no usable rewrite pass). Limit: the base
is one pass. Same mechanism as the recorded phone session of the diagnostic (hero band runs 90 to 2 and 28 to 0-1); the shipped text on the phone
is INFERRED from this lane.

**Gate (dispatch 3 of 3).** See the run id in the ledger row `engine.scroll.unthrottle`, field `visual`.

Not measured: the power cost of leaving the 100 ms throttle (WebKit: up to 2 percent), named as open.
