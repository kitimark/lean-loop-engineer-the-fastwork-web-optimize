---
id: 2026-10-17-gate-gaps-hover-pointer
kind: note
title: "Gate gaps (Q33): the WebKit hover x pointer cross cells are unreachable on every Apple WebKit, by source and by Simulator measurement"
status: draft
created: 2026-10-17
topics: [breakpoint-gate, webkit, ios-simulator, media-queries, hover, pointer, q33]
---

Question (work-graph task gap-research, hover half of Q33): the breakpoint gate's 4 WebKit `hover-pointer-cross`
probes (1024x768 and 1200x900, each with (none, fine) and (hover, coarse)) are NC because Playwright's `hasTouch`
flips hover and pointer together. Can a Simulator or a real Apple device reach those cells, and if not, what is the
right gate state?

## Answer

- **No Apple WebKit can produce (hover: none)+(pointer: fine) or (hover: hover)+(pointer: coarse) for our page.** On
  every Cocoa port the primary `hover` and `pointer` come from one boolean: iOS, iPadOS and visionOS hard-code "the
  primary device is not a mouse", and macOS hard-codes "hover, fine". CONFIRMED (source below) and MEASURED (iPhone and
  iPad Simulator, macOS system WKWebView, Playwright WebKit; every claim measured at least twice).
- A connected mouse or trackpad (emulated in the Simulator) changes only `any-hover` and `any-pointer`; the primary
  pair stays (none, coarse). MEASURED. The site uses no `any-*` query (grep of `snapshot/site` CSS and JS: only
  `(hover: hover)`, `(hover: none)` and `(hover: none) and (pointer: coarse) and (width<=1200px)`), so `any-*` is not a
  gate input. CONFIRMED.
- The two site-specific quirks that bend these features apply only to `disneyplus.com` and `play.hbomax.com`, so not
  to our page. CONFIRMED.
- **Right gate state:** the 4 WebKit cross cells should read `unreachable on WebKit` (a proved fact about the engine),
  not NC. They stay covered in Chromium, where all four pairs are built (`--blink-settings`) and pass.
  Recommendation: say this in a Lean statement, and confirm it once on the real iPhone in the planned Simulator/device session
  (see "Device proof").

## 1. How WebKit computes the four features (source, WebKit@862f17d = iOS 27.0 24A434 pin)

| feature | WebCore (`Source/WebCore/css/query/MediaQueryFeatures.cpp`) | status |
|---|---|---|
| `hover` | `hoverSupportedByPrimaryPointingDevice()` ? hover : none; forced to hover by the quirk `shouldSupportHoverMediaQueries()` (:439-453) | CONFIRMED |
| `pointer` | `pointerCharacteristicsOfPrimaryPointingDevice()`: fine if Fine, coarse if Coarse unless quirk `shouldHideCoarsePointerCharacteristics()`, none if neither (:521-541) | CONFIRMED |
| `any-hover` | `hoverSupportedByAnyAvailablePointingDevice()`, same hover quirk (:227-242) | CONFIRMED |
| `any-pointer` | `pointerCharacteristicsOfAllAvailablePointingDevices()`: fine and/or coarse, none if empty (:244-264) | CONFIRMED |

The four calls go `ChromeClient` (`Source/WebCore/page/ChromeClient.h:278-281`) → `WebChromeClient`
(`Source/WebKit/WebProcess/WebCoreSupport/WebChromeClient.cpp:677-700`) → the per-platform `WebPage` file:

| port | primary (hover, pointer) | any-hover / any-pointer | source | status |
|---|---|---|---|---|
| iOS, iPadOS, visionOS (`PLATFORM(IOS_FAMILY)`, not Catalyst) | `isMousePrimaryPointingDevice()` is the compile-time constant `false` → **(none, coarse)**, always | any-hover = hover iff a mouse is connected; any-pointer = coarse, plus fine iff a mouse **or a stylus (Pencil)** is present | `Source/WebKit/WebProcess/WebPage/ios/WebPageIOS.mm:4201-4255` | CONFIRMED |
| Mac Catalyst | same function returns `true` → (hover, fine) | hover / fine | same file :4201-4207 | CONFIRMED |
| macOS (Safari, WKWebView) | constant **(hover, fine)** | constant hover / fine | `Source/WebKit/WebProcess/WebPage/mac/WebPageMac.mm:762-780` | CONFIRMED |
| GTK/WPE (for contrast) | from `primaryPointingDevice()` (mouse or touchscreen); still one value drives both | from `availableInputDevices()` | `Source/WebKit/WebProcess/WebPage/glib/WebPageGLib.cpp:229-258` | CONFIRMED |
| Playwright WebKit 27.2 (mac build) | patched: `!screenHasTouchDevice()` for hover, Coarse if touch else Fine for pointer, so `hasTouch` flips both | the same bit for any-* (any-pointer becomes coarse **only**) | playwright `browser_patches/webkit/patches/bootstrap.diff:19155-19197` @ cfe490d (tag v1.64.1, WebKit base 56453fd) | CONFIRMED |

