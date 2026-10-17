---
id: 2026-10-17-gate-gaps-fractional
kind: note
title: "Fractional-gap gate cells (600.5, 640.5, 860.5, 1000.5): Chromium reaches them at browser zoom, WebKit never does"
status: draft
created: 2026-10-17
topics: [gate, breakpoints, media-queries, zoom, chromium, webkit, ios, lean, q33]
---

# Fractional-gap gate cells: how to cover them (Q33, fractional half)

## Answer

- **Chromium: reachable, and the harness can reach it on this Mac, headless.** Chromium's media `width` is
  `integer physical px / (DSF x page zoom)`, a double. At browser zoom 200 % and DSF 1, a viewport override of
  `2N+1` DIP gives a media width of exactly `N + 1/2` (600.5, 640.5, 860.5, 1000.5), and neither `(width<=Npx)` nor
  `(width>=N+1px)` matches (MEASURED twice, byte-identical). Real desktop Chrome at 110 %, 125 % or 90 % (on a
  2x screen) lands in the same gaps (MEASURED headless and headed).
- **WebKit: unreachable on every platform.** WebKit's media `width` is an `int` by type (frame layout width is
  `int`, the zoom adjustment returns `int`, iOS rounds the layout width with `std::round`). No zoom, DPR, Split View
  or scrollbar can put it strictly between N and N+1 (CONFIRMED by source; MEASURED with macOS WKWebView
  `pageZoom` and Playwright WebKit at fractional DPR). The real iPhone runs WebKit, so on the phone this cell is
  **physically unreachable**. The device check proves that rounding live; it cannot hit a gap.
- **The Lean probe needs one fix to match what a browser can produce.** `(600.5, dpr 5/4)` is not realizable in
  Chromium: there the media width is `P / dpr` with `P` a whole number, and `600.5 x 1.25 = 750.625`. Use dpr 2 (P = 1201).

## 1. How each engine computes the media `width`

### Chromium (pin chromium@f842f52, tag 156.0.8078.4; the Mac run used Chrome 155.0.8059.85)

| step | source | what |
|---|---|---|
| media value | `third_party/blink/renderer/core/css/media_values.cc:109-114@f842f52` | `CalculateViewportWidth` returns `View()->ViewportSizeForMediaQueries().width()` (double) |
| viewport size | `third_party/blink/renderer/core/frame/local_frame_view.cc:1009-1023@f842f52` | `gfx::SizeF viewport_size(layout_size_); viewport_size.Scale(1 / GetFrame().LayoutZoomFactor())`; no rounding |
| layout size type | `third_party/blink/renderer/core/frame/local_frame_view.h:1217@f842f52` | `gfx::Size layout_size_` (integers, physical px under zoom-for-DSF) |
| zoom factor | `third_party/blink/renderer/core/frame/local_frame.cc:3721-3723@f842f52` (comment) | "LayoutZoomFactor will be the combination of the device scale factor and the zoom percent of the page" |
| compare | `third_party/blink/renderer/core/css/media_query_evaluator.cc:288-309, 688-696@f842f52` | `CompareDoubleValue`: `>=` is `actual >= q - eps`, `<=` is `actual <= q + eps`, `<` and `>` are strict; `eps = LayoutUnit::Epsilon()` |
| epsilon | `third_party/blink/renderer/platform/geometry/layout_unit.h:339, 473@f842f52` | `Epsilon() = 1/kFixedPointDenominator`, `LayoutUnit = FixedPoint<6, int32_t>`, so eps = 1/64 |

So in Chromium the page sees **w = P / z**, with P a whole number of physical px and z = DSF x zoom (CONFIRMED).
For the edges, `(width<=Npx)` holds iff w <= N + 1/64 and `(width>=N+1px)` holds iff w >= N + 1 - 1/64. Neither
holds iff **N + 1/64 < w < N + 1 - 1/64** (CONFIRMED by source). The Lean gap is (N, N+1). The two agree at N + 1/2,
but not in the two slivers of width 1/64 at the ends of the gap (see section 4).

