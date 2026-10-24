---
id: 2026-10-2x-commission-band-mech
kind: note
title: "commission-band-mech: the WebKit saving at y 3500-4500 is the follower's exit band; the window is a Lean constant from the measured section rect"
status: draft
created: 2026-10-25
topics: [commission, band-gate, webkit, chromium, lean, layout]
---

Task commission-band-mech, finishing ledger row 48 (`commission.band-gate`). Statuses: PROVED (Lean), CONFIRMED (source or
artifact read), MEASURED (CI), INFERRED.

## Answer

- The WebKit saving at y 3500-4500 (RecalculateStyles 152/154 -> 106/101) is the same mechanism as at y 2500-3500, not noise and
  not a second one. The old claim "the model predicts no moving follower there" was wrong: the model never fixed a scroll window.
  The Chromium window 3070 <= scrollY < 3530 was one phone height (932 px) read off a class-toggle spike, and the follower has
  two bands (enter and exit), not one. At 430x775 the exit band lies at y 3424-3812 (measured section rect, below), which is the
  3500-4500 window. MEASURED, 2 passes per arm agree step for step.
- PROVED (`Fw.Parts.CommissionOptWindow.skip_in_band`): the variant skips the two writes of event k only if one of the last 29
  events (k included) lay inside a band. `quiet_run`: 29 events at one target pair settle both followers (0.78^29 < 8e-4).
- The window is now a Lean-generated constant: `lean/Fw/Parts/CommissionOptLayout.lean` holds the commission section and card rects
  that CI Chromium read at the 124 probes of the breakpoint gate; `CommissionOptWindow.rowBands` turns a row into the four band
  edges; golden `commission-gate.jsonl` (258 lines) carries them and `bandgate.test.ts` replays them through `window.ts` and the
  real driver.
- Behaviour is unchanged (no driver or CSS edit), so the breakpoint gate is unchanged: run 39843552595 stands.

## The model, extended

`CommissionOptWindow` (file `lean/Fw/Parts/CommissionOptWindow.lean`). Scroll positions: `enterFrom/enterTo cardTop vh` =
`cardTop - 0.42 vh` / `cardTop - 0.06 vh`; `exitFrom/exitTo bottom vh` = `bottom - 0.85 vh` / `bottom - 0.35 vh`.

| statement | meaning |
|---|---|
| `enterRaw_above`, `enterRaw_below`, `exitRaw_above`, `exitRaw_below` | one theorem per branch: outside a band the raw value is 1 or 0 (and so the target is constant, `tgtE_above` ...) |
| `tgtE_step`, `tgtX_step` | a monotone scroll step shorter than 0.36 vh with neither end inside the band keeps the target |
| `targets_chain` | the same over any run of events outside both bands |
| `n_contracts`, `r_contracts`, `step_contracts` | one frame closes at least 22 % of the distance to the target |
| `fol_mem`, `frame_mem` | without reduced motion the followers stay in [0, 1] |
| `quiet_run` | 29 events with one target pair: `more` is false at the last one |
| `rest_before` | a page that starts above both bands keeps the followers at their first targets |
| `skip_in_band` | headline: a skipped event has a band event among the last 29 |
| `no_skip_reduced`, `no_skip_ungated` | reduced motion and the wide layout (c1000 off) never skip |

Premises of `skip_in_band` (all decidable on the golden): the scroll is non-decreasing, each step is shorter than 0.36 vh (the
enter band width; 50 px against 279 px at 775, 10 px against 336 px at 932), the page starts above both bands, no reduced motion,
the c1000 gate is on. The bound is an upper bound: the real tail is the time the remaining distance needs to fall under 8e-4,
at most 28 events after the last band event.

## The measured section rect

