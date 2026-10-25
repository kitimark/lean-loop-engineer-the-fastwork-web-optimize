---
id: 2026-10-2x-toolbar-proof-morph
kind: note
title: "Toolbar-proof morph: one decision per touch gesture (touch-first, open-once) proved in Lean and filed as look-change proposals until touch same look is shown; the cost of unthrottle, the lvh read and threaded visuals decided from source; the Simulator lane and WKTR gate split to toolbar-sim-lane and toolbar-wktr-gate"
status: review
created: 2026-10-25
topics: [morph, morph.mount, toolbar, webkit, throttle, unthrottle, touch, look-change]
---

# Toolbar-proof morph

Task `toolbar-proof-morph`, started before `push-cycle-lag` landed (user, 2026-10-25), so none of its findings are inputs.
Base facts and the checked corrections: `10-25-toolbar-native.md`. WebKit cites are `file:line@862f17d`.

## Answer

| Candidate | Built | Verdict | Evidence |
|---|---|---|---|
| (e) decide on the first touchmove | flag `morph.mount:touch-first` (proposal, L) | proved; look-change proposal (L), same look under touch unproven until toolbar-sim-lane runs (touch-first differs when a drag enters the armed zone after its first move); wheel and pointer paths unchanged: **trade, no count yet** | Lean `first_same_first_move`, `native_no_start`, `take_le_orig`, `active_taken`; run 40213443051 |
| (a) one push opens once | flag `morph.mount:open-once` (proposal, L) | proved bound per gesture; same look under touch unproven until toolbar-sim-lane runs; the cause of the 8-41 reopens is not traced: **no count yet** | Lean `once_at_most_one`, `orig_reopens`; run 40214808662 |
| (f) unthrottle's own cost | Lean model only | **trade**: six times the forced layouts and viewport-unit invalidations of the throttled cadence; the measured per-frame cost is not delivered | Lean `unthrottle_costs_six_fold` |
| (b) toolbar-independent geometry | none | **no-win** (premise "arm decision equal for h and h+toolbar" refuted, ledger mount.touch-first note): the arm decision differs for a platform bottom in the 40 px band, and with unthrottle nothing is stale | Lean `armed_differs_in_band`, `armed_same_outside_band` |
| (c) threaded visuals | none new (`MorphPanelThreaded`, `platform` fade exist) | **undecided (INFERRED)**: threaded visuals draw every frame but clamp to the last committed scroll range (RemoteProgressBasedTimeline.cpp:52-77@862f17d); no count; needs the Simulator lane with morph.panel:threaded (toolbar-sim-lane) | Lean `threaded_does_not_lift`, `morph_props_not_accelerated` (definitional, not a verdict) |
| (g) `overscroll-behavior-y: none` while armed | flag `morph.mount:overscroll-lock`, look-change class | built for the user's visual review; never in a preset | Lean `lock_*`; `look-change.candidates.jsonl` |
| (d) scroll inside a container | not built | not delivered: it restructures the page scroll every part reads (scrollY, rects, IO roots) and needs its own task | open |

## (e) and (a): the gesture rule

`touch-first` and `open-once` replace the per-move rule `takes active delta geom` by a per-gesture machine
(`fresh | native | pushing | spent`, `Fw.Parts.MorphMountToolbar.step`). A `touchstart` resets it.

- `touch-first`: the first move of a gesture decides. Taken, the gesture is `pushing` (as the original). Not taken, or
  not cancelable, the gesture is `native` and no later move starts a push (`native_no_start`). A listener attached
  mid-gesture sees no `touchstart`, so it starts `native` (conservative: `take_le_orig`). An active morph keeps every push
  (`active_taken`).
- `open-once`: in `pushing`, an idle move closes the gesture to `spent`; no later move of it opens (`once_no_open`,
  `once_at_most_one`). The original opens on every forward move of an idle armed page (`orig_reopens`).
- Same look: equal to the original on the first move when it is cancelable (`first_same_first_move`). Not equal when a
  drag crosses into the armed zone after its first move: the handover moves to the next gesture (stated in the part's
  `limit`). Wheel input is untouched.
- WebKit premise (CONFIRMED): the first touchmove is cancelable because the native pan waits for it
  (`WKContentViewInteraction.mm:1368`, `:2562`); after the pan began, `preventDefault` no longer stops it (`:4239-4245`).
  That the page sees `cancelable === false` after the pan began is INFERRED.
- Golden `packages/contracts/golden/parts/morph-mount-toolbar.jsonl` (225 rows) replayed by
  `apps/site/src/parts/morph.mount/gesture.test.ts`.

## (f): what unthrottle costs

A layout-viewport height change forces layout and invalidates every viewport-unit element, `vh` included
(`LocalFrameView.cpp:1956-1957`, `StyleScope.cpp:779-784`). The throttle gives one update per 100 ms, unthrottle one per
frame: 6 against 36 in a 600 ms toolbar change at 60 Hz (Lean `unthrottle_costs_six_fold`). A measured Layout and
RecalcStyle count per frame needs the Simulator lane with `engine.scroll:unthrottle` against the default; the lane's arm
list is outside this task's writes.

## (b), (c): decided without a flag

- (b) For a platform of height `h` and bottom `b`, the arm test for the viewport `vh` and `vh + t` agrees outside the band
  `(vh + 8, vh + t + 8]` when the fill test agrees (`armed_same_outside_band`) and differs inside it
  (`armed_differs_in_band`: height 450, bottom 845, `vh` 800 against 840). A read that ignores the toolbar cannot
  reproduce the original decision there. With `engine.scroll:unthrottle` no read is stale (check of the first research).
- (c) Only a main-thread progress-based scroll-driven animation lifts the wait (`liftsThrottle`). The existing threaded
  panel and platform-fade flags keep their own verdicts.

## Reproduction lanes

- (a) Simulator XCUITest (`toolbar-throttle.yml`): not built in this task; owned by follow-up task toolbar-sim-lane (arms default,
  `morph.mount:touch-first`, `morph.mount:open-once`, `engine.scroll:unthrottle`, `morph.panel:threaded`; per-arm counts and the 10 Hz
  `visualViewport.height` step count). Until it runs, (e), (a) have no felt count and (f) is a model.
- (b), (f): decided from source and the Lean model, as stated in the table; (f) cost is a model until toolbar-sim-lane measures it.
- (c1) WKTR forced inset: not built in this task: writes exclude packages/measure-wktr; hook presence
  (beginInteractiveObscuredInsetsChange/setObscuredInsets, `ui-helper.js:2018-2050`, `UIScriptControllerIOS.mm:1486-1494`) in r324039
  INFERRED (no archive symbol check done); follow-up task toolbar-wktr-gate.
- Same-look check delivered: trajectory probe `fw=morph.mount:touch-first` widths 390,1280, both engines, run 40213443051:
  Chromium 0 new fails and 44 undecided open@1 units (every mount flag has them), Playwright WebKit 2000 of 2000 units pass.
  Same for `morph.mount:open-once`, run 40214808662: Chromium 0 new, 44 undecided; WebKit 2000 of 2000.
  It drives wheel and pointer scroll, so it shows the wheel path is unchanged, not the touch rule.

## Limits

Simulator stands in for the iPhone; felt smoothness is the user's step. `overscroll-lock` and any container-scroll variant
stay out of every preset until the user has looked at them. `touch-first` and `open-once` are filed as look-change proposals (L) in
`look-change.candidates.jsonl` until a touch-driven same-look check exists.