`innerWidth` and `documentElement.clientWidth` are whole numbers (601 at a 600.909 media width) and
`visualViewport.width` is the fractional value (MEASURED, table 2). The harness must not use `innerWidth` to check the
width. It must bisect the media width with the strict form `(width > Xpx)`, which has no epsilon.

### WebKit (pin WebKit@862f17d, WebKit-7625.1.29.10.29 = iOS 27.0 24A434)

| step | source | what |
|---|---|---|
| media value | `Source/WebCore/css/query/MediaQueryFeatures.cpp:716-728@862f17d` | `auto width = view->layoutWidth(); width = Style::adjustForAbsoluteZoom(width, *renderView);` then used as a `LayoutUnit` |
| layout width type | `Source/WebCore/platform/ScrollView.h:238-239@862f17d` | `IntSize layoutSize() const; int layoutWidth() const` |
| zoom adjust | `Source/WebCore/style/values/viewport/StyleZoomPrimitivesInlines.h:36-55@862f17d` | `int adjustForAbsoluteZoom(int value, ...)`: if zoom > 1 then `value++`; `return roundForImpreciseConversion<int>(value / zoomFactor)` |
| int rounding | `Source/WebCore/style/values/primitives/StylePrimitiveNumericTypes+Rounding.h:36-48@862f17d` | integral case: `value += 0.01` then truncate |
| compare | `Source/WebCore/css/query/GenericMediaQueryEvaluator.cpp:38-60, 129-142, 183-192@862f17d` | the query length becomes a `LayoutUnit` and is compared with the (integer) width; no epsilon |
| iOS layout width | `Source/WebCore/page/ViewportConfiguration.cpp:578-587, 598-631@862f17d` | `m_minimumLayoutSize = m_viewLayoutSize / effectiveLayoutSizeScaleFactor()` (float), then `int layoutWidth()` returns `std::round(...)` on every path |
| iOS page zoom input | `Source/WebKit/UIProcess/API/Cocoa/WKWebView.mm:6555-6587@862f17d` | `_setViewScale:` feeds `layoutSizeScaleFactor` into `setViewportConfigurationViewLayoutSize`, which is the rounded path above |
| macOS page zoom input | `Source/WebKit/UIProcess/API/Cocoa/WKWebView.mm:1770-1781@862f17d` | `pageZoom` sets `setPageZoomFactor`; this is the `usedZoom` in the int adjustment above |

So WebKit's media width is **trunc(L/z + 0.01)** for z <= 1 and **trunc((L+1)/z + 0.01)** for z > 1, with L an int.
That is always a whole number (CONFIRMED by source). Example, measured: L = 1201 at z = 2 gives 601, while
`visualViewport.width` is 600.5. That WKWebView exposes Safari's aA "page zoom" as `_viewScale` is INFERRED (the API
name and the code path fit; Safari's own code is not public). Either zoom path ends in an int.

### Real conditions (question 1)

| condition | Chromium (desktop, Android) | WebKit (Safari macOS, every iOS/iPadOS browser) |
|---|---|---|
| browser zoom 110 / 125 / 90 % | reaches the gaps: w = P/(DSF x z); 110 % at 661 DIP gives 600.909 (MEASURED) | whole px (MEASURED, WKWebView pageZoom 1.1, 1.25, 0.9, 2) |
| fractional DSF (Windows 125 %/150 %, Android 2.625) at zoom 100 % | reaches when the window's physical width / DSF is not whole; MEASURED with `--force-device-scale-factor=1.25` (601.6). INFERRED for Windows and Android | n/a (int layout width) |
| CDP DPR override (`setDeviceMetricsOverride` deviceScaleFactor 1.25 or 1.1) | **does not** reach: media width stays the requested whole DIP width (MEASURED 601, 641, 861, 1001) | Playwright DPR 1.25 or 1.1: 601 (MEASURED) |
| pinch zoom (`Emulation.setPageScaleFactor`) | does not change the media width; only `visualViewport.width` changes (MEASURED 601, vv 480.8) | same model, INFERRED |
| iOS Safari aA page zoom, text size | n/a | the layout width is rounded to an int (CONFIRMED source); text size does not change the layout width (INFERRED) |
| iPad Split View / Stage Manager widths | n/a | the int layout width, as above (CONFIRMED by type) |
| scrollbars | the media width is the frame layout size, scrollbar included, in whole physical px; no extra fraction (CONFIRMED, layout_size_) | the media width is the int layout width (CONFIRMED) |

