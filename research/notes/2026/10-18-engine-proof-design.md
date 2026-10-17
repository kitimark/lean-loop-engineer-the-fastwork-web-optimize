---
id: 2026-10-18-engine-proof-design
kind: note
title: "Engine proof design: a Lean render-pipeline model per engine, visual-equivalence and work-dominance theorems per optimization, and the 2-day task list"
status: review
created: 2026-10-18
topics: [lean, rendering, chromium, webkit, visual-equivalence, work-dominance, morph-tween, ci-validation, work-graph]
---

# Engine proof design: original vs optimized, same look and less work, proved in Lean

**Question (user direction 2026-10-18).** For each animation or rendering optimization, how do we prove two things
in Lean, from engine source rather than device measurement?
- (1) The optimized part looks the same as the original part.
- (2) The engine does less work.

**Inputs.** The three notes of 2026-10-18 (Chromium pipeline, WebKit pipeline, optimization inventory) and the
Lean modules already in the repo.

**Citation format.**
- Engine code: `path:line@sha7`, from the pinned clones `chromium@f842f52` and `WebKit@862f17d`.
- Repo files: `@56d3f96`.
- `B/` = `third_party/blink/renderer/`, `WC/` = `Source/WebCore/`.
- "(note C §x)", "(note W §x)" and "(note I §x)" point to the Chromium, WebKit and inventory notes. Their citations
  are not repeated here.
- Every line I re-read myself for this note says "re-read".

## 0. Answer first

- **One shared core and two engine tables.**
  - `Fw.Engine.Core` defines a stage type, a per-frame work vector over the stages, a per-frame *union* of the
    stages each change dirties, and the thread split.
  - `Fw.Engine.Chromium` and `Fw.Engine.WebKit` give each engine's map from a property change (and the target's layer
    state) to the stages it dirties. Every row cites a CONFIRMED engine line.
  - `Fw.Engine.Visual` defines the observable: a *scene* of boxes, each with geometry, paint key, transform,
    opacity, clip, filter and paint order. Pixels come from an arbitrary function `R : Scene → Image`, so the
    theorem says "equal scenes give equal images for every R".
- **Theorem pair per optimization.**
  - vis: $\forall\, \mathit{env} \in \mathrm{Bands},\ \forall t:\ \mathrm{visible}(\mathrm{scene}_o(\mathit{env},t)) \approx \mathrm{visible}(\mathrm{scene}_v(\mathit{env},t))$,
    where $\approx$ is `=` for class E and `Fw.Gate.Compare`'s PL1/PL2 tolerances for class Q.
  - work: $\forall \epsilon, \forall$ frames $k$: $W_\epsilon(v,k) \preceq W_\epsilon(o,k)$, strict somewhere.
  - `Screen.screen_sound` and `Cost.mainUs_mono` then give "no frame costs more under any non-negative unit costs".
  - `Measure.noMoreWork_sound` says which CI count types may confirm it. Stages the model predicts to be zero must
    read zero on CI, which makes CI a falsification test of the model.
- **Honest scope for the end-of-page decision.**
  - Under "looks the same", the provable savings in the morph are these:
    - **script**: the rAF tween becomes a WAAPI animation with the identical curve and clock;
    - **forced style and hit tests**: the nav.hitTest skips, already proved visually;
    - **hidden-animation pauses**: morph.columns and morph.countdown;
    - **layers**: the countdown strip;
    - **mount moved out of motion frames**: morph.mount.
  - The morph's dominant per-frame cost, layout of the nav's top/width/height plus the backdrop-blur paint, cannot
    be removed without a look change (CM, constant glass, finger-following). Those stay class L, for the user to
    decide.
  - The model can still predict their *work*. It cannot prove their *look*.
