import Fw.Engine.Core
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

$$\mathrm{CrKey} = \{\mathrm{transform}, \mathrm{transformToggle}, \mathrm{translate}, \mathrm{scale}, \mathrm{rotate}, \mathrm{opacity}, \mathrm{backdropFilter}, \mathrm{bgPosition}, \mathrm{bgImage}, \mathrm{bgColor}, \mathrm{color}, \mathrm{clipPath}, \mathrm{strokeDashoffset}, \mathrm{visibility}, \mathrm{zIndex}, \mathrm{top}, \mathrm{left}, \mathrm{width}, \mathrm{height}, \mathrm{margin}, \mathrm{padding}\} \cup \{\mathrm{filter}(b) \mid b \in \mathbb{B}\}$$
-/
inductive CrKey where
  | transform | transformToggle | translate | scale | rotate | opacity
  | filter (blur : Bool) | backdropFilter
  | backgroundPosition | backgroundImage | backgroundColor | color | clipPath | strokeDashoffset
  | visibility | zIndex
  | top | left
  | width | height | margin | padding
deriving Repr, DecidableEq, Inhabited

/-- Every plain property once (both `filter` variants), in the order the golden signature rows list them.

$$\mathrm{CrKey.all} = [\mathrm{transform}, \mathrm{transformToggle}, \mathrm{translate}, \mathrm{scale}, \mathrm{rotate}, \mathrm{opacity}, \mathrm{filter}(\mathrm{false}), \mathrm{filter}(\mathrm{true}), \mathrm{backdropFilter}, \mathrm{bgPosition}, \mathrm{bgImage}, \mathrm{bgColor}, \mathrm{color}, \mathrm{clipPath}, \mathrm{strokeDashoffset}, \mathrm{visibility}, \mathrm{zIndex}, \mathrm{top}, \mathrm{left}, \mathrm{width}, \mathrm{height}, \mathrm{margin}, \mathrm{padding}]$$
-/
def CrKey.all : List CrKey :=
  [.transform, .transformToggle, .translate, .scale, .rotate, .opacity, .filter false, .filter true,
    .backdropFilter, .backgroundPosition, .backgroundImage, .backgroundColor, .color, .clipPath, .strokeDashoffset,
    .visibility, .zIndex, .top, .left, .width, .height, .margin, .padding]

/-- The CSS spelling of a plain property, as the golden rows print it (`filter(blur)` for a pixel-moving filter,
`transform(none<->some)` for the toggle).

$$\operatorname{name} : \mathrm{CrKey} \to \mathrm{String},\quad \operatorname{name}(\mathrm{bgColor}) = \texttt{"background-color"},\ \operatorname{name}(\mathrm{filter}(\mathrm{true})) = \texttt{"filter(blur)"},\ \ldots$$
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

$$\mathrm{CrProp} = \{\mathrm{css}(k) \mid k \in \mathrm{CrKey}\} \cup \{\mathrm{custom}(i, R) \mid i \in \mathbb{N},\ R \in \mathrm{CrKey}^{*}\} \cup \{\mathrm{scroll}(r) \mid r \in \mathbb{B}\}$$
-/
inductive CrProp where
  | css (k : CrKey)
  | custom (id : Nat) (readers : List CrKey)
  | scroll (repaint : Bool)
deriving Repr, DecidableEq

/-- The Chromium invalidation levels, lowest first: no change, a style recalc only, a direct (deferred) property-tree
update, a full paint-property update, a re-raster of shared chunks, a repaint, a positioned layout, a full layout.

$$\mathrm{CrLevel} = \{\mathrm{none}, \mathrm{styleOnly}, \mathrm{direct}, \mathrm{ppFull}, \mathrm{raster}, \mathrm{paint}, \mathrm{layoutPos}, \mathrm{layoutFull}\}$$
-/
inductive CrLevel where
  | none | styleOnly | direct | ppFull | raster | paint | layoutPos | layoutFull
deriving Repr, DecidableEq, Inhabited

/-- Every level once, lowest first.

$$\mathrm{CrLevel.all} = [\mathrm{none}, \mathrm{styleOnly}, \mathrm{direct}, \mathrm{ppFull}, \mathrm{raster}, \mathrm{paint}, \mathrm{layoutPos}, \mathrm{layoutFull}]$$
-/
def CrLevel.all : List CrLevel := [.none, .styleOnly, .direct, .ppFull, .raster, .paint, .layoutPos, .layoutFull]

/-- The position of a level in the chain.

$$\operatorname{rank}(\mathrm{none}) = 0,\ \operatorname{rank}(\mathrm{styleOnly}) = 1,\ \operatorname{rank}(\mathrm{direct}) = 2,\ \operatorname{rank}(\mathrm{ppFull}) = 3,\ \operatorname{rank}(\mathrm{raster}) = 4,\ \operatorname{rank}(\mathrm{paint}) = 5,\ \operatorname{rank}(\mathrm{layoutPos}) = 6,\ \operatorname{rank}(\mathrm{layoutFull}) = 7$$
-/
def CrLevel.rank : CrLevel → Nat
  | .none => 0 | .styleOnly => 1 | .direct => 2 | .ppFull => 3 | .raster => 4 | .paint => 5 | .layoutPos => 6
  | .layoutFull => 7

/-- The level order is the rank order.

$$a \le b \iff \operatorname{rank}(a) \le \operatorname{rank}(b)$$
-/
instance : LE CrLevel := ⟨fun a b => a.rank ≤ b.rank⟩

instance (a b : CrLevel) : Decidable (a ≤ b) := inferInstanceAs (Decidable (a.rank ≤ b.rank))

/-- The larger of two levels (the second on a tie).

$$\max(a, b) = \begin{cases} b & \operatorname{rank}(a) \le \operatorname{rank}(b) \\ a & \text{otherwise} \end{cases}$$
-/
def CrLevel.max (a b : CrLevel) : CrLevel := if a.rank ≤ b.rank then b else a

/-- **The stage list of each level** (design note §1.2, note C §2.2).
* `none`: no stage (`B/core/style/computed_style.cc:767-931`, empty diff). CONFIRMED.
* `styleOnly`: style recalc only (a custom property no plain property reads). INFERRED.
* `direct`: style, props, commit. `transform` some-to-some or `opacity` on a box with its own cc layer: deferred node
  update (`B/core/paint/paint_layer.cc:2469-2497`), direct cc write
  (`B/core/paint/paint_property_tree_builder.cc:1224-1262`). CONFIRMED; commit per frame MEASURED (README:148).
