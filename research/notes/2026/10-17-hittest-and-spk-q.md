# HitTest quarantine and SPK-q (N0/N1 on arm A): causes and what the harness does now

Date 2026-10-17. Tasks `hittest` and `spk-q`. Harness: `packages/measure-chromium` (Chromium headless shell 156.0.8078.4,
`HeadlessExperimental.beginFrame`). Source citations are `file:line@f842f52` in the pinned clone
`.cache/upstream/chromium@f842f52/`. Status words: CONFIRMED (source or measurement cited), MEASURED, INFERRED.

## 1. Why `trace.HitTest` was quarantined

| Source of a HitTest slice | Driven by | Frame-locked in the harness? |
|---|---|---|
| Hover recompute in `BeginMainFrame` (`web_frame_widget_impl.cc:3063`) | frame | yes |
| `document.elementFromPoint` and similar, in page rAF | frame | yes |
| Touch events: one hit test per dispatched touch event | the event dispatch | only as far as the touch dispatch is (see 1.3) |
| `OverlayInterstitialAdDetector::MaybeFireDetection` | **wall clock** | **no** |

### 1.1 The wall-clock source (CONFIRMED in source, MEASURED on CI)

`LocalFrameView` calls `EnsureOverlayInterstitialAdDetector().MaybeFireDetection(frame_)` (`local_frame_view.cc:1161`).
The detector skips every call until first contentful paint, then runs at most once per `kFireInterval = base::Seconds(1)`
(`ad_tracker/overlay_interstitial_ad_detector.cc:26`), measured with `base::Time::Now()` against `last_detection_time_`
when `kFrequencyCappingForOverlayPopupDetection` is on (`:84-88`). A run hit-tests the viewport centre
(`HitTestNoLifecycleUpdate`, `:127-138`) inside Commit and emits `OverlayInterstitialAdDetector::MaybeFireDetection`
(`:93`). The harness runs virtual frames, but the 100 ms real-time network barrier per frame makes one second of wall time
about 8-9 frames, and which of two neighbouring frames gets the run follows real time. So the number of HitTest slices per
frame is not a function of virtual time. It is browser-internal work, not page work.

### 1.2 Fix in the harness (extraction, no decision logic)

`src/trace.mjs` counts a `HitTest` slice that lies inside a `MaybeFireDetection` slice under its own type
`trace.HitTest.overlayAdDetector`. `trace.HitTest` keeps the frame-driven rest. The split is containment of complete
events on the main thread. It needs no trace category beyond `blink,benchmark`, which was already on.
Alternative not taken: `--disable-features=FrequencyCappingForOverlayPopupDetection` would run the detector in every
frame and make it deterministic, but it changes browser behaviour (one extra hit test per frame); say so if you want it.

### 1.3 Result on CI (3 jobs on separate VMs per workflow run; classes by `measure.classify`)

| Profile | Type | before (frozen / earlier run) | after (this harness) |
|---|---|---|---|
| swipe-v1, A | `trace.HitTest` | quarantined (116, 0) | **stable (2, 0)** (run 39043025881) |
| swipe-v1, R | `trace.HitTest` | deterministic | deterministic |
| swipe-v1, A (final harness, run 39044815926) | `trace.HitTest` | quarantined (116, 0) | **deterministic (0, 0)**; R deterministic |
| swipe-v1, A | `trace.HitTest.overlayAdDetector` | (inside HitTest) | quarantined (114, 0): inherent, by design |
| swipe-touch-v1, A | `trace.HitTest` | quarantined (185, 23), run 39040473427 | quarantined (81, 13), run 39042903332 |
| swipe-touch-v1, R | `trace.HitTest` | quarantined (25, 1) | quarantined (17, 1) |
| swipe-touch-v1, A / R (final harness, run 39044812879) | `trace.HitTest` | | quarantined (69, 7) / (27, 7); EventDispatch (68, 8) / (27, 7) |

Touch stays quarantined, and it is not the detector. MEASURED: over the three jobs of run 39043999523 (a repeat), HitTest
differs between jobs in 123 frames, EventDispatch in 117 frames, and 116 frames are in both; the per-run total of
`HitTest - EventDispatch` is -20, -21, -21 (constant). In touch, a hit test follows each dispatched touch event, so
`trace.HitTest` inherits the known touchmove k/k+1 race that also quarantines EventDispatch, FunctionCall and PrePaint
(handoff touch-wedge: the race is not fixed). It cannot be stable until that race is. INFERRED: the one-frame shift is
which frame the Input event lands in; not traced further here.

### 1.4 The harness additions did not change the counts (control)

Run 39043990778 (branch `ci/hittest-ctl`, N0 census and the two new categories off) against run 39043999523 (same code as
39042903332, on):