## 2. Measurements on this Mac (each run twice; output identical across runs)

Probe page: a static page that reports `innerWidth`, `visualViewport.width`, `documentElement.clientWidth`,
`devicePixelRatio`, `screen.width`. It finds the exact media width by bisecting `matchMedia('(width > Xpx)')`
(40 steps over [0, 5000]). For each nearby edge N it reports `(width<=N)`, `(width>=N+1)`, `(max-width:N)` and
`(min-width:N+1)`. Chromium: Mac Chrome 155.0.8059.85 via puppeteer-core 25.14.0, a fresh `--user-data-dir` per load.
WebKit: Playwright WebKit 27.2 (playwright-core 1.64.1), and the macOS 27.0.1 system WebKit via a 40-line Swift
`WKWebView` host with `pageZoom` set. Both scripts were scratch files; the mechanism is restated in section 3.
Runs 1 and 2 agreed in every field. The C8 and WKWebView files were byte-identical (`cmp`).

| id | engine, mechanism | media width | innerWidth | vv.width | DPR | gap at N: neither matches |
|---|---|---|---|---|---|---|
| C0 | Chromium headless, override 601, DSF 1 | 601 | 601 | 601 | 1 | no |
| C1 | Chromium headless, override 601 / 641 / 861 / 1001, DSF 1.25 | 601 / 641 / 861 / 1001 | same | same | 1.25 | no |
| C1b | Chromium headless, override 601, DSF 1.1 | 601 | 601 | 601 | 1.1 | no |
| C2 | Chromium headless, override 601, `setPageScaleFactor 1.25` | 601 | 601 | 480.8 | 1 | no |
| C3 | Chromium headless, zoom pref 110 %, window 661 | **600.909** | 601 | 600.909 | 1.1 | **yes (600)** |
| C3b | Chromium headless, zoom pref 125 %, window 751 | **600.8** | 601 | 600.8 | 1.25 | **yes (600)** |
| C3c | Chromium headless, zoom pref 90 %, `--force-device-scale-factor=2`, window 541 | 601.111 | 601 | 601.111 | 1.8 | no (fraction above 601) |
| C4 | Chromium headless, `--force-device-scale-factor=1.25`, window 601 | 601.6 | 602 | 601.6 | 1.25 | no (fraction above 601) |
| C5 | Chromium **headed**, zoom pref 110 %, window 661 (Retina, DSF 2) | **600.909** | 601 | 600.909 | 2.2 | **yes (600)** |
| C6 | Chromium headless, zoom pref 110 %, windows 705 / 947 / 1101 | **640.909 / 860.909 / 1000.909** | 641 / 861 / 1001 | same as media | 1.1 | **yes (640, 860, 1000)** |
| C7 | Chromium headless, zoom pref 110 % + override 661, DSF 1 | **600.909** | 601 | 600.909 | 1.1 | **yes** (zoom pref and the CDP override combine) |
| C8 | Chromium headless, zoom pref **200 %** + override 1201 / 1281 / 1721 / 2001, DSF 1, screen = width | **600.5 / 640.5 / 860.5 / 1000.5** | 600 / 640 / 860 / 1000 | same as media | 2 | **yes, all four**; screen.width = 2N+1, innerHeight = override height / 2 |
| W0, W1 | Playwright WebKit 601, DPR 1 / 1.25 / 1.1 | 601 | 601 | 601 | as set | no |
| WK | macOS WKWebView `pageZoom` 1.1 @661, 1.25 @751, 2 @1201, 0.9 @541, 1.1 @705 / 947 / 1101 | 601, 601, **601**, 601, 641, 861, 1001 | 600 / 600 / 600 / 601 / 640 / 860 / 1000 | 600.909, 600.8, **600.5**, 601.111, 640.909, 860.909, 1000.909 | 2.2 / 2.5 / 4 / 1.8 / 2.2 | **never** |