* `ppFull`: style, props, commit. `translate`/`scale`/`rotate`/`filter` on its own layer, `backdrop-filter`
  (`computed_style.cc:881-891`, `B/core/layout/layout_object.cc:3224-3230`). CONFIRMED.
* `raster`: style, props, raster, commit. A transform, opacity or filter value on a box without its own layer
  re-rasters its chunks (`B/platform/graphics/paint/raster_invalidator.cc:64-142`). INFERRED.
* `paint`: style, props, paint, raster, commit. background-*, color, clip-path, stroke-dashoffset, visibility, z-index
  (`computed_style.cc:1104-1120`, `layout_object.cc:2932-2948`). CONFIRMED.
* `layoutPos`: adds layout. top/left of a positioned box (`computed_style.cc:792-798`). CONFIRMED (paint INFERRED).
* `layoutFull`: the same stages; width/height/margin/padding, a transform toggle that flips the stacking state
  (`computed_style.cc:779-784, 986-988`). CONFIRMED.

$$\begin{aligned} \operatorname{stages}(\mathrm{none}) &= [\,] & \operatorname{stages}(\mathrm{styleOnly}) &= [\mathrm{style}] \\ \operatorname{stages}(\mathrm{direct}) &= [\mathrm{style}, \mathrm{props}, \mathrm{commit}] & \operatorname{stages}(\mathrm{ppFull}) &= [\mathrm{style}, \mathrm{props}, \mathrm{commit}] \\ \operatorname{stages}(\mathrm{raster}) &= [\mathrm{style}, \mathrm{props}, \mathrm{raster}, \mathrm{commit}] & \operatorname{stages}(\mathrm{paint}) &= [\mathrm{style}, \mathrm{props}, \mathrm{paint}, \mathrm{raster}, \mathrm{commit}] \\ \operatorname{stages}(\mathrm{layoutPos}) &= [\mathrm{style}, \mathrm{layout}, \mathrm{props}, \mathrm{paint}, \mathrm{raster}, \mathrm{commit}] & \operatorname{stages}(\mathrm{layoutFull}) &= [\mathrm{style}, \mathrm{layout}, \mathrm{props}, \mathrm{paint}, \mathrm{raster}, \mathrm{commit}] \end{aligned}$$
-/
def CrLevel.stages : CrLevel → List Stage
  | .none => []
  | .styleOnly => [.style]
  | .direct => [.style, .props, .commit]
  | .ppFull => [.style, .props, .commit]
  | .raster => [.style, .props, .raster, .commit]
  | .paint => [.style, .props, .paint, .raster, .commit]
  | .layoutPos => [.style, .layout, .props, .paint, .raster, .commit]
  | .layoutFull => [.style, .layout, .props, .paint, .raster, .commit]

/-- **The level of a plain property change** on a target with layer state `l` (design note §1.2, note C §2.2 table).
`transform` and `opacity` on their own layer take the deferred direct path; `translate`/`scale`/`rotate` and `filter`
on their own layer a full property update (no deferred path, `computed_style.cc:881-891`); any of these without its
own layer re-rasters shared chunks; `backdrop-filter` changes compositing reasons (`computed_style.cc:1268-1292`,
Layerize INFERRED).

$$\operatorname{lvl}(k, l) = \begin{cases} \mathrm{direct} & k \in \{\mathrm{transform}, \mathrm{opacity}\},\ l = \mathrm{own} \\ \mathrm{ppFull} & k \in \{\mathrm{translate}, \mathrm{scale}, \mathrm{rotate}\} \cup \{\mathrm{filter}(b) \mid b \in \mathbb{B}\},\ l = \mathrm{own} \\ \mathrm{raster} & k \in \{\mathrm{transform}, \mathrm{opacity}, \mathrm{translate}, \mathrm{scale}, \mathrm{rotate}\} \cup \{\mathrm{filter}(b) \mid b \in \mathbb{B}\},\ l \ne \mathrm{own} \\ \mathrm{ppFull} & k = \mathrm{backdropFilter} \\ \mathrm{paint} & k \in \{\mathrm{bgPosition}, \mathrm{bgImage}, \mathrm{bgColor}, \mathrm{color}, \mathrm{clipPath}, \mathrm{strokeDashoffset}, \mathrm{visibility}, \mathrm{zIndex}\} \\ \mathrm{layoutPos} & k \in \{\mathrm{top}, \mathrm{left}\} \\ \mathrm{layoutFull} & k \in \{\mathrm{transformToggle}, \mathrm{width}, \mathrm{height}, \mathrm{margin}, \mathrm{padding}\} \end{cases}$$
-/
def keyLevel : CrKey → LayerState → CrLevel
  | .transform, .own => .direct
  | .opacity, .own => .direct
  | .translate, .own | .scale, .own | .rotate, .own | .filter _, .own => .ppFull
  | .transform, _ | .opacity, _ | .translate, _ | .scale, _ | .rotate, _ | .filter _, _ => .raster
  | .backdropFilter, _ => .ppFull
  | .backgroundPosition, _ | .backgroundImage, _ | .backgroundColor, _ | .color, _ | .clipPath, _
  | .strokeDashoffset, _ | .visibility, _ | .zIndex, _ => .paint
  | .top, _ | .left, _ => .layoutPos
  | .transformToggle, _ | .width, _ | .height, _ | .margin, _ | .padding, _ => .layoutFull

/-- **The level of a change.** A plain property takes `keyLevel`; a custom property takes the maximum over its
readers' levels, at least `styleOnly` (the write restyles the element; design note §1.2 "max over its readers"); a
scroll-offset change has no style level (its stages come from `CrProp.extra`).

$$\operatorname{lvl}(\mathrm{css}(k), l) = \operatorname{lvl}(k, l),\qquad \operatorname{lvl}(\mathrm{custom}(i, R), l) = \max\big(\mathrm{styleOnly}, \max_{k \in R} \operatorname{lvl}(k, l)\big),\qquad \operatorname{lvl}(\mathrm{scroll}(r), l) = \mathrm{none}$$
(the maximum is a left fold over $R$ in list order; on a tie the later level is kept, which has the same rank).
-/
def crLevel : CrProp → LayerState → CrLevel
  | .css k, l => keyLevel k l
  | .custom _ rs, l => rs.foldl (fun acc k => acc.max (keyLevel k l)) .styleOnly
  | .scroll _, _ => .none

