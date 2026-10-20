import Fw.Engine.Core
import Fw.Measure.EngineCheck
import Lean.Data.Json
/-!
# The Chromium table of the engine model (design note 2026-10-18 §1.2, §1.4, §3.2-3.3)

`chromiumAt m : Engine CrProp CrMode` instantiates `Fw.Engine.Core` for Chromium 156 (pinned clone
`chromium@f842f52`). Citations are `file:line@f842f52` with `B/` = `third_party/blink/renderer/`; each row carries
CONFIRMED (the line was read), INFERRED (follows from read lines, not read itself) or MEASURED (lane fixture,
`packages/measure-chromium/README.md:144-150`).

* **Properties** `CrKey` (plain CSS properties), `CrProp` (a plain property, a custom property with its readers, or a
  scroll-offset change).
* **Levels** `CrLevel`: `none < styleOnly < direct < ppFull < raster < paint < layoutPos < layoutFull`; every level's
  stage list contains the one below it (`crStages_mono`), so on Chromium a level `≤` gives a stage cover
  (`levelCover_coverB`) and `frame_le_of_cover` applies.
* **Thread rule** `crThread`: compositor iff every property is in the compositable set and none of the failure bits
  0, 5, 12, 13, 16 is set (`crThread_comp_iff`); bit 0 is never set in the lane (`failBits_lane_no0`, test F0).
* **Scroll** one BeginMainFrame per scrolled frame (props + commit), paint only once the cull rect has moved 512 px
  (`scrollPaints_moved`).
* **Golden rows** `goldenText` → `packages/contracts/golden/engine/chromium.jsonl` (tests F0-F2 and one signature row
  per level), written by `goldenRun`.

Known gaps (open): the native paint-worklet path for `background-color`/`clip-path` animations (stable features
`CompositeBGColorAnimation`/`CompositeClipPathAnimation`, `B/platform/runtime_enabled_features.json5:1333-1343`) is not
modelled, so those animations are `main` here (INFERRED to match the lane: MEASURED Paint 240 for the
background-color fixture under `--disable-gpu`); units count changes, not dirty objects or restyled subtrees (R2).
-/
namespace Fw.Engine.Chromium
open Fw.Engine

/-! ## Properties and levels -/

/-- A plain (non-custom) CSS property as the Chromium table tells them apart. `filter b`: `b` says the filter list
holds a filter that moves pixels (blur or drop-shadow). `transformToggle`: `transform` going between none and some
with a stacking-state flip. `transform` alone is a some-to-some value change.
-/
inductive CrKey where
  | transform | transformToggle | translate | scale | rotate | opacity
  | filter (blur : Bool) | backdropFilter
  | backgroundPosition | backgroundImage | backgroundColor | color | clipPath | strokeDashoffset
  | visibility | zIndex
  | top | left
  | width | height | margin | padding
deriving Repr, DecidableEq, Inhabited

/-- Every plain property once (both `filter` variants), in the order the golden signature rows list them. -/
def CrKey.all : List CrKey :=
  [.transform, .transformToggle, .translate, .scale, .rotate, .opacity, .filter false, .filter true,
    .backdropFilter, .backgroundPosition, .backgroundImage, .backgroundColor, .color, .clipPath, .strokeDashoffset,
    .visibility, .zIndex, .top, .left, .width, .height, .margin, .padding]

/-- The CSS spelling of a plain property, as the golden rows print it (`filter(blur)` for a pixel-moving filter,
`transform(none<->some)` for the toggle).
-/
def CrKey.name : CrKey → String
  | .transform => "transform" | .transformToggle => "transform(none<->some)" | .translate => "translate"
  | .scale => "scale" | .rotate => "rotate" | .opacity => "opacity"
  | .filter true => "filter(blur)" | .filter false => "filter" | .backdropFilter => "backdrop-filter"
  | .backgroundPosition => "background-position" | .backgroundImage => "background-image"
  | .backgroundColor => "background-color" | .color => "color" | .clipPath => "clip-path"
  | .strokeDashoffset => "stroke-dashoffset" | .visibility => "visibility" | .zIndex => "z-index"
  | .top => "top" | .left => "left" | .width => "width" | .height => "height" | .margin => "margin"
  | .padding => "padding"

/-- One property change on Chromium: a plain property, a custom property `--x` (its id and the plain properties
that read it through `var()`), or a scroll-offset change of the scroller (`repaint` says the cull rect moved enough
to repaint, see `scrollPaints`).
-/
inductive CrProp where
  | css (k : CrKey)
  | custom (id : Nat) (readers : List CrKey)
  | scroll (repaint : Bool)
deriving Repr, DecidableEq

/-- The Chromium invalidation levels: no change, a style recalc only, a direct (deferred) property-tree update, a full
paint-property update, a re-raster of shared chunks, a repaint, a layout that only moves an own composited layer
(`layoutMove`: no repaint, no re-raster), a positioned layout, a full layout. Since the counterexamples of CI run
39088367495 the levels are not a chain: `layoutMove` and `raster` each run a stage the other does not, so the order is
stage inclusion (`CrLevel` `≤`).

The nine invalidation levels a Chromium property change can have.
-/
inductive CrLevel where
  | none | styleOnly | direct | ppFull | raster | paint | layoutMove | layoutPos | layoutFull
deriving Repr, DecidableEq, Inhabited

/-- Every level once, in declaration order.

The list of all levels.
-/
def CrLevel.all : List CrLevel :=
  [.none, .styleOnly, .direct, .ppFull, .raster, .paint, .layoutMove, .layoutPos, .layoutFull]

/-- The position of a level in `CrLevel.all`. It is written to the signature golden; since `layoutMove` it is no
longer the level order (which is stage inclusion).

The index of a level in the list of all levels.
-/
def CrLevel.rank : CrLevel → Nat
  | .none => 0 | .styleOnly => 1 | .direct => 2 | .ppFull => 3 | .raster => 4 | .paint => 5 | .layoutMove => 6
  | .layoutPos => 7 | .layoutFull => 8

/-- **The stage list of each level** (design note §1.2, note C §2.2).
* `none`: no stage (`B/core/style/computed_style.cc:767-931`, empty diff). CONFIRMED.
* `styleOnly`: style recalc only (a custom property no plain property reads). INFERRED.
* `direct`: style, props, commit. `transform` some-to-some or `opacity` on a box with its own cc layer: deferred node
  update (`B/core/paint/paint_layer.cc:2469-2497`), direct cc write
  (`B/core/paint/paint_property_tree_builder.cc:1224-1262`). CONFIRMED; commit per frame MEASURED (README:148).
* `ppFull`: style, props, commit. `translate`/`rotate`/a non-blur `filter` on its own layer, `backdrop-filter`
  (`computed_style.cc:881-891`, `B/core/layout/layout_object.cc:3224-3230`). CONFIRMED.
* `raster`: style, props, raster, commit. A transform, opacity or filter value on a box without its own layer
  re-rasters its chunks (`B/platform/graphics/paint/raster_invalidator.cc:64-142`). INFERRED.
* `paint`: style, props, paint, raster, commit. background-*, color, clip-path, stroke-dashoffset, visibility, z-index
  (`computed_style.cc:1104-1120`, `layout_object.cc:2932-2948`). CONFIRMED.
* `layoutMove`: style, layout, props, commit. top/left/margin of a box with its own cc layer: the layout moves the
  layer, whose contents are neither repainted nor re-rastered. MEASURED (CI run 39088367495: no Paint and no
  RasterTask in 3 of 3 passes); mechanism INFERRED.
* `layoutPos`: adds layout. top/left of a positioned box without its own layer (`computed_style.cc:792-798`).
  CONFIRMED (paint MEASURED, run 39088367495).
* `layoutFull`: the same stages; width/height/padding, and margin or a transform toggle that flips the stacking state
  on a box without its own layer (`computed_style.cc:779-784, 986-988`). CONFIRMED.
-/
def CrLevel.stages : CrLevel → List Stage
  | .none => []
  | .styleOnly => [.style]
  | .direct => [.style, .props, .commit]
  | .ppFull => [.style, .props, .commit]
  | .raster => [.style, .props, .raster, .commit]
  | .paint => [.style, .props, .paint, .raster, .commit]
  | .layoutMove => [.style, .layout, .props, .commit]
  | .layoutPos => [.style, .layout, .props, .paint, .raster, .commit]
  | .layoutFull => [.style, .layout, .props, .paint, .raster, .commit]

/-- **The level order is stage inclusion**: `a ≤ b` iff every stage of `a` is a stage of `b` (a preorder; `direct`
and `ppFull`, `layoutPos` and `layoutFull` have equal stages). Before CI run 39088367495 it was the rank order of a
chain; `layoutMove` and `raster` are incomparable.
-/
instance : LE CrLevel := ⟨fun a b => ∀ s ∈ a.stages, s ∈ b.stages⟩

instance (a b : CrLevel) : Decidable (a ≤ b) := inferInstanceAs (Decidable (∀ s ∈ a.stages, s ∈ b.stages))

/-- **The join of two levels**: the second if the first is below it, else the first if the second is below it, else
the top level `layoutFull` (two incomparable levels, e.g. `layoutMove` and `raster`, join to the full pipeline).

The second level if it is above the first, else the first if it is above the second, else the top level. For
comparable levels the join's stages are the union of both (`Fw.Ops.EnginePremise.max_stages_of_comparable`), which
CI run 39124427211 MEASURED on two comparable joins. The incomparable case is refuted on the one pair measured:
`top` and `scale` read through one custom property on an own-layer box ran no `Paint` and no `RasterTask`
(`Fw.Ops.EnginePremise.cr_extra_cells`).
-/
def CrLevel.max (a b : CrLevel) : CrLevel := if a ≤ b then b else if b ≤ a then a else .layoutFull

/-- **The level of a plain property change** on a target with layer state `l` (design note §1.2, note C §2.2 table).
`transform` and `opacity` on their own layer take the deferred direct path; `translate`/`rotate` and a non-blur
`filter` on their own layer a full property update (no deferred path, `computed_style.cc:881-891`); any of these without its
own layer re-rasters shared chunks; `backdrop-filter` changes compositing reasons (`computed_style.cc:1268-1292`,
Layerize INFERRED).

