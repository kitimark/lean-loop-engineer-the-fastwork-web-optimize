---
id: 2026-10-2x-end-gpu-map
kind: note
title: "End of page: which parts load the main thread, and which can move to the GPU with the same look"
status: review
created: 2026-10-24
authors: [agent:researcher]
topics: [morph, nav, platform, webkit, chromium, compositor, gpu, translate3d, end-of-page]
---

# End of page: main-thread parts and GPU moves

## Question

The user asked whether the parts at the end of the page were analyzed, since many of them may push work back to the
main thread. Would moving them to GPU calculation help, and can `translate3d` do it?

## Answer first

- Yes, each part is mapped below. Most of the end-of-page cost is layout from box sizes that change on every morph
  frame (nav width, height and top, panel box, column widths), plus blur radii that change on every frame. INFERRED from
  the code lines in the cost map.
- Under the default Normal policy, translate3d/translateZ(0) creates a layer (RenderLayerCompositor.cpp:3898-3899;
  StyleTransformFunctionBase.h:105-116@862f17d). Under Conservative, which applies only under memory pressure
  (:705-718), a z=0 translate is 2D (StyleTranslateTransformFunction.h:63) and gets no layer. CONFIRMED.
- In the nav Lean model the logo costs 1 layout unit per frame as the original and as a 2D `translate` (bar-fixed), and 0 only
  as logo-3d under Normal, where the 3D transform gives it its own layer (10-2x-nav-fixed-size.md:71). Measured, logo-3d
  gave no gain (lag run 39872570182). MEASURED.
- Work leaves the main thread only when a time-based animation drives a property that WebKit hands to Core Animation:
  transform, translate, scale, rotate, opacity, filter and backdrop-filter (CSSProperties.json:12112, 7114, 10263,
  10639; PlatformCAFiltersCocoa.mm:555-570@862f17d). CONFIRMED. Width, height, top, border-radius, gap, clip-path, mask and
  custom properties never do.
- If JS writes the value each frame (here the inherited `--morph`), style recalc and the layer commit stay on the main
  thread whatever the property. INFERRED.
- `nav:logo-3d` was the translate3d test. It moved no Chromium or Simulator count. logo-3d: Chromium 39865303675
  against default 39865294590; Simulator census 39865284565 against base 39864122924. MEASURED.
- Five compositor variants have been tried at the end of the page. None shows a measured end-of-page gain. The only
  phone gain came from `engine.scroll:throttle-lift`, which moves nothing to the GPU (finish 1.17 slow frames per 100
  against 2.46 to 6.56 for the rewrite, verdict 'same' (originals 4.19 / 10.09,
  results/phone/2026-10-24-throttle-lift/summary.md:12)). MEASURED, one person.
- Both engines already skip painting an opacity-0 layer (WebKit RenderLayer.cpp:3365-3376, 6152-6157@862f17d;
  Chromium paint_layer_painter.cc:168-190,424-426@f842f52, ScopedEffectivelyInvisible below opacity 0.0004).
  CONFIRMED. The platform section uses `opacity: var(--morph-fade)` (platform.module.css:13), and `fade(m)` is exactly
  0 for m >= 0.55 (logic.ts:63-66), so its own paint, blur included, is already skipped there.
- The best new same-look move is `morph.columns:final-scale` (candidate 1): lay the columns out once and scale them.
  `platform:fade-hide` needs measurement first (candidate 6).

## Per-part cost map

Code lines are CONFIRMED. Stages are INFERRED. "Sim" is the iOS Simulator lane, which composites on the CPU.