/-- **Scroll rule** (note C §4). One scrolled frame is one BeginMainFrame with the scroll-translation update (props)
and a commit (`cc/input/input_handler.cc:425-429`, `B/core/paint/paint_layer_scrollable_area.cc:428-462`); paint and
raster only when the cull rect has moved enough (`B/platform/graphics/paint/cull_rect.cc:48-69,425-430`). CONFIRMED.

$$\operatorname{scrollStages}(r) = [\mathrm{props}, \mathrm{commit}] \mathbin{+\!\!+} \begin{cases} [\mathrm{paint}, \mathrm{raster}] & r \\ [\,] & \lnot r \end{cases}$$
-/
def scrollStages (repaint : Bool) : List Stage :=
  [.props, .commit] ++ (if repaint then [.paint, .raster] else [])

/-- The stages a change adds beyond its level: the scroll stages for a scroll-offset change, none otherwise.

$$\operatorname{extra}(\mathrm{scroll}(r)) = \operatorname{scrollStages}(r),\qquad \operatorname{extra}(\mathrm{css}(k)) = \operatorname{extra}(\mathrm{custom}(i, R)) = [\,]$$
-/
def CrProp.extra : CrProp → List Stage
  | .scroll r => scrollStages r
  | _ => []

/-- **`stagesOf` of the Chromium engine**: the level's stages, then the extra scroll stages.

$$\operatorname{stagesOf}_{\mathrm{cr}}(c) = \operatorname{stages}(\operatorname{lvl}(c.\mathrm{prop}, c.\mathrm{layer})) \mathbin{+\!\!+} \operatorname{extra}(c.\mathrm{prop})$$
-/
def crStagesOf (c : Change CrProp) : List Stage := (crLevel c.prop c.layer).stages ++ c.prop.extra

/-! ## Modes and the engine -/

/-- Chromium's run mode: threaded (compositor) animation on or off, and whether every BeginFrame is also a
BeginMainFrame (so a running compositor animation still gets a main-thread style ride-along each frame).

$$\mathrm{CrMode} = \underbrace{\mathbb{B}}_{\mathrm{threadedAnim}} \times \underbrace{\mathbb{B}}_{\mathrm{everyBeginFrameIsMainFrame}}$$
-/
structure CrMode where
  threadedAnim : Bool
  everyBeginFrameIsMainFrame : Bool
deriving Repr, DecidableEq

/-- The CI lane: threaded animation kept (`--disable-threaded-animation` not passed,
`packages/measure-chromium/src/run.mjs:41`, CONFIRMED, correction C-1), every BeginFrame a main frame (MEASURED
UpdateLayoutTree 120 in 120 frames for a compositor animation, README:146-148; INFERRED as a rule, gap R1).

$$\mathrm{lane} = (\mathrm{true}, \mathrm{true})$$
-/
def lane : CrMode := ⟨true, true⟩

/-- Real Chrome: threaded animation, and the main thread sleeps while only compositor animations run
(`B/core/animation/document_timeline.cc:111-135`, CONFIRMED).

$$\mathrm{realChrome} = (\mathrm{true}, \mathrm{false})$$
-/
def realChrome : CrMode := ⟨true, false⟩

/-- The stages one running compositor animation costs per frame: the compositor tick, plus in a mode where every
BeginFrame is a main frame the ride-along style recalc and property update of the target (MEASURED style 120 per
120 frames, Paint/Layout/cc.Commit 0, README:146-148; props INFERRED from `B/core/animation/keyframe_effect.cc:739-742`).

$$\operatorname{compStages}(m) = [\mathrm{comp}] \mathbin{+\!\!+} \begin{cases} [\mathrm{style}, \mathrm{props}] & m.\mathrm{everyBeginFrameIsMainFrame} \\ [\,] & \text{otherwise} \end{cases}$$
-/
def crCompStages (m : CrMode) : List Stage :=
  [.comp] ++ (if m.everyBeginFrameIsMainFrame then [.style, .props] else [])

/-- **The Chromium engine in mode `m`.** No base stages: a main frame with no change commits nothing (MEASURED
cc.Commit 0 with only compositor animations, README:146-148), so `commit` comes from the changes.

$$\operatorname{chromiumAt}(m) = \big(m,\ \operatorname{stagesOf}_{\mathrm{cr}},\ \operatorname{compStages}(m),\ [\,]\big)$$
-/
def chromiumAt (m : CrMode) : Engine CrProp CrMode where
  mode := m
  stagesOf := crStagesOf
  compStages := crCompStages m
  base := []

/-- **The Chromium engine of the CI lane.**

$$\mathrm{chromium} = \operatorname{chromiumAt}(\mathrm{lane})$$
-/
def chromium : Engine CrProp CrMode := chromiumAt lane

/-! ## Level chain theorems -/

/-- **Level monotonicity.** A lower or equal level dirties a subset of the stages.

$$\forall a, b \in \mathrm{CrLevel}:\ a \le b \Rightarrow \forall s \in \operatorname{stages}(a):\ s \in \operatorname{stages}(b)$$
-/
theorem crStages_mono {a b : CrLevel} (h : a ≤ b) : ∀ s ∈ a.stages, s ∈ b.stages := by
  revert h
  cases a <;> cases b <;> decide

/-- `max` is an upper bound of its left argument.

$$\forall a, b \in \mathrm{CrLevel}:\ a \le \max(a, b)$$
-/
theorem CrLevel.le_max_left (a b : CrLevel) : a ≤ a.max b := by
  show a.rank ≤ (a.max b).rank
  unfold CrLevel.max; split <;> omega

/-- `max` is an upper bound of its right argument.

$$\forall a, b \in \mathrm{CrLevel}:\ b \le \max(a, b)$$
-/
theorem CrLevel.le_max_right (a b : CrLevel) : b ≤ a.max b := by
  show b.rank ≤ (a.max b).rank
  unfold CrLevel.max; split <;> omega

/-- The level order is transitive.