Where the iOS "mouse connected" and "stylus" bits come from:
- Mouse: UI process `WKMouseDeviceObserver` counts `GCMouse.mice()` on `GCMouseDidConnect/Disconnect` (GameController)
  (`Source/WebKit/UIProcess/WKMouseDeviceObserver.swift:67-90`), sends `WebProcess::SetHasMouseDevice` to every web
  process (`Source/WebKit/UIProcess/WebProcessProxy.cpp:1859-1864`), and seeds new processes
  (`Source/WebKit/UIProcess/Cocoa/WebProcessPoolCocoa.mm:519`). Compiled only under `HAVE(MOUSE_DEVICE_OBSERVATION)` =
  `PLATFORM(IOS) || PLATFORM(VISION)` (`Source/WTF/wtf/PlatformHave.h:547-549`). CONFIRMED.
- Stylus: `UIScribbleInteraction.isPencilInputExpected` (`Source/WebKit/UIProcess/ios/WKStylusDeviceObserver.mm:56,86`),
  under `HAVE(STYLUS_DEVICE_OBSERVATION)` (`PlatformHave.h:742-744`). CONFIRMED.
- Neither enters the primary pair: `hoverSupportedByPrimaryPointingDevice` and `pointerCharacteristicsOfPrimaryPointingDevice`
  read only `isMousePrimaryPointingDevice()` (`WebPageIOS.mm:4233-4246`). CONFIRMED.

Overrides that exist, and why none reaches the cross cells:

| mechanism | effect | reach for our page | status |
|---|---|---|---|
| quirk `ShouldSupportHoverMediaQueriesQuirk` | hover and any-hover forced to `hover` → (hover, coarse) on iOS | only `play.hbomax.com`, and only with `ENABLE(DESKTOP_CONTENT_MODE_QUIRKS)` (`Source/WebCore/page/Quirks.cpp:2825-2834, 3574-3578`) | CONFIRMED |
| quirk `ShouldHideCoarsePointerCharacteristicsQuirk` | pointer drops coarse → (none, none) on iOS | only `disneyplus.com` (`Quirks.cpp:2263-2272, 3194-3201`) | CONFIRMED |
| Web Inspector `Page.overrideUserPreference` | prefers-reduced-motion, prefers-contrast, prefers-color-scheme only | no hover/pointer (`Source/JavaScriptCore/inspector/protocol/Page.json:36-40` @862f17d, fetched with curl) | CONFIRMED |
| `WKMouseDeviceObserver._setHasMouseDevice(forTesting:)` | any-* only | test SPI, not reachable from Safari; primary unchanged anyway (`WKMouseDeviceObserver.swift:110`) | CONFIRMED |
| Safari "Request Desktop Website" (iPad default) | user agent says Macintosh | does not touch the media features: the iPad Simulator sends a Mac UA and still reports (none, coarse) | MEASURED |

## 2. What each environment reports (MEASURED unless marked)