Corrected by CI run 39088367495 (MEASURED, 3 of 3 passes; mechanisms INFERRED): on its own layer `scale`, a blur
`filter` and a transform toggle re-raster (`raster`, was `ppFull`/`ppFull`/`layoutFull`: the toggle no longer flips
the stacking state, which `will-change` already fixed, and a new scale or blur radius changes the raster scale or the
filter's input), and `top`/`left`/`margin` only move the layer (`layoutMove`, was `layoutPos`/`layoutFull`).

The invalidation level of a plain property change on a box with the given layer state.
-/
def keyLevel : CrKey → LayerState → CrLevel
  | .transform, .own => .direct
  | .opacity, .own => .direct
  | .translate, .own | .rotate, .own | .filter false, .own => .ppFull
  | .scale, .own | .filter true, .own | .transformToggle, .own => .raster
  | .transform, _ | .opacity, _ | .translate, _ | .scale, _ | .rotate, _ | .filter _, _ => .raster
  | .backdropFilter, _ => .ppFull
  | .backgroundPosition, _ | .backgroundImage, _ | .backgroundColor, _ | .color, _ | .clipPath, _
  | .strokeDashoffset, _ | .visibility, _ | .zIndex, _ => .paint
  | .top, .own | .left, .own | .margin, .own => .layoutMove
  | .top, _ | .left, _ => .layoutPos
  | .transformToggle, _ | .width, _ | .height, _ | .margin, _ | .padding, _ => .layoutFull

/-- **The level of a change.** A plain property takes `keyLevel`; a custom property takes the maximum over its
readers' levels, at least `styleOnly` (the write restyles the element; design note §1.2 "max over its readers"); a
scroll-offset change has no style level (its stages come from `CrProp.extra`).

(the maximum is the join `CrLevel.max`, folded left over `R` in list order; two incomparable levels join to
`layoutFull`).

The level of a plain, custom or scroll property change.
-/
def crLevel : CrProp → LayerState → CrLevel
  | .css k, l => keyLevel k l
  | .custom _ rs, l => rs.foldl (fun acc k => acc.max (keyLevel k l)) .styleOnly
  | .scroll _, _ => .none

/-- **Scroll rule** (note C §4). One scrolled frame is one BeginMainFrame with the scroll-translation update (props)
and a commit (`cc/input/input_handler.cc:425-429`, `B/core/paint/paint_layer_scrollable_area.cc:428-462`); paint and
raster only when the cull rect has moved enough (`B/platform/graphics/paint/cull_rect.cc:48-69,425-430`). CONFIRMED.
-/
def scrollStages (repaint : Bool) : List Stage :=
  [.props, .commit] ++ (if repaint then [.paint, .raster] else [])

/-- The stages a change adds beyond its level: the scroll stages for a scroll-offset change, none otherwise. -/
def CrProp.extra : CrProp → List Stage
  | .scroll r => scrollStages r
  | _ => []

/-- **`stagesOf` of the Chromium engine**: the level's stages, then the extra scroll stages. -/
def crStagesOf (c : Change CrProp) : List Stage := (crLevel c.prop c.layer).stages ++ c.prop.extra

/-! ## Modes and the engine -/

/-- Chromium's run mode: threaded (compositor) animation on or off, and whether every BeginFrame is also a
BeginMainFrame (so a running compositor animation still gets a main-thread style ride-along each frame).
-/
structure CrMode where
  threadedAnim : Bool
  everyBeginFrameIsMainFrame : Bool
deriving Repr, DecidableEq

/-- The CI lane: threaded animation kept (`--disable-threaded-animation` not passed,
`packages/measure-chromium/src/run.mjs:41`, CONFIRMED, correction C-1), every BeginFrame a main frame (MEASURED
UpdateLayoutTree 120 in 120 frames for a compositor animation, README:146-148; INFERRED as a rule, gap R1).
-/
def lane : CrMode := ⟨true, true⟩

/-- Real Chrome: threaded animation, and the main thread sleeps while only compositor animations run
(`B/core/animation/document_timeline.cc:111-135`, CONFIRMED).
-/
def realChrome : CrMode := ⟨true, false⟩

/-- The stages one running compositor animation costs per frame: the compositor tick, plus in a mode where every
BeginFrame is a main frame the ride-along style recalc and property update of the target (MEASURED style 120 per
120 frames, Paint/Layout/cc.Commit 0, README:146-148; props INFERRED from `B/core/animation/keyframe_effect.cc:739-742`).
-/
def crCompStages (m : CrMode) : List Stage :=
  [.comp] ++ (if m.everyBeginFrameIsMainFrame then [.style, .props] else [])

/-- **The Chromium engine in mode `m`.** The base stage is `props`: every main frame that updates (a change or a
script callback) runs PrePaint, which `LocalFrameView::RunPrePaintLifecyclePhase` traces unconditionally before the
compositing inputs (`B/core/frame/local_frame_view.cc:2586`@f842f52, CONFIRMED; MEASURED: a script-only rAF frame
runs PrePaint in 3 of 3 passes, CI run 39088367495). Until that run the base was empty. A main frame with no change
commits nothing (MEASURED cc.Commit 0 with only compositor animations, README:146-148, and in the script-only frame),
so `commit` comes from the changes. The base rule is MEASURED for rAF callbacks only; for a timer task it is OPEN (the
lane's `shimTimer` step runs its callback through the virtual clock shim inside the driver's evaluate, not as a
Chromium timer task: `Fw.Ops.EnginePremise.Act`).

The Chromium engine whose updating frames always pay one PrePaint.
-/
def chromiumAt (m : CrMode) : Engine CrProp CrMode where
  mode := m
  stagesOf := crStagesOf
  compStages := crCompStages m
  base := [.props]

/-- **The Chromium engine of the CI lane.** -/
def chromium : Engine CrProp CrMode := chromiumAt lane

/-! ## Level order theorems -/

/-- **Level monotonicity.** A lower or equal level dirties a subset of the stages (since the order became stage
inclusion, this is its definition).

A level below another runs only stages the other runs.
-/
theorem crStages_mono {a b : CrLevel} (h : a ≤ b) : ∀ s ∈ a.stages, s ∈ b.stages := h

/-- The level order is reflexive.

Every level is below itself.
-/
theorem CrLevel.le_refl (a : CrLevel) : a ≤ a := fun _ h => h

/-- **`layoutFull` is the top level.**

Every level runs only stages a full layout runs.
-/
theorem CrLevel.le_layoutFull (a : CrLevel) : a ≤ .layoutFull := by
  cases a <;> decide

/-- `max` is an upper bound of its left argument.

The join is above its first argument.
-/
theorem CrLevel.le_max_left (a b : CrLevel) : a ≤ a.max b := by
  unfold CrLevel.max
  split
  · assumption
  · split
    · exact CrLevel.le_refl a
    · exact CrLevel.le_layoutFull a

/-- `max` is an upper bound of its right argument.

The join is above its second argument.
-/
theorem CrLevel.le_max_right (a b : CrLevel) : b ≤ a.max b := by
  unfold CrLevel.max
  split
  · exact CrLevel.le_refl b
  · split
    · assumption
    · exact CrLevel.le_layoutFull b

/-- The level order is transitive.

Stage inclusion composes.
-/
theorem CrLevel.le_trans {a b c : CrLevel} (h1 : a ≤ b) (h2 : b ≤ c) : a ≤ c :=
  fun s hs => h2 s (h1 s hs)

/-- **The levels are not a chain** (CI run 39088367495): `layoutMove` and `raster` are incomparable, each runs a stage
the other does not (layout, raster).

A layer move and a re-raster cannot be ranked against each other.
-/
theorem layoutMove_raster_incomparable : ¬ CrLevel.layoutMove ≤ .raster ∧ ¬ CrLevel.raster ≤ .layoutMove := by
  decide

/-- A left fold of `max` stays above its start and above every folded element. -/
theorem foldl_max_ge : ∀ (x : CrLevel) (L : List CrLevel),
    x ≤ L.foldl CrLevel.max x ∧ ∀ y ∈ L, y ≤ L.foldl CrLevel.max x
  | x, [] => ⟨CrLevel.le_refl _, fun _ h => nomatch h⟩
  | x, y :: ys => by
    obtain ⟨h1, h2⟩ := foldl_max_ge (x.max y) ys
    refine ⟨CrLevel.le_trans (CrLevel.le_max_left x y) h1, fun z hz => ?_⟩
    rcases List.mem_cons.mp hz with rfl | hz
    · exact CrLevel.le_trans (CrLevel.le_max_right x z) h1
    · exact h2 z hz

/-- **A custom property costs at least each reader.** Every plain property reading `--x` has a level at most the
custom property's level, so its stages are among the custom property's stages.
-/
theorem custom_ge_reader (i : Nat) (rs : List CrKey) (l : LayerState) :
    ∀ k ∈ rs, keyLevel k l ≤ crLevel (.custom i rs) l ∧
      ∀ s ∈ (keyLevel k l).stages, s ∈ (crLevel (.custom i rs) l).stages := by
  intro k hk
  have hfold : rs.foldl (fun acc k => acc.max (keyLevel k l)) .styleOnly =
      (rs.map (keyLevel · l)).foldl CrLevel.max .styleOnly := by
    rw [List.foldl_map]
  have hle : keyLevel k l ≤ crLevel (.custom i rs) l := by
    simp only [crLevel, hfold]
    exact (foldl_max_ge _ _).2 _ (List.mem_map.mpr ⟨k, hk, rfl⟩)
  exact ⟨hle, crStages_mono hle⟩

/-- A custom property write always restyles: its level is at least `styleOnly`. -/
theorem custom_ge_styleOnly (i : Nat) (rs : List CrKey) (l : LayerState) :
    CrLevel.styleOnly ≤ crLevel (.custom i rs) l := by
  have hfold : rs.foldl (fun acc k => acc.max (keyLevel k l)) .styleOnly =
      (rs.map (keyLevel · l)).foldl CrLevel.max .styleOnly := by
    rw [List.foldl_map]
  simp only [crLevel, hfold]
  exact (foldl_max_ge _ _).1

/-! ## Level covers -/

/-- The pairwise level check: equal lengths, and each change of the first list is not a scroll change and has a level
at most its partner's.
-/
def levelCover : List (Change CrProp) → List (Change CrProp) → Bool
  | [], [] => true
  | c :: cs, d :: ds =>
    c.prop.extra.isEmpty && decide (crLevel c.prop c.layer ≤ crLevel d.prop d.layer) && levelCover cs ds
  | _, _ => false

/-- **Level order gives a stage cover** on Chromium, in every mode: the core hypothesis of `frame_le_of_cover` holds
whenever the levels are pairwise `≤` (the step design note §3.1 names `crStages_mono`).
-/
theorem levelCover_coverB (m : CrMode) :
    ∀ {l l' : List (Change CrProp)}, levelCover l l' = true → coverB (chromiumAt m) l l' = true
  | [], [], _ => rfl
  | [], _ :: _, h => by simp [levelCover] at h
  | _ :: _, [], h => by simp [levelCover] at h
  | c :: cs, d :: ds, h => by
    simp only [levelCover, Bool.and_eq_true, List.isEmpty_iff, decide_eq_true_eq] at h
    obtain ⟨⟨hx, hl⟩, hr⟩ := h
    simp only [coverB, Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq]
    refine ⟨fun s hs => ?_, levelCover_coverB m hr⟩
    simp only [chromiumAt, crStagesOf, hx, List.append_nil, List.mem_append] at hs ⊢
    exact .inl (crStages_mono hl s hs)

/-! ## Thread rule -/

/-- The timeline an animation runs on: the document timeline, or a scroll timeline whose source scroller is or is
not user-scrollable.
-/
inductive CrTimeline where
  | document
  | scroll (userScrollable : Bool)
deriving Repr, DecidableEq

/-- A running animation: target element, animated properties, target layer state, whether the target has a valid
compositing state (layout object, not fragmented, a direct compositing reason, no `will-change: contents`), and its
timeline.
-/
structure CrAnim where
  elem : Nat
  props : List CrProp
  layer : LayerState
  validTarget : Bool := true
  timeline : CrTimeline := .document
deriving Repr

/-- **Compositable properties** (`kCompositableProperties`, `B/core/animation/compositor_animations.cc:78-83`,
CONFIRMED): transform (either kind of change), translate, scale, rotate, opacity, filter, backdrop-filter. The
paint-worklet entries background-color and clip-path are left out (module doc, open gap); custom properties and
scroll offsets are not compositable.
-/
def CrProp.eligible : CrProp → Bool
  | .css .transform | .css .transformToggle | .css .translate | .css .scale | .css .rotate | .css .opacity
  | .css (.filter _) | .css .backdropFilter => true
  | _ => false

/-- A filter that moves pixels (blur or drop-shadow); backdrop-filter is exempt
(`compositor_animations.cc:405-417`, CONFIRMED).
-/
def CrProp.movesPixels : CrProp → Bool
  | .css (.filter b) => b
  | _ => false

/-- **The modelled compositing failure bits** (`B/core/animation/compositor_animations.h:73-115`, CONFIRMED), in
increasing order:
* bit 0 `kAcceleratedAnimationsDisabled`: threaded animation off (`compositor_animations.cc:597-608`);
* bit 5 `kTargetHasInvalidCompositingState`: invalid target (`:282, :624-646`);
* bit 12 `kFilterRelatedPropertyMayMovePixels`: a blur or drop-shadow filter (`:405-417`);
* bit 13 `kUnsupportedCSSProperty`: a property outside the compositable set (`:173, :426-440`);
* bit 16 `kTimelineSourceHasInvalidCompositingState`: a scroll timeline whose source is not user-scrollable
  (`B/core/animation/animation.cc:2561-2566`).
-/
def failBits (m : CrMode) (a : CrAnim) : List Nat :=
  (if m.threadedAnim then [] else [0]) ++ (if a.validTarget then [] else [5]) ++
    (if a.props.any CrProp.movesPixels then [12] else []) ++ (if a.props.all CrProp.eligible then [] else [13]) ++
    (if a.timeline = .scroll false then [16] else [])

/-- **Chromium's thread rule.** An animation runs on the compositor iff all its properties are compositable and no
modelled failure bit is set; otherwise the main thread services it every frame (`animation.cc:3376-3400`, CONFIRMED).
-/
def crThread (m : CrMode) (a : CrAnim) : Thread :=
  if a.props.all CrProp.eligible && (failBits m a).isEmpty then .comp else .main

/-- **The thread rule, spelled out.** Compositor iff every property is compositable, threaded animation is on, the
target is valid, no filter moves pixels, and the timeline is not a scroll timeline on a non-user-scrollable source.
-/
theorem crThread_comp_iff (m : CrMode) (a : CrAnim) :
    crThread m a = .comp ↔ (∀ p ∈ a.props, p.eligible = true) ∧ m.threadedAnim = true ∧ a.validTarget = true ∧
      (∀ p ∈ a.props, p.movesPixels = false) ∧ a.timeline ≠ .scroll false := by
  unfold crThread failBits
  cases ht : m.threadedAnim <;> cases hv : a.validTarget <;>
    cases hm : a.props.any CrProp.movesPixels <;> cases he : a.props.all CrProp.eligible <;>
    by_cases hs : a.timeline = .scroll false <;>
    simp_all [List.any_eq_true, List.all_eq_true]

/-- **No bit 0 in the lane, nor in real Chrome** (falsification test F0): both modes keep threaded animation, so no
animation's failure bits contain bit 0.
-/
theorem failBits_lane_no0 (a : CrAnim) : 0 ∉ failBits lane a ∧ 0 ∉ failBits realChrome a := by
  constructor <;>
  · simp only [failBits, lane, realChrome, ↓reduceIte, List.nil_append, List.mem_append]
    split <;> split <;> split <;> split <;> simp

/-! ## Frames -/

/-- The main-thread changes an animation makes in one frame: one change per animated property, on its target. -/
def CrAnim.changes (a : CrAnim) : List (Change CrProp) := a.props.map fun p => ⟨a.elem, p, a.layer⟩

/-- **One frame of running animations** in mode `m`: the main-thread animations contribute their changes, the
compositor animations count as `compAnims`; no script, forced passes or hit tests.
-/
def animFrame (m : CrMode) (as : List CrAnim) : FrameIn CrProp where
  script := 0
  forcedStyle := 0
  forcedLayout := 0
  hits := 0
  changes := (as.filter fun a => decide (crThread m a = .main)).flatMap CrAnim.changes
  compAnims := (as.filter fun a => decide (crThread m a = .comp)).length

/-- A frame of script that writes styles: `n` callbacks and the written changes, nothing else. -/
def jsWrite (n : Nat) (cs : List (Change CrProp)) : FrameIn CrProp :=
  { script := n, forcedStyle := 0, forcedLayout := 0, hits := 0, changes := cs, compAnims := 0 }

/-! ## Worked theorems -/

/-- **A compositor animation does no main-thread layout, paint, raster or commit.** If every running animation is on
the compositor, the frame's layout, paint, raster and commit stages have no passes and no units, in every mode.
-/
theorem compAnim_no_layout_paint (m : CrMode) (as : List CrAnim) (h : ∀ a ∈ as, crThread m a = .comp) :
    ∀ s ∈ [Stage.layout, .paint, .raster, .commit],
      (frameWork (chromiumAt m) (animFrame m as)).passes s = 0 ∧
        (frameWork (chromiumAt m) (animFrame m as)).units s = 0 := by
  have hnil : (as.filter fun a => decide (crThread m a = .main)) = [] := by
    rw [List.filter_eq_nil_iff]
    intro a ha; simp [h a ha]
  intro s hs
  have hs' : s ∉ crCompStages m := by
    simp only [List.mem_cons, List.mem_nil_iff, or_false] at hs
    unfold crCompStages; split <;> rcases hs with rfl | rfl | rfl | rfl <;> decide
  simp only [List.mem_cons, List.mem_nil_iff, or_false] at hs
  refine ⟨?_, ?_⟩
  · simp only [frameWork, touched, animFrame, hnil, FrameIn.updates, chromiumAt]
    rcases hs with rfl | rfl | rfl | rfl <;> (split <;> simp_all [forcedPasses])
  · simp only [frameWork, stageUnits, animFrame, hnil, chromiumAt]
    rcases hs with rfl | rfl | rfl | rfl <;> simp_all

/-- A `transform` animation on a valid target with the document timeline runs on the compositor whenever threaded
animation is on.
-/
theorem transformAnim_comp (m : CrMode) (e : Nat) (l : LayerState) (h : m.threadedAnim = true) :
    crThread m ⟨e, [.css .transform], l, true, .document⟩ = .comp := by
  simp [crThread, failBits, h, CrProp.eligible, CrProp.movesPixels]

/-- **Worked theorem 2: a compositor transform animation has no layout and no paint stage on the main thread**, in
the lane and in real Chrome.
-/
theorem compTransform_no_layout_paint (m : CrMode) (hm : m = lane ∨ m = realChrome) (e : Nat) (l : LayerState) :
    (frameWork (chromiumAt m) (animFrame m [⟨e, [.css .transform], l, true, .document⟩])).passes .layout = 0 ∧
      (frameWork (chromiumAt m) (animFrame m [⟨e, [.css .transform], l, true, .document⟩])).passes .paint = 0 := by
  have ht : m.threadedAnim = true := by rcases hm with rfl | rfl <;> rfl
  have h := compAnim_no_layout_paint m [⟨e, [.css .transform], l, true, .document⟩] (by
    intro a ha; simp only [List.mem_cons, List.mem_nil_iff, or_false] at ha; subst ha
    exact transformAnim_comp m e l ht)
  exact ⟨(h .layout (by simp)).1, (h .paint (by simp)).1⟩

/-- **Worked theorem 1: a JS transform write on its own layer costs at most a top/left write**, through
`frame_le_of_cover`: same callbacks, the transform change (`direct`) is covered by the top/left change (`layoutPos`; `layoutMove` on its own layer since CI run 39088367495, which still
contains style, props and commit),
in every mode and for any target and layer state of the top/left write.
-/
theorem jsTransform_le_topLeft (m : CrMode) (n e e' : Nat) (l : LayerState) (k : CrKey)
    (hk : k = .top ∨ k = .left) :
    (frameWork (chromiumAt m) (jsWrite n [⟨e, .css .transform, .own⟩])).le
      (frameWork (chromiumAt m) (jsWrite n [⟨e', .css k, l⟩])) := by
  refine frame_le_of_cover (chromiumAt m) [⟨e', .css k, l⟩] [] (by simp [jsWrite]) ?_
    (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _)
  apply levelCover_coverB
  rcases hk with rfl | rfl <;> cases l <;> rfl

/-- **The top/left write is strictly more work**: the transform write has no layout pass, the top/left write has one. -/
theorem jsTransform_lt_topLeft (m : CrMode) (n e e' : Nat) (l : LayerState) (k : CrKey)
    (hk : k = .top ∨ k = .left) :
    (frameWork (chromiumAt m) (jsWrite n [⟨e, .css .transform, .own⟩])).lt
      (frameWork (chromiumAt m) (jsWrite n [⟨e', .css k, l⟩])) := by
  refine ⟨jsTransform_le_topLeft m n e e' l k hk, .inl ⟨.layout, .inl ?_⟩⟩
  simp only [frameWork, touched, jsWrite, chromiumAt, forcedPasses]
  rcases hk with rfl | rfl <;> cases l <;> by_cases hn : 0 < n <;>
    simp [crStagesOf, crLevel, keyLevel, CrLevel.stages, CrProp.extra, FrameIn.updates, hn]

/-! ## Scroll -/

/-- The cull-rect repaint period of a scroll at `d` px per frame: `⌈ 512/d ⌉` frames for `d > 0` and `0` for `d = 0` (changed-enough
distance 512 px at expansion ratio 1, `cull_rect.cc:48-69`, `B/../common/features.cc:627-652`; ratio 1 INFERRED).
-/
def cullPeriod (d : Nat) : Nat := (512 + d - 1) / d

/-- Whether frame `k` (counted from the last cull-rect update at frame 0) of a scroll at `d` px per frame repaints:
the cull rect is recomputed every `cullPeriod d` frames, never at frame 0, never when `d = 0`.
-/
def scrollPaints (d k : Nat) : Bool := decide (0 < k) && k % cullPeriod d == 0

/-- **Paint only after 512 px.** A scroll frame that repaints has moved the scroller at least 512 px since the last
cull-rect update.
-/
theorem scrollPaints_moved (d k : Nat) (h : scrollPaints d k = true) : 512 ≤ k * d := by
  simp only [scrollPaints, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at h
  obtain ⟨hk, hm⟩ := h
  rcases Nat.eq_zero_or_pos d with rfl | hd
  · simp [cullPeriod] at hm; omega
  · have hp : 0 < cullPeriod d := by
      unfold cullPeriod; exact Nat.div_pos (by omega) hd
    obtain ⟨q, hq⟩ := Nat.dvd_of_mod_eq_zero hm
    have hq1 : 1 ≤ q := by
      rcases Nat.eq_zero_or_pos q with rfl | h; · simp at hq; omega
      · exact h
    have hpd : 512 ≤ cullPeriod d * d := by
      have := Nat.div_add_mod (512 + d - 1) d
      have := Nat.mod_lt (512 + d - 1) hd
      unfold cullPeriod
      rw [Nat.mul_comm]
      omega
    calc 512 ≤ cullPeriod d * d := hpd
      _ ≤ (cullPeriod d * q) * d := Nat.mul_le_mul_right d (Nat.le_mul_of_pos_right _ hq1)
      _ = k * d := by rw [← hq]

/-- The scroll change of frame `k` of a scroll at `d` px per frame on scroller `e`. -/
def scrollChange (e d k : Nat) : Change CrProp := ⟨e, .scroll (scrollPaints d k), .own⟩

/-- **One BeginMainFrame per scrolled frame, without style or layout.** Every scroll frame runs props and commit,
never style or layout, and runs paint exactly when the cull rect is due (`scrollPaints`).
-/
theorem scroll_stages (e d k : Nat) :
    .props ∈ crStagesOf (scrollChange e d k) ∧ .commit ∈ crStagesOf (scrollChange e d k) ∧
      .style ∉ crStagesOf (scrollChange e d k) ∧ .layout ∉ crStagesOf (scrollChange e d k) ∧
      (.paint ∈ crStagesOf (scrollChange e d k) ↔ scrollPaints d k = true) := by
  simp only [scrollChange, crStagesOf, crLevel, CrLevel.stages, CrProp.extra, scrollStages, List.nil_append]
  cases scrollPaints d k <;> decide

/-! ## Decision examples -/

#guard crThread lane ⟨0, [.css .transform], .own, true, .document⟩ == .comp
#guard crThread lane ⟨0, [.css (.filter true)], .own, true, .document⟩ == .main
#guard failBits lane ⟨0, [.css (.filter true)], .own, true, .document⟩ == [12]
#guard crThread lane ⟨0, [.css .backdropFilter], .own, true, .document⟩ == .comp
#guard failBits lane ⟨0, [.custom 1 [.transform]], .own, true, .document⟩ == [13]
#guard failBits lane ⟨0, [.css .opacity], .own, false, .document⟩ == [5]
#guard failBits lane ⟨0, [.css .opacity], .own, true, .scroll false⟩ == [16]
#guard crThread lane ⟨0, [.css .opacity], .own, true, .scroll true⟩ == .comp
#guard failBits ⟨false, true⟩ ⟨0, [.css .width], .none, true, .document⟩ == [0, 13]
#guard crThread lane ⟨0, [.css .backgroundColor], .none, true, .document⟩ == .main
#guard keyLevel .transform .own == .direct && keyLevel .transform .layer == .raster
#guard keyLevel .translate .own == .ppFull && keyLevel .top .none == .layoutPos
#guard keyLevel .scale .own == .raster && keyLevel (.filter true) .own == .raster
#guard keyLevel (.filter false) .own == .ppFull && keyLevel .transformToggle .own == .raster
#guard keyLevel .transformToggle .layer == .layoutFull && keyLevel .margin .layer == .layoutFull
#guard keyLevel .top .own == .layoutMove && keyLevel .left .own == .layoutMove && keyLevel .margin .own == .layoutMove
#guard keyLevel .top .layer == .layoutPos && keyLevel .width .own == .layoutFull
#guard CrLevel.layoutMove.max .raster == .layoutFull && CrLevel.direct.max .ppFull == .ppFull
#guard CrLevel.paint.max .raster == .paint && CrLevel.raster.max .paint == .paint
#guard (chromiumAt lane).base == [.props]
#guard crLevel (.custom 0 [.opacity, .width]) .own == .layoutFull
#guard crLevel (.custom 0 []) .own == .styleOnly
#guard crLevel (.custom 0 [.transform]) .own == .direct
#guard crStagesOf ⟨0, .scroll false, .own⟩ == [.props, .commit]
#guard crStagesOf ⟨0, .scroll true, .own⟩ == [.props, .commit, .paint, .raster]
#guard cullPeriod 10 == 52 && cullPeriod 512 == 1 && cullPeriod 0 == 0
#guard (List.range 120).filter (scrollPaints 10 ·) == [52, 104]
#guard !(scrollPaints 0 5) && !(scrollPaints 10 0)
#guard levelCover [⟨0, .css .transform, .own⟩] [⟨1, .css .top, .none⟩]
#guard !levelCover [⟨0, .css .top, .none⟩] [⟨1, .css .transform, .own⟩]
#guard !levelCover [⟨0, .scroll false, .own⟩] [⟨1, .css .width, .none⟩]
#guard CrLevel.all.all fun a => CrLevel.all.all fun b =>
  !decide (a ≤ b) || a.stages.all (fun s => decide (s ∈ b.stages))

/-! ## Golden rows (tests F0-F2, design note §3.3) -/

/-- The prediction alphabet of a golden stage row: the variant's count is zero, equal to the reference's, strictly
below it, at most it, or unconstrained.
-/
inductive Pred where
  | zero | eqO | ltO | leO | any
deriving Repr, DecidableEq

/-- The JSON spelling of a prediction. -/
def Pred.str : Pred → String
  | .zero => "=0" | .eqO => "=o" | .ltO => "<o" | .leO => "≤o" | .any => "any"

/-- **The prediction of one stage** from the model's passes per frame of the variant (`v`) and the reference (`o`).
`props` counts lifecycle frames, not work (note C §5), so it is never predicted. Equal non-zero passes give `≤o`, not
`=o`: the model counts one pass per frame, while a BeginMainFrame can run more lifecycle updates (MEASURED
UpdateLayoutTree 162 in 120 frames for the main-thread fixture, README:148).

(first matching case)
-/
def predOf (s : Stage) (v o : Nat) : Pred :=
  if s = .props then .any else if v < o then .ltO else if v = 0 then .zero else if v = o then .leO else .any

/-- The lane count types that observe each stage (design note §3.2); the consumer drops the types `classes.frozen.json`
quarantines.
-/
def stageCounts : Stage → List String
  | .script => ["trace.FireAnimationFrame", "trace.FunctionCall"]
  | .style => ["trace.UpdateLayoutTree"]
  | .layout => ["trace.Layout", "trace.Layout.dirtyObjects"]
  | .props => ["trace.PrePaint"]
  | .paint => ["trace.Paint", "raster.invalidationAreaPx", "raster.invalidationRects"]
  | .raster => ["raster.invalidationAreaPx", "raster.invalidationRects"]
  | .commit => ["trace.cc.Commit"]
  | .comp => ["census.layers"]

/-- The JSON name of a stage. -/
def stageName : Stage → String
  | .script => "script" | .style => "style" | .layout => "layout" | .props => "props" | .paint => "paint"
  | .raster => "raster" | .commit => "commit" | .comp => "comp"

/-- The JSON name of a level. -/
def levelName : CrLevel → String
  | .none => "none" | .styleOnly => "styleOnly" | .direct => "direct" | .ppFull => "ppFull" | .raster => "raster"
  | .paint => "paint" | .layoutMove => "layoutMove" | .layoutPos => "layoutPos" | .layoutFull => "layoutFull"

/-- The JSON name of a layer state. -/
def layerName : LayerState → String
  | .none => "none" | .layer => "layer" | .own => "own"

/-- The lane fixture with nothing animating (reference of F1). -/
def fxRest : List CrAnim := []

/-- `packages/measure-chromium/fixtures/anim-compositor`: a `transform` animation on a `will-change: transform` box and
an `opacity` animation (its own layer through the active-animation compositing reason,
`B/core/paint/compositing/compositing_reason_finder.cc:563-600`, CONFIRMED in note C).
-/
def fxAnimComp : List CrAnim :=
  [⟨0, [.css .transform], .own, true, .document⟩, ⟨1, [.css .opacity], .own, true, .document⟩]

/-- `packages/measure-chromium/fixtures/anim-layout`: a `width` animation and a `background-color` animation, both on
plain boxes.
-/
def fxAnimLayout : List CrAnim :=
  [⟨0, [.css .width], .none, true, .document⟩, ⟨1, [.css .backgroundColor], .none, true, .document⟩]

/-- One golden stage row: test id, scenario and reference names and animations, lane mode, one stage, with the
model's passes and units per frame for both and the prediction.
-/
def stageRow (test x : String) (ax : List CrAnim) (y : String) (ay : List CrAnim) (s : Stage) : Lean.Json :=
  let wv := frameWork chromium (animFrame lane ax)
  let wo := frameWork chromium (animFrame lane ay)
  Lean.Json.mkObj [("kind", "stage"), ("test", .str test), ("scenario", .str x), ("ref", .str y), ("mode", "lane"),
    ("stage", .str (stageName s)), ("counts", Lean.toJson (stageCounts s)),
    ("v", Lean.toJson (wv.passes s)), ("o", Lean.toJson (wo.passes s)),
    ("vUnits", Lean.toJson (wv.units s)), ("oUnits", Lean.toJson (wo.units s)),
    ("pred", .str (predOf s (wv.passes s) (wo.passes s)).str)]

/-- The number of animations whose failure bits contain bit `b` in the lane. -/
def bitCount (b : Nat) (as : List CrAnim) : Nat := (as.filter fun a => decide (b ∈ failBits lane a)).length

/-- One golden F0 row: the number of the scenario's animations with bit 0 set in the lane (always 0,
`failBits_lane_no0`).
-/
def f0Row (x : String) (ax : List CrAnim) : Lean.Json :=
  Lean.Json.mkObj [("kind", "stage"), ("test", "F0"), ("scenario", .str x), ("ref", "rest"), ("mode", "lane"),
    ("stage", "comp"), ("counts", Lean.toJson ["trace.Animation.compositeFailedBits.bit0"]),
    ("v", Lean.toJson (bitCount 0 ax)), ("o", Lean.toJson (bitCount 0 fxRest)), ("vUnits", Lean.toJson (0 : Nat)),
    ("oUnits", Lean.toJson (0 : Nat)), ("pred", .str (if bitCount 0 ax = 0 then Pred.zero else Pred.any).str)]

/-- One signature row per level: its rank, its stages, and every (plain property, layer state) pair `keyLevel` maps
to it.
-/
def signatureRow (lv : CrLevel) : Lean.Json :=
  let members := CrKey.all.flatMap fun k =>
    ([LayerState.none, .layer, .own].filter fun l => decide (keyLevel k l = lv)).map fun l => s!"{k.name}@{layerName l}"
  Lean.Json.mkObj [("kind", "signature"), ("level", .str (levelName lv)), ("rank", Lean.toJson lv.rank),
    ("stages", Lean.toJson (lv.stages.map stageName)), ("members", Lean.toJson members)]

/-- One mode row: the mode's flags and the stages one compositor animation costs per frame. -/
def modeRow (x : String) (m : CrMode) : Lean.Json :=
  Lean.Json.mkObj [("kind", "mode"), ("mode", .str x), ("threadedAnim", Lean.toJson m.threadedAnim),
    ("everyBeginFrameIsMainFrame", Lean.toJson m.everyBeginFrameIsMainFrame),
    ("compStages", Lean.toJson ((crCompStages m).map stageName))]

/-- **All golden rows**, in order: one signature row per level, one row per mode, the F0 rows (bit 0 per fixture),
then per stage the F1 rows (compositor fixture against rest) and the F2 rows (compositor fixture against the
main-thread fixture).
-/
def goldenRows : List Lean.Json :=
  CrLevel.all.map signatureRow ++ [modeRow "lane" lane, modeRow "realChrome" realChrome] ++
    [f0Row "rest" fxRest, f0Row "anim-compositor" fxAnimComp, f0Row "anim-layout" fxAnimLayout] ++
    Stage.all.map (stageRow "F1" "anim-compositor" fxAnimComp "rest" fxRest) ++
    Stage.all.map (stageRow "F2" "anim-compositor" fxAnimComp "anim-layout" fxAnimLayout)

/-- The text of `chromium.jsonl`: one compressed JSON object per line. -/
def goldenText : String := String.join (goldenRows.map fun r => r.compress ++ "\n")

/-- The golden file, relative to `lean/`. -/
def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "engine" / "chromium.jsonl"

/-- Write the golden file (`write`) or compare it; returns 1 when the file is stale, else 0. Run from `lean/` as
`lake env lean --run <script>` with a script whose `main` calls `Fw.Engine.Chromium.goldenRun "." (write)`.
-/
def goldenRun (root : System.FilePath) (write : Bool) : IO Nat := do
  let p := root / goldenPath
  if write then
    if let some d := p.parent then IO.FS.createDirAll d
    IO.FS.writeFile p goldenText
    IO.println s!"chromium golden: {goldenRows.length} rows written to {p}"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur == goldenText then
    IO.println s!"chromium golden: {goldenRows.length} rows, up to date"
    return 0
  IO.println s!"chromium golden: {p} is stale"
  return 1

#guard goldenRows.length == 9 + 2 + 3 + 8 + 8
#guard (frameWork chromium (animFrame lane fxAnimComp)).passes .style == 1
#guard (frameWork chromium (animFrame lane fxAnimComp)).units .style == 2
#guard (frameWork chromium (animFrame lane fxAnimComp)).passes .commit == 0
#guard (frameWork chromium (animFrame lane fxAnimLayout)).passes .layout == 1
#guard (frameWork chromium (animFrame lane fxAnimLayout)).units .paint == 2
#guard (frameWork (chromiumAt realChrome) (animFrame realChrome fxAnimComp)).passes .style == 0
#guard predOf .layout 0 1 == .ltO && predOf .layout 0 0 == .zero && predOf .props 0 1 == .any
#guard predOf .style 1 1 == .leO && predOf .style 1 0 == .any

/-! ## Engine mechanisms (why-engines)

Each section below closes one ledger statement (`research/findings/ledger.json`, `missingWhy` of
`Fw.Engine.Chromium`) with the mechanism read from Chromium source @f842f52 (`B/` = `third_party/blink/renderer/`).
A corrected rule is a new definition with a bridge theorem back to the old one, as `frameWorkE` does in
`Fw.Engine.Core`. Exception: the counterexamples of CI run 39088367495 (task engine-model-fix) corrected the tables
above themselves (`keyLevel`, `CrLevel.stages`, the base stage) and the hit count of `crWorkH`. -/

/-! ### Hit tests run PrePaint (ledger n=3) -/

/-- **The hover hit test after a layout** (CI run 39088367495). `LocalFrameView::PerformPostLayoutTasks` marks the
hover state dirty after every layout (`B/core/frame/local_frame_view.cc:1960-1965`@f842f52, CONFIRMED), and the widget
recomputes a dirty hover state with a hit test at the mouse position (`B/core/frame/web_frame_widget_impl.cc:3058-3063`,
CONFIRMED). That the hit test lands in the same frame is MEASURED: each of the 18 Chromium steps with a layout counted
`trace.HitTest` in 3 of 3 passes, and no step without a layout did except the `elementFromPoint` step. A forced layout (`forcedLayout`) is not
counted: the run measured only frame layouts.

One hover hit test in a frame whose lifecycle runs layout, none otherwise.
-/
def crHover (m : CrMode) (f : FrameIn CrProp) : Nat :=
  if Stage.layout ∈ touched (chromiumAt m) f then 1 else 0

/-- **Frame work with hit tests on PrePaint** (ledger n=3). A hit test (`elementFromPoint`, `TreeScope::HitTestPoint`,
`B/core/dom/tree_scope.cc:246-281, 421-437`) calls `LayoutView::HitTest`, which first runs
`UpdateAllLifecyclePhasesExceptPaint` (`B/core/layout/layout_view.cc:149-151`), i.e. the lifecycle up to
`kPrePaintClean` (`B/core/frame/local_frame_view.cc:2199-2203`). That path has no "already clean" early return
(`:2395-2452`) and emits the `PrePaint` trace event on every run (`:2570-2593`). So each hit test costs one PrePaint
(`props`) pass on top of the frame's own lifecycle. CONFIRMED.

Since CI run 39088367495 the hit count also has the **hover hit test** (`crHover`): a frame whose lifecycle runs
layout pays one more hit test. Its PrePaint is not added: the hover path may enter at `HitTestNoLifecycleUpdate`
(`B/core/layout/layout_view.cc:160-164`), and the pinned sparse clone lacks `event_handler.cc` to tell.

Chromium's frame work in which every hit test also pays one PrePaint pass and a layout frame pays a hover hit test. -/
def crWorkH (m : CrMode) (f : FrameIn CrProp) : Work where
  passes s := (frameWork (chromiumAt m) f).passes s + (if s = .props then f.hits else 0)
  units s := (frameWork (chromiumAt m) f).units s
  hits := f.hits + crHover m f

/-- **PrePaint passes are at least the hit tests.**

Every hit test in a frame shows up as a PrePaint pass. -/
theorem crWorkH_props_ge_hits (m : CrMode) (f : FrameIn CrProp) : f.hits ≤ (crWorkH m f).passes .props := by
  simp [crWorkH]

/-- **The old frame work is a lower bound.**

Adding the PrePaint pass of each hit test and the hover hit test only raises the work. -/
theorem crWorkH_ge (m : CrMode) (f : FrameIn CrProp) : (frameWork (chromiumAt m) f).le (crWorkH m f) :=
  ⟨fun _ => ⟨Nat.le_add_right _ _, Nat.le_refl _⟩, Nat.le_add_right _ _⟩

/-- **A layout frame pays one hover hit test**, a frame without layout none.

The hit count is the page's hit tests plus one when the frame lays out.
-/
theorem crWorkH_hits (m : CrMode) (f : FrameIn CrProp) :
    (crWorkH m f).hits = f.hits + (if Stage.layout ∈ touched (chromiumAt m) f then 1 else 0) := rfl

/-- **No hit test, no change.**

Without hit tests the corrected and the old pass counts agree. -/
theorem crWorkH_no_hits (m : CrMode) (f : FrameIn CrProp) (h : f.hits = 0) (s : Stage) :
    (crWorkH m f).passes s = (frameWork (chromiumAt m) f).passes s := by
  simp [crWorkH, h]

/-- **Skipping one hit test removes exactly one PrePaint pass** (the hit-skip variant of `nav.hitTest`).

A frame that skips one probe runs one PrePaint fewer, whatever else it does. -/
theorem hitSkip_props (m : CrMode) (f : FrameIn CrProp) :
    (crWorkH m { f with hits := f.hits + 1 }).passes .props = (crWorkH m f).passes .props + 1 := by
  simp [crWorkH, frameWork, touched, forcedPasses, FrameIn.updates]
  omega

#guard (crWorkH lane ⟨0, 0, 0, 0, [⟨0, .css .width, .none⟩], 0⟩).hits == 1
#guard (crWorkH lane ⟨0, 0, 0, 0, [⟨0, .css .top, .own⟩], 0⟩).hits == 1
#guard (crWorkH lane ⟨0, 0, 0, 0, [⟨0, .css .transform, .own⟩], 0⟩).hits == 0
#guard (crWorkH lane ⟨0, 0, 1, 0, [], 0⟩).hits == 0 && (crWorkH lane ⟨0, 0, 0, 2, [], 0⟩).hits == 2
#guard (crWorkH lane ⟨1, 0, 0, 0, [], 0⟩).passes .props == 1

/-! ### Hit-test units: single point vs list (ledger n=4, first statement) -/

/-- The kind of a hit test: a single point (`elementFromPoint`) or a list-based one (`elementsFromPoint`). -/
inductive HitKind where
  | single | list
deriving Repr, DecidableEq

/-- **Which hit tests the cache may serve.** `HitTestCache::LookupCachedResult` and `AddCachedResult` return early for
list-based (and rect-based) requests (`B/core/layout/hit_test_cache.cc:54-56`, `B/core/layout/hit_test_request.h:146-152`
`AvoidCache`). CONFIRMED.

Only a single-point hit test can be answered from the hit-test cache. -/
def HitKind.cacheable : HitKind → Bool
  | .single => true
  | .list => false

/-- **Hit-test units**: the boxes a hit test visits among `n` candidate boxes in paint order, when the first hit is
at depth `d`. A cached single-point test visits none; an uncached one stops at the first hit; a list-based test is
never cached and keeps going past every hit (`HitTestResult::AddNodeToListBasedTestResult` returns "continue" for a
penetrating list, `B/core/layout/hit_test_result.cc:565-586`), so it visits all `n`. CONFIRMED.

The boxes one hit test walks: none on a cache hit, up to the first hit for a single point, all for a list. -/
def hitUnits (k : HitKind) (cacheHit : Bool) (d n : Nat) : Nat :=
  match k with
  | .single => if cacheHit then 0 else min (d + 1) n
  | .list => n

/-- **A single-point test never visits more than a list-based one.**

Whatever the cache does, the list-based test walks at least as many boxes. -/
theorem single_le_list (c c' : Bool) (d n : Nat) : hitUnits .single c d n ≤ hitUnits .list c' d n := by
  cases c <;> simp [hitUnits]; omega

/-- **When the list costs strictly more.** Uncached, the list-based test walks strictly more boxes iff the first hit
lies before the last candidate.

The trade is strict exactly when boxes lie behind the first hit. -/
theorem single_lt_list_iff (d n : Nat) : hitUnits .single false d n < hitUnits .list false d n ↔ d + 1 < n := by
  simp [hitUnits]; omega

/-- **A list-based test ignores the cache.**

The list-based answer is never served from the cache and always walks every candidate. -/
theorem list_uncached (c : Bool) (d n : Nat) : HitKind.cacheable .list = false ∧ hitUnits .list c d n = n :=
  ⟨rfl, rfl⟩

#guard hitUnits .single true 2 9 == 0 && hitUnits .single false 2 9 == 3 && hitUnits .list true 2 9 == 9
#guard hitUnits .single false 12 9 == 9 && HitKind.cacheable .single && !HitKind.cacheable .list

/-! ### Paint fan-out of an inherited pointer-events write (ledger n=4, second statement) -/

/-- Duplicate-free copy of a list, keeping the last occurrence of each value.

The list with repeated values removed. -/
def nub {α : Type} [DecidableEq α] : List α → List α
  | [] => []
  | x :: l => if x ∈ l then nub l else x :: nub l

/-- `nub` keeps exactly the members.

Removing duplicates loses no value. -/
theorem mem_nub {α : Type} [DecidableEq α] (l : List α) (y : α) : y ∈ nub l ↔ y ∈ l := by
  induction l with
  | nil => simp [nub]
  | cons x l ih =>
    by_cases hx : x ∈ l
    · simp only [nub, hx, ↓reduceIte, ih, List.mem_cons]
      constructor
      · exact Or.inr
      · rintro (rfl | h)
        · exact hx
        · exact h
    · simp [nub, hx, ih]

/-- `nub` never lengthens.

Dropping duplicates gives at most as many values. -/
theorem nub_length_le {α : Type} [DecidableEq α] (l : List α) : (nub l).length ≤ l.length := by
  induction l with
  | nil => simp [nub]
  | cons x l ih =>
    by_cases hx : x ∈ l <;> simp [nub, hx] <;> omega

/-- `nub` of a non-empty list is non-empty.

A non-empty list keeps at least one value. -/
theorem nub_length_pos {α : Type} [DecidableEq α] (l : List α) (h : l ≠ []) : 1 ≤ (nub l).length := by
  cases l with
  | nil => exact absurd rfl h
  | cons x l =>
    have hm : x ∈ nub (x :: l) := (mem_nub _ x).2 (List.mem_cons_self ..)
    cases hn : nub (x :: l) with
    | nil => rw [hn] at hm; simp at hm
    | cons _ _ => simp

/-- `nub` of a duplicate-free list is the list.

A list with no repeated value is left as it is. -/
theorem nub_eq_of_nodup {α : Type} [DecidableEq α] (l : List α) (h : l.Nodup) : nub l = l := by
  induction l with
  | nil => rfl
  | cons x l ih =>
    rw [List.nodup_cons] at h
    simp [nub, h.1, ih h.2]

/-- `nub` of a non-empty list of one repeated value is that value once.

A list that repeats one value collapses to it. -/
theorem nub_eq_single {α : Type} [DecidableEq α] (l : List α) (y : α) (hne : l ≠ []) (h : ∀ x ∈ l, x = y) :
    nub l = [y] := by
  induction l with
  | nil => exact absurd rfl hne
  | cons x l ih =>
    have hx : x = y := h x (List.mem_cons_self ..)
    cases l with
    | nil => simp [nub, hx]
    | cons z l =>
      have hz : x ∈ z :: l := by
        rw [hx, h z (List.mem_cons_of_mem _ (List.mem_cons_self ..))]
        exact List.mem_cons_self ..
      simp only [nub, hz, ↓reduceIte]
      exact ih (List.cons_ne_nil _ _) (fun w hw => h w (List.mem_cons_of_mem _ hw))

/-- **Paint units of an inherited `pointer-events` write** (ledger n=4). `pointer-events` is inherited
(`B/core/css/css_properties.json5:5316-5328`); a changed value on a box sets
`SetShouldInvalidatePaintForHitTest` (`B/core/layout/layout_object.cc:3477-3480, 5211-5219`), which pre-paint turns
into `SetNeedsRepaint` on the box's **painting layer** (`B/core/paint/pre_paint_tree_walk.cc:285-302`). So the
repaint units are the distinct painting layers among the boxes that inherit the value, not the boxes. CONFIRMED.

One repaint per painting layer reached by the inherited value. -/
def pePaintUnits (layerOf : Nat → Nat) (inh : List Nat) : Nat := (nub (inh.map layerOf)).length

/-- **Bounds of the fan-out.** At least one layer repaints when some box inherits the value, and never more than one
per inheriting box.

The old row's "one unit per inheriting box" is only an upper bound. -/
theorem pePaintUnits_bounds (layerOf : Nat → Nat) (inh : List Nat) :
    pePaintUnits layerOf inh ≤ inh.length ∧ (inh ≠ [] → 1 ≤ pePaintUnits layerOf inh) := by
  refine ⟨?_, fun h => ?_⟩
  · have := nub_length_le (inh.map layerOf)
    simpa [pePaintUnits] using this
  · apply nub_length_pos
    simpa using h

/-- **One layer per box: the old count holds.**

When every inheriting box paints into its own layer, each costs one repaint. -/
theorem pePaintUnits_distinct (layerOf : Nat → Nat) (inh : List Nat) (h : (inh.map layerOf).Nodup) :
    pePaintUnits layerOf inh = inh.length := by
  simp [pePaintUnits, nub_eq_of_nodup _ h]

/-- **One shared layer: one repaint.**

Boxes that share one painting layer cost one repaint together. -/
theorem pePaintUnits_shared (layerOf : Nat → Nat) (inh : List Nat) (L : Nat) (hne : inh ≠ [])
    (h : ∀ b ∈ inh, layerOf b = L) : pePaintUnits layerOf inh = 1 := by
  have hm : ∀ x ∈ inh.map layerOf, x = L := by
    intro x hx
    obtain ⟨b, hb, rfl⟩ := List.mem_map.1 hx
    exact h b hb
  simp [pePaintUnits, nub_eq_single _ L (by simpa using hne) hm]

#guard pePaintUnits id [1, 2, 3] == 3 && pePaintUnits (fun _ => 7) [1, 2, 3] == 1
#guard pePaintUnits (fun b => b / 2) [2, 3, 4] == 2 && pePaintUnits id [] == 0

/-! ### Opacity crossing 1 (ledger n=19) -/

/-- **The level of an opacity change that crosses 1** (ledger n=19). `opacity < 1` makes a box a stacking context
(`HasOpacity`, `B/core/style/computed_style.h:2085`; `CalculateIsStackingContextWithoutContainment`,
`B/core/style/computed_style.cc:2958-2995`). When the stacking-context bit flips, the style diff asks for a full
layout and a paint invalidation (`computed_style.cc:779-784`). It does not flip when another reason keeps the box a
stacking context (a transform, a running opacity animation, `will-change`, a z-index on a positioned box, ...); then
the change is the plain opacity row. CONFIRMED.

Crossing 1 relays out the box unless it is a stacking context for another reason. -/
def opacityCross1Level (otherSC : Bool) (l : LayerState) : CrLevel :=
  if otherSC then keyLevel .opacity l else .layoutFull

/-- **A stacking-context flip lays out.**

Without another stacking-context reason, crossing 1 costs a layout. -/
theorem opacityCross1_layout (l : LayerState) : Stage.layout ∈ (opacityCross1Level false l).stages := by
  simp [opacityCross1Level, CrLevel.stages]

/-- **No flip, no new row.**

A box that stays a stacking context pays the plain opacity row. -/
theorem opacityCross1_otherSC (l : LayerState) : opacityCross1Level true l = keyLevel .opacity l := rfl

/-- **Resting at 0.999 never lays out** (the `people.carousel` rest at opacity 0.999): an opacity change that stays
below 1 is the plain opacity row, which is at most the crossing row and has no layout.

Staying below 1 costs no more than crossing it, and never a layout. -/
theorem rest999_le (o : Bool) (l : LayerState) :
    keyLevel .opacity l ≤ opacityCross1Level o l ∧ Stage.layout ∉ (keyLevel .opacity l).stages := by
  cases o <;> cases l <;> decide

#guard opacityCross1Level false .own == .layoutFull && opacityCross1Level true .own == .direct
#guard opacityCross1Level true .none == .raster

/-! ### The extended property type and engine -/

/-- **Chromium properties with the why-engines rows.** `base p` is a row of the table above; `opacityCross1 o` an
opacity change across 1 (`o`: another stacking-context reason); `pointerEvents` an inherited `pointer-events` write;
`svgPaintServerAttr` a geometry attribute (`x1`, `x2`, `y1`, `y2`) of an SVG gradient.

The Chromium property type extended by the rows this section proves. -/
inductive CrPropX where
  | base (p : CrProp)
  | opacityCross1 (otherSC : Bool)
  | pointerEvents
  | svgPaintServerAttr
deriving Repr, DecidableEq

/-- **Stages of the extended rows.** `base` keeps `crStagesOf`; `opacityCross1` takes its level's stages;
`pointerEvents` restyles, runs pre-paint (where the hit-test paint invalidation is applied,
`pre_paint_tree_walk.cc:285-302`), repaints, and commits (the commit is INFERRED from the repaint). An SVG gradient
attribute runs no style recalc: `SVGLinearGradientElement::SvgAttributeChanged` handles `x1`/`x2`/`y1`/`y2` by
`InvalidateGradient` (`B/core/svg/svg_linear_gradient_element.cc:69-78`, `B/core/svg/svg_gradient_element.cc:135-138`),
which removes the resource's cached data and marks every client for **paint** invalidation only
(`B/core/layout/svg/layout_svg_resource_container.cc:337-342`,
`B/core/layout/svg/layout_svg_resource_gradient.cc:81-86`). CONFIRMED except the noted commit.

The stages each extended Chromium change dirties. -/
def crStagesOfX (c : Change CrPropX) : List Stage :=
  match c.prop with
  | .base p => crStagesOf ⟨c.elem, p, c.layer⟩
  | .opacityCross1 o => (opacityCross1Level o c.layer).stages
  | .pointerEvents => [.style, .props, .paint, .commit]
  | .svgPaintServerAttr => [.props, .paint, .raster, .commit]

/-- **The extended Chromium engine in mode `m`**: `chromiumAt m` with the extended rows.

The Chromium engine over the extended property type (base `props` like `chromiumAt` since CI run 39088367495). -/
def chromiumX (m : CrMode) : Engine CrPropX CrMode where
  mode := m
  stagesOf := crStagesOfX
  compStages := crCompStages m
  base := [.props]

/-- A table change as an extended change.

Wraps an old Chromium change in the extended type. -/
def liftCr (c : Change CrProp) : Change CrPropX := ⟨c.elem, .base c.prop, c.layer⟩

/-- A frame of table changes as an extended frame.

Wraps every change of an old Chromium frame. -/
def liftCrFrame (f : FrameIn CrProp) : FrameIn CrPropX :=
  ⟨f.script, f.forcedStyle, f.forcedLayout, f.hits, f.changes.map liftCr, f.compAnims⟩

/-- **The extension keeps the old table.** A lifted frame has the same passes, units and hit tests under the
extended engine.

Every theorem about the old Chromium rows carries over to the extended engine. -/
theorem chromiumX_lift (m : CrMode) (f : FrameIn CrProp) (s : Stage) :
    (frameWork (chromiumX m) (liftCrFrame f)).passes s = (frameWork (chromiumAt m) f).passes s ∧
      (frameWork (chromiumX m) (liftCrFrame f)).units s = (frameWork (chromiumAt m) f).units s ∧
      (frameWork (chromiumX m) (liftCrFrame f)).hits = (frameWork (chromiumAt m) f).hits := by
  have hs : ∀ c : Change CrProp, crStagesOfX (liftCr c) = crStagesOf c := fun _ => rfl
  have hfm : (f.changes.map liftCr).flatMap crStagesOfX = f.changes.flatMap crStagesOf := by
    induction f.changes with
    | nil => rfl
    | cons c cs ih => simp only [List.map_cons, List.flatMap_cons, hs, ih]
  have hcount : (f.changes.map liftCr).countP (fun c => decide (s ∈ (chromiumX m).stagesOf c)) =
      f.changes.countP (fun c => decide (s ∈ (chromiumAt m).stagesOf c)) := by
    induction f.changes with
    | nil => rfl
    | cons c cs ih => rw [List.map_cons, List.countP_cons, List.countP_cons, ih]; rfl
  refine ⟨?_, ?_, rfl⟩
  · simp only [frameWork, touched, chromiumX, chromiumAt, liftCrFrame, FrameIn.updates, forcedPasses, hfm,
      List.isEmpty_map]
    cases s <;> rfl
  · simp only [frameWork, stageUnits, liftCrFrame]
    rw [hcount]
    rfl

/-- **An SVG gradient attribute repaints without layout** (ledger n=24): one change of `x1`/`x2`/`y1`/`y2` in a
frame with nothing else costs no layout and no style pass, one paint pass.

In Chromium a SMIL gradient attribute step is a repaint only. -/
theorem svgAttr_paint_only (m : CrMode) (e : Nat) (l : LayerState) :
    (frameWork (chromiumX m) ⟨0, 0, 0, 0, [⟨e, .svgPaintServerAttr, l⟩], 0⟩).passes .layout = 0 ∧
      (frameWork (chromiumX m) ⟨0, 0, 0, 0, [⟨e, .svgPaintServerAttr, l⟩], 0⟩).passes .style = 0 ∧
      (frameWork (chromiumX m) ⟨0, 0, 0, 0, [⟨e, .svgPaintServerAttr, l⟩], 0⟩).passes .paint = 1 := by
  simp [frameWork, touched, chromiumX, crStagesOfX, forcedPasses, FrameIn.updates]

#guard crStagesOfX ⟨1, .svgPaintServerAttr, .none⟩ == [.props, .paint, .raster, .commit]
#guard crStagesOfX ⟨1, .opacityCross1 false, .own⟩ == CrLevel.layoutFull.stages
#guard crStagesOfX ⟨1, .base (.css .opacity), .own⟩ == crStagesOf ⟨1, .css .opacity, .own⟩
#guard crStagesOfX ⟨1, .pointerEvents, .layer⟩ == [.style, .props, .paint, .commit]

/-! ### Animations with no visible change (ledger n=25) -/

/-- **Failure bits with bit 17.** Bit 17 `kAnimationHasNoVisibleChange` (`B/core/animation/compositor_animations.h:116-120`)
is set when the animation cannot change any pixel (`compositor_animations.cc:285-290, 491-495, 514-588`). `vis` says
whether the animation can change pixels. CONFIRMED for the bit; whether an effective opacity of 0 on the target sets
it is the open premise of ledger n=25 (CI fixture R6).

The modelled failure bits plus the no-visible-change bit. -/
def failBitsV (m : CrMode) (a : CrAnim) (vis : Bool) : List Nat :=
  failBits m a ++ (if vis then [] else [17])

/-- Where a running animation is serviced: on the compositor, on the main thread every frame, or nowhere. -/
inductive CrRun where
  | comp | main | idle
deriving Repr, DecidableEq

/-- **The thread rule with bit 17.** `Animation::animation_has_no_effect_` is set iff the failure reasons are exactly
`kAnimationHasNoVisibleChange` (`B/core/animation/animation.cc:860-865`), and such an animation is not ticked on the
main thread (`:3389-3393`) nor started on the compositor: it idles. Otherwise the old rule applies. CONFIRMED.

An animation that can change no pixel and has no other failure is neither ticked nor composited. -/
def crRunV (m : CrMode) (a : CrAnim) (vis : Bool) : CrRun :=
  if failBitsV m a vis = [17] then .idle else if crThread m a = .comp then .comp else .main

/-- **Bit 17 is not among the modelled bits.**

The old bit list never contains the no-visible-change bit. -/
theorem failBits_no17 (m : CrMode) (a : CrAnim) : 17 ∉ failBits m a := by
  simp only [failBits, List.mem_append]
  split <;> split <;> split <;> split <;> split <;> simp

/-- **A visible animation keeps the old rule.**

For an animation that changes pixels, the bit-17 rule is `crThread`. -/
theorem crRunV_visible (m : CrMode) (a : CrAnim) :
    crRunV m a true = if crThread m a = .comp then .comp else .main := by
  have h : failBitsV m a true ≠ [17] := by
    intro h
    have : 17 ∈ failBits m a := by simp [failBitsV] at h; simp [h]
    exact failBits_no17 m a this
  simp [crRunV, h]

/-- **When an invisible animation idles.**

An animation with no visible change idles exactly when nothing else stops it from compositing. -/
theorem crRunV_idle_iff (m : CrMode) (a : CrAnim) : crRunV m a false = .idle ↔ failBits m a = [] := by
  constructor
  · intro h
    simp only [crRunV] at h
    split at h
    · rename_i hb
      simp only [failBitsV, Bool.false_eq_true, ↓reduceIte] at hb
      cases hf : failBits m a with
      | nil => rfl
      | cons x xs =>
        rw [hf] at hb
        cases xs with
        | nil => simp at hb
        | cons y ys => simp at hb
    · split at h <;> cases h
  · intro h
    simp [crRunV, failBitsV, h]

/-- **One frame of animations with visibility flags**: like `animFrame`, but an idle animation contributes nothing.

The frame of running animations once idle ones are dropped. -/
def animFrameV (m : CrMode) (as : List (CrAnim × Bool)) : FrameIn CrProp where
  script := 0
  forcedStyle := 0
  forcedLayout := 0
  hits := 0
  changes := (as.filter fun x => decide (crRunV m x.1 x.2 = .main)).flatMap fun x => x.1.changes
  compAnims := (as.filter fun x => decide (crRunV m x.1 x.2 = .comp)).length

/-- **All visible: the old frame.**

With every animation visible, the bit-17 frame is the old frame. -/
theorem animFrameV_visible (m : CrMode) (as : List CrAnim) :
    animFrameV m (as.map fun a => (a, true)) = animFrame m as := by
  have hr : ∀ a : CrAnim, crRunV m a true = .main ↔ crThread m a = .main := by
    intro a; rw [crRunV_visible]; cases crThread m a <;> simp
  have hc : ∀ a : CrAnim, crRunV m a true = .comp ↔ crThread m a = .comp := by
    intro a; rw [crRunV_visible]; cases crThread m a <;> simp
  simp only [animFrameV, animFrame]
  congr 1
  · induction as with
    | nil => rfl
    | cons a as ih =>
      simp only [List.map_cons, List.filter_cons, hr a]
      split <;> simp [ih]
  · induction as with
    | nil => rfl
    | cons a as ih =>
      simp only [List.map_cons, List.filter_cons, hc a]
      split <;> simp [ih]

/-- **An idle animation drops out of the frame**, so pausing it saves nothing (ledger n=25: the hidden pause of an
animation that already idles is free).

Removing an idle animation leaves the frame, hence its work, unchanged. -/
theorem idle_drops (m : CrMode) (a : CrAnim) (v : Bool) (as : List (CrAnim × Bool)) (h : crRunV m a v = .idle) :
    animFrameV m ((a, v) :: as) = animFrameV m as := by
  simp [animFrameV, h]

#guard crRunV lane ⟨1, [.css .transform], .own, true, .document⟩ false == .idle
#guard crRunV lane ⟨1, [.css .transform], .own, true, .document⟩ true == .comp
#guard crRunV lane ⟨1, [.css .width], .own, true, .document⟩ false == .main
#guard crRunV lane ⟨1, [.css .transform], .own, false, .document⟩ false == .main

/-! ### Size-container style rounds (ledger n=22, Chromium half) -/

/-- The largest value of `f` over a list, 0 for the empty list.

The maximum of a measure over a list. -/
def maxOf {β : Type} (f : β → Nat) : List β → Nat
  | [] => 0
  | x :: l => max (f x) (maxOf f l)

/-- `maxOf` is monotone in the measure.

A pointwise smaller measure has a smaller maximum. -/
theorem maxOf_le {β : Type} (f g : β → Nat) (l : List β) (h : ∀ x ∈ l, f x ≤ g x) : maxOf f l ≤ maxOf g l := by
  induction l with
  | nil => simp [maxOf]
  | cons x l ih =>
    simp only [maxOf]
    have h1 := h x (List.mem_cons_self ..)
    have h2 := ih (fun y hy => h y (List.mem_cons_of_mem _ hy))
    omega

/-- `maxOf` bounds every member.

No member exceeds the maximum. -/
theorem le_maxOf {β : Type} (f : β → Nat) (l : List β) (x : β) (hx : x ∈ l) : f x ≤ maxOf f l := by
  induction l with
  | nil => simp at hx
  | cons y l ih =>
    simp only [maxOf]
    rcases List.mem_cons.1 hx with rfl | h
    · omega
    · have := ih h; omega

/-- `maxOf` of a mapped list.

Measuring after a map is measuring the composite. -/
theorem maxOf_map {β γ : Type} (f : γ → Nat) (h : β → γ) (l : List β) :
    maxOf f (l.map h) = maxOf (fun x => f (h x)) l := by
  induction l with
  | nil => rfl
  | cons x l ih => simp [maxOf, ih]

/-- **Chromium style rounds of one lifecycle update** (ledger n=22). Each chain lists the size containers on one
root-to-leaf path the style traversal reaches, outermost first, with `(id, layoutDirty)`. A container skips its
subtree's style recalc only if it **needs layout** and is eligible for size containment, or is being re-attached
(`Element::SkipStyleRecalcForContainer`, `B/core/dom/element.cc:5187-5225`, called at `:5360-5375`); the skipped
subtree is resumed during layout (`BlockNode::Layout` calls `UpdateStyleAndLayoutTreeForSizeContainer`). So the
rounds of style recalc are 1 plus the most layout-dirty containers on one chain; they run inside the one layout pass.
CONFIRMED (the re-attach case is folded into `layoutDirty`).

Chromium recalculates style once more per layout-dirty container nesting level. -/
def crRounds (chains : List (List (Nat × Bool))) : Nat :=
  1 + maxOf (fun ch => (ch.filter fun x => x.2).length) chains

/-- **Rounds are bounded by nesting depth.**

Only layout-dirty containers add a round, so the count is at most one more than the deepest chain. -/
theorem crRounds_le_depth (chains : List (List (Nat × Bool))) :
    crRounds chains ≤ 1 + maxOf List.length chains := by
  have := maxOf_le (fun ch : List (Nat × Bool) => (ch.filter fun x => x.2).length) List.length chains
    (fun ch _ => List.length_filter_le _ _)
  simp only [crRounds]; omega

/-- **Removing a container never adds a round** (Chromium).

Dropping `container-type` from one element can only lower Chromium's style rounds. -/
theorem crRounds_remove (chains : List (List (Nat × Bool))) (c : Nat) :
    crRounds (chains.map fun ch => ch.filter fun x => decide (x.1 ≠ c)) ≤ crRounds chains := by
  simp only [crRounds, maxOf_map]
  have := maxOf_le (fun ch : List (Nat × Bool) => ((ch.filter fun x => decide (x.1 ≠ c)).filter fun x => x.2).length)
    (fun ch => (ch.filter fun x => x.2).length) chains
    (fun ch _ => ((List.filter_sublist (l := ch)).filter _).length_le)
  omega

#guard crRounds [] == 1 && crRounds [[(1, true), (2, false), (3, true)], [(4, true)]] == 3
#guard crRounds [[(1, false), (2, false)]] == 1

/-! ### Refuted predictions of `model-checks`, re-judged (task model-bug-fixes)

`research/notes/2026/10-19-model-checks.md` refuted four Chromium rows on swipe-v1 (base run 39130874266). Each one is
re-judged here, on the same CI counts, under the adopted wave-1 class table
(`packages/measure-chromium/classes.frozen.json`), with the mechanism from Chromium source @f842f52. Two are class
findings (the frame a task's work lands in is not fixed), two are model findings (a forced style pass; a tween that
never starts). -/

section Refuted
open Fw.Measure

/-- **One unit of work crosses one frame boundary.** The main-thread frame is itself a task:
`ProxyImpl::ScheduledActionSendBeginMainFrame` posts `ProxyMain::BeginMainFrame` to the main-thread task runner
(`cc/trees/proxy_impl.cc:848-851`@f842f52, CONFIRMED), so a script task (timer, idle or observer callback) runs before or
after it by arrival order, and the harness books its work in the frame on either side. Moving `m` units from frame
`|p|` to frame `|p| + 1`.

The series in which `m` units of frame `|p|` were booked one frame later. -/
def crossFrame (p : Series) (a b m : Int) (q : Series) : Series := p ++ [a - m, b + m] ++ q

#guard crossFrame [5] 1 0 1 [2] == [5, 0, 1, 2]
#guard crossFrame [] 13 5 8 [] == [5, 13]

/-- **A crossing keeps the run total.**

Booking work one frame later moves it between frames and changes no total. -/
theorem crossFrame_total (p q : Series) (a b m : Int) :
    Measure.total (crossFrame p a b m q) = Measure.total (p ++ [a, b] ++ q) := by
  simp only [crossFrame, Measure.total, sumBy_append, sumBy, id]
  omega

/-- **Totals certify `=o` on a class with frame slack and no total slack.** For `stable(k + 1, 0)` the claim is about
totals (`Claim`), and equal observed totals pass.

A class that lets frames move but not totals judges `=o` by the totals. -/
theorem eqO_totals_pass (k : Nat) (b v : Series) (h : Measure.total v = Measure.total b) :
    EngineCheck.verdict .eqO (.stable (k + 1) 0) b v = .pass := by
  simp [EngineCheck.verdict, EngineCheck.passes, EngineCheck.exact, EngineCheck.slack, h]

/-- **A deterministic class refutes `=o` at the first differing frame.**

Under a frame-exact class a single moved unit is a model bug. -/
theorem eqO_det_bug (b v : Series) (h : diffFrames v b ≠ 0) :
    EngineCheck.verdict .eqO .deterministic b v = .bug := by
  simp [EngineCheck.verdict, EngineCheck.passes, EngineCheck.fails, EngineCheck.exact, h]

/-- **Two base runs that differ in a frame refute the deterministic class.**

A class that the base runs themselves break is stale, and a bug verdict judged in it is a class finding. -/
theorem det_stale (b₁ b₂ : Series) (h : diffFrames b₁ b₂ ≠ 0) : ¬ Within .deterministic b₁ b₂ := h

/-- **A comparison judged with a quarantined variant class is unusable.** `judgeClass` joins the two arms' classes,
and a quarantined class joins to quarantined with every class.

Nothing is concluded from a count type the class table quarantines. -/
theorem judge_quarantined (p : EngineCheck.Pred) (hz : p ≠ .zero) (ha : p ≠ .any) (cB : Class) (b v : Series) :
    EngineCheck.verdict p (EngineCheck.judgeClass p .quarantined cB) b v = .unusable .quarantined := by
  cases p <;> cases cB <;> simp_all [EngineCheck.judgeClass, Class.join, EngineCheck.verdict]

/-- **Row nav.hitTest `trace.FunctionCall =o`, re-judged** (hit-skip run 39131343835, elements-skip run 39131395370).
MEASURED: every differing frame pairs with its neighbour at an equal pair sum (e.g. frames 181-182: 13, 5 against
5, 13), base runs differ among themselves the same way (r2 against r1 in 6 frames), and all totals are 2552. So the
old `det` class was stale (`det_stale`) and the moves are frame-boundary crossings (`crossFrame_total`). The adopted
table quarantines `trace.FunctionCall` on the swipe-v1 rewrite arm (k = 57, t = 1), so the row is unusable, not a bug.

The FunctionCall row says nothing on the current classes; its frames move with task order, not with the flag. -/
theorem navHit_functionCall_rejudged (b v : Series) :
    EngineCheck.verdict .eqO (EngineCheck.judgeClass .eqO .quarantined .quarantined) b v = .unusable .quarantined :=
  judge_quarantined .eqO (by decide) (by decide) .quarantined b v

/-- **Row morph.mount:shift `metric.LayoutCount =o`, re-judged** (run 39131302530). MEASURED: the three base runs are
equal; one variant run books the layout of frame 525 at frame 524 (`[0, 1]` against `[1, 0]`), totals 94 = 94. The
shift arm mounts from an idle callback after a 150 ms timer (`apps/site/src/parts/morph.mount/index.tsx`), a task whose
place against `BeginMainFrame` is arrival order (`crossFrame`). The adopted class of the rewrite arm is
`stable(4, 0)`, so the row is judged by totals and passes.

A layout booked one frame early passes `=o` on the refrozen class. -/
theorem mount_layoutCount_rejudged (p q : Series) (a b m : Int) :
    EngineCheck.verdict .eqO (EngineCheck.judgeClass .eqO (.stable 4 0) (.stable 4 0)) (p ++ [a, b] ++ q)
      (crossFrame p a b m q) = .pass :=
  eqO_totals_pass 3 _ _ (crossFrame_total p q a b m)

#guard EngineCheck.verdict .eqO .deterministic [1, 0] [0, 1] == .bug
#guard EngineCheck.verdict .eqO (.stable 4 0) [1, 0] [0, 1] == .pass

/-- **The frame of a hidden section's return** (engine.scene `hidden-pause`). On return the arm removes
`data-fw-hidden` (a style change `c` of the subtree) and then seeks its animations with `getAnimations({subtree: true})`.
`Element::GetAnimationsInternal` first calls `UpdateStyleAndLayoutTreeForSubtree` (`B/core/dom/element.cc:833-842`),
which recalculates style whenever the subtree needs it (`B/core/dom/document.cc:3004-3020`), and every recalculation
emits one `UpdateLayoutTree` trace event (`document.cc:2815`); all CONFIRMED @f842f52. So the order "remove, then seek"
forces one style pass in the callback task; "seek, then remove" finds the subtree clean and forces none (INFERRED: no
other write is pending in that task).

The page frame `f` plus the return's write, and a forced style pass unless the seek runs first (`σ`). -/
def sceneReturn (f : FrameIn CrProp) (c : Change CrProp) (seekFirst : Bool) : FrameIn CrProp :=
  { f with changes := c :: f.changes, forcedStyle := f.forcedStyle + (if seekFirst then 0 else 1) }

/-- **Row engine.scene:hidden-pause `trace.UpdateLayoutTree ≤o`, corrected.** If the rest of the frame already
restyles, the return adds exactly its forced pass: one with "remove, then seek", none with "seek, then remove".
MEASURED (run 39131168588 against base 39130874266): one frame (351, scrollY 3420) has 4 passes against 3 in all three
runs, totals 1851 against 1850; the all-arms run 39131249517 gives the same 1851. Against `passes_not_compositional`
(`Fw.Engine.Compose`): the return's write joins the frame's style pass and is absorbed, but a forced pass is not a frame
pass and adds; the theorem holds for every rest-of-page frame `f`, so the columns and countdown arms (no forced pass)
leave the +1 unchanged.

The scene arm's `≤o` is false by one pass per return as written, and true once the seek runs before the removal. -/
theorem sceneReturn_style (m : CrMode) (f : FrameIn CrProp) (c : Change CrProp) (sf : Bool)
    (hf : Stage.style ∈ touched (chromiumAt m) f) :
    (frameWork (chromiumAt m) (sceneReturn f c sf)).passes .style =
      (frameWork (chromiumAt m) f).passes .style + (if sf then 0 else 1) := by
  have h' : Stage.style ∈ touched (chromiumAt m) (sceneReturn f c sf) := by
    simp only [touched, sceneReturn, FrameIn.updates, List.mem_append, List.mem_flatMap, List.mem_cons] at hf ⊢
    rcases hf with ((⟨x, hx, hs⟩ | h2) | h3) | h4
    · exact .inl (.inl (.inl ⟨x, .inr hx, hs⟩))
    · exact .inl (.inl (.inr h2))
    · refine .inl (.inr ?_)
      by_cases hu : (!f.changes.isEmpty || decide (0 < f.script)) = true
      · simp only [hu, ↓reduceIte] at h3; simpa using h3
      · simp only [hu] at h3; simp at h3
    · exact .inr h4
  show (if Stage.style ∈ touched (chromiumAt m) (sceneReturn f c sf) then 1 else 0) +
      forcedPasses (sceneReturn f c sf) .style =
    (if Stage.style ∈ touched (chromiumAt m) f then 1 else 0) + forcedPasses f .style + (if sf then 0 else 1)
  simp only [h', hf, ↓reduceIte]
  simp only [forcedPasses, sceneReturn]
  omega

/-- **A rAF series of one arm.** Each frame lists the callbacks the rest of the page registers and whether the
original's tween is running. `FrameRequestCallbackCollection::ExecuteFrameCallbacksImpl` emits one
`FireAnimationFrame` per registered, uncancelled callback
(`B/core/dom/frame_request_callback_collection.cc:95-116`@f842f52, CONFIRMED), and the original tween requests a frame
only between a push and its end (`Fw.Parts.MorphTweenOpt.stepO`); the `waapi` arm requests none.

The callbacks fired per frame: the page's own, plus one for the tween in the arm that runs it (`w`). -/
def rafSeries (fs : List (Nat × Bool)) (tween : Bool) : List Nat :=
  fs.map fun x => x.1 + if tween && x.2 then 1 else 0

#guard rafSeries [(2, false), (2, true)] true == [2, 3] && rafSeries [(2, false), (2, true)] false == [2, 2]

/-- **Row morph.tween:waapi `trace.FireAnimationFrame <o`, corrected.** The two arms fire the same callbacks in every
frame iff no frame runs the tween. swipe-v1 scrolls with `scrollTo` and never pushes the morph, so no frame does and the
row is `=o` on swipe-v1; `<o` needs a profile that pushes. MEASURED (run 39131146372): 1748 = 1748 in all three pairs.
The same cause gives the reverse row `trace.Animation.compositeFailedBits <o` (rewrite against waapi): no WAAPI
animation of `--morph` (registered, `inherits: true`) starts without a push, 167936 = 167936; the adopted table makes it
deterministic, so it surfaces as a bug under the new classes, and the old FireAnimationFrame row is now quarantined.

On a run without a push the waapi arm saves no animation frame. -/
theorem waapi_raf_eq_iff (fs : List (Nat × Bool)) :
    rafSeries fs false = rafSeries fs true ↔ ∀ x ∈ fs, x.2 = false := by
  induction fs with
  | nil => simp [rafSeries]
  | cons x xs ih =>
    simp only [rafSeries, List.map_cons, List.cons.injEq, List.mem_cons, forall_eq_or_imp] at ih ⊢
    rw [ih]
    cases x.2 <;> simp

end Refuted

end Fw.Engine.Chromium