The legacy forms agree with the range forms in every row (`max-width` = `width<=`, `min-width` = `width>=`).
The earlier gate finding still holds: no emulation of the **DPR** gives a fractional viewport (C1). But **browser
zoom** does, and in Chromium a fresh profile's preferences are enough to set it, in headless mode too.

## 3. Mechanism for the harness (question 2)

**Chromium arm, fractional block (reaches all 4 cells exactly, MEASURED C8):**

1. Launch the block's browser with its own `--user-data-dir` (one per hover/pointer pair, as today). Before launch,
   write `Default/Preferences` containing `{"partition":{"default_zoom_level":{"x": 3.8017840169239308}}}`. The value
   is `log(2)/log(1.2)`, Chrome's zoom level for 200 %. The key `x` is the default partition; that this works is
   MEASURED (C3 to C8). That it is the default-partition key is INFERRED: Chrome's prefs code is not in the pin.
2. `Emulation.setDeviceMetricsOverride { width: 2N+1, height: 2H, deviceScaleFactor: 1, screenWidth: 2N+1,
   screenHeight: 2H, mobile: false }`. The page sees width N + 1/2, height H, DPR 2, `screen.width` 2N+1.
   Device width 2N+1 >= 1201 is on the same side of 500/501 as the Lean value N + 1/2, which `envDeviations`
   already allows.
3. Hover, pointer, reduced motion and scheme go through the existing paths (`--blink-settings`, `setEmulatedMedia`);
   the zoom pref does not touch them (INFERRED; not run with the gate).
4. Width check: bisect `(width > Xpx)` and compare with the requested rational exactly. `innerWidth` is N there.
5. Boxes: Chromium reports `getBoundingClientRect` in CSS px under page zoom, so the A-vs-R box comparison is
   unchanged (INFERRED; measure on the first gate run).

Other Chromium routes and why not: CDP has no browser-zoom command. In devtools-protocol 0.0.1696802 the only
zoom-like commands are `Emulation.setPageScaleFactor` (pinch, C2: no effect on the media width) and the DPR inside
`setDeviceMetricsOverride` (C1: no effect) (CONFIRMED by grep of `browser_protocol.json`). `--force-device-scale-factor`
reaches fractions (C4), but only as `round(W x DSF)/DSF` from the window size, so exact N + 1/2 needs odd DSF tricks.
A headed browser is not needed (C5 = C3).

**WebKit arm: no mechanism exists, because the engine cannot produce the state.** Playwright WebKit has no zoom
API (grep of playwright-core 1.64.1: no `pageZoom` or `ZoomFactor`). It would not help anyway: macOS WKWebView
`pageZoom` and fractional DPR both give whole-px media widths (MEASURED). On the iOS Simulator, Safari's aA zoom and a
WKWebView `_viewScale` both go through `ViewportConfiguration::layoutWidth`, which returns an `int` (CONFIRMED by source). Not
measured in the Simulator: that would need UI automation or a test app, and the source and the macOS measurement already settle it.

## 4. Is the gap reachable at all? (question 3)

| engine | reachable? | evidence | what the gate cell should say |
|---|---|---|---|
| Chromium | **yes**, on real desktops (any zoom that is not 100 %, fractional OS scaling) and in the harness (zoom pref) | source table 1 + C3 to C8 | run the 4 probes at zoom 200 %; Lean check applies (it becomes comparable, not NC) |
| WebKit (Safari macOS, iPhone, iPad) | **no, physically unreachable**: the media width is an int by type | source table 1 + WK, W0, W1 | mark **unreachable**, not NC. Lean `no_gap_ofNat` (`lean/Fw/Site/BreakpointFacts.lean`) already proves that whole-px widths have no gap, so the WebKit cell is fully covered by: the source fact (width in N) + `no_gap_ofNat` + the device proof below |

Two consequences for the Lean model:

