---
id: 2026-10-20-webkit-lag-source
kind: note
title: "Why the hero exit and the end-of-page morph lag in Safari (WebKit, Mac and iPhone): per-frame cost paths from source"
status: review
created: 2026-10-20
topics: [webkit, safari, ios, macos, compositing, filters, backdrop-filter, images, wheel, hero.exit, morph.tween, nav, cost-model, lean]
---

# Why the hero exit and the end-of-page morph lag in Safari

This note uses source and docs only. Nothing here is measured on a device; webkit-lag-probe measures.

## Answer

- **Hero exit (region A).** JS writes `--exit-opacity` and `--exit-scatter` on `.hero` once per scroll frame. WebKit never runs a custom property in the UI process. Each frame then costs a restyle of the readers, a layout (the blur outsets change), a **full repaint of the `.copy` and `.cue` layers** (a Layout diff marks the layer for full repaint), a new CA filter radius, and a render-server re-blur at up to 18px.
  - Predicted dominant cost, Mac: the per-frame repaint plus re-blur of the copy group, and the copy trailing the async-scrolled sticky hero by one or more commits (INFERRED).
  - Predicted dominant cost, iPhone (≤600px): `.copy` and the deck have `filter: none`. What remains is main-thread rendering-update latency per delivered scroll position plus the cue repaint and blur (INFERRED).
- **End of page (region B).** A 680 ms rAF tween writes `--morph`, which drives `top`, `width` and `height` of the fixed nav. Each frame then lays out from the view root and fully repaints every resized backed layer: the nav, the panel and the 5 (desktop) or 3 (phone) image tracks. At the end state that is about 4.6 + 4.6 + 8.5 ≈ 17.7 Mpx per frame on a 2x Mac and at most about 10.4 Mpx on a 3x iPhone (areas INFERRED from CSS; the iPhone tracks are tiled, so their share is an upper bound). Four blurs change radius every frame: the panel `filter`, the platform `filter`, the earn button `filter` (first 20%) and the nav `backdrop-filter`.
  - Predicted dominant cost: the resize repaints (raster in the GPU process), plus view-root layout; render-server blur and backdrop work come second (INFERRED).
  - Per transition: at morph start about 80 countdown faces and the 5 or 3 tracks regain `will-change` and become new layers, and the column images get their first decodes (INFERRED from CSS and the decode path below).
  - Mac input: a **mouse wheel** scrolls synchronously on the main thread while the non-passive `wheel` listener is armed, so each long frame shows as scroll stutter. A **trackpad** gesture turns async after its first event (≤ 50 ms wait) unless that first event is default-prevented (CONFIRMED). A trackpad gesture that starts before the armed band cannot be stopped later, so `pin()` fights the async scroll on Mac as it does on iPhone (CONFIRMED path; visible effect INFERRED).
