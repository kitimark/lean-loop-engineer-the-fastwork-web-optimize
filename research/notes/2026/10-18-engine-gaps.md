---
id: 2026-10-18-engine-gaps
kind: note
title: "Engine research gaps RG1-RG11 (design note R1-R11) closed at the pins"
status: review
created: 2026-10-18
topics: [chromium, webkit, animation, style, hit-testing, scroll-timeline, lean-premises, counts-lane]
---

# Engine research gaps RG1-RG11 at the pins

This note answers the research gaps in `research/notes/2026/10-18-engine-proof-design.md` (list at lines 469-483).
The design note names them R1-R11; PLAN rev 10 names them RG1-RG11 (A33 maps them one-to-one, in order).

**Pins** (`refs/upstream/sources.lock.yaml`):
- Chromium `f842f52` (Chrome Headless Shell 156.0.8078.4, the lane's binary);
- WebKit `862f17d`.

**How the source was read.** From the pinned sparse clones in `.cache/upstream/`, or with
`curl https://raw.githubusercontent.com/<o>/<r>/<sha>/<path>` for files outside the clones. Spec pages were read
through WebFetch.

**Path shorthands used below:**
- `blink/` = `third_party/blink/renderer/`
- `cc/` = `cc/`
- `WebCore/` = `Source/WebCore/`
- `WebKit/` = `Source/WebKit/`

Every Chromium citation is `@f842f52` and every WebKit citation is `@862f17d`, unless stated otherwise.

## Summary

| Gap | Status | Premise it serves | Result in one line |
|---|---|---|---|
| R1 | **OPEN** (value MEASURED) | Mode `everyBeginFrameIsMainFrame` (F-checks only) | No source path forces a main frame per BeginFrame; the requester is not located |
| R2 | CONFIRMED | MT-W (work) | Same restyle set for animated and inline writes: the writer's subtree in both engines |
| R3 | CONFIRMED | MT3: linear `<number>`; registration needed | Linear in both, with different fp forms; unregistered properties flip at 0.5 |
| R3b | CONFIRMED | MT4 flag timing | `[0:a, c:a, c:b, 1:b]` gives b exactly when p ≥ c, in both engines |
| R4 | CONFIRMED | NH-W `hitSkip_work_lt` | Sites listed below; Blink hit-testing also runs pre-paint |
| R5 | CONFIRMED in engines; **lane breaks it** | MT3 clock premise | The zero is the HR-time origin in both engines; the Chromium lane's clock shim makes `performance.now()` virtual |
| R6 | CONFIRMED, small residual OPEN | HP `hidden_pause_eq` work side | Paint skip and animation ticking per hidden form, both engines |
| R7 | O3 CONFIRMED; O2 CONFIRMED for the lane, OPEN for shipping Safari | Mode `threadedTimeBased`, P1 | Lane: threaded scroll-driven on, threaded time-based off |
| R8 | MEASURED (Node golden test) | MT2 fp premise | cx = 1.0 exactly; max diff 3.33e-16 |
| R9 | CONFIRMED that it is **not** vacuous in the Chromium lane | H1 (design C1) | DPR 3 only stops compositing from caring about LCD; LCD text stays enabled on Linux |
| R10 | CONFIRMED | MP (morph.panel) rest premise | Any non-`none` filter, `blur(0)` included, makes a containing block and a stacking context |
| R11 | CONFIRMED | HE (hero.exit) progress premise | progress = offset / range, with engine-specific quantization |

**Tally** (12 items, counting R3b on its own):

| Status | Count | Gaps |
|---|---|---|
| CONFIRMED | 8 | R2, R3, R3b, R4, R5, R7, R10, R11 |
| MEASURED | 1 | R8 |
| CONFIRMED with an open residual | 2 | R6, R9 |
| OPEN | 1 | R1 |

**No open item blocks a theorem**, because every residual premise is carried as a hypothesis. Three items do block
**predictions or lane runs**:
- R5 blocks the lane measurement of variant `waapi`.
- The R6 residual blocks HP's per-frame work prediction for Chromium.
- R9 needs one lane flag before H1 can be discharged for the Chromium lane.

---

## R1. Is every BeginFrame in the lane a main frame?

**MEASURED, what happens.** `packages/measure-chromium/README.md:144-150` reports the fixture
`fixtures/anim-compositor/index.html`:
- `#a`: transform, 2 s, infinite, with `will-change`;
- `#b`: opacity, 3 s, infinite.

The counts are Paint 0, Layout 0 and `cc.Commit` 0, but `UpdateLayoutTree` 120 with 2 elements per frame. So a
main frame runs on every BeginFrame even though both animations are composited.

**How the lane runs** (CONFIRMED, `packages/measure-chromium/src/run.mjs`):
- `:41` passes `--enable-begin-frame-control --run-all-compositor-stages-before-draw`, without
  `--disable-threaded-animation`.
- `:63` creates the target with `enableBeginFrameControl`.
- On each frame:
  - `:108` advances the shim clock with `Runtime.evaluate`;
  - `:114` sends `HeadlessExperimental.beginFrame {frameTimeTicks: T0+vt}`, with T0 = 5,000,000 ms (`:29`).

**Ruled out by reading the source** (CONFIRMED):
- **Blink does not request per-frame service for a composited animation.**
  - `blink/core/animation/animation.cc:3376-3400`: `TimeToEffectChange` returns 0 only when
    `!HasActiveAnimationsOnCompositor()` in the active phase.
  - `keyframe_effect.cc:798-846`: otherwise the next wake-up is the end of the active phase, or the next iteration
    when iteration events are needed.
  - `document_timeline.cc:111-135` turns delays ≥ 0.04 s into a timer wake-up, not a frame request.
- **Headless BeginFrame does not force a main frame.**
  - `headless/lib/browser/headless_web_contents_impl.cc:533-574` only issues an external BeginFrame (normal args).
  - `cc/scheduler/headless_scheduler_state_machine.cc` always subscribes to BeginFrames and triggers the deadline at
    once. `cc/scheduler/scheduler.cc:66` selects it under `wait_for_all_pipeline_stages_before_draw`.
  - A main frame still needs `needs_begin_main_frame` (`cc/trees/proxy_main.cc:1036-1040`).
- **Why it shows 2 elements whenever a main frame runs.** `keyframe_effect.cc:739-742`: `ApplyEffects` marks the
  target `SetNeedsAnimationStyleRecalc` whenever its sampled value changed. This holds even when the animation also
  runs on the compositor.

**Not located: who asks for the main frame on every frame.** Candidates read so far:
- `PendingAnimations::Update` (`document_animations.cc:233-236`, `pending_animations.cc:62-200`), which returns
  true while it waits for a compositor start;
- `animation_timeline.cc:183-196`.

Neither path stays true in a steady state (INFERRED).

**What closes R1.** One CI run of the fixture with `FW_EXTRA_CATEGORIES=cc`, then read:
- the `"location"` arg of `LocalFrameView::ScheduleAnimation` (`blink/core/frame/local_frame_view.cc:4031-4039`);
- the `ProxyMain::SetNeedsAnimate` instants (`cc/trees/proxy_main.cc:715-723`).

**Premise.** This is the lane Mode premise `everyBeginFrameIsMainFrame`, which only the F-check predictions use. It
stays a **measured** premise: the value is MEASURED and only its cause is open. No theorem depends on it.

## R2. Custom-property fan-out, and whether animated and inline writes restyle the same set

### Blink (CONFIRMED)

**How a change in inherited variables fans out:**
- `blink/core/style/computed_style.cc:470-478`: when the inherited variables differ, the result is `kInherited` if
  the element has variable references or declarations, and `kIndependentInherited` otherwise.
- `blink/core/dom/element.cc:5608-5625` (`ApplyComputedStyleDiff`): `kInherited` becomes `kRecalcChildren`, and
  `kIndependentInherited` becomes `kIndependentInherit`.
- This diff runs inside `Element::RecalcOwnStyle` (`:5662`; `ComputeDifference` at `:5750`, apply at `:5943`)
  whatever the reason for the recalc was.

**Animated write:** `element.cc:7419-7432`, `SetNeedsAnimationStyleRecalc` → `kLocalStyleChange` with reason
`kAnimation`.

**Inline write:**
- `element.cc:12620-12624`: `InlineStyleChanged` with `only_changed_independent_properties = false`;
- `element.cc:13300-13306`: → `kLocalStyleChange` with reason `kInlineCSSStyleMutated`.

**Per-element cost.** The base-computed-style shortcut (`blink/core/css/resolver/style_resolver.cc:1380-1389`) is
disabled when the element animates custom properties: `CanReuseBaseComputedStyle` returns false on
`IsAnimatingCustomProperties` (`:2925-2940`). So the animated path does a full cascade, like the inline path, and
the per-element cost is about equal.

### WebKit (CONFIRMED)

**How a change in inherited variables fans out:**
- `WebCore/style/StyleChange.cpp` `determineChanges` compares `nonFastPathInheritedEqual`
  (`style/computed/StyleComputedStyle.cpp:285-300`).
- That comparison covers `m_inheritedRareData`, which holds `customProperties`
  (`style/computed/data/StyleInheritedRareData.h:153`). An inequality gives `Change::Inherited`.
- `style/StyleTreeResolver.cpp:283-315` (`computeDescendantsToResolve`) turns it into `Children`.
- `:1185-1205`: under `Children`, each child is resolved fully unless a fast-path inherit applies.

**The two write paths:**
- Animated (`AnimationInvalid`) resolves as `AnimationOnly` (`:1173-1179`). It reuses the last style-change-event
  style (`:180-182`), which is cheaper per element.
- Inline (`InlineStyleInvalid`) resolves as `FullWithMatchResultCache`.
- Both paths go through `resolveElement` (`:325`) → `createAnimatedElementUpdate` (`:346`, defined at `:811`) →
  `determineChanges` (`:947`) → `computeDescendantsToResolve` (`:355`).

### Result

**The restyle set is the same for both write paths in both engines** (CONFIRMED): the writer plus every descendant
that inherits the property.
- Subtrees that redeclare the property stop the fan-out (INFERRED from the recursion).
- A registered property with `inherits: false` does not fan out (INFERRED: Blink keeps it in the non-inherited
  variables).
- Per-element cost differs only in WebKit, where the animated path is cheaper.

**Premise.** This discharges MT-W's "same set" premise. A work theorem stated as "≤ componentwise on the restyle
count" holds in both engines. A strict per-element cost claim would hold for WebKit only.

## R3. Registered `<number>` interpolation; unregistered properties are discrete

### Blink (CONFIRMED)

**Registered `<number>`:**
- `blink/core/animation/interpolation_types_map.cc:111-114` takes the interpolation types from the registration.
- `:529-531`: `<number>` maps to `CSSNumberInterpolationType`.
- `:572-602`: the list ends with `CSSDefaultInterpolationType`.

**Unregistered properties:**
- They get only `CSSDefaultInterpolationType` (`:490-499`), so pairwise conversion fails.
- `invalidatable_interpolation.cc:184` then builds a `FlipPrimitiveInterpolation`.
- `primitive_interpolation.h:129-146`: the flip yields `fraction < 0.5 ? start : end`.

**The number formula** (`interpolable_value.cc:105-115`): `p == 0 || from == to` → from; `p == 1` → to; otherwise
`from*(1-p) + to*p`.

### WebKit (CONFIRMED)

**Registered `<number>`:**
- `WebCore/style/StyleInterpolation.cpp:69-77`: numeric syntax values go to `blend`.
- `style/values/primitives/StylePrimitiveNumericTypes+Blending.h:36-53`: p = 0 → from, p = 1 → to, otherwise
  `WebCore::blend` clamped to the range.
- `platform/animation/AnimationUtilities.h:98-108`: with Replace, that is `from + (to - from) * progress`.

**Unregistered properties:** every other case is discrete, `progress < 0.5 ? from : to`
(`StyleInterpolation.cpp:157-177`). INFERRED: unregistered values are token data, not syntax values, so they take
this branch.

### Premise

Both formulas are exact at the endpoints and equal in ℚ. In fp they differ by a few ulps, inside MT2's bound.

**Plan change.** MT3's premise should name both forms: WebKit $a+(b-a)p$ and Blink $(1-p)a+pb$, with
$p\in\{0,1\}$ exact. "Registration is required" is CONFIRMED in both engines.

## R3b. Where the discrete flip falls for keyframes `[0:a, c:a, c:b, 1:b]`

### Blink (CONFIRMED)

- `blink/core/animation/keyframe_effect_model.cc:567-626` builds one record per pair of adjacent keyframes, over
  `[start_offset, end_offset)`:
  - the first record extends to −∞ and the last to +∞;
  - zero-length pairs are dropped (`apply_from != apply_to`).
- `interpolation_effect.cc:9-39`: a record is active iff `apply_from ≤ fraction < apply_to`. Inside it, the local
  fraction is `(fraction - start)/(end - start)` after keyframe easing.
- `keyframe_effect.cc:719,724`: the effect samples with `Progress()`, the iteration progress after the effect's
  easing.

### WebKit (CONFIRMED)

- `WebCore/animation/KeyframeInterpolation.cpp:84-120` follows the Web Animations procedure: the interval starts at
  the last keyframe with offset ≤ p (and < 1) and ends at the next keyframe.
- `:192-205`: the interval distance, then the keyframe's timing function.

### Result

For `[0:a, c:a, c:b, 1:b]`, the value is **a for p < c and b for p ≥ c, in both engines**. The flip is inclusive at
c (CONFIRMED).

**Premise.** MT4's flag is $[\mathrm{ease}(i) \ge c]$. The original site code uses strict `>`, so the two differ
only at an exact tie. MT4 must either state ≥ or carry "no sample lands exactly on c" as a premise.

## R4. Forced style, layout and hit-test sites

| API | Chromium (Blink) | WebKit |
|---|---|---|
| `getBoundingClientRect` | `blink/core/dom/element.cc:3542-3546`: `UpdateStyleAndLayoutForNode(this, kJavaScript)`, style + layout | `WebCore/dom/Element.cpp:2086-2103`: `updateLayoutIfDimensionsOutOfDate(*this, {Left, Top, Width, Height, IgnoreOverflow})`, a conditional style + layout |
| `getComputedStyle(...).x` | `blink/core/css/css_computed_style_declaration.cc:256-305`: style only (`UpdateStyleAndLayoutTreeForElement`, `:304`); `:308-332`: layout only for `IsLayoutDependent` properties; `:340-356` call both | `WebCore/style/StyleExtractor.cpp:184-207`: `updateStyleIfNeededForProperty` flushes style only if the property's style is invalid; `:430-452`: layout (`updateLayoutIgnorePendingStylesheets`) if `isLayoutDependent` (`:289`), the element is in a shadow tree, or a subframe has viewport media queries or container queries. Custom properties: `css/CSSComputedStyleDeclaration.cpp:130` (style only) |
| `elementFromPoint` | `blink/core/dom/tree_scope.cc:268-282` → `HitTestInDocumentImpl` (`:246-261`) → `UpdateStyleAndLayout(kHitTest)` (`:232`). Then `blink/core/layout/layout_view.cc:123-147` (`LayoutView::HitTest`) runs `UpdateAllLifecyclePhasesExceptPaint(kHitTest)`, i.e. style + layout + **pre-paint**. `HitTestNoLifecycleUpdate` emits the `HitTest` trace event, counts `hit_test_count_`, and has a hit-test cache keyed by DOM-tree version | `WebCore/dom/TreeScope.cpp:366-375`: `updateLayout()` when client coordinates are layout-viewport-relative; `:400-457` → `WebCore/dom/Document.cpp:11532-11552` (`Document::hitTest`): `updateLayoutAndStyleIfNeededRecursive()` if `allowsAnyFrameContent`, else `updateLayout()`, then the render-layer hit test |

All rows are CONFIRMED.

**Premise.** This discharges NH-W's site list. Every call is a no-op when the tree is clean. The cost of a call is
the dirty work it flushes, plus one hit test for `elementFromPoint`.

One Chromium detail matters for `hitSkip_work_lt`: a hit test after a style-only change also runs **pre-paint**,
so the "skip" side saves the pre-paint walk as well. Each hit test is countable through the `HitTest` trace event.

## R5. Document timeline zero equals the `performance.now()` origin

### Blink (CONFIRMED)

**The timeline:**
- `blink/core/animation/document_timeline.cc:150-157`: `CalculateZeroTime` returns the loader's
  `ReferenceMonotonicTime()` plus `origin_time_`.
- `origin_time_` defaults to zero (`document_timeline.h:65`; the document creates its timeline that way,
  `blink/core/dom/document.cc:1035`).
- `:170-181`: current time = (animation-clock time − zero) × rate.

**`performance.now()`:**
- `blink/core/timing/window_performance.cc:296-304`: the time origin is the same
  `loader->GetTiming().ReferenceMonotonicTime()`.
- `performance.cc:1354-1356`: `now()` is `TimeTicks::Now()` relative to it.
- `performance.cc:1327-1345`: the result is clamped to the coarsened resolution.

**rAF:** `blink/core/page/page_animator.cc:135-142` passes the timeline's current time as the rAF timestamp.

### WebKit (CONFIRMED)

**The timeline:**
- `WebCore/animation/DocumentTimeline.cpp:58-60` creates the timeline with origin 0 s.
- `:130-138`: current time = controller time − origin.
- `AnimationTimelinesController.cpp:330-333`: the controller time is `window->nowTimestamp()`.

**`performance.now()`:**
- `page/LocalDOMWindow.cpp:823-826`: `nowTimestamp()` is `performance()->nowInReducedResolutionSeconds()`.
- `page/Performance.cpp:159-171`: `now()` reads the same function, `reduceTimeResolution(MonotonicTime::now() - m_timeOrigin)`.

**Per frame:** the time is cached (`AnimationTimelinesController.cpp:335-381`), and `:124-129` says it "has to match
the rAF timestamp".

### The Chromium lane breaks the premise (CONFIRMED)

`packages/measure-chromium/src/clock-shim.js@70c3370` makes `performance.now()` return the virtual `vnow`
(`:2-5`, `:12`, `:28-29`), and hands `vnow` to rAF callbacks (`:65-69`). `document.timeline` stays native:
- each frame's time is `T0 + vt` (T0 = 5,000,000 ms, `run.mjs:29`), minus the document's real time origin;
- so it differs from `vnow` by a per-run constant that is not zero.

A WAAPI animation started with `startTime := performance.now()` would therefore start far in the past or the
future, and finish at once or never begin.

The WebKit lanes (Simulator, WKTR) do not use this shim, so the premise holds there (INFERRED from
`packages/measure-wktr/src/wktr.mjs`, which only sets a test header).

**Premise.** MT3's clock premise is discharged for both engines. **It does not hold in the Chromium lane**, and the
`waapi` variant cannot be counted there until one of these fixes lands:
- (a) the variant takes `startTime` from `document.timeline.currentTime`, which is what the proof's $o$ means;
- (b) the shim also virtualizes `document.timeline`, which is hard because the native animation clock is the
  BeginFrame time;
- (c) the shim maps `performance.now()` onto the native timeline: `vnow := document.timeline.currentTime` at frame
  start.

The lead decides. (a) keeps the proof and the variant identical in both engines.

## R6. Hidden states: which skip paint, and whether their animations tick

### Paint (CONFIRMED)

**Blink:**

| Hidden form | Paint behaviour | Source |
|---|---|---|
| opacity below 0.0004 | Painted as "effectively invisible"; its chunks do not draw, so its layer is not drawable | `blink/core/paint/paint_layer_painter.cc:168-191` (`PaintedOutputInvisible`), used at `:424-426`; `blink/platform/graphics/paint/paint_chunk.h:133-135` (`DrawsContent`) |
| visibility hidden | The box itself skips painting | `blink/core/paint/box_painter.cc:58` |
| content-visibility hidden or auto, off-screen | The display lock prevents paint | `LockedAncestorPreventingPaint`, used at `blink/core/animation/animation.cc:3938` |

The opacity rule has exceptions: it does not apply with `will-change: opacity`, with a running opacity animation,
or with a backdrop-filter.

**WebKit:**

| Hidden form | Paint behaviour | Source |
|---|---|---|
| opacity exactly 0 | The layer and its subtree return early | `WebCore/rendering/RenderLayer.cpp:3365-3376` (`paintLayerWithEffects`) |
| visibility hidden | The layer has no visible content, so it is not visually non-empty; individual box phases also check `usedVisibility()` | `WebCore/rendering/RenderLayer.cpp:6142-6157` (`isVisibilityHiddenOrOpacityZero`, `isVisuallyNonEmpty`); `RenderBox.cpp:2058,2068` (mask phases), among others. Not traced into every painter (INFERRED for text and backgrounds) |

The opacity-0 early return has exceptions: accessibility-region paints and event-region collection still paint.

### Ticking

**Blink** (CONFIRMED):
- **Skipped subtrees.** CSS animations and transitions in a display-locked subtree do not update per frame
  (`animation.cc:3283-3285`, `:3928-3943`). Only animations with an owning element qualify:
  `animation.h:146` returns null by default, and `css/css_animation.h:30` and `css/css_transition.h:28` override
  it. So **script (WAAPI) animations still tick**.
- **Composited animations whose target does not paint.**
  - If the target has no composited property node, the compositor check sets `kAnimationHasNoVisibleChange`
    (`compositor_animations.cc:491-495`, `:514-572`; the comment at `:567` says "hidden animations that do not
    paint").
  - If that is the only failure reason, `animation_has_no_effect_` is set (`animation.cc:860-865`).
  - `TimeToEffectChange` then skips per-frame main ticking (`:3389-3393`).
- **Animations that cannot be composited** (custom properties, layout properties) tick every frame whatever the
  visibility. Neither `TimeToEffectChange` nor the timeline checks visibility.

**WebKit** (CONFIRMED):
- **Skipped subtrees.** Style-originated animations on skipped content are skipped in the timeline update
  (`WebCore/animation/AnimationTimelinesController.cpp:150`; `WebAnimation.cpp:1947-1956`) and cannot be
  accelerated (`KeyframeEffect.cpp:1972`). Script animations still tick.
- **No renderer.** An effect whose target has no renderer (display none, not display contents, not animating
  `display`) does not tick continuously (`KeyframeEffect.cpp:2733`).
- **Everything else** ticks continuously unless it is completely accelerated (`:2724-2745`). That includes
  visibility hidden and opacity 0, because they keep their renderer.

### Residual (OPEN)

Which hidden forms in Blink actually remove the composited property node, and so get the no-effect skip, is
INFERRED only. It covers an opacity-0 ancestor, `visibility: hidden` and a clipped/offscreen element.

**What closes it.** One CI fixture: a composited marquee under each hidden form. Read
`compositeFailedBits` (bit 17) and `UpdateLayoutTree` per frame.

**Premise.** HP's visual theorem is independent of R6, because a hidden box contributes nothing to the scene. HP's
**work prediction** is now CONFIRMED in its shape: pausing saves main-thread ticks only for animations that would
otherwise tick. Those are:
- any non-composited animation in both engines;
- in WebKit, every animation with a renderer that is not completely accelerated.

The residual only decides whether a *composited* Chromium marquee under opacity 0 already costs nothing. The design
note's F1 says a composited marquee costs style 1 per frame, which links back to R1.

## R7. WebKit O2 and O3

### O2: threaded animation preferences

`WTF/Scripts/Preferences/UnifiedWebPreferences.yaml`:

| Preference | Status | WebKit default | Lines |
|---|---|---|---|
| `ThreadedScrollDrivenAnimationsEnabled` | stable | true | 8518-8531 |
| `ThreadedTimeBasedAnimationsEnabled` | preview | false | 8557-8570 |

What the statuses mean (`:34-42`): **preview** = "ON by default in Safari Technology Preview and test
infrastructure. OFF by default elsewhere. May be enabled automatically by clients."

`ENABLE_THREADED_ANIMATIONS` is 1 on Cocoa (`WTF/wtf/PlatformEnableCocoa.h:904-905`). All CONFIRMED.

**WKTR lane** (CONFIRMED):
- WebKitTestRunner enables all experimental features by default (`Tools/WebKitTestRunner/Options.h:52`,
  `TestController.cpp:1415-1419`).
- Our lane passes `--no-enable-all-experimental-features` (`packages/measure-wktr/src/wktr.mjs:57`, commit
  8473028), which `Options.cpp:150-153` honours.
- So the lane runs the WebKit defaults: scroll-driven animations threaded, time-based animations on the legacy
  `GraphicsLayerCA` path.
- Without that flag, the lane would run threaded time-based animations, unlike shipping Safari.

**Shipping Safari stays OPEN.** "May be enabled automatically by clients" means the WebKit source cannot settle it.

**What closes it:** read Safari's Feature Flags settings on the Simulator once, or match a WKTR count against a
Simulator Safari count for the same fixture.

### O3: how a Some-state effect is split (CONFIRMED)

- `WebCore/animation/KeyframeEffect.cpp:1736-1768` classifies the effect's properties into None, Some or All
  accelerated.
- On the threaded path, `platform/animation/AcceleratedEffect.cpp:250-270` copies **only** the accelerated
  properties (`Style::Interpolation::isAccelerated`, minus disallowed ones) into the `AcceleratedEffect`.
- `KeyframeEffect.cpp:2724-2745` (`ticksContinuouslyWhileActive`): a Some effect ticks the main thread every frame.
  Only an All effect running accelerated stops ticking, and on the threaded path only if it has no disallowed
  properties.

So **a Some effect runs its accelerated properties off the main thread and its other properties on the main thread,
every frame**.

**Premise.** Mode `threadedTimeBased = false` holds for the WKTR lane by construction. For shipping Safari it is a
premise (O2). P1 (threaded scroll-driven animations) holds in the lane. O3 gives the WebKit per-frame cost rule for
mixed effects: main ticks iff not (All ∧ running accelerated).

## R8. The fp tie in the morph curve

**MEASURED in Node**: `apps/site/src/parts/morph.tween/curve.golden.test.ts` on `main`, from commit 5352ca8
(task morph-tween-curve). The test compares the engines' cubic-bezier solve in double against $1-(1-x)^3$:
- the max difference is 3.33e-16;
- cx = 1.0 exactly;
- Newton exits on the first step.

**Premise.** This discharges MT2's fp premise. It is a Node measurement of the engines' algorithms, transcribed
from `ui/gfx/geometry/cubic_bezier.cc` and WebKit's `UnitBezier.h`, as cited in the test header. It is not a
browser run.

## R9. LCD text at DPR 3 in the lane

### Chromium (CONFIRMED)

**What DPR 3 does:**
- `blink/platform/widget/widget_base.cc:2014-2035` (`ComputeLCDTextPreference`) returns `kIgnored` when the device
  scale factor is ≥ 1.5.
- DevTools emulation (our `deviceScaleFactor: 3`) puts the emulated factor into the widget's screen info
  (`blink/core/frame/screen_metrics_emulator.cc:119-122`, `:158-167`).
- The widget then recomputes the preference (`blink/core/frame/web_frame_widget_impl.cc:5517-5532`).

**What DPR 3 does not do:**
- That preference only stops *compositing decisions* from caring about LCD text. It does not turn LCD text off.
- `cc/layers/picture_layer_impl.cc:693-744` still allows LCD text per layer when `settings.can_use_lcd_text` is set
  and the layer is opaque and pixel-aligned.
- `blink/platform/widget/compositing/layer_tree_settings.cc:340` sets `can_use_lcd_text` from
  `IsLcdTextEnabled()`.
- `content/renderer/render_thread_impl.cc:597-609` makes that **true on Linux** unless `--disable-lcd-text` is
  passed.

So C1/H1 is **not vacuous** in the Chromium lane: a text layer that moves between paths (an opaque layer versus its
own non-opaque layer) can change its antialiasing.

Whether glyphs really rasterize with subpixel AA also depends on the font render parameters of headless Linux. That
is not read (OPEN), and the flag below makes it moot.

### WebKit iOS (INFERRED)

`WebCore/platform/graphics/coretext/FontCascadeCoreText.cpp:337-339`: on iOS, WebKit never sets CoreGraphics font
smoothing (`UNUSED_VARIABLE(shouldSmoothFonts)`). iOS has no subpixel text AA, so H1 holds for WebKit.

### Premise

H1 stays a hypothesis for Chromium. Add `--disable-lcd-text` to the lane's Chromium flags (`run.mjs:41`), and H1
holds by construction in the lane. iOS has no LCD text, so the lane then matches the phone better, not worse.

## R10. Filter as containing block and stacking context (`blur(0)` versus `none`)

**Spec** (CONFIRMED, https://drafts.csswg.org/filter-effects-1/#FilterProperty): "A computed value of other than
none results in the creation of a stacking context". A value other than none also creates "a containing block for
absolute and fixed positioned descendants unless the element it applies to is a document root element in the
current browsing context."

### Blink (CONFIRMED)

- `blink/core/style/computed_style.h:540`: `HasFilter()` means the operation list is not empty, and `blur(0)` is
  one operation.
- `:2185-2187`: `HasNonInitialFilter()` is `HasFilter()` or `will-change: filter`.
- **Fixed container:** `blink/core/layout/layout_object.cc:2014` (`ComputeIsFixedContainer`), except for the
  document element.
- **Absolute container:** it derives from the fixed container (`:2066-2069`).
- **Stacking context:** `computed_style.h:2224-2228` (`HasStackingGroupingProperty`), used by
  `computed_style.cc:2977-2978`.

### WebKit (CONFIRMED)

- **Containing block** for out-of-flow descendants: `WebCore/rendering/RenderElementStyleInlines.h:72`
  (`!style.filter().isNone() && !isDocumentElementRenderer()`, inside `mayContainOutOfFlowPositionedObjects`).
  That function feeds both `canContainAbsolutelyPositionedObjects` and `canContainFixedPositionObjects` (`:80-93`).
- **Stacking context:** `WebCore/style/StyleAdjuster.cpp:386` (`shouldTreatAutoZIndexAsZero`, applied at
  `:584-588`) and `rendering/RenderLayer.cpp:612` (`canCreateStackingContext`).
- **Grouping:** `RenderElementStyleInlines.h:102` (`createsGroupForStyle`).

### Premise

Swapping `blur(0)` for `none` at rest is **E (same scene) iff no descendant**:
- is `position: fixed`, or is `position: absolute` with this element as its nearest positioned-or-filter ancestor;
- and the stacking order of the subtree's z-indexed descendants is unchanged.

That is exactly MP's stated premise, now CONFIRMED to be both necessary and sufficient on the containing-block and
stacking side. The premise is checked per part by PL0/PL2.

## R11. ScrollTimeline progress formula

**Spec** (CONFIRMED, https://drafts.csswg.org/scroll-animations-1/#scroll-timeline-progress):
- progress = scroll offset ÷ (scrollable overflow size − scroll container size);
- the timeline is inactive when the 0 % and 100 % positions coincide;
- its duration is 100 % (#scrolltimeline-interface).

### Blink main thread (CONFIRMED)

- `blink/core/animation/scroll_timeline.cc:145-173`:
  - offset = |scroll offset| along the axis;
  - range = end − start, with start 0 and end = maximum − minimum scroll offset
    (`scroll_snapshot_timeline.cc:329-338`);
  - the timeline is active only if range > 0.
- current time = `base::Microseconds(offset·16)` and duration = range·16/1000 ms
  (`kScrollTimelineMicrosecondsPerPixel = 16`, `cc/animation/scroll_timeline.h:85`).
- `base::Microseconds` stores int64 microseconds (`base/time/time.h:918-920`), so main-thread progress is
  $\lfloor 16\,o\rfloor / (16\,R)$. The truncation of the double-to-int64 conversion is INFERRED from saturated
  conversion.

### cc compositor (CONFIRMED)

`cc/animation/scroll_timeline.cc:126-150`: progress = $\mathrm{round}(16\,o)/\mathrm{round}(16\,R)$. A reversed
direction uses $R - o$.

### WebKit (CONFIRMED)

- **Main thread:** `WebCore/animation/ScrollTimeline.cpp:383-397` computes progress = distance / range as a
  percentage. `:258-270` reads the offsets as float from `ScrollableArea::scrollOffset()`, and `ScrollOffset` is an
  `IntPoint` (`WebCore/platform/ScrollTypes.h:49`). So main-thread progress is quantized to whole CSS pixels. It is
  clamped to [0, max] when max > 0.
- **UI process (threaded):** `WebKit/UIProcess/RemoteLayerTree/RemoteProgressBasedTimeline.cpp:63-74` uses the
  scrolling node's fractional `clampedCurrentScrollOffset()`, with the same formula.

### Premise

HE needs $p(o) = o/R$ up to an engine quantum:

| Engine side | Bound on the progress error |
|---|---|
| Chromium, main thread or compositor | at most $1/(16R)$ |
| WebKit, main thread | below $1/R$ |
| WebKit, UI process | none (float, exact up to fp) |

Main and compositor can therefore disagree by one quantum at the same offset. HE stays **E-s**: exact for the value
function of the quantized progress, with the quantum as the stated premise. `exitOpacity_linear` composes with it
directly.

---

## What this changes in the plan

| Section | Change |
|---|---|
| PLAN §4.7, MT3 premises | Replace "$a+(b-a)p$" with "WebKit $a+(b-a)p$, Blink $(1-p)a+pb$, endpoints exact" (R3). Mark "registration required" and the timeline-origin premise CONFIRMED in both engines (R5). |
| PLAN §4.7, MT4 | The engines flip at $p \ge c$ (inclusive) (R3b). Either state the flag as $\ge$, or add the premise "no sample lands exactly on c". |
| PLAN §6 (Chromium lane) and the work graph | **New blocker for `morph-tween-waapi` lane counts:** the clock shim makes `performance.now()` virtual while `document.timeline` stays native (R5). Recommend fix (a): the variant takes `startTime` from `document.timeline.currentTime`. The lead decides. |
| PLAN §6 (Chromium lane flags) | Add `--disable-lcd-text` to `run.mjs:41`, so H1 holds by construction in the lane (R9). Note in §4.7 that H1 is not vacuous at DPR 3 in Chromium. |
| PLAN §4.7, MT-W | Same restyle set CONFIRMED (R2). State the work theorem on the restyle count, not on per-element cost (WebKit's animated path is cheaper per element). |
| PLAN §4.7, NH-W | Use R4's site table. In Chromium, a hit test also runs pre-paint; count the `HitTest` trace event. |
| PLAN §4.7, HP | The visual theorem is unaffected. The work prediction is per engine and per form (R6 tables). Add the R6 residual fixture (composited marquee under each hidden form, bit 17) to the CI check list. |
| PLAN §4.7, MP | The containing-block and stacking-context premise is CONFIRMED (R10). The premise text stays as written. |
| PLAN §4.7, HE | Replace "cite needed" with the R11 formulas and quanta: Chromium 1/(16R), WebKit main 1 px, WebKit UI process float. |
| PLAN §4.7, Mode | `threadedTimeBased = false`, `threadedScrollDriven = true` for the WKTR lane by construction (R7/O2). Shipping Safari stays a premise. Keep `--no-enable-all-experimental-features` in `wktr.mjs`, and say why. `everyBeginFrameIsMainFrame` stays a MEASURED premise; R1 closes with one `cc`-category trace run. |
| PLAN §12, research gaps | Mark RG2, RG3, RG3b, RG4, RG5, RG7 (O3), RG10, RG11 CONFIRMED and RG8 MEASURED. Keep RG1, RG6 (residual), RG7 (O2 for Safari) and RG9 (headless font parameters, moot with the flag) open, each with its closing step above. |