| Part | Per-frame main-thread work | Stage | Measured cost | Variants tried, result |
|---|---|---|---|---|
| morph.tween | rAF writes `--morph`, `data-fw-morph`, `--morph-fade`, `pointer-events`; wheel and touchmove read `getBoundingClientRect`; scroll repin with `scrollTo` (driver.ts:106-117,155-169,205-207) | style, forced layout | pin fight: 5-31 reversals per pass on the phone | `waapi` refuted (nav classes stale, logo jumps). `waapi-scoped` -3745 elements (-6.8 %) on Chromium (39337815445), WebKit not measured. `scroll-lock` is L |
| morph.mount | second non-passive wheel and touchmove pair; `geom()` reads `getBoundingClientRect` per event (index.tsx:39-53,76-81) | input blocking, forced layout | not measured | `band` built, probed clean, touch-to-first-scroll not measured. `shift-dormant` -3 layouts (39325721909) |
| nav | width, height, top, gap, logo left, earn max-width and padding-inline (layout); radius, color-mix background (paint); backdrop blur 20 to 0; earn blur 0 to 10 px (nav.module.css:14-30,122-130,168-182) | style of the whole subtree, layout, paint | Chromium swipe tail Layout.totalObjects 718 orig vs 1554 rewrite (39184646781) | `clip-box`, `bar-fixed`, `logo-3d`: no count moves (clip-box 39872606664, bar-fixed 39873283200, logo-3d 39865303675 (default 39865294590)); mid-morph pixels differ, max delta 220. `earn-no-transition` L. `nav.oofRoot` refuted |
| nav.hitTest | per scroll frame: write `pointer-events`, `elementFromPoint`, restore, `getComputedStyle`, 3x `getBoundingClientRect` (probe.ts:41-67,96-103) | forced style and layout | not measured | `hit-skip`, `elements-skip` built, not measured |
| morph.panel | blur 12 to 0, opacity, scale; box is 100 % of the nav, so it re-lays out each frame (morph.module.css:7-17) | style, layout, software blur paint | 26 % of the open-push paint area (10-21-lag-windows) | `const-bounds`: Sim Composite 100-148 vs 176-181 ms (39760667274), 2 passes. `threaded`: Sim 236-552 vs 151-213 ms, higher (39846909558); phone 5.61, no gain |
| morph.columns | transform keyframes on the compositor; column width follows the backdrop, so 21 images re-lay out and track layers get new surfaces | layout, raster | F4 tile re-setup per width change (source) | `idle-none`: Chromium -3440 layer-frames (39897818039); Sim backing 106 to 90 MB (39897807511) |
| morph.countdown | 1 s interval plus a spring rAF writing transforms on 10 faces per digit; 80 layers | style, composite | F7: 80-160 UIViews at morph start (source, INFERRED) | `hidden-pause` no element drop (39312082945). `one-chain` -243 FireAnimationFrame (39313828270). `strip` (16 layers) not measured |
| platform (fade) | `--morph-fade` restyles the section; blur 0 to 12 px, opacity (platform.module.css:12-13) | style, paint | 83 % of the close-push paint area; Sim RecalculateStyles 259, Layout 169-174 (39731023406) | `fade-threaded`: no fewer style or layout passes (39731104953); held |
| platform (shrink) | card rect read, `--platform-shrink` write | forced layout, paint | premise false, nothing written (39680964944) | `mq` closed |
| platform.sweep | 4 s `background-position` under `background-clip: text` (sweep.module.css:6-20) | paint every frame | not measured | none |
| platform.glint | SMIL `x1`/`x2` on a 94x3.2 SVG gradient (Visuals.tsx:291-292) | SMIL, paint | not measured | none |
| platform.entries | count-up and typing text writes, entry keyframes | layout, paint | not measured | none |
| engine.scroll | one rAF per scroll event; `faithful` interleaves reads and writes (scroll.ts:60-79) | repeated forced layout | `unthrottle`: Sim band runs 163 to 0; phone finish 1.17 (`throttle-lift`) | `batched` not measured at the end |

## What the GPU can and cannot do in WebKit iOS

WebKit @862f17d (trunk; a shipping Safari may differ, INFERRED). Chromium @f842f52.