- **Images.** No WebKit-side cache of a scaled image exists: each repaint of a track re-draws each 1282px image scaled from its full decoded bitmap (CONFIRMED). The cards (region A) only recomposite, so their images are not redrawn (CONFIRMED path). The panel blur and the nav backdrop act on rasterized layers, not on the images (INFERRED, closed source).
- **Is Safari "unoptimized" here?** Partly. CSS and WAAPI animations of `filter`, `opacity` and `transform` get the CA animation path; custom properties never do. Threaded time-based animations are a preview preference, off by default. [Bug 228312](https://bugs.webkit.org/show_bug.cgi?id=228312) (blur cost) is open, with a fix reverted in 2026-01. The site routes both regions onto the slow path: JS-written custom properties, a layout-driven morph and a radius that changes every frame (INFERRED).

Citation prefixes: `WC/` = Source/WebCore/, `WK/` = Source/WebKit/, `WTF/` = Source/WTF/, all at WebKit 862f17dcae0a (tag
WebKit-7625.1.29.10.29). `Prefs.yaml` = WTF/Scripts/Preferences/UnifiedWebPreferences.yaml. Files outside the sparse
clone were read with curl from raw.githubusercontent at the same sha and are marked "(raw)". Stage names follow
[10-18-engine-webkit-pipeline.md](10-18-engine-webkit-pipeline.md) (S0-S6).

## Shared mechanisms

| # | Question | Finding | Evidence | Status |
|---|---|---|---|---|
| Q1 | Per-frame path, drawing area | script, style, layout, compositing update, layer flush, paint of dirty backings, commit (one in flight). iOS and Mac Safari both use RemoteLayerTree: the UI process applies layer properties and CoreAnimation renders. On Mac this holds with ≥ 4 physical cores, Lockdown or site isolation. | `WTF/wtf/PlatformEnableCocoa.h:817-818` (`REMOTE_LAYER_TREE_ON_MAC_BY_DEFAULT` = 1 on Mac). `WK/UIProcess/mac/WebViewImpl.mm:1352-1368` | CONFIRMED; the user's Mac core count INFERRED (every Apple silicon Mac has ≥ 8) |
| Q1b | Where paint runs | DOM rendering runs in the GPU process by default on iOS and on Mac with ≥ 4 cores. The web process records the paint; the GPU process rasterizes it into the backing. | `WTF/wtf/PlatformEnableCocoa.h:396-404`. `WK/Shared/WebPreferencesDefaultValues.cpp:312-321` (raw). Prefs.yaml:8854-8866 | CONFIRMED (Safari ships the default: INFERRED) |
| Q2a | When a filter is a CA filter | Drawn by CA when its layer is composited and `GraphicsLayerCA::setFilters` accepts it (any blur list). Otherwise it is painted. A static filter alone never composites. | `WC/rendering/RenderLayer.cpp:1053-1072`. `WC/rendering/RenderLayerBacking.cpp:868-871`. `WC/platform/graphics/ca/GraphicsLayerCA.cpp:925-945`. `WC/platform/graphics/ca/cocoa/PlatformCALayerCocoa.mm:929-949`. Prefs.yaml:3509-3523 | CONFIRMED |
| Q2b | Radius change from a JS-written custom property | Restyle, then a **Layout** diff (the outsets change). Layout marks the element's layer for full repaint, so after layout its whole content is repainted into its compositing backing. Then `FiltersChanged`, a commit, a new CAFilter array in the UI process and a render-server re-blur. A CA filter does not grow the layer bounds. | `WC/style/StyleDifference.cpp:68-83` (MEASURED as Layout, CI run 39088367495). `WC/rendering/RenderElement.cpp:1355-1357`. `WC/rendering/RenderObjectInlines.h:87-97` (`setLayerNeedsFullRepaint`). `WC/rendering/RenderLayer.cpp:1329-1355`. `WK/WebProcess/WebPage/RemoteLayerTree/PlatformCALayerRemote.mm:896-899`. `WK/Shared/RemoteLayerTree/RemoteLayerTreePropertyApplier.mm:513-514`. `WC/platform/graphics/ca/cocoa/PlatformCAFiltersCocoa.mm:214-230, 309-312` | CONFIRMED (GPU cost INFERRED) |
| Q2c | Same change as a CSS or WAAPI animation of `filter` | A time-based animation takes the GraphicsLayerCA CAAnimation path: no per-frame style, layout, paint or commit. Scroll-driven animations are threaded (stable, Safari 26.4). Threaded time-based animations are a preview preference, off. A custom property, registered or not, is never accelerated. | Prefs.yaml:8557-8570. [Safari 26.4 post](https://webkit.org/blog/17862/webkit-features-for-safari-26-4/). `Fw.Engine.WebKit` "custom properties never in UI process" | CONFIRMED |
| Q3 | backdrop-filter | Always composited, no software fallback: a CABackdropLayer named "backdrop" that masks to bounds, capped at `1242*2208*10` px total. A value change is RecompositeLayer plus `BackdropFiltersChanged`; a rect change goes through `updateClippingStrategy`. It re-samples whatever is behind it when that changes. | `GraphicsLayerCA.cpp:112, 947-965, 974-981, 2682-2762, 3218`. `WC/style/StyleDifference.cpp:273, 593-596`. `WC/rendering/RenderElement.cpp:333-339` | CONFIRMED (sampling cost INFERRED) |
| Q4 | will-change, policy, preserve-3d | `will-change: transform/opacity/filter` composites a box. On non-Mac it does not under the Conservative policy. The policy turns Conservative when the memory usage policy is not Unrestricted. `preserve-3d` makes a CATransformLayer only with 3D-transformed descendants. A scale change does not re-rasterize. | `WC/rendering/RenderLayerCompositor.cpp:3997-4018` (Conservative return 4008-4012), `:691-724` (policy, 718). `GraphicsLayerCA.cpp:420, 4380-4387, 4411-4435` | CONFIRMED |
| Q4b | Indirect compositing | A layer with composited descendants is composited when it has a transform, creates a group (opacity, filter, mask) or is a backdrop root. | `RenderLayerCompositor.cpp:4176-4191` | CONFIRMED |
| Q5 | top/width/height vs transform | A size change sets the layer bounds (`GeometryChanged`), re-creates the backing at the new size and repaints it fully. A filtered box with non-zero outsets always repaints fully on a size change. A transform change edits the existing layer, with no paint. A fixed element's relayout root is the view. | `GraphicsLayerCA.cpp:641-648`. `PlatformCALayerRemote.mm:333-355, 596-607`. `RenderElement.cpp:1498`. `Fw.Engine.WebKit.resizePaint`. ledger `nav.oofRoot.containment` | CONFIRMED |
| Q6 | Tiled backing | A layer wider or taller than `cMaxPixelDimension` × page scale becomes a TiledBacking layer, which paints only the tiles in its coverage rect (visible rect plus margins). The limit is 2048 on Mac and 1280 on iOS (1024 under low memory). Crossing it swaps the layer type. | `GraphicsLayerCA.cpp:100-106, 4843-4857, 2157-2163, 1853-1856`. `WC/platform/graphics/ca/TileController.cpp:441` | CONFIRMED (coverage size per frame INFERRED) |
| Q7 | Mac wheel by input type | A non-passive `wheel` listener on `window` makes the page a NonPassiveWheel region. A gesture start or a non-gesture event resets the gesture state; with no state the event is `SynchronousScrolling + BlockingDOMEventDispatch`. **Trackpad:** the scrolling thread waits ≤ 50 ms for the main thread on the gesture's first event. If that event is not default-prevented the gesture turns NonBlocking: the rest of it, momentum included, scrolls async, and its DOM events are dispatched non-cancelable. **Mouse wheel** (non-gesture events): every event stays synchronous. | `WC/page/scrolling/ScrollingTree.cpp:118-131, 149-150`. `WK/UIProcess/RemoteLayerTree/mac/RemoteLayerTreeEventDispatcher.mm:272-283`. `WK/UIProcess/RemoteLayerTree/mac/RemoteScrollingTreeMac.mm:333-355, 358-376, 378-395`. `WC/page/EventHandler.cpp:3623, 3786-3794`. Prefs.yaml:10223-10236 (`WheelEventGesturesBecomeNonBlocking`, mature). `WK/Shared/WebPreferencesDefaultValues.cpp:103-107` (raw; Mac default is linked-on-or-after) | CONFIRMED (Safari linked on a current SDK: INFERRED) |
| Q8 | Image draw per repaint | A repaint draws each image from its decoded frame scaled to the destination; WebKit keeps no scaled copy. A decoded frame is reused while it is compatible (full size, or a sizeForDrawing at least as large). A 1282px image (< 5 MiB px) is never subsampled. The first paint of a new layer decodes async; a later paint of a visible image decodes sync, and a bigger request than the cached async decode triggers a full-size synchronous decode. | `WC/platform/graphics/BitmapImage.cpp:88-143` (raw). `WC/platform/graphics/DecodingOptions.h:67-88` (raw). `WC/platform/graphics/BitmapImageSource.cpp:582-616, 639-646` (raw). `WC/platform/graphics/BitmapImageDescriptor.cpp:229-273` (raw). `WC/rendering/RenderBoxModelObject.cpp:256-317`. `WC/rendering/RenderLayerBacking.cpp:4557-4560` | CONFIRMED (CoreGraphics resample cost INFERRED) |

## Region A: hero cards moving out (hero.exit, faithful)

Inputs: `apps/site/src/parts/hero.exit/{driver.ts,hero.module.css}` and the readers in hero, hero.cue, hero.orbit and hero.deck.

| Stage | Cost driver | Evidence | Status |
|---|---|---|---|
| S0 script | Own rAF per scroll frame: one `getBoundingClientRect` on the track, then `--exit-opacity` and `--exit-scatter` written inline on `.hero`, plus `pointerEvents`. | hero.exit/driver.ts | CONFIRMED |
| S1 style | `--exit-*` is inherited, so the MatchedDeclarationsCache misses and the readers restyle: 99 resolutions per frame at narrow, 9 with inline writes. | branch `ci/exit-scoped-inline` @071906af: research/notes/2026/10-20-exit-scoped-inline.md:57-58, Lean `HeroExitOpt.inline_units` (HeroExitOpt.lean:1308), `inline_narrow_delta`. `WC/style/MatchedDeclarationsCache.cpp:123-163` | CONFIRMED on that branch (not on main yet) |
| S2 layout | `.copy` (≥ 600px) and `.cue` (all widths) change blur radius, so a Layout diff. Cards change only `opacity` and `translate`. | `StyleDifference.cpp:68-83`. hero/hero.module.css:23-25, hero.cue/cue.module.css:12-13, hero.orbit/card.module.css:24, 33-34 | CONFIRMED |
| S3 compositing | Cards (`will-change: transform, translate, scale, opacity`) get RecompositeLayer. `.copy` is composited by its will-change. `.cue` is composited through its animated `.float` child. Filter outsets enter overlap bounds, so overlap may churn. | `RenderLayerCompositor.cpp:3997-4018` (will-change), `:4176-4191` (cue, GraphicalEffect), `:4317` | CONFIRMED (cue reason and churn INFERRED) |
| S5 paint | Full repaint of the `.copy` and `.cue` backings every frame (Q2b), rasterized in the GPU process. Copy group about 900 × 400 CSS px, about 1.4 Mpx at 2x. The countdown faces inside it are their own layers and are not repainted. | Q2b, Q1b | Mechanism CONFIRMED; area INFERRED |
| S4/S6 flush, commit | `FiltersChanged` on copy and cue, transform and opacity on 10 cards, one commit per frame. | `PlatformCALayerRemote.mm:896-899` | CONFIRMED |
| UI, render server | A new CAFilter array each frame; the copy subtree and the cue are re-blurred at up to 18px. | `PlatformCAFiltersCocoa.mm:214-230, 309-312` | INFERRED (cost) |
| Sync | The sticky hero scrolls async in the UI process; the values arrive one or more commits later, so the cards trail the scroll. | pipeline note §4.2 | INFERRED |
| iPhone ≤ 600 | `.copy` and the deck have `filter: none` and the orbit is hidden; only the cue blurs and repaints. Under Conservative policy the cards lose will-change compositing, and the JS translate becomes a repaint of their images. | hero/hero.module.css, hero.deck/deck.module.css. Q4 | CONFIRMED (Conservative occurrence INFERRED) |

**Predicted dominant cost (INFERRED).** Mac: the per-frame repaint and re-blur of the copy group, plus main-thread latency. iPhone: rendering-update cadence and latency, plus the cue. Card backings (10 × about 0.2 Mpx at 2x) only recomposite.

## Region B: end of page (morph.tween, nav, morph.panel, morph.columns, morph.countdown, morph.mount, platform)

Inputs: `apps/site/src/parts/{morph.tween/driver.ts,nav/nav.module.css,morph.panel/morph.module.css,morph.columns,morph.countdown,morph.mount/logic.ts,platform/platform.module.css}`.

| Stage | Cost driver | Evidence | Status |
|---|---|---|---|
| Input, Mac trackpad | The `wheel` listener (`passive: false`) is attached while the platform is within 200% of the viewport. The first event of each gesture waits ≤ 50 ms; `onWheel` prevents it only when `takenFor` holds, so most gestures turn async. In a gesture that starts outside the armed band, a later `preventDefault` is ignored: the scroll keeps moving while `pin()` calls `scrollTo` every scroll frame. | morph.tween/driver.ts:67-72, 89, 100, 142. Q7 | CONFIRMED (visible fight INFERRED) |
| Input, Mac mouse wheel | Every notch is synchronous while the listener is attached: it scrolls on the main thread after the DOM dispatch, so every long frame on the approach and in the morph is scroll stutter. | Q7 | CONFIRMED (effect INFERRED) |
| Input, iPhone | `touchmove` is preventable only until UIKit starts the pan. After that `pin()` calls `scrollTo` every frame and fights the UIKit scroll. | `WK/UIProcess/ios/WKContentViewInteraction.mm:2262-2268, 2491-2497, 4239-4245`. pipeline note §4.3 | CONFIRMED (visible fight INFERRED) |
| S0 script | rAF tween, 680 ms: `--morph` on the nav, `--morph-fade` and `pointerEvents` on the platform. | morph.tween/driver.ts:52-58, 104-112 | CONFIRMED |
| S1 style | `--morph` is inherited, so the whole nav subtree restyles; `--morph-fade` restyles the platform subtree. | MatchedDeclarationsCache (region A) | CONFIRMED |
| S2 layout | The nav's `top`, `width` (984 to 1398 desktop; about 345 to 353 phone) and `height` (64 to `min(820px, 100vh - 40px)`) change, so layout runs from the view root. The panel, center, `text-wrap: balance` title, backdrop and `flex: 1 1 0` columns get new sizes. The logo `left`, the actions `gap`, and the earn button `max-width` and `padding-inline` (first 20%) also change. Four blur radii add outset layout. | nav/nav.module.css:14-30, 123-130, 168-180. morph.panel/morph.module.css:7-17. ledger `nav.oofRoot.containment` | CONFIRMED |
| S3/S4 geometry | Resized backed layers each frame: the nav (composited by its backdrop-filter), the panel (filter, opacity and scale over composited tracks), the tracks (`will-change: transform`). Each gets new bounds and a backing at the new size. The panel `transform: scale(0.96 + 0.04·morph)` and `opacity` are layer properties (RecompositeLayer). | `PlatformCALayerRemote.mm:333-355, 596-607`. `RenderLayerCompositor.cpp:4176-4191`. morph.panel/morph.module.css:7-17 | CONFIRMED (panel reason INFERRED) |
| S3 filters | Panel `filter: blur` 12px to 0, platform `filter: blur` 0 to 12px with opacity, earn button `filter: blur` 0 to 10px (morph 0 to 0.2) with opacity and translateY, nav `backdrop-filter: blur` 20px to 0. All change every frame in their range. The backdrop rect follows the nav size and radius. | morph.panel/morph.module.css:9, platform/platform.module.css:12-13, nav/nav.module.css:28-29, 168-178. `GraphicsLayerCA.cpp:925-981, 2682-2764` | CONFIRMED |
| S5 paint | Full repaint of each resized layer (per-layer table below). The panel and platform also repaint because their radius changes (Q2b). The earn button has no composited descendants, so its blur is painted into the nav backing (small). The platform repaints only its own background; its `.card` is a separate will-change layer while the scene is active. | Q2b, Q5, Q6. platform/platform.module.css:5-34, platform/scene.ts | Mechanism CONFIRMED; areas INFERRED |
| UI, render server | New IOSurfaces for the repainted backings; CA re-blurs the panel and platform subtrees; the CABackdropLayer re-samples while the panel under the nav changes. | `PlatformCAFiltersCocoa.mm:309-312` | INFERRED (cost) |

**Per-layer repaint area per frame at the end state** (2x Mac at 1440 × 900; 3x iPhone at 390 × 844). Intermediate frames are smaller, so these are per-frame maxima.

| Layer | CSS size | Mac 2x | iPhone 3x | Tiled? | Status |
|---|---|---|---|---|---|
| nav (background, radius) | 1398 × 820; phone 353 × 804 | 4.6 Mpx | 2.6 Mpx | no | INFERRED |
| panel (veil gradient, center text, footer, unless overlap gives them own layers) | same as nav | 4.6 Mpx | 2.6 Mpx | no | INFERRED |
| tracks, 5 or 3 (fixed image heights; width follows the column) | 287 × 1340-1612 (sum 7418); phone about 135 × 1450 | 8.5 Mpx | ≤ 5.3 Mpx | Mac no; iPhone yes (> 1280), coverage-limited | INFERRED |
| Total | | about 17.7 Mpx | ≤ 10.4 Mpx | | INFERRED |
| platform section own background (fade only) | about the viewport | ≤ 5.2 Mpx | ≤ 3 Mpx | if taller than the limit | INFERRED |

Track heights come from morph.columns/data.ts:14-18. The `.backdrop` paints nothing of its own, so it has no backing (INFERRED).

**Per-transition effects.**
- **Mount** (morph.mount, `rootMargin: 200% 0px`): the panel subtree enters the DOM with the scene `paused` (no `will-change`), opacity 0 and blur 12px. That costs one style, layout and image fetch. The task title counts +9 drawing layers in Chromium. A zero-opacity layer is skipped in paint, so the column images are likely not decoded before the morph (`RenderLayer.cpp:6144-6149`; INFERRED).
- **Morph start**: `data-start-selling-scene` leaves `paused`. The tracks regain `will-change: transform` and their 16s animation, and the countdown digit faces regain `will-change: transform`: about 8 digits × 10 faces ≈ 80 new layers, plus ancestor clipping layers for `.digit { overflow: hidden }`. Each new layer is created, gets a first paint with async image decode, and is committed (morph.columns/morph.module.css:9-12, morph.countdown/morph.module.css:13-17, hero.countdown/hero.module.css:71-72, hero.countdown/index.tsx:30-55; Q8; INFERRED counts).
- **First morph frames**: once a column image has painted and is visible, the next repaint decodes it synchronously. Because the columns grow, the cached async decode is too small, so each image can get one full-size synchronous decode on the main thread (Q8; CONFIRMED path, count and timing INFERRED).

**Predicted dominant cost (INFERRED).** First, the resize repaints (about 17.7 Mpx per frame at the end on Mac, at most 10.4 on iPhone) and view-root layout. Second, at morph start, the layer creation and the image decodes. Third, the render-server blur and backdrop work. On Mac with a mouse wheel, any long frame on the approach shows as scroll stutter. Chrome hides more of this because its compositor scrolls and rasters off the main thread (engine contrast, not measured).

## Images in both regions

| Region | Images | Effect over them | Redrawn per frame? | Status |
|---|---|---|---|---|
| A | Orbit and deck card `cover` and `avatar` `<img>` (hero.orbit/card.tsx:29, 36) | Card opacity and translate only (no blur radius change) | No: RecompositeLayer. Yes under Conservative policy on iPhone (translate becomes a repaint of the ancestor backing). | CONFIRMED path; Conservative INFERRED |
| A | None under the `.copy` and `.cue` blurs (hero, hero.cue have no `<img>`) | Blur, repaint | n/a | CONFIRMED (grep) |
| B | 21 (desktop) or 12 (phone) column images, 1282px natural (task title), `loading="eager" decoding="async"`, `object-fit: cover` (morph.columns/index.tsx:75, data.ts:14-18) | Inside the resized tracks; under the panel blur and opacity; seen through the nav backdrop | Yes: every track repaint draws each image scaled from the full decoded bitmap, about 2.2x downscale on Mac and 3.2x on iPhone. No re-decode per frame while the decode stays cached. | CONFIRMED (Q8); resample cost INFERRED |
| B | Platform images (Visuals.tsx `loading="lazy"`, mesh.jpg, grain.png backgrounds) | Under the platform blur, inside the composited `.card` | No: the platform repaint covers only the section's own background; CA blurs the card layer. | INFERRED (card composited while the scene is active) |

A blurred composited layer is blurred from its rasterized backing in the render server; the blur does not re-sample the images inside it (INFERRED, closed source). The images cost per frame only where their layer is repainted, which is the tracks. Decoded memory also counts: a 1282² frame is about 6.6 MB, so 21 of them are about 140 MB on desktop. That pressure can push iOS to the Conservative policy, which drops will-change compositing (Q4; INFERRED). For image-audit: natural vs drawn size per breakpoint and DPR, decodes during the morph (async, then sync full-size), and decoded bytes. For webkit-lag-probe: A/B the images-at-drawn-size arm on the morph paint area and decode count.

## Candidate changes

| # | Region | Change | Predicted effect | Visual risk |
|---|---|---|---|---|
| C1 | B | Lay the panel, backdrop and columns out once at the final panel size, centered in the nav and clipped by it (`overflow: hidden` is already there). Only the nav box changes size. | Removes the track and panel resize repaints (about 13 Mpx at the end on Mac). The residual is the nav backing repaint, about 4.6 Mpx at the end state (INFERRED). The panel radius change still repaints the panel unless C2 lands too. | Medium: mid-morph content is cropped instead of reflowed; must pass the parity gate. |
| C1b | B | Morph the nav with `transform: scale` plus `clip-path: inset(... round r)` at final size, instead of `width`, `height` and `top`. | No layout and no repaint per frame; scale does not re-rasterize (`GraphicsLayerCA.cpp:4386`). | High: radius and content scale distort unless counter-scaled. |
| C2 | B | Run the panel, platform and earn button `filter`, `opacity` and `transform` as real-property CSS or WAAPI animations started at the trigger. The `waapi` variants animate registered custom properties (morph.tween/waapi.logic.ts:17-22, 97-107), which WebKit still runs on the main thread, so they do not do this. | No per-frame style, outset layout or repaint for those subtrees; CA interpolates them. The GPU blur stays. | Low, if the timing equals the proved curve (MT1 `bezier_eq_ease`); reversal and retarget need a rule. |
| C3 | B (Mac) | Attach the non-passive `wheel` listener only inside the trigger band, not at the 200% margin. | Mouse wheel: the approach scroll becomes async. Trackpad: only the ≤ 50 ms gesture-start wait goes away, because those gestures are already async. Needs a Lean arm decision. | None if the trigger frame is unchanged. |
| C4 | B (Mac and iPhone) | Lock scroll during the morph (`overflow: hidden` on the scroller, or `touch-action: none` on the armed region for touch) instead of a `scrollTo` pin every frame. | No pin fight on iPhone, and none on Mac for trackpad gestures (and their momentum) that started before the armed band. No scroll round trip per frame. | Medium: the lock behaves differently (rubber-band, address bar, scrollbar). |
| C5 | A | Drive the hero exit with a scroll-driven animation (`animation-timeline: view()` on the track) on the real properties: copy and cue `filter`, `opacity`, `transform`; card `translate`, `opacity`. | Threaded in Safari 26.4+: no main-thread style, layout or repaint per frame, values in sync with the scroll. Older Safari falls back to the main thread. | Low, if the keyframes equal the Lean `exitFrame`; the `pointerEvents` toggle stays in JS. |
| C6 | A | `hero.exit:scoped` with inline reader writes (branch `ci/exit-scoped-inline`). | Style resolutions only, 99 to 9 at narrow; the copy repaint and blur stay. | None (VisSame proved on that branch). |
| C7 | B | Images at drawn size (image-audit arm). | Less source sampling per track repaint and less decoded memory; the repaint area is unchanged. | Low within the PL tolerance. |

C1 with C2 checks the predicted dominant cost in B; C3 and C4 check the input terms. C5 is the only change that removes A's main-thread latency and repaint.

## WebKit cost terms `Fw.Engine.WebKit` lacks

1. **Repaint on radius change:** a blur radius change is a Layout diff that fully repaints the filtered layer's content each frame, on top of the CA re-blur (Q2b).
2. **CA filter raster:** filtered area × radius in the render server, each frame the radius or the subtree changes.
3. **Backdrop sampling:** backdrop area × radius when the content behind it or the rect changes; the `cMaxTotalBackdropFilterArea` cap; the rounded-rect clip update.
4. **Painted filter:** a non-composited filter costs (dirty rect + outsets) × radius (`RenderLayerFilters.cpp:160-235`); the earn button is one.
5. **Tiled vs untiled backing:** above 2048 (Mac) or 1280/1024 (iOS) CSS px × page scale a layer is tiled and paints only its coverage; a crossing swaps the layer type (Q6).
6. **Paint split:** web-process recording vs GPU-process raster (Q1b).
7. **Image draw:** a scaled draw from the decoded frame per repaint (natural px × repaints), the decode mode per paint (async first paint, sync later, a full-size sync decode when the drawn size grows), and decoded memory (Q8).
8. **Layer creation:** layers created when `will-change` returns at morph start, with first paint and commit.
9. **Overlap churn** from filter outsets in overlap bounds (`RenderLayerCompositor.cpp:4317`).
10. **Input path by type:** trackpad gesture (≤ 50 ms wait, then async unless the first event is prevented; later `preventDefault` ignored), mouse wheel (synchronous per event), iOS touch (preventable until the pan starts), and the commits by which main-thread visuals trail the async scroll.
11. **Cadence:** one commit in flight, a 60 fps preference (Prefs.yaml:6505-6520), and the Low Power Mode and thermal throttle to 30 fps (`WC/platform/graphics/AnimationFrameRate.h:43, 50-57`; `WC/page/Page.cpp:544-549, 2809-2817`).
12. **Device scale** in paint area (2x Mac, 3x iPhone).
13. **Policy trigger:** `Policy` exists, but the memory condition that switches it to Conservative (`RenderLayerCompositor.cpp:705-722`) does not.

## Limits

- The render server, CoreAnimation and CoreGraphics are closed source, so every GPU and resample cost is INFERRED.
- Layer reasons for the panel, veil, center, cue and platform are read from CSS and source, not observed; a WKTR layer dump would confirm them.
- Areas assume a 1440 × 900 Mac and a 390 × 844 iPhone viewport.

## What this changes in the plan

- **§4.2 Step 1 (deterministic work counts), WebKit lane.** webkit-lag-probe gains counters for:
  - repainted area per layer per frame, split resized vs radius-changed, and tiled coverage;
  - filter and backdrop layers, with radius and area;
  - layers created per frame (morph start) and image decodes per frame (async or sync, full or sized);
  - wheel processing steps on the approach, split by trackpad and mouse wheel, and `scrollTo` calls from `pin()`;
  - commit cadence.
  
  These rank C1-C7 before any becomes a task.
- **§5.1 (what is proved).** A lean-prover task adds terms 1-13 to `Fw.Engine.WebKit`, first 1, 5, 7 and 10, which carry both predicted dominant costs and the input stutter.
- **§6.1 (parts).** After the probe ranks them, C1 with C2 (`nav`, `morph.panel`), C3 and C4 (`morph.tween`) and C5 (`hero.exit`) become graph candidates, each through proof, flag and gate. C6 continues as exit-scoped-inline; C7 is image-audit's arm.

## Sources

- WebKit source at 862f17dcae0a (paths above; "(raw)" files from raw.githubusercontent at that sha).
- [WebKit Features for Safari 26.4](https://webkit.org/blog/17862/webkit-features-for-safari-26-4/): threaded scroll-driven animations; "Improved drop-shadow and blur effects rendering performance" (169472992).
- [WebKit bug 228312](https://bugs.webkit.org/show_bug.cgi?id=228312): CSS blur() filter performance (NEW; a fix reverted 2026-01).
- Safari Technology Preview 234 and 238 release notes: threaded scroll-driven and time-based animation work.
- [Mozilla bug 1732817](https://bugzilla.mozilla.org/show_bug.cgi?id=1732817): backdrop filter defeats picture caching (an analogy only).
