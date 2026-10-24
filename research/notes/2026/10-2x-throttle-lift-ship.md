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
- **Its cost (PROVED bound; MEASURED on Chromium; WEBKIT_ROW).** One element restyled per scroll frame and no layout. Chromium
  counts, 535 swipe frames in each of 3 runs: +1 element restyled in 95.5 %, 98.1 % and 99.1 % of the frames, no extra
  layout, no extra style-recalc event in at least 532 of 535 frames. It also adds 2 compositor layers (one drawing layer)
  in about 530 frames: the bound does not cover this, it is the measured price (below).
- **Phone (felt, one person, preview):** recorded in the toolbar-throttle note and the ledger. A recorded phone session
  is a separate lead step.
- **Preset (item 5):** proposed, not a member: the generator needs trajectory cells and a `proved` ledger row; see the end.

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

Reading: the page already recalculates style every frame, so the element adds no recalc event, only one element to each
one (the Lean bound, MEASURED at 0.99 per frame); layout and paint are unchanged. The surprise is the layers: Chromium
composites the fixed 1 px element, 2 layers more in every scroll frame. They are 1 px layers (the drawing area difference is
10 px of 6,333,730), so the raster and memory cost is negligible; the compositor walks two more layers per frame. This is not
in the Lean bound. `position: absolute` would likely avoid the layer, but it is not the element the user tested; it is a
follow-up (a dispatch for it would be a fourth).

WebKit Simulator (MEASURED): WEBKIT_BLOCK

## 4. The device observation

Written in `10-2x-toolbar-throttle.md` (section "Phone pass") and in the ledger rows `engine.scroll.throttleLift` (updated)
and `engine.scroll.unthrottle` (new). Felt, one person, preview, the diagnostic flag; it says nothing about the shipped
text, which differs by `@supports` and the custom property name.

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

- Phone evidence is one person's felt preview of the diagnostic; the CI Simulator is not the phone.
- Chromium baseline and flag ran at the same sha; the WebKit baseline did not (the push run was skipped as unchanged), see section 3.
- TS stand-ins: `installUnthrottle` (DOM glue, no decision logic). The style text is Lean-generated and golden-checked.
- The 100 ms throttle saves power (up to 2 % on WebKit's benchmark); the variant gives that up while scrolling.
- `unthrottle` applies on every device, also desktop, where the element adds one restyled element per frame for no gain
  (Chromium: no throttle). A `(pointer: coarse)` guard is a follow-up.