$$\forall a, b, c \in \mathrm{CrLevel}:\ a \le b \land b \le c \Rightarrow a \le c$$
-/
theorem CrLevel.le_trans {a b c : CrLevel} (h1 : a ≤ b) (h2 : b ≤ c) : a ≤ c :=
  Nat.le_trans h1 h2

/-- A left fold of `max` stays above its start and above every folded element.

$$\forall x \in \mathrm{CrLevel},\ \forall L \in \mathrm{CrLevel}^{*}:\ x \le \operatorname{foldl}(\max, x, L) \land \forall y \in L:\ y \le \operatorname{foldl}(\max, x, L)$$
-/
theorem foldl_max_ge : ∀ (x : CrLevel) (L : List CrLevel),
    x ≤ L.foldl CrLevel.max x ∧ ∀ y ∈ L, y ≤ L.foldl CrLevel.max x
  | x, [] => ⟨Nat.le_refl _, fun _ h => nomatch h⟩
  | x, y :: ys => by
    obtain ⟨h1, h2⟩ := foldl_max_ge (x.max y) ys
    refine ⟨CrLevel.le_trans (CrLevel.le_max_left x y) h1, fun z hz => ?_⟩
    rcases List.mem_cons.mp hz with rfl | hz
    · exact CrLevel.le_trans (CrLevel.le_max_right x z) h1
    · exact h2 z hz

/-- **A custom property costs at least each reader.** Every plain property reading `--x` has a level at most the
custom property's level, so its stages are among the custom property's stages.

$$\forall i \in \mathbb{N},\ \forall R \in \mathrm{CrKey}^{*},\ \forall l \in \mathrm{LayerState},\ \forall k \in R:\ \operatorname{lvl}(k, l) \le \operatorname{lvl}(\mathrm{custom}(i, R), l) \land \operatorname{stages}(\operatorname{lvl}(k, l)) \subseteq \operatorname{stages}(\operatorname{lvl}(\mathrm{custom}(i, R), l))$$
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

/-- A custom property write always restyles: its level is at least `styleOnly`.

$$\forall i \in \mathbb{N},\ \forall R \in \mathrm{CrKey}^{*},\ \forall l \in \mathrm{LayerState}:\ \mathrm{styleOnly} \le \operatorname{lvl}(\mathrm{custom}(i, R), l)$$
-/
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

$$\operatorname{levelCover}(L, M) = \mathrm{true} \iff |L| = |M| \ \land\ \forall i < |L|:\ \operatorname{extra}(L_i.\mathrm{prop}) = [\,] \land \operatorname{lvl}(L_i.\mathrm{prop}, L_i.\mathrm{layer}) \le \operatorname{lvl}(M_i.\mathrm{prop}, M_i.\mathrm{layer})$$
-/
def levelCover : List (Change CrProp) → List (Change CrProp) → Bool
  | [], [] => true
  | c :: cs, d :: ds =>
    c.prop.extra.isEmpty && decide (crLevel c.prop c.layer ≤ crLevel d.prop d.layer) && levelCover cs ds
  | _, _ => false

/-- **Level order gives a stage cover** on Chromium, in every mode: the core hypothesis of `frame_le_of_cover` holds
whenever the levels are pairwise `≤` (the step design note §3.1 names `crStages_mono`).

$$\forall m \in \mathrm{CrMode},\ \forall L, M \in \mathrm{Change}(\mathrm{CrProp})^{*}:\ \operatorname{levelCover}(L, M) = \mathrm{true} \Rightarrow \operatorname{cover}_{\operatorname{chromiumAt}(m)}(L, M) = \mathrm{true}$$
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

$$\mathrm{CrTimeline} = \{\mathrm{document}\} \cup \{\mathrm{scroll}(u) \mid u \in \mathbb{B}\}$$
-/
inductive CrTimeline where
  | document
  | scroll (userScrollable : Bool)
deriving Repr, DecidableEq

/-- A running animation: target element, animated properties, target layer state, whether the target has a valid
compositing state (layout object, not fragmented, a direct compositing reason, no `will-change: contents`), and its
timeline.

$$\mathrm{CrAnim} = \underbrace{\mathbb{N}}_{\mathrm{elem}} \times \underbrace{\mathrm{CrProp}^{*}}_{\mathrm{props}} \times \underbrace{\mathrm{LayerState}}_{\mathrm{layer}} \times \underbrace{\mathbb{B}}_{\mathrm{validTarget}} \times \underbrace{\mathrm{CrTimeline}}_{\mathrm{timeline}}$$
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

$$\operatorname{elig}(p) \iff p \in \{\mathrm{css}(k) \mid k \in \{\mathrm{transform}, \mathrm{transformToggle}, \mathrm{translate}, \mathrm{scale}, \mathrm{rotate}, \mathrm{opacity}, \mathrm{backdropFilter}\} \cup \{\mathrm{filter}(b) \mid b \in \mathbb{B}\}\}$$
-/
def CrProp.eligible : CrProp → Bool
  | .css .transform | .css .transformToggle | .css .translate | .css .scale | .css .rotate | .css .opacity
  | .css (.filter _) | .css .backdropFilter => true
  | _ => false

/-- A filter that moves pixels (blur or drop-shadow); backdrop-filter is exempt
(`compositor_animations.cc:405-417`, CONFIRMED).

$$\operatorname{movesPx}(p) \iff p = \mathrm{css}(\mathrm{filter}(\mathrm{true}))$$
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

$$\operatorname{bits}(m, a) = [0 \mid \lnot m.\mathrm{threadedAnim}] \mathbin{+\!\!+} [5 \mid \lnot a.\mathrm{validTarget}] \mathbin{+\!\!+} [12 \mid \exists p \in a.\mathrm{props}:\ \operatorname{movesPx}(p)] \mathbin{+\!\!+} [13 \mid \exists p \in a.\mathrm{props}:\ \lnot\operatorname{elig}(p)] \mathbin{+\!\!+} [16 \mid a.\mathrm{timeline} = \mathrm{scroll}(\mathrm{false})]\quad\text{where } [n \mid \varphi] = [n] \text{ if } \varphi \text{, else } [\,]$$
-/
def failBits (m : CrMode) (a : CrAnim) : List Nat :=
  (if m.threadedAnim then [] else [0]) ++ (if a.validTarget then [] else [5]) ++
    (if a.props.any CrProp.movesPixels then [12] else []) ++ (if a.props.all CrProp.eligible then [] else [13]) ++
    (if a.timeline = .scroll false then [16] else [])