Static probe page (15 `matchMedia` queries: the 5 primary values, the 5 any-* values, the 4 hover x pointer
combinations and the site's touch arm), served on 127.0.0.1, which reports back with a POST. Simulator runs used
`scripts/sim-lock.sh` (owner gap-research-hover), fresh Safari launch per load and `simctl openurl`. Runs on
2026-10-17, Xcode 27.1, iOS 27.0 (24A434) runtime, Playwright WebKit 27.2, macOS 27.0.1.

| environment | loads | hover | pointer | any-hover | any-pointer | (none, fine) | (hover, coarse) | touch arm at its width |
|---|---|---|---|---|---|---|---|---|
| iPhone Simulator (fw-iphone-27, 430x932 DPR 3), Safari | 2 | none | coarse | none | coarse | false | false | true (430) |
| iPad Pro 13-inch (M5) Simulator, iOS 27.0, Safari (Mac UA, 1032 wide) | 2+ | none | coarse | none | coarse | false | false | true (1032) |
| same iPad + emulated mouse **and** pointer HID service | 2 | none | coarse | **hover** | **fine, coarse** | false | false | true |
| same iPad + pointer service only | 2 | none | coarse | hover | fine, coarse | false | false | true |
| same iPad + mouse service only | 2 | none | coarse | hover | fine, coarse | false | false | true |
| same iPad after removing both services | 2 | none | coarse | none | coarse | false | false | true |
| iPhone Simulator + emulated mouse service | 2 | none | coarse | hover | fine, coarse | false | false | true |
| macOS system WKWebView (same WebKit as macOS Safari), 1200x900 | 2 | hover | fine | hover | fine | false | false | false |
| Playwright WebKit 27.2, default context, 1200x900 | 2 | hover | fine | hover | fine | false | false | false |
| Playwright WebKit, `hasTouch` (with or without `isMobile`) | 2+2 | none | coarse | none | coarse (only) | false | false | true |
| real iPhone (iOS 27.0.1): INFERRED from the 27.0 source (27.0.1 build not pinned) | not run | none | coarse | none (hover with a mouse) | coarse (+ fine with mouse) | false | false | true |
| real iPad with trackpad or Pencil: INFERRED (source + Simulator) | not run | none | coarse | hover (trackpad) | fine, coarse | false | false | true at <= 1200 |
| macOS Safari.app: INFERRED, same `WebPageMac.mm` as the WKWebView row (not opened, to leave the user's browser alone) | not run | hover | fine | hover | fine | false | false | false |

How the emulated mouse was made: Xcode 27.1 ships no Simulator.app (MEASURED: not in `Xcode.app/Contents/Applications`,
`open -Ra Simulator` fails), so the GUI's "send pointer to device" capture was not available. Instead a 40-line
Objective-C tool sends `IndigoHIDMessageToCreateMouseService` / `...CreatePointerService` (exported by
`Xcode.app/Contents/SharedFrameworks/SimulatorKit.framework`, `nm -gU`) through
`_TtC12SimulatorKit24SimDeviceLegacyHIDClient -initWithDevice:error:` and
`-sendWithMessage:freeWhenDone:completionQueue:completion:` (private SPI, the path Simulator.app's own pointer
capture uses: INFERRED from the symbol names). Either service makes iOS report a `GCMouse`, which is the path the source
predicts. MEASURED (table rows 3 to 7). Tool kept out of the repo (scratch only); rebuild it from this description if needed.

Reachable gate combinations, per environment:

| (hover, pointer) | Chromium (blink settings) | Playwright WebKit | iOS/iPadOS Simulator or device | macOS Safari |
|---|---|---|---|---|
| (hover, fine) | yes | yes (default) | no | yes |
| (none, coarse) | yes | yes (`hasTouch`) | yes (always) | no |
| (none, fine) | yes | **no** | **no** | **no** |
| (hover, coarse) | yes | **no** | **no** (only via the hbomax quirk) | **no** |

## 3. Combinations that exist on no Apple WebKit

(none, fine) and (hover, coarse) are unreachable on every Apple WebKit for any non-quirked origin. Evidence:
`WebPageIOS.mm:4233-4246` and `WebPageMac.mm:762-780` derive both primary features from one constant, so the
pair is a function of the platform alone (CONFIRMED). The measurements above agree on both iOS form factors with and
without a pointer (MEASURED). On WebKit the site's touch arm `(hover: none) and (pointer: coarse)` is therefore
equivalent to `(hover: none)` alone and to `(pointer: coarse)` alone (INFERRED, follows from the table).

So the gate state for the 4 WebKit `hover-pointer-cross` probes should be **unreachable on WebKit**, not NC: NC
means "we could not build it"; here the environment cannot exist on that engine. The Lean check and A=R for these 4
probes stay with Chromium (passing today).

## Device proof (one phone session, reuses the Simulator check)

1. Serve the probe page from the Mac (same 15 queries; the page shows its JSON on screen and POSTs it) and open it in
   Safari on the iPhone twice (fresh tab each time), or read it through the measure-webkit device lane
   (Inspector via ios_webkit_debug_proxy).
2. Compare field by field with the Simulator record for fw-iphone-27 (rows 1 above): hover none, pointer coarse,
   any-hover none, any-pointer coarse, both cross combinations false, touch arm true.
3. Optional, if a Bluetooth mouse or trackpad is at hand: connect it, reload twice; expect only any-hover → hover
   and any-pointer → fine+coarse, primary pair unchanged.
4. Pass rule: all 15 booleans equal to the Simulator's in both loads (and, for step 3, equal to the "+ mouse" row).
   Any primary-pair difference falsifies this note and reopens the 4 cells as NC.

## What this changes in the plan

| section | change |
|---|---|
| §6.6 gate status table, "Not reachable" | split: "WebKit hover x pointer cross: unreachable on WebKit (every Apple WebKit derives hover and pointer from one constant; this note), covered in Chromium"; fractional gaps stay a separate item |
| §6.6 / `packages/gate-breakpoints` verdict | add a cell state `unreachable` (distinct from `not-comparable`) for probes whose env is outside the engine's reachable set; Lean first: a `Fw/Site` definition `webkitPrimaryPairs = {(hover, fine), (none, coarse)}`, a theorem that the cross block's probes are exactly the matrix probes outside it, and the verdict rule extended in Lean before `verdict.mjs` changes |
| §12.1 Q33 | answered for the hover half: no Simulator or device can build these cells; the device session runs the 2-load probe only to confirm the iOS 27.0.1 build matches the 27.0 source |
| PLAN Simulator check (§6.6, §9 fidelity) | add the probe page (2 loads) to the one Simulator check and the phone session; no pointer-capture lane is needed because the site uses no any-* query |
