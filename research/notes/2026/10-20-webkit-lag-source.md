---
id: 2026-10-20-webkit-lag-source
kind: note
title: "Why the hero exit and the end-of-page morph lag in Safari (WebKit, Mac and iPhone): per-frame cost paths from source"
status: review
created: 2026-10-20
topics: [webkit, safari, ios, macos, compositing, filters, backdrop-filter, hero.exit, morph.tween, nav, cost-model, lean]
---

# Why the hero exit and the end-of-page morph lag in Safari

Task webkit-lag-source. This note uses source and docs only. Nothing here is measured on a device; webkit-lag-probe does that.

## Answer

- **Hero exit (region A).** All the exit motion is a custom property (`--exit-opacity`, `--exit-scatter`). JS writes it once per scroll frame
  from the main thread. WebKit never runs a custom property in the UI process. So every frame costs:
  - a restyle of the readers;
  - a layout, because a blur radius change changes the filter outsets;
  - a new CA filter radius on the hero copy (and on the cue), sent in the commit.
  - The render server then blurs the whole copy group again at up to 18px radius.
  - **Predicted dominant cost, Mac:** the GPU blur of the big copy group, plus the copy being one or more commits behind the async-scrolled sticky hero (INFERRED).
  - **Predicted dominant cost, iPhone (≤600px):** the copy and the deck have `filter: none`, so the cost is main-thread rendering-update latency per delivered scroll position, not raster (INFERRED).
- **End of page (region B).** A 680 ms JS tween drives `top`/`width`/`height` of the fixed nav. Every frame then:
  - lays out from the view root;
  - resizes every backed layer inside the nav: the panel, the backdrop and the 5 (desktop) or 3 (phone) tall image column tracks;
  - repaints each resized backed layer in full, at 2x or 3x;
  - changes three blurs: a panel `filter`, a platform-section `filter` and the nav `backdrop-filter`.
  - On Mac, a non-passive `wheel` listener on `window` makes wheel scrolling synchronous for the whole approach.
  - **Predicted dominant cost:** the full repaint of the resized track and panel layers in the web process, plus layout. GPU blur and backdrop work comes after that (INFERRED). On Mac, synchronous wheel scrolling shows every long frame as scroll stutter (mechanism CONFIRMED, effect INFERRED).