/-- **Chromium's thread rule.** An animation runs on the compositor iff all its properties are compositable and no
modelled failure bit is set; otherwise the main thread services it every frame (`animation.cc:3376-3400`, CONFIRMED).

$$\operatorname{crThread}(m, a) = \begin{cases} \mathrm{comp} & (\forall p \in a.\mathrm{props}:\ \operatorname{elig}(p)) \land \operatorname{bits}(m, a) = [\,] \\ \mathrm{main} & \text{otherwise} \end{cases}$$
-/
def crThread (m : CrMode) (a : CrAnim) : Thread :=
  if a.props.all CrProp.eligible && (failBits m a).isEmpty then .comp else .main

/-- **The thread rule, spelled out.** Compositor iff every property is compositable, threaded animation is on, the
target is valid, no filter moves pixels, and the timeline is not a scroll timeline on a non-user-scrollable source.

$$\forall m \in \mathrm{CrMode},\ \forall a \in \mathrm{CrAnim}:\ \operatorname{crThread}(m, a) = \mathrm{comp} \iff (\forall p \in a.\mathrm{props}:\ \operatorname{elig}(p)) \land m.\mathrm{threadedAnim} \land a.\mathrm{validTarget} \land (\forall p \in a.\mathrm{props}:\ \lnot\operatorname{movesPx}(p)) \land a.\mathrm{timeline} \ne \mathrm{scroll}(\mathrm{false})$$
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

$$\forall a \in \mathrm{CrAnim}:\ 0 \notin \operatorname{bits}(\mathrm{lane}, a) \land 0 \notin \operatorname{bits}(\mathrm{realChrome}, a)$$
-/
theorem failBits_lane_no0 (a : CrAnim) : 0 ∉ failBits lane a ∧ 0 ∉ failBits realChrome a := by
  constructor <;>
  · simp only [failBits, lane, realChrome, ↓reduceIte, List.nil_append, List.mem_append]
    split <;> split <;> split <;> split <;> simp

/-! ## Frames -/

/-- The main-thread changes an animation makes in one frame: one change per animated property, on its target.

$$\operatorname{changes}(a) = [\,(a.\mathrm{elem}, p, a.\mathrm{layer}) \mid p \in a.\mathrm{props}\,]$$
-/
def CrAnim.changes (a : CrAnim) : List (Change CrProp) := a.props.map fun p => ⟨a.elem, p, a.layer⟩

/-- **One frame of running animations** in mode `m`: the main-thread animations contribute their changes, the
compositor animations count as `compAnims`; no script, forced passes or hit tests.

$$\operatorname{animFrame}(m, A) = \Big(0, 0, 0, 0,\ \mathop{+\!\!+}_{a \in A,\ \operatorname{crThread}(m, a) = \mathrm{main}} \operatorname{changes}(a),\ \big|[\,a \in A \mid \operatorname{crThread}(m, a) = \mathrm{comp}\,]\big|\Big)$$
-/
def animFrame (m : CrMode) (as : List CrAnim) : FrameIn CrProp where
  script := 0
  forcedStyle := 0
  forcedLayout := 0
  hits := 0
  changes := (as.filter fun a => decide (crThread m a = .main)).flatMap CrAnim.changes
  compAnims := (as.filter fun a => decide (crThread m a = .comp)).length

/-- A frame of script that writes styles: `n` callbacks and the written changes, nothing else.

$$\operatorname{jsWrite}(n, C) = (n, 0, 0, 0, C, 0)$$
-/
def jsWrite (n : Nat) (cs : List (Change CrProp)) : FrameIn CrProp :=
  { script := n, forcedStyle := 0, forcedLayout := 0, hits := 0, changes := cs, compAnims := 0 }

/-! ## Worked theorems -/

/-- **A compositor animation does no main-thread layout, paint, raster or commit.** If every running animation is on
the compositor, the frame's layout, paint, raster and commit stages have no passes and no units, in every mode.

$$\forall m \in \mathrm{CrMode},\ \forall A \in \mathrm{CrAnim}^{*}:\ (\forall a \in A:\ \operatorname{crThread}(m, a) = \mathrm{comp}) \Rightarrow \forall s \in \{\mathrm{layout}, \mathrm{paint}, \mathrm{raster}, \mathrm{commit}\}:\ W.\mathrm{passes}(s) = 0 \land W.\mathrm{units}(s) = 0\quad\text{where } W = \operatorname{frameWork}_{\operatorname{chromiumAt}(m)}(\operatorname{animFrame}(m, A))$$
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

$$\forall m \in \mathrm{CrMode},\ \forall e \in \mathbb{N},\ \forall l \in \mathrm{LayerState}:\ m.\mathrm{threadedAnim} \Rightarrow \operatorname{crThread}\big(m, (e, [\mathrm{css}(\mathrm{transform})], l, \mathrm{true}, \mathrm{document})\big) = \mathrm{comp}$$
-/
theorem transformAnim_comp (m : CrMode) (e : Nat) (l : LayerState) (h : m.threadedAnim = true) :
    crThread m ⟨e, [.css .transform], l, true, .document⟩ = .comp := by
  simp [crThread, failBits, h, CrProp.eligible, CrProp.movesPixels]

/-- **Worked theorem 2: a compositor transform animation has no layout and no paint stage on the main thread**, in
the lane and in real Chrome.

$$\forall m \in \{\mathrm{lane}, \mathrm{realChrome}\},\ \forall e \in \mathbb{N},\ \forall l \in \mathrm{LayerState}:\ W.\mathrm{passes}(\mathrm{layout}) = 0 \land W.\mathrm{passes}(\mathrm{paint}) = 0\quad\text{where } W = \operatorname{frameWork}_{\operatorname{chromiumAt}(m)}\big(\operatorname{animFrame}(m, [(e, [\mathrm{css}(\mathrm{transform})], l, \mathrm{true}, \mathrm{document})])\big)$$
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
`frame_le_of_cover`: same callbacks, the transform change (`direct`) is covered by the top/left change (`layoutPos`),
in every mode and for any target and layer state of the top/left write.