| Property or technique | Off the main thread on iOS WebKit? | Evidence |
|---|---|---|
| transform, translate, scale, rotate | yes, as a time-based animation | CSSProperties.json:12112,12260,12281,12306 CONFIRMED |
| opacity | yes | CSSProperties.json:7114 CONFIRMED |
| filter, backdrop-filter incl. blur | yes, unless drop-shadow, `url()`, or keyframe function lists differ | CSSProperties.json:10263; PlatformCAFiltersCocoa.mm:555-570; GraphicsLayerCA.cpp:289,1207,3950-3958; GraphicsLayer.cpp:843-844 (lists must match); KeyframeEffect.cpp:1981 CONFIRMED |
| width, height, top, radius, gap, clip-path, mask, custom properties | no | StyleInterpolation.cpp:262; RenderElement.cpp:321-325; StyleDifference.cpp:582 CONFIRMED |
| any value written from JS each frame | no: style and commit run each frame | INFERRED |
| steps(), linear() points, composite add, url() filter, cascade override, progress-based (scroll-driven) timelines, skipped-content animations, size-dependent transforms | fall back to the main thread | KeyframeEffect.cpp:1970-2023 (1972 isSkippedContentAnimation, 1987 size-dependent transform, 2008 progress-based timeline) CONFIRMED |
| translate3d, translateZ(0), will-change | Normal policy (default): creates a layer. Conservative (memory pressure only): a z=0 translate is 2D, no layer | RenderLayerCompositor.cpp:705-718,3898-3899,4008-4011; StyleTransformFunctionBase.h:105-116; StyleTranslateTransformFunction.h:63 CONFIRMED |
| scale of a layer from JS or CSS | GPU-scales the bitmap, no re-raster: root-relative scale updates are off outside LBSE | GraphicsLayerCA.cpp:4378-4387 CONFIRMED |
| visibility: hidden | the layer's content is not painted | RenderLayer.cpp:3715-3717; RenderLayer.h:284 CONFIRMED |
| opacity: 0 | paint skipped for the layer and its non-composited descendants | RenderLayer.cpp:3365-3376 CONFIRMED |
| Chromium filter: blur animation | stays on the main thread | compositor_animations.cc:408-415 CONFIRMED |

Layer cost on iOS: one WKCompositingView per layer in the UI process (RemoteLayerTreeHostIOS.mm:60-75). The backing
store takes width x height x scale² x 4 bytes (RemoteLayerBackingStore.mm:275,288), about 1.1 MB for a 390x80 bar
at 3x. Layers over 1280 px tile (GraphicsLayerCA.cpp:101-102). A size change discards the backing store
(RemoteLayerBackingStore.mm:145-151). Layers that overlap a promoted layer get promoted too
(RenderLayerCompositor.cpp:1335). All CONFIRMED.

## Candidates ranked

Expected gains are INFERRED until the named measurement runs.

1. **`morph.columns:final-scale`** (new, class L). Lay the 5 columns out once at the final panel width and draw each at
   `scale(s(m))` with a per-column translate, so the column box edges match the faithful ones. Leaves the main thread:
   the 21-image re-layout and the new track surfaces per frame (WebKit does not re-raster a scaled layer, see the table).
   Remains: style recalc from `--morph`. Look: image boxes are exact, since the images keep their aspect ratio
   (morph.columns/morph.module.css:36-40); the 12 px gap, the 12 px radius and the 56 px drift scale by s. Lean: column
   edges equal (in the style of `Fw.Parts.MorphConstBounds.paint_eq`) plus bounds such as gap delta at most 12(1 - s);
   pixel check goes to the user's look review. On a 390 px phone the nav width moves only 342 to 350 px at
   nav-expand 1 (nav.module.css:10-20, INFERRED), so s stays above 0.97. Layer risk: none added. Decides: Chromium
   Layout counts, Simulator backing MB and Composite, then the phone.
2. **`nav.hitTest:elements-skip`** (built). One `elementsFromPoint` with no `pointer-events` write. Leaves: the forced
   style recalc that the write-then-read causes on each approach scroll frame. Remains: one hit test. Same look: no
   paint change; needs a Lean proof that the first non-nav element equals the faithful probe result (part.json lists
   only a v1 provenance). Decides: Chromium RecalculateStyles and Layout counts on the approach, then WKTR.
3. **`morph.tween:waapi-scoped`** (built, Lean `Fw.Parts.MorphTweenOpt` waapi_eq_tween, fade_eq). WAAPI drives the
   registered `--morph`; `--morph-fade` stops inheriting. Leaves: the JS writes between thresholds and part of the
   subtree restyle. Remains: style recalc of every element that reads `--morph`. Measured -6.8 % elements on Chromium.
   Decides: WebKit Simulator RecalculateStyles on the morph pass, then the phone.
4. **`morph.countdown:strip`** (built, layerBudget 16). One transform per digit instead of 10 faces. Leaves: 64 of 80
   layers and the UIViews made at morph start (F7). Remains: one spring write per moving digit. Same look needs a Lean
   proof that the strip offset shows the same face as the faithful face transforms, plus the breakpoint gate. Decides:
   Simulator layer count and backing MB, then WKTR layer census.