- **Two new engine facts make morph.tween's WAAPI variant exact, not approximate** (both re-read):
  1. **Curve.** $1-(1-t)^3$ is `cubic-bezier(1/3,1,2/3,1)` exactly. Both engines use the same Newton/bisection
     solver, which stops when $|x(t)-x| < \varepsilon$ (`ui/gfx/geometry/cubic_bezier.cc:181-237`@f842f52;
     `WC/platform/graphics/UnitBezier.h:111-169`@862f17d). For this curve $x(t)=t$, so the solver error in $y$ is at
     most $3\varepsilon$, and with exact double coefficients it is zero (§4.1).
  2. **Clock.** The rAF timestamp equals the document timeline time in both engines
     (`B/core/page/page_animator.cc:140-142`@f842f52 sets the rAF frame time from `Timeline().CurrentTimeDelta()`;
     `WC/animation/AnimationTimelinesController.cpp:125-129`@862f17d caches the timeline time because it "has to
     match the rAF timestamp"). The original samples `ease((rafTime − o)/680)` with `o = performance.now()` at the
     push (snapshot `_app/immutable/nodes/2.DyWL8TcE.js:13020-13021, 13032`). So a WAAPI animation with
     `startTime := o` samples the same function at the same instants.
- **Three corrections to the input notes.**
  - **C-1: the Chromium lane is threaded.** Note C (claim 4 and §0) says the lane passes `--deterministic-mode`, so
    every animation runs on main. In fact the lane passes `--enable-begin-frame-control
    --run-all-compositor-stages-before-draw` and explicitly *not* `--disable-threaded-animation`. CONFIRMED by
    `packages/measure-chromium/src/run.mjs:41`@56d3f96 and `README.md:144-150`. The README also MEASURED the fixture
    in both modes.
    - Consequences: compositor eligibility *is* observable in the lane (`trace.Animation.compositeFailedBits`, det).
      A separate free-running census is not needed. Note C's "every decision includes bit 0" becomes falsification
      test F0 (§3.3).
  - **C-2: WebKit's stage map is not monotone in the `StyleDifference` order.** RecompositeLayer dirties the
    compositing update (S3) and no paint. Repaint dirties paint (S5) and no S3 (note W §2.1-2.2). So
    $\mathrm{recomposite} < \mathrm{repaint}$ does not give $\mathrm{stages} \subseteq$. Note W's theorem
    `diff_order` is false as stated (INFERRED from note W's own table). Work dominance must therefore be proved on
    the **per-frame union of stages**, not on the enum order (§3.1).
  - **C-3: `trace.UpdateLayoutTree.elementCount` is quarantined** on the Chromium original arm
    (`packages/measure-chromium/classes.frozen.json`, swipe-v1/original, t = 11). So no element-count prediction
    (for example a non-inherited `--morph`) can be confirmed by `noMoreWork` today (`quarantined_unsound`).

## 1. The model

### 1.1 Shared core: `lean/Fw/Engine/Core.lean`

```lean
inductive Stage | script | style | layout | props | paint | raster | commit | comp
  -- props = Chromium PrePaint property-tree update / WebKit compositing update (S3)
  -- commit = Chromium cc.Commit / WebKit rendering-update commit (Composite)
  -- comp   = compositor-thread (Chromium impl) / UI-process (Core Animation) animation tick
inductive Thread | main | comp
inductive LayerState | none | layer | own            -- WebKit noLayer/layer/composited; Chromium "own cc layer"
structure Change where elem : Nat; prop : Prop'; layer : LayerState
structure FrameIn where                              -- what a variant does in one frame
  script  : Nat            -- JS callbacks (rAF + listeners), units = FunctionCall
  forced  : Nat × Nat      -- forced style, forced layout (reuse EngineScroll.forced_ρ)
  hits    : Nat            -- hit tests (elementFromPoint)
  changes : List Change    -- main-thread property changes (from JS or main-thread animations)
  compAnims : Nat          -- running compositor animations
structure Work where passes : Stage → Nat; units : Stage → Nat   -- per frame
structure Resident where layers : Nat; backingKpx : Nat          -- state, not per frame
```

Definitions:
- `stagesOf_ε : Change → Finset Stage`, one per engine (§1.2, §1.3).
- `frameWork_ε (f : FrameIn) : Work`:
  - `passes s = 1` iff `s ∈ ⋃ stagesOf_ε c` or `s` is forced;
  - `units s = #{c | s ∈ stagesOf_ε c}`;
  - plus `script` and `hits` under their own stages.
- `Work.le` is componentwise; `Work.lt` is `le` plus one strict component.
- `toCounts : Work → Screen.Counts` uses a fixed stage order.
- `toCost : Work → Cost.Work` maps script → `scriptUs`, style units → `styleElems`, layout units → `layoutObjs` and
  paint units → `paintKpx`. It is monotone, so `Cost.mainUs_mono` applies.

`Resident` is kept separate on purpose. An optimization that adds a layer (`will-change`) is a **trade**: per-frame
raster goes down and layers go up, which `Screen.screen` reports as `mixed`. Such a change is reported as a trade
and never as dominance (PLAN §6.6 PL5 bands already say layers ±0).

**Modes.** Each engine has `Mode := { threadedAnim : Bool, everyBeginFrameIsMainFrame : Bool }`.
- Chromium lane: `{true, true}`. The first value is CONFIRMED (run.mjs:41). The second is INFERRED from the fixture
  (MEASURED `UpdateLayoutTree 120` per 120 frames for a compositor animation, README:146-148); research gap R1.
- Real Chrome: `{true, false}`.
- WebKit Simulator and phone: `{threadedScrollDriven = true (CONFIRMED default, note W §3.2), threadedTimeBased =
  false (default; Safari value is open item O2)}`.

### 1.2 Chromium table (`lean/Fw/Engine/Chromium.lean`)

**Level chain.** Every level's stage set contains the one below it, so the order *is* monotone here (INFERRED from
note C §2.2; it holds row by row).

| `CrLevel` | stages | properties (target state) | engine source (note C) | status |
|---|---|---|---|---|
| `none` | ∅ | value unchanged | `computed_style.cc:767-931` diff empty | CONFIRMED |
| `direct` | style, props, commit | `transform` (only-property change, box already has a transform node), `opacity` in [0,1) | deferred update `paint_layer.cc:2469-2497`, direct cc write `paint_property_tree_builder.cc:1224-1262`; commit per frame MEASURED (`--disable-threaded-animation` fixture: cc.Commit 120, Paint 0, README:148) | CONFIRMED + MEASURED |
| `ppFull` | style, props, commit | `translate`/`scale`/`rotate` (no deferred path), `filter` on its own layer | `computed_style.cc:881-891`; `LayoutObject::SetStyle :3224-3230` | CONFIRMED |
| `raster` | style, props, commit, raster | transform or filter **not** on its own layer (chunk-to-layer changes) | `raster_invalidator.cc:64-142` | INFERRED (raster split) |
| `paint` | style, props, paint, commit, raster | background-position/-image, background-color and clip-path (no worklet), color (text or currentColor), stroke-dashoffset, visibility, z-index | `computed_style.cc:1104-1120`, `layout_object.cc:2932-2948` | CONFIRMED |
| `layoutPos` | style, layout, props, paint, commit, raster | top/left on a positioned box | `computed_style.cc:792-798` | CONFIRMED (paint INFERRED) |
| `layoutFull` | same set; units = dirty objects up to the relayout boundary | width/height/margin/padding, transform none↔some when the stacking state flips, contain change | `:986-988`, `:779-784`, `local_frame_view.cc:894-895` | CONFIRMED |

**Custom property.** A write of a custom property `--x` is mapped to the **max over its readers** of each reader's
level, plus style units equal to the restyled subtree. The fan-out of an inherited custom property is research gap
R2.

**Thread rule.** `crThread(anim) = comp` iff all of the following hold:
- `props ⊆ {transform, translate, scale, rotate, opacity, filter, backdrop-filter}`
  (`compositor_animations.cc:78-83`);
- none of the modelled failure bits is set:
  - bit 12: blur or drop-shadow in `filter` (`:405-417`);
  - bit 13: unsupported property, which includes custom properties without a paint worklet (`:173, :426-440`);
  - bit 16: the scroll-timeline source is not user-scrollable (`animation.cc:2561-2566`);
  - bit 5: invalid target (`:282, :624-646`);
  - bit 0: accelerated animations disabled, which is false in the lane (C-1).

All bits are CONFIRMED (note C §3). The per-frame work of a running animation:
- **comp:** `passes comp = 1`, `style = 1` per main frame (ride-along, MEASURED README:146-148), no layout, paint or
  commit;
- **main:** the property's `CrLevel` stages, every frame (`animation.cc:3376-3400`).

**Scroll.**
- Each scrolled frame costs one BeginMainFrame with `ScrollLayer` and `props`, but no paint until the cull rect has
  moved 512 px (`cull_rect.cc:48-69,425-430`).
- Scroll listeners never force main-thread scrolling (`main_thread_scrolling_reason.h:25-70`). The lane scrolls with
  `scrollTo` or CDP touch, so the scroll itself is `main`.

All of this is CONFIRMED (note C §4).

### 1.3 WebKit table (`lean/Fw/Engine/WebKit.lean`)

**Levels.** `Diff` (10 levels, `WC/style/StyleDifference.h:28-55`) is adjusted by `LayerState`
(`WC/rendering/RenderElement.cpp:297-359`). Stage sets (note W §2.2):

| `Diff` (adjusted) | stages | typical source (target state) | status |
|---|---|---|---|
| `equal` | ∅ | — | CONFIRMED |
| `recomposite` | style, props (S3) | transform/translate/scale/rotate/opacity/filter on a **composited** layer; clip-path when `willCompositeClipPath` | CONFIRMED |
| `repaint`, `repaintIfText`, `repaintLayer` | style, paint | background-*, color, mask, clip-path (not composited), opacity/filter on a non-composited layer | CONFIRMED |
| `overflow`, `overflowOOF` | style, layout (simplified), paint | transform value on a **non-composited** layer | CONFIRMED |
| `layoutOOFMoveOnly` | style, layout | top/left on an absolute box | CONFIRMED |
| `layout`, `newStyle` | style, layout, props, paint | size, margin, transform or filter appearing or disappearing, opacity crossing 1 (`StyleDifference.cpp:208-215`), stroke-dashoffset (`:161`) | CONFIRMED |

**Per update.** Every rendering update also pays the **baseline**: the transaction walk over all layers plus one
commit (`RemoteLayerTreeDrawingArea.mm:319-443`, "commit even if nothing changed"). So `commit ∈` every frame that
has an update. CONFIRMED (note W §1.1).

**Thread rule.** `wkThread(anim) = comp` iff all of the following hold:
- `props ⊆ {opacity, filter, backdrop-filter, transform, translate, scale, rotate}` (`CSSProperties.json`
  animation-wrapper-acceleration);
- `canBeAccelerated` holds (`KeyframeEffect.cpp:1970-2033`);
- the path is allowed:
  - the threaded path is used for scroll timelines (default on);
  - the legacy CA path is used for time timelines, which rejects `steps()`, `linear()` with points, playbackRate ≠ 1,
    and cubic y outside [0,1] (`GraphicsLayerCA.cpp:1169-1215`).

Custom properties are never accelerated (`StyleInterpolation.cpp:256-265`). A comp animation costs **zero
web-process work** per frame (`KeyframeEffect.cpp:2724-2744`, `DocumentTimeline.cpp:156-168`). All CONFIRMED.

**Scroll.** Every delivered scroll position costs one rendering update plus a commit, with or without listeners
(`WC/dom/Document.cpp:5913-5937`, note W §4.2). So on iOS a scroll step is never free. The theorem compares
style/layout/paint on top of an equal baseline (note W P4).

**Composited state.** A static 2D transform does **not** composite (`RenderLayerCompositor.cpp:3878-3907`). Under
the Conservative policy (memory pressure) `will-change` is dropped (`:3997-4018`, `:691-719`). So any Lean premise
"target is `own`" on WebKit must come from an animation, a 3D op or backdrop-filter, never from `will-change` alone.
CONFIRMED.

### 1.4 Where the engines differ (one row per rule the theorems touch)

| rule | Chromium | WebKit |
|---|---|---|
| blur `filter` animation | main thread (bit 12) | accelerated |
| custom property animation | main (bit 13) | main |
| opacity crossing 1 | `direct` (no layout, note I §3; v1 KD#8) | `layout` |
| stroke-dashoffset | `paint` | `layout` |
| JS-written 2D transform, no compositing reason | `raster` (re-raster chunks) | `overflow` (layout + layer repaint) |
| scroll step with no listener | BMF: props, Layerize, Commit only | full update plus commit (baseline) |
| scroll-driven transform/opacity | comp if the source is user-scrollable | comp (threaded, default on) |
| lane | threaded, every BeginFrame a main frame (C-1, R1) | Simulator = real Safari path; WKTR page counts quarantined |

## 2. Visual equivalence

### 2.1 Observable: `lean/Fw/Engine/Visual.lean`

```lean
structure BoxVis where
  box    : Rect            -- layout geometry, CSS px (Rat)          -- what PL1 measures
  paint  : List (String × String)  -- paint-relevant computed values  -- what PL2 measures
  xf     : Affine           -- accumulated transform (Rat 2x3)
  alpha  : Rat              -- effective opacity
  clip   : Option Shape
  filter : List FilterOp
  order  : Nat              -- paint order (stacking)
abbrev Scene := List (BoxId × BoxVis)
def visible (vp : Rect) : Scene → Scene   -- drops alpha = 0, visibility hidden, clipped to empty, fully under an opaque box
```

`render` is never defined. Every visual theorem is quantified over all `R : Scene → α`, so it says
"identical inputs to rasterization". The engine's rasterization is then assumed to be **path-invariant**, with three
explicit premises. They are `structure PathPremises`, carried as hypotheses, never axioms:
- **C1 text antialiasing:** no LCD text in a layer that moves between the main and compositor paths. INFERRED; at
  DPR 3 this is likely vacuous (gap R9).
- **C2 raster scale:** no scale animation on the compositor.
- **C3 sample phase:** the compositor (Chromium impl, WebKit UI process) samples the *same value function* at its own
  frame time. The theorems below are stated for the value function v(t), so C3 only concerns which instants are
  shown.

### 2.2 Theorem shape

For part $P$, original $o$, optimized $v$:

$$\textbf{(vis)}\quad \forall \mathit{env} \in \mathrm{Env},\ \forall t \in T:\ \mathrm{visible}_{\mathit{vp}(\mathit{env})}\big(\mathrm{scene}_o(\mathit{env},t)\big) \approx_{c} \mathrm{visible}_{\mathit{vp}(\mathit{env})}\big(\mathrm{scene}_v(\mathit{env},t)\big)$$

- $\mathit{env}$ ranges over **every width** (and touch × hover, DPR), not only the 124 loads. Each scene function
  depends on $\mathit{env}$ only through the 30 decidable media predicates of `Fw.Site.Breakpoints`, so the proof
  splits per band. CONFIRMED that the predicates exist (note I §4).
- $t$ is time (ms since the push) or scroll offset.
- $c \in \{E, Q\}$.
  - $E$ is `=`.
  - $Q$ is `Compare.near tolBox` (½ px, PL1) on `box`/`xf` translations and `Compare.near tolStyle` (10⁻³, PL2) on
    numbers in `paint`/`alpha`. Q's tolerance must be the gate's, never a new one.

The class letters follow note I §0: E, E-s (E for every sample t of a function), Q and L. An L change gets no vis
theorem. It goes to `proposal`.

### 2.3 How the proof and the breakpoint gate split the work

The chain from the original site to the optimized site has four links:
1. The original snapshot and the `faithful` TS part are linked by the breakpoint gate: PL0-PL2 at stops, 124 loads,
   Chromium and Playwright WebKit (PLAN §6.6).
2. The `faithful` TS part and the Lean `faithful` spec are linked by golden vectors (e.g. `Fw.Parts.MorphTween`,
   restated line by line from snapshot JS).
3. The Lean `faithful` spec and the Lean `optimized` spec are linked by the **(vis)** and **(work)** theorems.
4. The Lean `optimized` spec and the `optimized` TS part are linked by golden vectors, and also by the gate at frozen
   stops plus the pixel spot check (§5, optional).

What each side covers:
- **The proof covers** every t and every width (continuous, not sampled), every push sequence, and the engine rules
  of §1.
- **The gate covers** three things:
  - that code equals spec on both ends (TS against golden vectors);
  - that the engine realises the scene (PL1 boxes, PL2 computed styles);
  - with PL3/PL4 pixels, the path premises C1-C3.

  PLAN §6.6 says PL3 pixels are "not yet covered (reported, not gated)". So C1-C3 are covered by **nothing** today.
  The optional `pixel-spot` task (§5) closes this in Chromium only.
- **Neither covers** UIKit's `setContentOffset` fight (note W O1). That is the phone spot check.
- **The `faithful` rule stays the anchor.** The "original" in every theorem is the Lean restatement of the
  original's JS and CSS. Its fidelity is the gate's job, not the theorem's.

## 3. Work dominance

### 3.1 Theorem shape

$$\textbf{(work)}\quad \forall \epsilon \in \{\mathrm{cr}, \mathrm{wk}\},\ \forall k:\ W_\epsilon(v,k) \preceq W_\epsilon(o,k)\quad\text{and}\quad \exists k, s:\ W_\epsilon(v,k)_s < W_\epsilon(o,k)_s$$

**Proof route.**
1. **`frame_le_of_cover`.** Suppose there is an injection $\iota$ from $v$'s changes to $o$'s changes with
   $\mathrm{stages}_\epsilon(c) \subseteq \mathrm{stages}_\epsilon(\iota c)$, and also
   $\mathrm{script}_v \le \mathrm{script}_o$, $\mathrm{forced}_v \le \mathrm{forced}_o$ and
   $\mathrm{hits}_v \le \mathrm{hits}_o$. Then $W_v \preceq W_o$.
   - For Chromium the subset condition follows from `CrLevel` `≤` (`crStages_mono`).
   - For WebKit it must be checked per change. This is C-2: `recomposite` is **not** below `repaint` in stages.
     `wk_not_mono` is a `#guard` counterexample.
2. **`frame_le_union`.** A decidable variant for concrete frames: the union of $v$'s stages is contained in the
   union of $o$'s stages, and the units are `≤`. It closes by `decide`. This is how a WebKit
   repaint → recomposite trade is accepted when the original's frame already pays S3 (e.g. through layout).
3. **`run_dominates`.** If every frame satisfies $\preceq$ and one frame satisfies $\prec$, then
   `screen (toRun o) (toRun v) = .ok .dominates`, and `Screen.screen_sound` gives
   $T_{\kappa,c}(v_k) \le T_{\kappa,c}(o_k)$ for all $\kappa$ and all $c \ge 0$. The bridge `toCost` gives
   `Cost.mainUs_mono`.
4. **Resident.** $R_v \le R_o$ is required for "dominates". Otherwise the result is labelled "trade".

**Time alignment.** Frames are aligned by index under the lane's BeginFrame control, with the same virtual
timestamps. A variant that moves work across frames (morph.mount) gets a **shift** theorem instead:
$\max_{k \in \mathrm{motion}} W_v \preceq \max_{k \in \mathrm{motion}} W_o$ and $\sum_k W_v = \sum_k W_o$. That is
honest, because `screen` would say `mixed`.

### 3.2 Stage → CI count types (classes from `classes.frozen.json`, swipe-v1, original arm)

| stage | Chromium count (class) | WebKit Simulator count (class; original only today) | WKTR |
|---|---|---|---|
| script | `trace.FireAnimationFrame` (det), `FunctionCall` (det), `EventDispatch` (det) | FireAnimationFrame, EventDispatch (det per step) | — |
| style | `trace.UpdateLayoutTree` (det); `.elementCount` (**quarantined**, C-3) | RecalculateStyles (stable, tol 1) | `styleRecalcs` (quarantined) |
| layout | `trace.Layout` (stable, t 0), `.dirtyObjects` (stable) | Layout (quarantined per step, stable as total) | `layoutUpdates` (quarantined) |
| props | `trace.PrePaint` (stable): counts lifecycle frames, **not work**; no prediction beyond "= main frames" (note C §5) | — | `compositingUpdates` |
| paint | `trace.Paint` (quarantined) → use `raster.invalidationAreaPx` and `raster.invalidationRects` (stable) | Paint (quarantined per step, stable as total) | — (gap O4) |
| raster | `RasterTask` (quarantined) → `raster.invalidation*` | — | — |
| commit | `trace.cc.Commit` (det) | Composite (det) | `renderingUpdates`, `layerFlushes` (det) |
| comp | `trace.Animation.compositeFailedBits` (det), `census.layers` (stable, t 3) | LayerTree census | — |
| hits | `trace.HitTest` (stable) | — | — |

### 3.3 Falsification tests (golden vectors emitted by Lean, checked by a reducer)

Lean emits one row per (scenario, variant, stage) with a prediction in {`=0`, `=o`, `<o`, `≤o`, `any`}.
- **Det types** must match exactly.
- **Stable types** must match within margin $2t$ (`margin_sound`).
- **Quarantined types** are never used (`quarantined_unsound`).
- **A mismatch is a model bug.** It is fixed from engine source and never by widening a tolerance (inventory
  "What this changes", V-h).

| id | prediction | count | expected (status) |
|---|---|---|---|
| F0 | the lane does not disable threaded animation | `compositeFailedBits` bit 0 never set | INFERRED from C-1; checks note C's "always odd" claim |
| F1 | compositor transform/opacity animation: layout = paint = commit = 0, style = 1 per frame | fixture-rest | MEASURED (README:146-148); becomes a regression golden |
| F2 | main-thread width/background-color: layout > 0, paint > 0 per frame | fixture-rest | MEASURED (README:148-149) |
| F3 | for each landed variant, every stage the model says is 0 reads 0 in its zone | swipe-v1, rewrite arm per flag | new |
| F4 | `=o` stages within PL5 bands; `<o` stages strictly lower (det) | same | new |
| F5 | WebKit P1-P5 (note W §5.3) | webkit-sim on the rewrite | blocked on `webkit-sim-rewrite`; until then a local run is debug only, never a result |

## 4. Candidates: theorems, premises, effort (ranked for the end-of-page decision first)

Effort: S ≤ 4 h, M 4-10 h, L > 10 h (one agent).

### 4.1 morph.tween in detail (ranks 1-2)

**MT1 `bezier_eq_ease` (E, S).** For $P_1 = (\tfrac13, 1)$ and $P_2 = (\tfrac23, 1)$:

$$X(s) = s, \qquad Y(s) = 3s - 3s^2 + s^3 = 1 - (1-s)^3$$

This closes by `ring` over ℚ. Engine premise: none. Note I #9 INFERRED this; it is now a theorem target.

**MT2 `solver_exact` (Q, then E under an fp premise, S).**
- **Code facts (re-read).**
  - Both engines solve $x$ with Newton (4 iterations, ε = 10⁻⁷) and then bisection, returning $t$ with
    $|X(t)-x| < \varepsilon$ (`cubic_bezier.cc:18,22,181-237`@f842f52; `UnitBezier.h:39-40,111-160`@862f17d).
  - Blink calls `Solve(fraction)` with the default ε = 10⁻⁷ (`B/platform/animation/timing_function.cc:132-135`).
  - WebKit passes $\varepsilon = 1/(1000 \cdot \mathit{dur_s})$ ≈ 1.47·10⁻³ for 0.68 s (`TimingFunction.cpp:107-110`),
    but uses $\min(10^{-7}, \varepsilon)$ for the Newton exit (`UnitBezier.h:133`).
- **Theorem.** If $X(t) = t$ and $|X(t)-x| < \varepsilon$, then $|Y(t) - \mathrm{ease}(x)| \le 3\varepsilon$, because
  $|Y'| \le 3$ on [0,1].
- **fp premise (INFERRED, to be MEASURED as gap R8).** In IEEE double, `3.0*(1/3)` rounds to exactly 1.0 (a tie, to
  even). That gives $c_x = 1$ and $b_x = a_x = 0$, so $X(t) = t$ exactly, the spline guess is $t = x$, and Newton
  exits on its first test. The engine value is then the Horner form $((x-3)x+3)x$ in double. That differs from JS
  `1-(1-x)**3` only by a few ulp, about 10⁻¹⁵.
- Without the premise, the WebKit bisection bound $3 \cdot 1.47 \cdot 10^{-3}$ on a 1000 px width would be about 4 px,
  so R8 matters.

**MT3 `waapi_eq_tween` (E-s, M).** Variant `waapi`:
- Register `--morph` as `@property <number>` (inherits, initial 0).
- On a push, cancel any running animation and start a WAAPI animation `[{--morph: current}, {--morph: target}]`:
  680 ms, `cubic-bezier(1/3,1,2/3,1)`, `fill: forwards`, `startTime := o` (the push's `performance.now()`).
- Under reduced motion, jump to the target as before.

Theorem, over every push sequence and every frame time $T_k$:

$$\mathrm{val}_v(T_k) = \mathrm{tween}(\mathit{from}, \mathit{to}, T_k - o).\mathrm{value}$$

Exact in ℚ. In the engine it is MT2's bound. It reuses `MorphTween.tween`, `push` and `push_continuous`, with the
clock from §0 (CONFIRMED both engines).

Premises:
- registered `<number>` interpolation is $a + (b-a)p$ (gap R3);
- unregistered custom properties animate discretely, so registration is required (R3);
- `document.timeline` zero equals the `performance.now()` origin (gap R5; the Blink side is
  `document_timeline.cc:49-61`, not yet traced to the time origin).

**MT4 `flags_same_frame` (E-s, M).**
- `--morph-fade` becomes `calc(1 - min(1, var(--morph)/0.55))`, which is exactly `MorphTween.fade`.
- `pointer-events`, `is-on-dark` (> 0.2), `is-expanded` (> 0.92) and `is-morphing` flip through discrete keyframes
  placed at the crossing offsets.
- Lemma `ease_gt_iff`: for $i \in [0,1]$, $\mathrm{ease}(i) > \theta \iff (1-i)^3 < 1-\theta$. The flip frame is
  therefore the same as the original's, except at fp ties.
- Premise: discrete keyframe semantics (R3b).
- If R3b fails, keep a JS flag listener on `finish` and on the crossing timers. That is still no per-frame rAF.

**MT-W `waapi_work_le` (work, M).** Per tween frame, on both engines:
- script goes from `FireAnimationFrame + FunctionCall` to 0. That is strict.
- style, layout, paint and commit stay **equal**. The engines compute the diff from the old and new ComputedStyle,
  whatever wrote the value (`computed_style.cc:767`; `RenderElement::setStyle`). That is CONFIRMED for the diff;
  whether the restyle *scope* (inline write vs animation) is the same is INFERRED (R2).
- The custom property stays on main in both engines (CONFIRMED), so it is not a compositor claim.

CI predictions:
- `FireAnimationFrame` `<o` by about 41 frames per push (det);
- `UpdateLayoutTree` `=o` (det);
- `Layout` `=o` (stable);
- `compositeFailedBits` gains bit 13 (det), which is a direct check of the custom-property rule.

**MT5 scoped `--morph` (E, M; low CI value).** Set the value on the readers only, with `inherits: false`.
- Visual: every reader's computed value is unchanged.
- Work: style units go down from the header subtree to the readers.
- It cannot be confirmed on Chromium (C-3), and WKTR is quarantined. So it stays a model claim.

### 4.2 Ranked table

| rank | id | part | candidate (note I #) | vis theorem (class) | work theorem | engine premises (status) | CI check | effort |
|---|---|---|---|---|---|---|---|---|
| 1 | MT1-MT2 | morph.tween | curve identity, solver error | `bezier_eq_ease` (E), `solver_exact` (Q→E) | — | solver code CONFIRMED; fp tie R8 | Node golden: engine Horner vs `ease` over 10⁴ points (MEASURED) | S |
| 2 | MT3-MT4, MT-W | morph.tween | `waapi` (#9) | `waapi_eq_tween`, `flags_same_frame` (E-s) | `waapi_work_le` (script strict) | clock CONFIRMED both; R3, R3b, R5 | F3/F4: FireAnimationFrame, UpdateLayoutTree, Layout, bit 13 | M + M |
| 3 | NH-W | nav.hitTest | hit-skip, elements-skip, write-on-change (#3-5) | **done**: `hitSkip_morph`, `allowHit_eq_faithful`, `changed_write` | `hitSkip_work_lt`: in morph > 0.2, forced style −1 and hits −1 per frame; `elementsSkip_work_lt`: −2 style writes; via `EngineScroll.forced_ρ` | forced-update sites for getComputedStyle, rects and elementFromPoint (R4) | `trace.HitTest` (stable), `UpdateLayoutTree` (det) `<o` | S |
| 4 | HP | morph.columns, morph.countdown, engine.scene | pause animations whose box is not visible (#14, #25) | `hidden_pause_eq`: when `visible` drops the box, every value of it gives the same visible scene (E) | Chromium: a comp marquee still costs style 1 per frame (F1) → 0; WebKit: 0 web-process delta predicted (falsifiable: the Simulator sees no change) | which "hidden" forms skip paint while animations still tick (R6) | `UpdateLayoutTree` `<o` in hidden zones; `compositeFailedBits` unchanged | M |
| 5 | CD-W | hero.countdown, morph.countdown | strip (#7, #13) | **done**: `strip_shows_same` | Resident: layers 80 → 16 per clock; per-frame `=o` | layer per `will-change` face (Chromium `compositing_reason_finder.cc:76-137`, CONFIRMED); WebKit drops it under Conservative (CONFIRMED) | `census.layers` (stable, t 3) `<o` | S |
| 6 | MM-S | morph.mount | warm-up at a still moment (#12) | E after mount (`mountNext_mono` gives the trigger) | **shift** theorem: max motion-frame work `<`, total `=` | DOM insertion = layout + paint of the subtree (INFERRED) | per-zone `Layout`/`UpdateLayoutTree` moved out of y04500 | M |
| 7 | MP | morph.panel | `blur(0)` → `none` at rest; own layer during fade (#11 partial) | rest: E given no fixed-position descendants and an unchanged stacking order (premise checked by PL0/PL2); fade on own layer: Q (blur sampling differs between raster and GPU) | rest: removes the effect node; fade: raster `<`, layers +1 → **trade** | filter creates a containing block and stacking context (gap R10) | `raster.invalidationAreaPx` (stable) | M |
| 8 | HE | hero.exit | `hero-exit-threaded` (#6) | E-s from `exitOpacity_linear` + timeline progress (cite needed) | consumers off main **except** blur (Chromium bit 12) | ScrollTimeline progress formula (R11) | bits per consumer | M-L |

Outside the end-of-page region, each in the same form and after ranks 1-6:
- people.card MQ-gated shrink (#16): E, S.
- pain.notes armed only when visible (#21): E, S.
- people.deck `cqi` (#20): E by algebra, M.
- hero.accent boil (#15): E per sample, M.
- carousel 0.999 (#19): Q; needs the alpha quantization cite in Skia and CA, L.
- platform.sweep and glint (#23, #24): E-s claimed but hard with `background-clip:text`, L.

**No vis theorem, class L → `proposal`:** CM (#10), constant glass (#11), FLIP (#18), st6 (#19), typing chunks
(#22), PR-040 and PR-041. The model may still give them **work-only** theorems for the report, labelled
"look changed".

## 5. Task list for the work graph (dependency order, no calendar; about 6 agents in parallel)

| id | owner | deps | output | size |
|---|---|---|---|---|
| `engine-core-lean` | lean-prover | — | `lean/Fw/Engine/Core.lean` (Stage, Work, Resident, `frame_le_of_cover`, `frame_le_union`, `run_dominates` → `screen_sound`, `toCost` → `mainUs_mono`), `lean/Fw/Engine/Visual.lean` (Scene, `visible`, E/Q relations over `Compare.near`, `PathPremises`); types first so the next two can start | M |
| `engine-chromium-lean` | lean-prover | engine-core-lean | `lean/Fw/Engine/Chromium.lean` (`CrLevel` chain, §1.2 table with cites, `crThread`, `crStages_mono`); golden `packages/contracts/golden/engine/chromium.jsonl` (F0-F2 + signature rows) | M |
| `engine-webkit-lean` | lean-prover | engine-core-lean | `lean/Fw/Engine/WebKit.lean` (`Diff`, `adjust`, stage sets, `wk_not_mono` guard, `wkThread`, scroll baseline); golden `…/engine/webkit.jsonl` (P1-P5) | M |
| `morph-tween-curve` | lean-prover | — | MT1, MT2 in `lean/Fw/Parts/MorphTweenOpt.lean`; R8 fp check as a golden test in `apps/site/src/parts/morph.tween/` | S |
| `morph-tween-waapi` | lean-prover + part-builder | morph-tween-curve, engine-chromium-lean, engine-webkit-lean, port-morph-tween, R3/R5 answered | MT3, MT4, MT-W; TS variant `waapi` checked against Lean golden vectors; flag on R | M + M |
| `engine-part-work` | lean-prover | engine-chromium-lean, engine-webkit-lean, R4, R6 | NH-W, CD-W, HP, MM-S theorems (+ golden predictions per variant) | M |
| `engine-ci-check` | measure-engineer | engine-chromium-lean | reducer that reads the engine golden rows and checks F0-F4 on chromium-counts runs (fixture-rest, swipe-v1, rewrite arm per flag) through `noMoreWork`; a mismatch opens a model-bug item | M |
| `webkit-sim-rewrite` | measure-engineer (2nd) | — | `webkit-sim.yml` serves `?fw=` so F5 (P1-P5) gets CI counts; if not green at the M5 gate, WebKit stays model-only and is named so in the report | M |
| `engine-gaps` | researcher | — | close R1-R11 below at the pins, each CONFIRMED or explicitly open; one note | M |
| `pixel-spot` (optional) | measure-engineer | engine-ci-check | Chromium BeginFrame screenshots at k sampled t, original vs variant flag, byte-compare; covers C1-C3 in Chromium only | S-M |
| `plan-engine-proof` | plan-editor | this note | PLAN edits listed below | S |

**Research gaps** (all read at the pins; none needs a device):
- **R1.** Why every BeginFrame in the lane is a main frame (comp-animation ride-along style 1 per frame).
- **R2.** The fan-out of an inherited custom-property change (Blink `StyleRecalcChange`, WebKit `Style::Change`), and
  whether an animation-driven and an inline-driven change restyle the same set.
- **R3.** Registered `<number>` interpolation is linear (Blink `CSSNumberInterpolationType` or the custom-property
  path; WebKit `StyleInterpolation.cpp`). **R3b:** where the discrete flip falls for custom-property keyframes.
- **R4.** The forced style, layout and hit-test sites for `getComputedStyle`, `getBoundingClientRect` and
  `elementFromPoint`.
- **R5.** Document timeline zero = `performance.now()` origin.
- **R6.** Which hidden states (opacity 0 ancestor, visibility hidden, content-visibility, clipped) skip paint, and
  whether their animations still tick.
- **R7.** WebKit O2/O3.
- **R8.** The fp tie, MEASURED in Node.
- **R9.** LCD text at DPR 3 in the lane.
- **R10.** Filter as containing block and stacking context (`blur(0)` vs `none`).
- **R11.** The ScrollTimeline progress formula.

**Critical path.** engine-core-lean → engine-chromium-lean → engine-ci-check gives the first falsification result.
morph-tween-curve and engine-gaps start at once. morph-tween-waapi lands once R3 and R5 are answered.

## What this changes in the plan

- **PLAN §5.1 (what is proved).**
  - Add `Fw.Engine.{Core, Visual, Chromium, WebKit}`: the stage model, the engine tables with their cites, and the
    vis and work theorem shapes of §2.2 and §3.1.
  - Path premises C1-C3 are hypotheses, never axioms.
- **PLAN §6.2, `optimized` kind row.**
  - An `optimized` variant lands with a Lean pair: (vis) of class E, E-s or Q (with the gate's tolerances) and (work)
    over `Fw.Engine`. Class L goes to `proposal`.
  - The compositor gate's `compositeFailed = 0` is checked in the counts lane itself, because the lane is threaded
    (C-1, run.mjs:41). Drop "free-running census" as a separate requirement.
- **PLAN §6.6, PL5 / V-h.**
  - Add the predicted-vs-counted check (F0-F4). Predicted-zero stages must read 0 (det) or stay within $2t$
    (stable).
  - A mismatch is a model bug to fix from engine source.
  - `elementCount` and `Paint` are quarantined, so paint predictions use `raster.invalidation*`.
- **PLAN §10.1 (the end-of-page experiment, line 1046).**
  - Add an arm `v2-proved` = the flags with a proved pair (MT3/MT4 `waapi`, nav hit-skip/elements-skip, hidden
    pause, strip, mount shift). It sits beside `faithful` and `v1-best`.
  - The decision text states that `v2-proved` is look-identical by theorem and that `v1-best` is a look change.
- **PLAN §4 / §10.3 (phone).** The phone becomes a spot check of what neither proof nor CI covers: UIKit
  `scrollTo` feel (O1), WebKit path premises while `webkit-sim-rewrite` is open, and felt smoothness. It is no
  longer the evidence for "less work".
- **`docs/team/work-graph.json`.** Add the 11 tasks of §5 under milestone M5, with the deps above.