Source: breakpoint-gate run 39843552595, CI Chromium (Chrome Headless Shell 156.0.8078.4), rewrite arm, `raw.viewFirst.commission`
of each of the 124 probes (the page at the top, so a rect's y is its document top). `results/commission-band-mech/layout.mjs
--extract` reduces the 136 MB artifact to `layout-rows.json`; `--write` generates the Lean table, `--check` compares it.

| probe | vh | compact | card top | section bottom | enter band | exit band |
|---|---|---|---|---|---|---|
| desk-319 | 900 | true | 2915.8 | 4127.5 | 2537.8 to 2861.8 | 3362.5 to 3812.5 |
| desk-400 | 900 | true | 3064.9 | 4267.9 | 2686.9 to 3010.9 | 3502.9 to 3952.9 |
| desk-461 | 900 | true | 3197.0 | 4363.1 | 2819.0 to 3143.0 | 3598.1 to 4048.1 |
| desk-600 | 900 | true | 3429.8 | 4519.1 | 3051.8 to 3375.8 | 3754.1 to 4204.1 |
| desk-641 | 900 | true | 3518.5 | 4348.3 | 3140.5 to 3464.5 | 3583.3 to 4033.3 |
| desk-860 | 900 | true | 3992.5 | 4755.1 | 3614.5 to 3938.5 | 3990.1 to 4440.1 |
| desk-1000 | 900 | true | 5876.0 | 6620.2 | 5498.0 to 5822.0 | 5855.2 to 6305.2 |
| desk-1001 | 900 | false | 5876.0 | 6939.4 | 5498.0 to 5822.0 | 6174.4 to 6624.4 |
| touch-1200 | 900 | true | 4644.9 | 5695.5 | 4266.9 to 4590.9 | 4930.5 to 5380.5 |
| touch-1201 | 900 | false | 5885.2 | 6887.2 | 5507.2 to 5831.2 | 6122.2 to 6572.2 |
| dark-430x932 | 932 | true | 3193.9 | 4396.8 | 2802.4 to 3137.9 | 3604.6 to 4070.6 |
| height-probes-430x775 | 775 | true | 2879.9 | 4082.8 | 2554.4 to 2833.4 | 3424.1 to 3811.6 |

83 of the 124 probes are in the c1000 band (the only place the variant skips); their section heights run 744-1212 px and their
document tops 2880-5876 px. No single scroll window serves all breakpoints, and none serves two phone heights. The windows of
non-compact rows are listed in the golden but the variant never skips there (`no_skip_ungated`).

In-session check of the rect (MEASURED, push 1, runs 40139371262 r1 and r2, profile `commission-rect-v1` = swipe-v1 plus
`cardProbe` on the section and the card, replay pass after the counted pass): at 430x932 the section top is 3193.859375 and its
height 1202.953125 in all 575 frames of both runs, the card equals the section. The gate's first read (3193.859375, 1202.953125)
is the same to the last digit, so a rect read at rest is the rect of the scroll in this layout.

## What the counts show against the model

Chromium (HEAD build, base arm, runs 40139371262 r1 and r2, 10 px per frame, 430x932). The measured rect puts the model's moving
frames at y 2810-3310 (enter band 2802-3138 plus its tail) and y 3620-4220 (exit band 3605-4071 plus its tail). Per frame
RecalcStyleCount and restyled elements in the base arm: 2800 -> 3 / 42, 2810 -> 4 / 74, 2820 -> 5 / 116 (up), back to 3 / 45 at
y 3320 (the model ends at 3310); the second run starts at 3610 (5 / 99, model 3620) and ends at 4120-4130 in the element count.
Edges agree within one 10 px frame. The one-frame lead at 3610 is the snap: the first frame with a target change below 8e-4 writes
the snapped value, which the base arm sees as a changed property and the model does not call "moving".

The older runs (flag 39843560957, base 39837044649, commit 2a74101) saw one contiguous run 2700-3590 and no second run. Their
page was 720 px shorter (maxScroll 4626 against 5346 now); a fit of the same frame model to their 463 frames has zero mismatches
for card top 3076 and section bottom 3768 (search over card top, bottom and viewport height, scratch only), i.e. a different
layout of that commit. That is why the earlier window never showed the exit band: it was one layout's enter tail.

WebKit (iOS Simulator 430x775, 50 px steps, 2 frames per step, 2 passes; base run 39837001915, flag run 39843567401),
RecalculateStyles per step, base against flag, both passes (same per step in both passes):

| y | 2700-3250 | 3600-4200 |
|---|---|---|
| steps | 12 | 13 |
| base per step | 7-10 | 8-10 |
| flag per step | 4-6 (one step at 8) | 4-7 |

Outside these two runs base and flag differ by less than 1.5 per step on the average of the two passes except three isolated steps
(y 200, 300, 900; page top, not the commission). The model with the measured 430x775 rect (golden `scrollTrace`) skips at y 2600-4350: the observed runs lie inside it,
as `skip_in_band` demands. The WebKit page is not the Chromium page: a fit of the model to the 107 WebKit steps (scratch only)
gives card top about 2925 and section height about 1250 against the gate's 2880 and 1203, and a gap at y 3300-3550 that the
upper bound does not show (the real tail is shorter than 28 events). The saving at y 3500-4500 is therefore the exit band, which
starts at y 3424 on the measured rect and at about 3600 on the WebKit page.

## Why a skipped write saves a style recalculation (WebKit source, WebKit-7625.1.29.10.29 @862f17d)

CONFIRMED by reading; the per-frame count of forced flushes is INFERRED (no instrumented run).

- A RecalculateStyles record is one `Document::resolveStyle` that passes its early returns: `InspectorInstrumentation::willRecalculateStyle`
  at `Source/WebCore/dom/Document.cpp:2865`, `didRecalculateStyle` at `:2940`; the timeline agent pushes the record in
  `Source/WebCore/inspector/agents/page/PageTimelineAgent.cpp:237-253` (called from `InspectorInstrumentation.cpp:648-666`).
- `Document::updateStyleIfNeeded` (`Document.cpp:3025-3051`) returns without resolving when `needsStyleRecalc()` is false (`:3005-3023`);
  `Document::updateLayout` calls it first (`:3128`). So every layout read that follows a style-dirtying write adds one record.
- A changed inherited custom property is a style change that reaches the descendants: an inherited custom property lives in the
  inherited rare data (`Source/WebCore/style/computed/StyleComputedStyleBase.cpp:128-133`), a difference there fails
  `nonFastPathInheritedEqual` (`StyleComputedStyle.cpp:296-297`), `determineChanges` adds `Change::Inherited` (`StyleChange.cpp:42-43`),
  and `Change::Inherited` makes the resolver resolve the children (`StyleTreeResolver.cpp:307-308`), recursively.
- The part's body reads the section and card rects first, then writes the two properties, then (compact layout only)
  `measureWrap` calls `lineBoxes` = `Range.getClientRects` (`driver.ts` `body` -> `measureWrap`; `index.tsx` `lineBoxes`), a layout read
  after the writes. With the writes skipped nothing is dirty and the read finds a clean style: one record less per moving frame,
  next to the one of the rendering update itself.
- Chromium 5.02 -> 3.09 recalcs per frame (about 2 fewer) and WebKit 9 -> 6 per two-frame step (1.5 fewer per frame) fit the same
  picture; the difference in the two engines is how many of the flushes fall inside one frame.

## Limits and follow-ups

- Frame times of the scroll-in: Simulator or phone replay, follow-up until sim-touch-timeout lands. Accepted limit.
- Playwright WebKit and the Simulator stand in for Safari.
- The rect table is one gate run at probe heights of 900 px (plus the 775, 815, 932 phone probes); a window at another height
  is the same formulas on the same section rect only if the document above the section does not depend on the height (it does:
  the section top moves by 2 px per px of viewport height at 430 wide, 3194 at 932 against 2880 at 775).
- `window.ts` is used by the test only (the driver needs no window); it is the TS twin of the golden, listed as a stand-in.

## Runs

| run | what |
|---|---|
| 39843552595 | breakpoint-gate, CI Chromium, the 124 rects (source of `layout-rows.json`) |
| 40139371262 | chromium-counts push 1: profile `commission-rect-v1`, rewrite base, 2 runs, in-session rect + counts |
| 40139371309 | lean, push 1 |
| 39837001915, 39843567401 | webkit-sim base and flag, per-step counts re-read |
| 39837044649, 39843560957 | chromium-counts swipe-v1 base and flag, older layout |
