# End-of-page morph on compositor-only layers

Repo 07b1a75be; WebKit 862f17d (paths under `.cache/upstream/WebKit@862f17d/Source/WebCore/`), Chromium f842f52.

## Answer first
* Design: a corner-door FLIP. While a push runs, the nav and the panel stay laid out at their final (m = 1) size, and
  the pill is cut out of that box by four nested rounded clippers that move only by transform. Every value that reads
  `--morph` today becomes a piecewise-linear (PL) track in m on a transform, opacity or filter. Lean generates the knots.
* Flags. Deliverable 2 is a new part `morph.geom` with variant `on`. It drives the tracks from today's tween by
  setting `currentTime`. Deliverable 3 is `morph.tween:geom-timed`, which requires `morph.geom:on`. It starts one Web
  Animation per track per push on a shared start time, with duration 680 ms and easing cubic-bezier(1/3,1,2/3,1). The
  name avoids `morph.end.flip`, where "flip" means a direction reversal.
* Expected class: L. End states (m = 0 and m = 1) are E by construction. Mid-morph frames differ by more than 12 levels
  at moving text edges and at the title wrap on desktop. The variant goes to the user's look review in the look-change
  class, never to `optimized`.
* Expected WebKit effect, INFERRED from the source cited below. Under `geom-timed`, a 680 ms push costs no main-thread
  JS, style, layout or paint per frame from the morph. The push itself costs one style and layout pass plus about 45
  `animate()` calls. Under `morph.geom:on` the per-frame layout and nav/panel repaint go away, and one style pass per
  frame (the `currentTime` write) remains. The pin fight, nav.hitTest per scroll frame and the toolbar throttle are
  outside this design, so felt lag from them stays.

## Chosen design and layer structure
Notation: nav-local coordinates of the final box (Wp by Hp). W, H, T and r are `navWidth`, `navHeight`, `navTop` and
`navRadius` (lean/Fw/Parts/Nav.lean:244-257). The used radius is r^ = min(r, H/2, W/2); on phone it has one kink at
m_k = 12/(vh-52), because the 52 px pill clamps 32 to 26. Offsets x0 = (Wp-W)/2 and y0 = T(m)-T(1) are affine in m.
Precondition: `--nav-expand` is 1 (the width rule at nav.module.css:17-20 reads it).

```
nav            .is-flip: final size; no background, radius, backdrop or clip; layout unchanged per frame
└ K0           2Wp x 2Hp, radius 20, overflow hidden; translate(x0, y0) scale(k), k = r^/20 (1..1.6)
  └ K1         translate(tau1(m))  top-right corner, in K0's scaled frame
    └ K2       translate(tau2(m))  bottom-left
      └ K3     translate(tau3(m))  bottom-right
        └ U    scale(1/k) translate(-sigma(m))   net transform of U's content is the identity, PL-bounded
          ├ G  #ffffff1a, backdrop-filter blur(20(1-m)); extended 4 px up on desktop (top is 16+4m, nav.module.css:14)
          ├ D  #131922, opacity m
          └ W0 nav box content
             ├ bar     .bar translate(0,y0); .actions translate(-x0); logo translate track (quadratic, PL)
             │         lang: `translate` gets the gap term, `transform` the earn-width term
             │         earn E (opacity, blur, translate -8e) > K_L clip (48/24 desktop, 36/18 phone) > label
             └ P       .panel: `translate: 0 d`, `scale: p`, `transform: translate(0,-d)`; opacity o, blur 12(1-o)
                ├ backdrop clip translate(1.06x0, y0) + K_b/U_b for the bottom-right edge
                ├ columns translate; each image translate(0,(s-1)Y_i) scale(s), s = cw(m)/cw1
                ├ veil translate(x0,y0) scale(W/Wp, H/Hp)   (gradient radii are box-relative)
                ├ .center translate(0,d)                    (laid out at the final width)
                └ footer translate(x0, y0+H-Hp); gradient on ::before scaleX(W/Wp); .footerEnd translate(-2x0)
platform .section: opacity fade(m), filter blur(12(1-fade)), knot 0.55
```
* Clip. Only K0 scales. K1 to K3 translate in K0's frame, so tau_i = (corner of the pill)/k minus the clipper size, a
  rational function (a+bm)/(1-cm) per segment. U is the single counter layer (graft from reveal-doors, 3 fewer layers
  than four K/U pairs). The intersection of the four clips is the rounded rect (x0, y0, W, H, r^), and the corners stay
  circles because the scale is uniform.