- **Is Safari "unoptimized" here?** Partly.
  - Time-based CSS/WAAPI filter, opacity and transform animations do get the CA animation path. Custom-property animations never do.
  - Threaded time-based animations are still a preview preference, off by default.
  - There is an open WebKit bug about `blur()` cost ([228312](https://bugs.webkit.org/show_bug.cgi?id=228312), a fix reverted in 2026-01).
  - The site's choices are what route both regions onto the slow path: JS-written custom properties, a layout-driven morph, and a radius that changes every frame (INFERRED).

Citation prefixes: `WC/` = Source/WebCore/, `WK/` = Source/WebKit/, `WTF/` = Source/WTF/, all at WebKit 862f17dcae0a (tag
WebKit-7625.1.29.10.29). `Prefs.yaml` = Source/WTF/Scripts/Preferences/UnifiedWebPreferences.yaml. Stage names follow
[research/notes/2026/10-18-engine-webkit-pipeline.md](10-18-engine-webkit-pipeline.md) (S0-S6).

## Shared mechanisms (one row per question)

| # | Question | Finding | Evidence | Status |
|---|---|---|---|---|
| Q1 | Per-frame path | script → style → layout → compositing update → layer flush → paint of dirty backing → commit (one in flight). On iOS, and on Mac when RemoteLayerTree is active, the UI process applies the layer properties and CoreAnimation renders. | pipeline note §1. `WK/UIProcess/mac/WebViewImpl.mm:1352-1368` picks RemoteLayerTree on Mac (≥ 4 cores, Lockdown or site isolation) | CONFIRMED; the Mac macro default is INFERRED |
| Q2a | When a filter is a CA filter | A filter is drawn by CA when its layer is composited and `GraphicsLayerCA::setFilters` accepts it. Any blur list is accepted. If the layer is not composited, the filter is painted in software (or by GraphicsContext filters) in the web process. A static filter alone never composites (there is no FilterTrigger). | `WC/rendering/RenderLayer.cpp:1053-1072`. `WC/rendering/RenderLayerBacking.cpp:868-871`. `WC/platform/graphics/ca/GraphicsLayerCA.cpp:925-945`. `WC/platform/graphics/ca/cocoa/PlatformCALayerCocoa.mm:929-949`. Prefs.yaml:3509-3523 | CONFIRMED |
| Q2b | Radius change from a JS-written custom property | Per frame: restyle, then a **Layout**-level diff (the outsets change), then `FiltersChanged`, then a commit. The UI process builds a new CAFilter array (`kCAFilterGaussianBlur`, `inputRadius`), and the render server re-blurs the subtree. A composited CA filter does not grow the layer bounds, so there is no resize. | `WC/style/StyleDifference.cpp:68-83` (MEASURED as Layout, CI run 39088367495). `WK/WebProcess/WebPage/RemoteLayerTree/PlatformCALayerRemote.mm:896-899`. `WK/Shared/RemoteLayerTree/RemoteLayerTreePropertyApplier.mm:513-514`. `WC/platform/graphics/ca/cocoa/PlatformCAFiltersCocoa.mm:214-230, 309-312`. `WC/rendering/RenderLayer.cpp:5728` | CONFIRMED (GPU cost INFERRED; the render server is closed source) |
| Q2c | Same change as a CSS/WAAPI animation of `filter` | A time-based animation takes the legacy GraphicsLayerCA CAAnimation path. CA interpolates the filter, so there is no per-frame style, layout or commit. A scroll-driven animation is threaded (stable, Safari 26.4). Threaded time-based animations are a preview preference, off by default. A custom property is never accelerated. | Prefs.yaml:8557-8570. [Safari 26.4 post](https://webkit.org/blog/17862/webkit-features-for-safari-26-4/). `Fw.Engine.WebKit` "custom properties never in UI process" | CONFIRMED |
| Q3 | backdrop-filter | Always composited. There is no software fallback. It is a CABackdropLayer named "backdrop" that masks to bounds and is capped at `1242*2208*10` px total. A value change is a Filter-context diff, so RecompositeLayer plus `BackdropFiltersChanged`. A rect change goes through `updateClippingStrategy` (rounded rect). The backdrop re-samples whatever is behind it whenever that content changes. | `GraphicsLayerCA.cpp:112, 947-965, 974-981, 2682-2762, 2764ff, 3218`. `WC/style/StyleDifference.cpp:273, 593-596`. `WC/rendering/RenderElement.cpp:333-339` | CONFIRMED (sampling cost INFERRED) |
| Q4 | preserve-3d, will-change, memory | `preserve-3d` makes a CATransformLayer only when there are 3D-transformed descendants. The orbit cards are 2D. `will-change: transform/opacity/filter` composites under the Normal policy, not under Conservative (memory pressure, non-Mac). A scale change does not re-rasterize, because root-relative scale updates are off. | `GraphicsLayerCA.cpp:420, 4380-4387, 4411-4435`. `WC/rendering/RenderLayerCompositor.cpp:4176-4191`. `Fw.Engine.WebKit.Policy` | CONFIRMED (stage3d not composited is INFERRED) |
| Q5 | top/width/height vs transform | A size change sets the layer bounds (`GeometryChanged`), then `ensureBackingStore` at the new size, then a full repaint of that backing store. A transform change is a property change on the existing backing, with no paint. A fixed element's relayout root is the view. | `GraphicsLayerCA.cpp:641-648`. `PlatformCALayerRemote.mm:333-355, 596-607`. `Fw.Engine.WebKit.resizePaint`. ledger `nav.oofRoot.containment` (Lean `Tree.oof_view_full`) | CONFIRMED |

## Region A: hero cards moving out (hero.exit, faithful)

The inputs are `apps/site/src/parts/hero.exit/{driver.ts,hero.module.css}` and the readers in hero, hero.cue, hero.orbit and hero.deck.

| Stage | Cost driver | Evidence | Status |
|---|---|---|---|
| S0 script | Own rAF per scroll frame: one `getBoundingClientRect` on the track, then `--exit-opacity` written inline on `.hero`. `pointerEvents` is written too. | hero.exit/driver.ts | CONFIRMED |
| S1 style | `--exit-*` is inherited, so the parent's inherited custom properties change and the MatchedDeclarationsCache misses. The readers restyle (copy, cue, 10 cards wide; 99 resolutions per frame at narrow). | exit-scoped-inline note (`WC/style/MatchedDeclarationsCache.cpp:123-163`). Lean `inline_units` | CONFIRMED |
| S2 layout | `.copy` (≥ 600px) and `.cue` (all widths) change their blur radius, so a Layout diff. The cards' `blur(0)` is identity (`RenderLayerFilters::isIdentity`), so they get no filter cost. | `StyleDifference.cpp:68-83`. hero/hero.module.css, hero.cue/cue.module.css, hero.orbit/card.module.css | CONFIRMED |
| S3 compositing | Cards (`will-change: transform, translate, scale, opacity`) get RecompositeLayer for translate and opacity. `.copy` is composited by its will-change. `.cue` is composited through its animated `.float` child (GraphicalEffect). The filter outsets enter overlap bounds, so overlap may churn. | `RenderLayerCompositor.cpp:4176-4191, 4317` | CONFIRMED (cue reason and churn INFERRED) |
| S4/S6 flush, commit | `FiltersChanged` on copy and cue, plus transform and opacity on 10 cards. One commit per frame. | `PlatformCALayerRemote.mm:896-899` | CONFIRMED |
| UI, render server | A new CAFilter array each frame. The Gaussian blur re-runs over the copy group (headline, CTA, countdown faces; about 900 CSS px wide at 2x) at up to 18px, and over the cue. | `PlatformCAFiltersCocoa.mm:214-230, 309-312` | INFERRED (cost) |
| Sync | The sticky hero scrolls async in the UI process. The values arrive one or more commits later, so the cards trail the scroll. | pipeline note §4.2 | INFERRED |
| iPhone ≤600 | `.copy` and the deck have `filter: none` and the orbit is hidden, so only the cue blurs. What remains is style, recomposite and commit per delivered scroll position. Under Conservative policy the cards and copy lose will-change compositing, and the JS translate becomes a repaint. | hero/hero.module.css, hero.deck/deck.module.css. `Fw.Engine.WebKit.Policy` | CONFIRMED (Conservative occurrence INFERRED) |

**Predicted dominant cost (INFERRED).** Mac: the per-frame render-server blur of the copy group, plus main-thread latency (the cards trail the scroll). iPhone: main-thread rendering-update cadence and latency, plus the cue blur. Card backing stores are small (10 × about 0.05 Mpx CSS × 4 ≈ 2 Mpx device at 2x). They are not the cost.

## Region B: end of page (morph.tween, nav, morph.panel, morph.columns, platform)

The inputs are `apps/site/src/parts/{morph.tween/driver.ts,nav/nav.module.css,morph.panel/morph.module.css,morph.columns,platform/platform.module.css}`.

| Stage | Cost driver | Evidence | Status |
|---|---|---|---|
| Input (Mac) | The `wheel` listener on `window` is `{passive: false}` and is armed whenever the platform section is within 200% of the viewport. A non-passive wheel event region gives `SynchronousScrolling + BlockingDOMEventDispatch`, latched for the gesture. The gesture start waits up to 50 ms for the main thread. | morph.tween/driver.ts. `WC/page/scrolling/ScrollingTree.cpp:101-159`. `WC/page/scrolling/ThreadedScrollingTree.cpp:114-137` | CONFIRMED |
| Input (iPhone) | `touchmove` is preventable only until UIKit starts the pan. After that, `pin()` calls `scrollTo` every frame of the morph and fights the UIKit scroll (round trip, §4.3). | `WK/UIProcess/ios/WKContentViewInteraction.mm:2262-2268, 2491-2497, 4239-4245`. pipeline note §4.3 | CONFIRMED (visible fight INFERRED) |
| S0 script | rAF tween, 680 ms. It writes `--morph` on the nav and `--morph-fade` on the platform section. | morph.tween/driver.ts | CONFIRMED |
| S1 style | `--morph` is inherited, so the whole nav subtree restyles. `--morph-fade` restyles the platform subtree. | MatchedDeclarationsCache key (see A) | CONFIRMED |
| S2 layout | The nav's `top`, `width` (984 → 1398 desktop; about 345 → 353 phone) and `height` (64 → `min(820px, 100vh - 40px)`) change, so layout runs from the view root. The panel (`inset: 0`), center, `text-wrap: balance` title, backdrop and `flex: 1 1 0` columns all get new sizes. The panel and platform blur radii add outset layout. | nav/nav.module.css, morph.panel/morph.module.css. ledger `nav.oofRoot.containment` | CONFIRMED |
| S3/S4 geometry | Every backed layer that changes size: the nav, the panel (composited through its composited descendants), the 5 or 3 tracks (`will-change: transform`, 16s animation). For each one, `setBounds` → `ensureBackingStore` at the new size. | `PlatformCALayerRemote.mm:333-355, 596-607`. `RenderLayerCompositor.cpp:4176-4191` | CONFIRMED (panel reason INFERRED) |
| S5 paint | A full repaint of each resized backing store. Desktop: 5 tracks × about 287 × 1300-1600 CSS px at 2x ≈ 1.6 Mpx each, about 8 Mpx per frame. Phone: 3 × about 135 × 1450 at 3x ≈ 1.76 Mpx each. Each repaint resamples the 1282² PNGs (`object-fit: cover`), plus the nav background, the veil gradient and the footer. | `Fw.Engine.WebKit.resizePaint`, `partialRepaint`. morph.columns CSS. 10-20-morph-layers note (Chromium track sizes) | Mechanism CONFIRMED. Areas INFERRED from CSS |
| S3 filters | The panel `filter: blur` (12px → 0), the platform `filter: blur` (0 → 12px) with opacity, and the nav `backdrop-filter: blur` (20px → 0). All three change every frame. The backdrop rect follows the nav size and radius. | `GraphicsLayerCA.cpp:925-981, 2682-2764`. `StyleDifference.cpp:593-596` | CONFIRMED |
| UI, render server | Commit and new IOSurfaces for the repainted backings. CA blurs the panel and the platform subtree again. The CABackdropLayer re-samples while the panel under the nav changes. | `PlatformCAFiltersCocoa.mm:309-312` | INFERRED (cost) |

**Predicted dominant cost (INFERRED).** First, the web-process full repaint of the resized track and panel backings (about 8 Mpx device per frame on desktop, about 5 Mpx on iPhone), plus view-root layout. Second, the render-server blur and backdrop work. On Mac the non-passive wheel listener makes any long frame visible as scroll stutter during the approach, not only during the 680 ms tween. Chrome hides more of this, because its compositor scrolls and rasters off the main thread. That is an engine contrast, not measured here.

## Candidate changes

| # | Region | Change | Predicted effect | Visual risk |
|---|---|---|---|---|
| C1 | B | Lay the panel, backdrop and columns out once at the final panel size, centered in the nav and clipped by it (`overflow: hidden` is already there). Only the nav box changes size. | No per-frame resize and full repaint of the tracks and panel. Only the nav background repaints. This removes the predicted dominant term. | Medium: mid-morph the content is cropped instead of reflowed. Must pass the parity gate. |
| C1b | B | Morph the nav with `transform: scale` plus `clip-path: inset(... round r)` at final size, instead of `width`/`height`/`top`. | No layout and no repaint per frame. Scale does not re-rasterize (`GraphicsLayerCA.cpp:4386`). | High: radius and content scale distort unless counter-scaled. |
| C2 | B | Run the panel and platform `filter`/`opacity`/`transform` as real-property WAAPI or CSS animations, started at the trigger, instead of values derived from `--morph`/`--morph-fade`. | No per-frame style or outset layout for those subtrees. CA interpolates them, so they are smooth even when the main thread is busy. The GPU blur stays. | Low, if the timing equals the proved curve (MT1 `bezier_eq_ease`). Reversal and retarget need a rule. |
| C3 | B (Mac) | Arm the non-passive `wheel` listener only inside the trigger band, instead of the 200% margin. | The approach scroll stays async (no `SynchronousScrolling`). Needs a Lean arm decision. | None if the trigger frame is unchanged. |
| C4 | B (iPhone) | Lock scroll during the morph (`overflow: hidden` on the scroller or `touch-action: none` on the armed region) instead of a `scrollTo` pin every frame. | No UIKit fight and no round trip per frame. | Medium: the scroll lock behaves differently (rubber-band, address bar). |
| C5 | A | Drive the hero exit with a scroll-driven animation (`animation-timeline: view()` on the track) on the real properties: copy and cue `filter`/`opacity`/`transform`, card `translate`/`opacity`. | Threaded in Safari 26.4+: no main-thread work per frame, and values in sync with the scroll. Older Safari falls back to the main thread. | Low, if the keyframes equal the Lean `exitFrame`. The `pointerEvents` toggle stays in JS. |
| C6 | A | `hero.exit:scoped` with inline reader writes (already in flight). | Style resolutions only (99 → 9 at narrow). It does not touch the blur or commit cost. | None (VisSame proved). |

C1 and C3 are the cheapest checks of the predicted dominant costs in B. C5 is the only change that removes A's main-thread
latency term.

## WebKit cost terms `Fw.Engine.WebKit` lacks

1. **CA filter raster:** filtered area × radius, charged each frame the radius or the filtered subtree changes (render server, UI side).
2. **Backdrop sampling:** backdrop area × radius, re-run when the content behind it or the backdrop rect changes. Also the `cMaxTotalBackdropFilterArea` cap and the rounded-rect clipping update.
3. **Painted filter:** a non-composited filter costs filter region (dirty rect + outsets) × radius in the web process (`RenderLayerFilters.cpp:160-235`).
4. **Overlap churn** from filter outsets in overlap bounds (`RenderLayerCompositor.cpp:4317`).
5. **Input path:** the wheel processing steps (synchronous scrolling, a 50 ms gesture-start wait) and iOS preventable touch. Also a latency term: how many commits main-thread-driven visuals trail the async scroll.
6. **Cadence:** one commit in flight, a 60 fps preference (Prefs.yaml:6505-6520), and the LowPowerMode and thermal throttle to 30 fps (`WC/platform/graphics/AnimationFrameRate.h:43, 50-57`; `WC/page/Page.cpp:544-549, 2809-2817`).
7. **Device scale and image resampling** in paint area (2x Mac, 3x iPhone; a scaled `object-fit` image per repaint).
8. **Policy trigger:** `Policy` exists, but the memory-pressure condition that switches it to Conservative does not.

## Limits

- The render server and CoreAnimation are closed source, so every GPU cost above is INFERRED.
- The value of `ENABLE(REMOTE_LAYER_TREE_ON_MAC_BY_DEFAULT)` was not read. If Mac Safari uses TiledCoreAnimationDrawingArea instead, the CA filter still runs in CoreAnimation, but in-process.
- The panel and cue compositing reasons are read from CSS plus `RenderLayerCompositor.cpp:4176-4191`, not observed (WKTR layer dumps would show them).

## What this changes in the plan

- **§4.2 Step 1 (deterministic work counts), WebKit lane.** webkit-lag-probe gains counters for:
  - resized backed layers per frame, with their area;
  - filter and backdrop layers, with radius and area;
  - wheel processing steps (synchronous or not) on the approach;
  - commit cadence.
  
  These rank C1-C5 before any of them becomes a task.
- **§5.1 (what is proved).** A lean-prover task adds cost terms 1-8 to `Fw.Engine.WebKit`. Terms 1-3 and 7 come first, because they carry both predicted dominant costs.
- **§6.1 (parts).** After the probe ranks them, C1 (`nav`/`morph.panel`), C3 and C4 (`morph.tween`) and C5 (`hero.exit`) become graph candidates. Each follows proof → flag → gate. C6 continues as exit-scoped-inline.

## Sources

- WebKit source at 862f17dcae0a (paths above).
- [WebKit Features for Safari 26.4](https://webkit.org/blog/17862/webkit-features-for-safari-26-4/): threaded scroll-driven animations; "Improved drop-shadow and blur effects rendering performance" (169472992).
- [WebKit bug 228312](https://bugs.webkit.org/show_bug.cgi?id=228312): CSS blur() filter performance (NEW; a fix reverted 2026-01).
- Safari Technology Preview 234 and 238 release notes: threaded scroll-driven and time-based animation work.
- [Mozilla bug 1732817](https://bugzilla.mozilla.org/show_bug.cgi?id=1732817): backdrop filter defeats picture caching (an analogy only).