5. **`morph.mount:band`** (built, Lean `Fw.Parts.MorphListen` band_same, armed_in_band). One merged touch listener,
   passive outside the band. Inside the band, where the end of the page sits, it halves the handler work but stays
   non-passive. Decides: phone touch-to-first-scroll, which has never been measured.
6. **`platform:fade-hide`** (new, needs measurement first). Set `visibility: hidden` on the platform section while
   `fade(m) = 0`, which holds for m from 0.55 on (morph.tween/logic.ts:11,63-66 CONFIRMED). Both engines already skip
   the section's own paint at opacity 0 (see the table). `visibility: hidden` adds a paint skip only for composited
   descendants (`.card`, will-change: transform, platform.module.css:34), whose own backing stores still repaint under
   an opacity-0 parent in WebKit. INFERRED. Same look: Lean theorem that `fade m = 0` makes the section's alpha 0, so
   the pixel equals the backdrop, and that pointer events are already off (0 < 0.05, logic.ts:68-70); breakpoint gate
   on every breakpoint; pixel check at m = 0.5, 0.55, 0.6, 1, delta 0. Limits: keyboard focus inside the hidden
   section changes (behavior, not look); animation phase must keep running under `visibility: hidden` (open
   question 1). Decides first: WebKit Simulator Paint counts for `.card` layers on the open push; build only if they
   repaint.

## Not worth it

- translate3d, translateZ(0) or will-change on the nav, panel or platform: each adds a layer under the Normal policy.
  In the Lean model only the 3D layer drops the logo layout to 0 (a 2D translate keeps 1, 10-2x-nav-fixed-size.md:71);
  `logo-3d` measured no gain (39872570182).
- A GPU form of the nav box (3-slice or 9-slice transforms): radius, height, top, color-mix and backdrop blur all change
  per frame, and 9 slices each need a backdrop-filter layer. clip-path has no Core Animation animation, so style still runs each frame, but a composited layer's clip-path
  change skips repaint (RenderElement.cpp:321-325; RenderLayer.cpp:779-791). The three L
  variants moved no count.
- Rerunning `morph.panel:threaded` or `platform:fade-threaded`: the Simulator moves the blur into CPU Composite, the
  phone showed no gain, Chromium keeps blur on the main thread, and the `--morph` write keeps the style pass. Revisit
  only once a real-GPU lane gives per-part Composite time.
- Pre-blurred copies cross-faded by opacity: doubled layer memory and a look change; both engines already skip the
  platform's paint once its opacity is 0.
- `platform.sweep` on the GPU: `background-clip: text` has no compositor form, and a moving gradient layer cannot be
  clipped to web-font glyphs without a text mask. INFERRED. Its paint is already skipped at opacity 0 (m >= 0.55) unless it sits in a composited descendant.
- `platform.glint` to CSS: a 94x3.2 SVG, small paint. `platform.marquee`: already a transform. Platform shrink: its
  premise is false (39680964944).

## Open questions

1. Do CSS animations, SMIL and the typing loop keep their timeline under `visibility: hidden` in WebKit and Chromium?
   Read the source before building `fade-hide`.
2. Do the composited `.card` layers repaint under the opacity-0 platform section in WebKit? The section's own paint is
   skipped (RenderLayer.cpp:3365-3376); this decides whether `fade-hide` gains anything.
3. Is `m_shouldUpdateRootRelativeScaleFactor` set anywhere for HTML layers on iOS? Candidate 2 assumes not.
4. Do the `<=640` and `<=720` panel media blocks change the phone column width? This sets s for candidate 2.
5. No lane gives per-part GPU time on a real GPU: the Mac Safari lane has pixels only, and the phone has zone totals.

## Sources

- Code: apps/site/src/parts/{nav,nav.hitTest,morph.tween,morph.mount,morph.panel,morph.columns,morph.countdown,platform,platform.glint}/ and their part.json files.
- WebKit @862f17d and Chromium @f842f52 under .cache/upstream/, paths as cited above.
- Notes: 10-22-webkit-render-cost.md, 10-2x-morph-panel-threaded.md, 10-2x-morph-constant-bounds.md,
  10-2x-platform-fade-threaded.md, 10-2x-nav-fixed-size.md, 10-2x-gpu-safari-lane.md, 10-2x-scroll-throttle-parts.md,
  10-2x-morph-reopen.md, 10-2x-smoothness-webkit.md, 10-2x-mac-safari-measure.md.
- research/findings/ledger.json; results/phone/2026-10-24*/summary.md.