| frames that differ across 3 jobs | EventDispatch | HitTest | FunctionCall | census.layers |
|---|---|---|---|---|
| control (N0 and categories off) | 97 | 101 | 81 | 3 |
| harness as committed | 117 | 123 | 93 | 3 |

The first touch run (39042903332) was noisier (census.layers 18): touch run-to-run noise, since the same code repeated at
census.layers 3. For swipe-v1 the new runs equal or beat the earlier ones on every type (HitTest 116 to 2 frames,
nothing worse). Residual risk: the repeat is 3 jobs, not a class freeze.

## 2. SPK-q: do N0/N1 read 0 on arm A? (PLAN 6.7 N0/N1, line 1553 "SPK-q open (moved to M1)")

### 2.1 N0 (page-side census) is 0, and the census can see (MEASURED)

`src/n0-census.js` wraps the CSSOM write APIs and watches `<style>`/`<link>` nodes; `src/n0.mjs` assigns events to
frames by virtual time. On arm A (original) all 3 jobs of runs 39043025881 (swipe-v1) and 39042903332 (touch): load window
7 events (the 7 sheet nodes added by the parser), **0 events in preroll, in every recorded frame and after**; the sheet
shape hash (7 sheets, 1557 rules, hash `1de9869`) is identical at the start and the end of the profile. R: 0 events,
shape 2 sheets / 5 rules. Positive control (`fixtures/sheet-mutate`, run locally, one short debug run): 4 changes
(insertRule, a new `<style>`, a rule-style `setProperty`, a `<style>` text edit) read as 4 events in 4 frames. So the zero is
real, not a blind census.

### 2.2 N1 (engine-side slices) was never recorded, then read 17 (MEASURED, cause CONFIRMED in the trace)

The slices `StyleEngine::updateActiveStyleSheets` and `scheduleInvalidationsForRuleSets` have categories
`blink,blink_style` (`style_engine.cc:681`, `:2515`) and `InvalidateStyleAndLayoutForFontUpdates` is `blink` only
(`:1351`). The harness traced neither category, so the count would have been 0 for a wrong reason (the positive control
showed it: 0 until the categories were added, 1 per mutating frame after). `TRACE_CATEGORIES` now has `blink_style` and
`blink`.

With the categories on, arm A reads `updateActiveStyleSheets` = **17 in one frame** (frame 164 of swipe-v1, 172 of touch;
identical in all 6 jobs; `scheduleInvalidationsForRuleSets` and font updates 0). It is not a sheet mutation: N0 is 0 in
that frame and the sheet shape hash does not move. All 17 slices are nested in
`IsolatedSVGDocumentHost > Document::FinishedParsing > UpdateLayoutTree > Document::updateActiveStyle`: 17 SVG images
arrive in that frame (25 image requests, `metric.Documents` +34, then -17 about 12-19 frames later when they are
released). Each isolated SVG document runs its own first style-sheet update. R reads 0.

Harness fix (extraction by containment, as for HitTest): a slice inside an `IsolatedSVGDocumentHost` slice is counted as
`trace.N1.svgImageDocument`; `trace.N1.updateActiveStyleSheets` is then 0 on A in W-measure. Verified offline on the
stored trace (0 and 17) and on CI, final harness: run 39044815926, job original r1 reads `updateActiveStyleSheets` 0,
`svgImageDocument` 17, `n0.events` 0; all four N1 types and the three N0 types are deterministic on A and R in both
profiles (runs 39044815926, 39044812879).

### 2.3 Answer

N0 and N1 read 0 on arm A in W-rest and W-measure for Chromium, after separating the SVG-image documents. WebKit: not
touched here (the WebKit side of SPK-q stays open). The earlier "non-zero on arm A is a harness finding" applies:
it was a harness finding (categories missing, then SVG-image documents counted as page sheet updates).

## 3. For the lead: Lean task requests (decision logic stays out of TS)

1. N1 gate rule: the read is `updateActiveStyleSheets - svgImageDocument` per window, i.e. only the slices outside
   isolated SVG documents count; and N0/N1 gate semantics `0 in W-rest and W-measure` as a Lean verdict over the
   per-frame counts (`n0.events`, `trace.N1.*`). The TS side only extracts (containment, frame attribution).
2. Class handling for a type that is quarantined by design (`trace.HitTest.overlayAdDetector`, k about 114): excluded from
   the gate list, or listed as "wall-clock browser work"; and the freeze rule for a type absent on one arm (the detector
   did not appear on R).
3. `classes.frozen.json` still has the old table: freeze needs 3 workflow runs of the final harness per profile
   (`src/freeze.mjs`). Not regenerated here.