$$\forall m \in \mathrm{CrMode},\ \forall n, e, e' \in \mathbb{N},\ \forall l \in \mathrm{LayerState},\ \forall k \in \{\mathrm{top}, \mathrm{left}\}:\ \operatorname{frameWork}_{\operatorname{chromiumAt}(m)}\big(\operatorname{jsWrite}(n, [(e, \mathrm{css}(\mathrm{transform}), \mathrm{own})])\big) \preceq \operatorname{frameWork}_{\operatorname{chromiumAt}(m)}\big(\operatorname{jsWrite}(n, [(e', \mathrm{css}(k), l)])\big)$$
-/
theorem jsTransform_le_topLeft (m : CrMode) (n e e' : Nat) (l : LayerState) (k : CrKey)
    (hk : k = .top ∨ k = .left) :
    (frameWork (chromiumAt m) (jsWrite n [⟨e, .css .transform, .own⟩])).le
      (frameWork (chromiumAt m) (jsWrite n [⟨e', .css k, l⟩])) := by
  refine frame_le_of_cover (chromiumAt m) [⟨e', .css k, l⟩] [] (by simp [jsWrite]) ?_
    (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _)
  apply levelCover_coverB
  rcases hk with rfl | rfl <;> cases l <;> rfl

/-- **The top/left write is strictly more work**: the transform write has no layout pass, the top/left write has one.

$$\forall m \in \mathrm{CrMode},\ \forall n, e, e' \in \mathbb{N},\ \forall l \in \mathrm{LayerState},\ \forall k \in \{\mathrm{top}, \mathrm{left}\}:\ \operatorname{frameWork}_{\operatorname{chromiumAt}(m)}\big(\operatorname{jsWrite}(n, [(e, \mathrm{css}(\mathrm{transform}), \mathrm{own})])\big) \prec \operatorname{frameWork}_{\operatorname{chromiumAt}(m)}\big(\operatorname{jsWrite}(n, [(e', \mathrm{css}(k), l)])\big)$$
-/
theorem jsTransform_lt_topLeft (m : CrMode) (n e e' : Nat) (l : LayerState) (k : CrKey)
    (hk : k = .top ∨ k = .left) :
    (frameWork (chromiumAt m) (jsWrite n [⟨e, .css .transform, .own⟩])).lt
      (frameWork (chromiumAt m) (jsWrite n [⟨e', .css k, l⟩])) := by
  refine ⟨jsTransform_le_topLeft m n e e' l k hk, .inl ⟨.layout, .inl ?_⟩⟩
  simp only [frameWork, touched, jsWrite, chromiumAt, forcedPasses]
  rcases hk with rfl | rfl <;> cases l <;> by_cases hn : 0 < n <;>
    simp [crStagesOf, crLevel, keyLevel, CrLevel.stages, CrProp.extra, FrameIn.updates, hn]

/-! ## Scroll -/

/-- The cull-rect repaint period of a scroll at `d` px per frame: $\lceil 512/d \rceil$ frames (changed-enough
distance 512 px at expansion ratio 1, `cull_rect.cc:48-69`, `B/../common/features.cc:627-652`; ratio 1 INFERRED).

$$\operatorname{period}(d) = \left\lfloor \frac{512 + d - 1}{d} \right\rfloor \quad (\text{Lean } \mathbb{N} \text{ division: } \operatorname{period}(0) = 0)$$
-/
def cullPeriod (d : Nat) : Nat := (512 + d - 1) / d

/-- Whether frame `k` (counted from the last cull-rect update at frame 0) of a scroll at `d` px per frame repaints:
the cull rect is recomputed every `cullPeriod d` frames, never at frame 0, never when `d = 0`.

$$\operatorname{scrollPaints}(d, k) \iff 0 < k \land k \bmod \operatorname{period}(d) = 0 \qquad (k \bmod 0 = k \text{ in Lean, so } d = 0 \text{ never repaints})$$
-/
def scrollPaints (d k : Nat) : Bool := decide (0 < k) && k % cullPeriod d == 0

/-- **Paint only after 512 px.** A scroll frame that repaints has moved the scroller at least 512 px since the last
cull-rect update.

$$\forall d, k \in \mathbb{N}:\ \operatorname{scrollPaints}(d, k) \Rightarrow 512 \le k \cdot d$$
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

/-- The scroll change of frame `k` of a scroll at `d` px per frame on scroller `e`.

$$\operatorname{scrollChange}(e, d, k) = \big(e, \mathrm{scroll}(\operatorname{scrollPaints}(d, k)), \mathrm{own}\big)$$
-/
def scrollChange (e d k : Nat) : Change CrProp := ⟨e, .scroll (scrollPaints d k), .own⟩

/-- **One BeginMainFrame per scrolled frame, without style or layout.** Every scroll frame runs props and commit,
never style or layout, and runs paint exactly when the cull rect is due (`scrollPaints`).

$$\forall e, d, k \in \mathbb{N}:\ \{\mathrm{props}, \mathrm{commit}\} \subseteq S \land \mathrm{style} \notin S \land \mathrm{layout} \notin S \land (\mathrm{paint} \in S \iff \operatorname{scrollPaints}(d, k))\quad\text{where } S = \operatorname{stagesOf}_{\mathrm{cr}}(\operatorname{scrollChange}(e, d, k))$$
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

$$\mathrm{Pred} = \{=\!0,\ =\!o,\ <\!o,\ \le\!o,\ \mathrm{any}\}$$
-/
inductive Pred where
  | zero | eqO | ltO | leO | any
deriving Repr, DecidableEq

/-- The JSON spelling of a prediction.

$$\operatorname{str}(=\!0) = \texttt{"=0"},\ \operatorname{str}(=\!o) = \texttt{"=o"},\ \operatorname{str}(<\!o) = \texttt{"<o"},\ \operatorname{str}(\le\!o) = \texttt{"≤o"},\ \operatorname{str}(\mathrm{any}) = \texttt{"any"}$$
-/
def Pred.str : Pred → String
  | .zero => "=0" | .eqO => "=o" | .ltO => "<o" | .leO => "≤o" | .any => "any"

/-- **The prediction of one stage** from the model's passes per frame of the variant (`v`) and the reference (`o`).
`props` counts lifecycle frames, not work (note C §5), so it is never predicted. Equal non-zero passes give `≤o`, not
`=o`: the model counts one pass per frame, while a BeginMainFrame can run more lifecycle updates (MEASURED
UpdateLayoutTree 162 in 120 frames for the main-thread fixture, README:148).

$$\operatorname{pred}(s, v, o) = \begin{cases} \mathrm{any} & s = \mathrm{props} \\ <\!o & v < o \\ =\!0 & v = 0 \land o = 0 \\ \le\!o & v = o \ne 0 \\ \mathrm{any} & v > o \end{cases}$$
(first matching case)
-/
def predOf (s : Stage) (v o : Nat) : Pred :=
  if s = .props then .any else if v < o then .ltO else if v = 0 then .zero else if v = o then .leO else .any

/-- The lane count types that observe each stage (design note §3.2); the consumer drops the types `classes.frozen.json`
quarantines.

$$\operatorname{counts}(\mathrm{script}) = [\texttt{trace.FireAnimationFrame}, \texttt{trace.FunctionCall}],\ \operatorname{counts}(\mathrm{style}) = [\texttt{trace.UpdateLayoutTree}],\ \ldots,\ \operatorname{counts}(\mathrm{comp}) = [\texttt{census.layers}]$$
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

/-- The JSON name of a stage.

$$\operatorname{name}(s) = \text{the constructor name of } s,\ \text{e.g. } \operatorname{name}(\mathrm{props}) = \texttt{"props"}$$
-/
def stageName : Stage → String
  | .script => "script" | .style => "style" | .layout => "layout" | .props => "props" | .paint => "paint"
  | .raster => "raster" | .commit => "commit" | .comp => "comp"

/-- The JSON name of a level.

$$\operatorname{name}(\ell) = \text{the constructor name of } \ell,\ \text{e.g. } \operatorname{name}(\mathrm{layoutPos}) = \texttt{"layoutPos"}$$
-/
def levelName : CrLevel → String
  | .none => "none" | .styleOnly => "styleOnly" | .direct => "direct" | .ppFull => "ppFull" | .raster => "raster"
  | .paint => "paint" | .layoutPos => "layoutPos" | .layoutFull => "layoutFull"

/-- The JSON name of a layer state.

$$\operatorname{name}(\mathrm{none}) = \texttt{"none"},\ \operatorname{name}(\mathrm{layer}) = \texttt{"layer"},\ \operatorname{name}(\mathrm{own}) = \texttt{"own"}$$
-/
def layerName : LayerState → String
  | .none => "none" | .layer => "layer" | .own => "own"

/-- The lane fixture with nothing animating (reference of F1).

$$\mathrm{rest} = [\,]$$
-/
def fxRest : List CrAnim := []

/-- `packages/measure-chromium/fixtures/anim-compositor`: a `transform` animation on a `will-change: transform` box and
an `opacity` animation (its own layer through the active-animation compositing reason,
`B/core/paint/compositing/compositing_reason_finder.cc:563-600`, CONFIRMED in note C).

$$\mathrm{animComp} = [(0, [\mathrm{css}(\mathrm{transform})], \mathrm{own}, \mathrm{true}, \mathrm{document}),\ (1, [\mathrm{css}(\mathrm{opacity})], \mathrm{own}, \mathrm{true}, \mathrm{document})]$$
-/
def fxAnimComp : List CrAnim :=
  [⟨0, [.css .transform], .own, true, .document⟩, ⟨1, [.css .opacity], .own, true, .document⟩]

/-- `packages/measure-chromium/fixtures/anim-layout`: a `width` animation and a `background-color` animation, both on
plain boxes.

$$\mathrm{animLayout} = [(0, [\mathrm{css}(\mathrm{width})], \mathrm{none}, \mathrm{true}, \mathrm{document}),\ (1, [\mathrm{css}(\mathrm{bgColor})], \mathrm{none}, \mathrm{true}, \mathrm{document})]$$
-/
def fxAnimLayout : List CrAnim :=
  [⟨0, [.css .width], .none, true, .document⟩, ⟨1, [.css .backgroundColor], .none, true, .document⟩]

/-- One golden stage row: test id, scenario and reference names and animations, lane mode, one stage, with the
model's passes and units per frame for both and the prediction.

$$\operatorname{row}(t, x, A_x, y, A_y, s) = \{\mathrm{test}{:}\,t,\ \mathrm{scenario}{:}\,x,\ \mathrm{ref}{:}\,y,\ \mathrm{stage}{:}\,s,\ v{:}\,W_x.\mathrm{passes}(s),\ o{:}\,W_y.\mathrm{passes}(s),\ \mathrm{pred}{:}\,\operatorname{pred}(s, v, o), \ldots\}\quad\text{where } W_z = \operatorname{frameWork}_{\mathrm{chromium}}(\operatorname{animFrame}(\mathrm{lane}, A_z))$$
-/
def stageRow (test x : String) (ax : List CrAnim) (y : String) (ay : List CrAnim) (s : Stage) : Lean.Json :=
  let wv := frameWork chromium (animFrame lane ax)
  let wo := frameWork chromium (animFrame lane ay)
  Lean.Json.mkObj [("kind", "stage"), ("test", .str test), ("scenario", .str x), ("ref", .str y), ("mode", "lane"),
    ("stage", .str (stageName s)), ("counts", Lean.toJson (stageCounts s)),
    ("v", Lean.toJson (wv.passes s)), ("o", Lean.toJson (wo.passes s)),
    ("vUnits", Lean.toJson (wv.units s)), ("oUnits", Lean.toJson (wo.units s)),
    ("pred", .str (predOf s (wv.passes s) (wo.passes s)).str)]

/-- The number of animations whose failure bits contain bit `b` in the lane.

$$\operatorname{nBit}(b, A) = \big|[\,a \in A \mid b \in \operatorname{bits}(\mathrm{lane}, a)\,]\big|$$
-/
def bitCount (b : Nat) (as : List CrAnim) : Nat := (as.filter fun a => decide (b ∈ failBits lane a)).length

/-- One golden F0 row: the number of the scenario's animations with bit 0 set in the lane (always 0,
`failBits_lane_no0`).

$$\operatorname{f0}(x, A) = \{\mathrm{test}{:}\,\mathrm{F0},\ \mathrm{scenario}{:}\,x,\ \mathrm{stage}{:}\,\mathrm{comp},\ v{:}\,\operatorname{nBit}(0, A),\ \mathrm{pred}{:}\,=\!0, \ldots\}$$
-/
def f0Row (x : String) (ax : List CrAnim) : Lean.Json :=
  Lean.Json.mkObj [("kind", "stage"), ("test", "F0"), ("scenario", .str x), ("ref", "rest"), ("mode", "lane"),
    ("stage", "comp"), ("counts", Lean.toJson ["trace.Animation.compositeFailedBits.bit0"]),
    ("v", Lean.toJson (bitCount 0 ax)), ("o", Lean.toJson (bitCount 0 fxRest)), ("vUnits", Lean.toJson (0 : Nat)),
    ("oUnits", Lean.toJson (0 : Nat)), ("pred", .str (if bitCount 0 ax = 0 then Pred.zero else Pred.any).str)]

/-- One signature row per level: its rank, its stages, and every (plain property, layer state) pair `keyLevel` maps
to it.

$$\operatorname{sig}(\ell) = \{\mathrm{level}{:}\,\ell,\ \mathrm{rank}{:}\,\operatorname{rank}(\ell),\ \mathrm{stages}{:}\,\operatorname{stages}(\ell),\ \mathrm{members}{:}\,[\,(k, l) \mid k \in \mathrm{CrKey.all},\ l \in [\mathrm{none}, \mathrm{layer}, \mathrm{own}],\ \operatorname{lvl}(k, l) = \ell\,]\}$$
-/
def signatureRow (lv : CrLevel) : Lean.Json :=
  let members := CrKey.all.flatMap fun k =>
    ([LayerState.none, .layer, .own].filter fun l => decide (keyLevel k l = lv)).map fun l => s!"{k.name}@{layerName l}"
  Lean.Json.mkObj [("kind", "signature"), ("level", .str (levelName lv)), ("rank", Lean.toJson lv.rank),
    ("stages", Lean.toJson (lv.stages.map stageName)), ("members", Lean.toJson members)]

/-- One mode row: the mode's flags and the stages one compositor animation costs per frame.

$$\operatorname{modeRow}(x, m) = \{\mathrm{mode}{:}\,x,\ \mathrm{threadedAnim}{:}\,m.\mathrm{threadedAnim},\ \mathrm{everyBeginFrameIsMainFrame}{:}\,m.\mathrm{everyBeginFrameIsMainFrame},\ \mathrm{compStages}{:}\,\operatorname{compStages}(m)\}$$
-/
def modeRow (x : String) (m : CrMode) : Lean.Json :=
  Lean.Json.mkObj [("kind", "mode"), ("mode", .str x), ("threadedAnim", Lean.toJson m.threadedAnim),
    ("everyBeginFrameIsMainFrame", Lean.toJson m.everyBeginFrameIsMainFrame),
    ("compStages", Lean.toJson ((crCompStages m).map stageName))]

/-- **All golden rows**, in order: one signature row per level, one row per mode, the F0 rows (bit 0 per fixture),
then per stage the F1 rows (compositor fixture against rest) and the F2 rows (compositor fixture against the
main-thread fixture).

$$\mathrm{rows} = [\operatorname{sig}(\ell) \mid \ell \in \mathrm{CrLevel.all}] \mathbin{+\!\!+} [\operatorname{modeRow}(\mathrm{lane}), \operatorname{modeRow}(\mathrm{realChrome})] \mathbin{+\!\!+} [\operatorname{f0}(\ldots)]_{3} \mathbin{+\!\!+} [\operatorname{row}(\mathrm{F1}, \mathrm{animComp}, \mathrm{rest}, s) \mid s \in \mathrm{Stage.all}] \mathbin{+\!\!+} [\operatorname{row}(\mathrm{F2}, \mathrm{animComp}, \mathrm{animLayout}, s) \mid s \in \mathrm{Stage.all}]$$
-/
def goldenRows : List Lean.Json :=
  CrLevel.all.map signatureRow ++ [modeRow "lane" lane, modeRow "realChrome" realChrome] ++
    [f0Row "rest" fxRest, f0Row "anim-compositor" fxAnimComp, f0Row "anim-layout" fxAnimLayout] ++
    Stage.all.map (stageRow "F1" "anim-compositor" fxAnimComp "rest" fxRest) ++
    Stage.all.map (stageRow "F2" "anim-compositor" fxAnimComp "anim-layout" fxAnimLayout)

/-- The text of `chromium.jsonl`: one compressed JSON object per line.

$$\mathrm{goldenText} = \mathop{+\!\!+}_{r \in \mathrm{rows}} (\operatorname{compress}(r) \mathbin{+\!\!+} \texttt{"\textbackslash n"})$$
-/
def goldenText : String := String.join (goldenRows.map fun r => r.compress ++ "\n")

/-- The golden file, relative to `lean/`.

$$\mathrm{goldenPath} = \texttt{../packages/contracts/golden/engine/chromium.jsonl}$$
-/
def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "engine" / "chromium.jsonl"

/-- Write the golden file (`write`) or compare it; returns 1 when the file is stale, else 0. Run from `lean/` as
`lake env lean --run <script>` with a script whose `main` calls `Fw.Engine.Chromium.goldenRun "." (write)`.

$$\operatorname{goldenRun}(r, \mathrm{false}) = [\operatorname{read}(r / \mathrm{goldenPath}) \ne \mathrm{goldenText}]$$
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

#guard goldenRows.length == 8 + 2 + 3 + 8 + 8
#guard (frameWork chromium (animFrame lane fxAnimComp)).passes .style == 1
#guard (frameWork chromium (animFrame lane fxAnimComp)).units .style == 2
#guard (frameWork chromium (animFrame lane fxAnimComp)).passes .commit == 0
#guard (frameWork chromium (animFrame lane fxAnimLayout)).passes .layout == 1
#guard (frameWork chromium (animFrame lane fxAnimLayout)).units .paint == 2
#guard (frameWork (chromiumAt realChrome) (animFrame realChrome fxAnimComp)).passes .style == 0
#guard predOf .layout 0 1 == .ltO && predOf .layout 0 0 == .zero && predOf .props 0 1 == .any
#guard predOf .style 1 1 == .leO && predOf .style 1 0 == .any

end Fw.Engine.Chromium