* Fill. D at opacity m over G over the page equals the premultiplied `color-mix` of nav.module.css:22-26 over the page
  (premultiplied mixing, css/values/color/CSSColorMixResolver.cpp:111, CONFIRMED).
* Earn per engine. The faithful earn follows retargeted transitions (nav.module.css:179-182,
  10-20-earn-transition-retarget.md). On WebKit `transition: padding-inline` starts nothing
  (lean/Fw/Engine/TransitionStart.lean:84 `wk_paddingInline_never`), so WebKit padding is an m-track. Max-width creep
  and the delayed opacity are time tracks from the engine's run model on a 60 Hz grid. A feature probe, not a UA test,
  picks the engine table: it changes padding under `transition: padding-inline` on a hidden element and counts
  `getAnimations()`. Phone constants come from nav.module.css:288-300 (36 px button, 16 px padding, 9.5rem).
* Guards. Every flip layer has `transition: none` under `.is-flip`. A push falls back to today's tween when the nav is
  not `is-on-dark` at push time (the off-dark fills #ffffff7a and #ffffff38 at nav.module.css:57,60 are not modelled)
  or under reduced motion. The title wrap is not guarded; it is a disclosed L item.
* `.is-flip` enters at the first push from rest and leaves only when a close reaches m = 0. Leaving costs one layout,
  which `end_eq` at m = 0 makes invisible. The open state keeps `.is-flip`, so reversals never relayout.

## Same look and the look premise
Exact for every m (Rat identities): the clip outline, fill colour, backdrop blur radius, bar and actions rects,
column, image, veil, centre, footer and backdrop-clip rects, the panel scale centre, panel opacity and blur, platform
fade and blur. Bounded at 1/64 css px or less: U's counter-transform and tau tracks (`chord_sub_eq`) and the logo
(dW h^2/8). Exact at m = 0 and m = 1: every track sits on a knot.

Mid-morph differences, largest first:

| Item | Where | Size (INFERRED unless noted) |
|---|---|---|
| Title wrap: `.title` is min(941, W-176) wide with `text-wrap: balance` (morph.panel/morph.module.css:52-57) | desktop m < 0.32 at 1440, m < 0.52 at 1280; phone if a line falls in an 8 px window | large area, under o <= 0.61 and blur >= 4.7 px |
| Text moved by CA transforms at fractional offsets, rasterized once (root-relative scale updates off, GraphicsLayerCA.cpp:4378-4387, CONFIRMED) | logo, lang, earn, centre and footer text, 1 px outline row | 20-100 levels at glyph edges; v1's four-clipper morph measured 3.2 % of pixels over 8 at m = 0.8 (v1 fixes/compositor-morph/README.md:295-298, MEASURED) |
| Backdrop edge band: CABackdropLayer blur uses inputNormalizeEdges or inputHardEdges at G's bounds, which are the final box (PlatformCAFiltersCocoa.mm:313-325, CONFIRMED) | within about 40(1-m) px inside the pill edge | up to 0.9(1-m) of local backdrop contrast |
| Earn lens when w is below the button height | 1-2 frames, alpha <= 0.27, blur >= 7 px | 10-15 levels |
| CA Gaussian against painted blur | panel, platform, earn | a few levels |
| Image radius 12s instead of 12 | s >= 0.70 desktop, >= 0.978 phone, alpha 0.4o | a few levels |
| Earn on the 60 Hz grid against real frames | earn and lang | under 0.5 px |

Look premise to run (gate task, both engines, every breakpoint band): pin m by pausing the variant's effects at
`currentTime = 1000m` (linear easing) and writing the faithful `--morph = m`, at m in {0, .01, .05, .08, .15, .2, .32,
.5, .55, .8, 1}. Report per region (box edge ring, bar, panel centre, columns, corners, platform) the max delta and the
share of pixels over 12. A region at a given m is E when its max delta is 12 or less. The run must show E at m = 0 and
m = 1 everywhere; any other E is a bonus.

## WebKit acceleration evidence (CONFIRMED by reading, 862f17d)
* Accelerated properties come from `CSSProperty::animationIsAccelerated`; a custom property returns false
  (style/StyleInterpolation.cpp:256-265). That is why `--morph` never reaches Core Animation.
* An effect is accelerable only without steps, linear() points, non-replace composite, a progress timeline, or a
  size-dependent transform next to a size animation (animation/KeyframeEffect.cpp:1987-2017). One non-accelerable
  effect blocks all effects on the element (KeyframeEffectStack.cpp:215-283), so every flip layer is a new wrapper with
  no transitions and explicit end keyframes.
* Transform, filter, backdrop-filter and opacity become CA animations (platform/graphics/ca/GraphicsLayerCA.cpp:1183-1215);
  filter animations are supported (289-292). Matching translate()/scale() lists interpolate per primitive (3883-3914).
* `animationCanBeAccelerated` needs playbackRate 1 and a forward direction (GraphicsLayerCA.cpp:1168-1181), so a
  reversal is a new forward animation, never `reverse()`. A cubic with y outside [0,1] is restricted (1192-1198); ours
  is inside.
* The effect easing is the CA animation-wide timing function and keyframes default to linear (GraphicsLayerCA.cpp:4036-4057).
  That CA applies it across all keyTimes is INFERRED (CA is closed source); a premise checks it.
* Begin time is `CACurrentMediaTime()` at the commit (GraphicsLayerCA.cpp:3462), set on leaf animations at 3493 and on
  transform groups at 3624. Fill backwards maps to CA fill both (4012-4014).
* A completely accelerated running effect does not tick (animation/KeyframeEffect.cpp:2736-2741); its next tick is at
  endTime (animation/AnimationEffect.cpp:391-393). Threaded time-based animations are off by default
  (UnifiedWebPreferences.yaml:8557-8570), so this legacy CA path is the one taken.
* A uniform radius whose clip bounds equal the rect becomes masksToBounds plus cornerRadius, with no shape mask
  (GraphicsLayerCA.cpp:3228-3237). Transform and overflow do not make a backdrop root (rendering/RenderLayer.cpp:667-678).
* WKTR can assert the accelerated set: `internals.acceleratedAnimationsForElement` (testing/Internals.idl:585).
* Chromium composites backdrop-filter animations but not filter blur (compositor_animations.cc:408-420@f842f52), so
  panel, platform and earn blur tick on its main thread, without layout (INFERRED).

## Lean spec to write first (statements)
`Fw.Parts.MorphGeom` (Rat, imports Nav, MorphTween, MorphTweenOpt, NavEarnOpt, NavEarnWebkit, Engine.TransitionStart):
* Types. `AnimProp` is an inductive with only translate, scale, transformList (translate, scale), opacity, blur and
  backdropBlur: the accelerable allowlist by type. `Track` holds sorted knots with `Track.eval`; `Anim` is (element,
  prop, track, easing, composite, rate, direction); `layers v` and `anims v` build the tree above for viewport v.
* `box_eq`: `boxAt v m` = (x0, y0, navWidth, navHeight, min(navRadius, H/2, W/2)), with the phone kink as a knot.
* `cover`: each clipper's scaled extent covers the pill side it does not cut (affine, endpoint lemma).
* `clip_eq`: a point is inside all four clips iff it is inside `rrect (boxAt v m)`, discs as squared distances.
* `chord_sub_eq`: for f = (a+bm)/(1-cm) and A = a+b/c, chord_pq f m - f m = (m-p)(q-m) A c^2 / ((1-cp)(1-cq)(1-cm)).
* `net_err`: for every point in the box and every m, the content offset under K0..U is at most 1/64 px (decide over
  the knot table per band). `logo_err`: at most dW h^2/8 <= 1/64.
* `rect_eq e`: for bar, actions, columns, each image, veil, centre, footer, backdrop clip and panel centre, the
  composed rect equals the faithful rect restated from the CSS rules.
* `fill_eq`: D at alpha m over G over bg equals premultiplied colorMix(#ffffff1a, #131922, m) over bg, per channel.
* `panel_eq`, `fade_eq`: tracks equal clamp((m-0.08)/0.72) with blur 12(1-o), and `MorphTween.fade` with blur.
* `earn_eq eng`: the earn and lang tracks equal NavEarnWebkit (WebKit) or NavEarnOpt (Chromium) runs on the 60 Hz grid.
* `end_eq`: at m = 1 and m = 0 every track equals the faithful value, with net transforms the identity.
* `accelerable v`: for every anim, one effect per (element, prop), the same function-list shape in every keyframe,
  offsets 0 and 1 present and sorted, linear keyframe easing, effect easing linear or a cubic with y in [0,1],
  composite replace, rate 1, forward. `noTransition`: every animated element is in the generated `transition: none` list.
* `memBytes v <= budget v` per band, from the backing census rows.

`Fw.Parts.MorphGeomTimed`:
* Reuse `bezier_eq_ease` (MorphTweenOpt.lean:63) and `solver_exact` (:95).
* `rebase_eval`: eval (rebase tr m0 g) u = eval tr (m0 + (g-m0)u).
* `timed_eq_ideal`: for every push sequence and time t, each track shows eval tr (ideal pushes t), where ideal samples
  the tween at the event time.
* `faithful_gap`: after a reversal, |MorphTween frame value - ideal| <= 3Δ/680 for frame interval Δ ms (the faithful
  push starts from the last frame's value, morph.tween/logic.ts:84-88).
* `reverse_continuous`: the new set at the event time equals the old set there.
* `commit_eq`: the generated goal CSS equals every track's last keyframe.
* `crossTime c`: t = 680(1 - cbrt(1 - (c-m0)/(g-m0))) brackets the first grid ms with tween >= c (golden for Math.cbrt).

Lean generates the knot JSON, the `.is-flip` and goal CSS, and golden vectors for the TS track builder.
## Timed variant
* Start. The capture handler keeps push, taken and armed unchanged (logic.ts:44-95). On a taken push toward g at event
  time e it computes m0 = tween(from, to, e - S) (or the rest value), cancels live animations and timers, writes
  `data-morph-goal = g` (goal CSS sets base values), and calls `el.animate(kf, {duration: 680, easing:
  'cubic-bezier(1/3,1,2/3,1)', fill: 'backwards'})` per track with startTime = e, all in this task. Keyframes are m0,
  every knot strictly between, and g, at offsets (m_k - m0)/(g - m0). ease(s) = 1-(1-s)^3 equals the bezier exactly, so
  the shown m is today's tween (logic.ts:31-41) sampled at event time.
* Reversal. The same path with the new e: cancel and create in the event task, no rAF hop. Residual jump on screen is
  speed times the commit-latency difference between the two sets (RenderLayerBacking.cpp:5060-5062 feeds nothing back);
  a WKTR reversal probe measures it.
* Earn time tracks and threshold timers (is-morphing 0.001, is-on-dark 0.2, earn tabindex 0.4, aria 0.55, platform
  pointer-events, is-expanded 0.92, scene attribute) are scheduled at `crossTime`.
* End. The base style already equals the last keyframe, so `finished` cancels with no flash. A close that reaches 0
  also drops `.is-flip` and writes `--morph: 0`; an open writes `data-fw-morph`, `--morph: 1` and `--morph-fade: 0` once.
  Under reduced motion the push sets the goal and starts nothing, as the faithful push does.

## Tasks
| id | title | depends |
|---|---|---|
| morph-geom | Compositor-only morph geometry as `morph.geom:on`: Lean spec, premises, gate, counts | none |
| morph-timed | Timed driver `morph.tween:geom-timed` on the morph-geom layers | morph-geom landed |

morph-geom writes: `lean/Fw/Parts/MorphGeom.lean`, `lean/Fw/Parts/MorphGeomCounts.lean`,
`lean/scripts/MorphGeomGolden.lean`, the Lean root import line, `packages/contracts/golden/morph-geom*.jsonl`,
`apps/site/src/parts/morph.geom/**` (new part), `apps/site/src/parts/{nav,morph.panel,morph.columns,platform}/`
(`part.json`, `index.tsx`, `*.module.css`, new `geom.*` files), `lean/Fw/Ops/Premise.lean`,
`packages/premise-tests/pages/geom.*.html`, `packages/premise-tests/src/tests.mjs`, `.github/workflows/wktr-fixtures.yml`,
`packages/gate-breakpoints/src/trajectory/registry.mjs`, `research/notes/2026/*-morph-geom-*.md`. Premises: CA timing
across keyTimes, nested cornerRadius clips intersect, backdrop clipped under masked ancestors, every geom element in
`acceleratedAnimationsForElement`. Counts: Chromium and WebKit Simulator per morph frame on CI.
Unit of decision: one (element, property) track. It passes when its Lean statement (exact or bounded) is proved, its
generated keyframes match the golden, and it is in the `accelerable` list. The per-band look report and the counts are
deliverables that are reported, not graded; class L is the expected outcome.

morph-timed writes: `lean/Fw/Parts/MorphGeomTimed.lean`, `lean/scripts/MorphGeomTimedGolden.lean`,
`packages/contracts/golden/morph-geom-timed.jsonl`, `apps/site/src/parts/morph.tween/{part.json,index.tsx}`,
`apps/site/src/parts/morph.tween/geom-timed.*`, `apps/site/src/parts/morph.geom/goal.*` (generated goal CSS),
`lean/Fw/Ops/Premise.lean`, premise pages for shared start and the reversal jump, `research/notes/2026/*-morph-timed-*.md`.
Unit of decision: one push scenario from the Lean push-sequence golden (open, close, reversal at 3 phases). It passes
when the shown m matches `timed_eq_ideal` at sampled times within the premise bound, the end leaves base equal to the
last keyframe, and the WebKit Simulator count shows no morph style, layout, paint or rAF between push and end.

## Rejected designs
| Design | Why not |
|---|---|
| reveal-doors (permanent doors, score 6.1) | rest not E: misses the phone radius clamp, fixed glass #ffffff1a against off-dark fills, 4 px top strip without backdrop on desktop; restructures the nav root for hitTest and measure. Its timed commit, shared-scale doors, `AnimProp` and `chord_sub_eq` are grafted |
| morph.skins (score 4.6) | uniform column scale repeats `morph.columns:final-scale`; earn opacity and lang x modelled as m-functions, which the retargeted transitions refute; its timed refinement claim is false |
| Paint nine-slice of the pill | glass seams and double alpha at joins, 9 backdrop layers, panel content still needs the rounded clip |
| `morph.tween:waapi` (registered `--morph`) | refuted: nav classes stale, logo jumps |
| `morph.panel:threaded`, `:const-bounds`, `platform:fade-threaded` | Composite up, nav and columns still resize per frame, no fewer style passes |
| Per-push wrap guard | balanced breaks can differ mid-range even when W0 and Wp agree; disclosed as L instead |