- **Realizability.** Chromium only shows w = P/z with P a whole number. The current probe `(half N, dpr 5/4)` has
  `w x dpr = 750.625` (not whole), so no Chromium setup can produce exactly that probe (CONFIRMED by the formula;
  C1 and C4 show the nearby values 601 and 601.6, never 600.5). DPR enters no condition: Lean already proves it
  (`MQ.eval_indep_height_dpr`, `lean/Fw/Site/BreakpointFacts.lean:386-393`, CONFIRMED). So moving the 4 probes to
  dpr 2 changes no expected vector. Add a theorem stating that `w x dpr` is whole for every matrix probe.
- **Chromium's 1/64 slack.** For w in (N, N + 1/64] Chromium says `(width<=N)` holds, and for w in [N+1-1/64, N+1)
  it says `(width>=N+1)` holds. Lean `gap_iff` says neither, so Lean and Chromium disagree in those two slivers
  (CONFIRMED by source, `media_query_evaluator.cc:294-299`). The probes at N + 1/2 avoid them. If the Lean model is
  meant to match Chromium for every rational width, add the 1/64 slack to `LeNat`/`GeNat` for the Chromium
  instance, or limit the agreement theorem to widths at least 1/64 from an edge. A real Chromium viewport can land
  in a sliver, for example z = 1.925 (175 % OS scaling x 110 %) at N ≡ 27 (mod 40). None of our N (600, 640, 860,
  1000) does that (INFERRED by arithmetic).

## 5. Device proof (real iPhone, iOS 27.0.1, one session)

The goal is to show the WebKit rounding live on the phone, and that it holds on 27.0.1 (the pin is 27.0).
1. Serve the probe page from the Mac on the local network; do not commit the address. The page measures on load and on
   every `resize` / `visualViewport` resize, and POSTs one JSON line (media width by bisection, innerWidth,
   vv.width, clientWidth, DPR, the four gap results) to the Mac's log.
2. In Safari: portrait, then landscape. In each, step through every aA page-zoom level (50 % to 300 %). That is
   about 2 x 11 records.
3. Optional, same session: Settings > Accessibility > larger text, one record (text size must not change the media width).
4. Compare with the same page in the Simulator fw-iphone-27 (with `sh scripts/sim-lock.sh acquire <name>` /
   `release`), same zoom levels by hand: the integers must match level for level if the screen sizes match;
   otherwise they only have to be integers.

**Pass:** every record's media width is a whole number, and no record has "neither" true for any N.
**Informative, not required:** at least one record has a media width that differs from
`round(screen width / zoom)` or a non-whole `visualViewport.width`. That shows a fractional value existed and was
rounded. **Fail:** any non-whole media width. Then the WebKit cell becomes reachable on the device and the 27.0
source citation no longer covers 27.0.1.

## What this changes in the plan

- **PLAN 6.6 (breakpoint parity gate), "fractional gaps" row:** split by engine. Chromium: run the 4 probes under
  browser zoom 200 % (profile `default_zoom_level`, override width 2N+1, height 2H, DSF 1, width checked by
  `(width > X)` bisection), and run the Lean check (no longer NC). WebKit: the cell is **unreachable** (an int media
  width), backed by WebKit source, `no_gap_ofNat`, and the iPhone record from section 5. It is not NC and needs no
  harness change.
- **Lean (`lean/Fw/Site/BreakpointMatrix.lean`, `fractionalGaps`):** change the probe DPR from 5/4 to 2, and add a
  realizability theorem (`w x dpr` whole for every probe). Optionally add the Chromium 1/64 slack note or lemma to
  `BreakpointFacts.gap_iff`'s docstring.
- **`packages/gate-breakpoints`:** a `zoom` field on fractional probes (engines.mjs writes the Preferences file
  before launch), and media-width bisection in `page.mjs`. `verdict.mjs` needs an `unreachable` cell status (or a
  reason on NC) that the Lean verdict spec defines first. That is a Lean decision, not glue.
- **Q33 device session:** add the section 5 records for the fractional cells. The hover x pointer half is a separate note.
