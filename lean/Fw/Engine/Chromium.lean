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

$$\operatorname{name}(k) = \text{the CSS property name of } k \text{ (e.g. } \operatorname{name}(\mathrm{bgColor}) = \texttt{"background-color"}\text{)},\ \operatorname{name}(\mathrm{filter}(\mathrm{true})) = \texttt{"filter(blur)"},\ \operatorname{name}(\mathrm{filter}(\mathrm{false})) = \texttt{"filter"},\ \operatorname{name}(\mathrm{transformToggle}) = \texttt{"transform(none<->some)"}$$
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

$$\operatorname{lvl}(\mathrm{css}(k), l) = \operatorname{lvl}(k, l),\qquad \operatorname{lvl}(\mathrm{custom}(i, R), l) = \operatorname{foldl}\big(\max, \mathrm{styleOnly}, [\,\operatorname{lvl}(k, l) \mid k \in R\,]\big)\ (= \mathrm{styleOnly} \text{ for } R = [\,]),\qquad \operatorname{lvl}(\mathrm{scroll}(r), l) = \mathrm{none}$$
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

/-- The cull-rect repaint period of a scroll at `d` px per frame: $\lceil 512/d \rceil$ frames for $d > 0$ and $0$ for $d = 0$ (changed-enough
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

$$\begin{aligned} \operatorname{counts}(\mathrm{script}) &= [\texttt{trace.FireAnimationFrame}, \texttt{trace.FunctionCall}] & \operatorname{counts}(\mathrm{style}) &= [\texttt{trace.UpdateLayoutTree}] \\ \operatorname{counts}(\mathrm{layout}) &= [\texttt{trace.Layout}, \texttt{trace.Layout.dirtyObjects}] & \operatorname{counts}(\mathrm{props}) &= [\texttt{trace.PrePaint}] \\ \operatorname{counts}(\mathrm{paint}) &= [\texttt{trace.Paint}, \texttt{raster.invalidationAreaPx}, \texttt{raster.invalidationRects}] & \operatorname{counts}(\mathrm{raster}) &= [\texttt{raster.invalidationAreaPx}, \texttt{raster.invalidationRects}] \\ \operatorname{counts}(\mathrm{commit}) &= [\texttt{trace.cc.Commit}] & \operatorname{counts}(\mathrm{comp}) &= [\texttt{census.layers}] \end{aligned}$$
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

$$\operatorname{bitCount}(b, A) = \big|[\,a \in A \mid b \in \operatorname{bits}(\mathrm{lane}, a)\,]\big|$$
-/
def bitCount (b : Nat) (as : List CrAnim) : Nat := (as.filter fun a => decide (b ∈ failBits lane a)).length

/-- One golden F0 row: the number of the scenario's animations with bit 0 set in the lane (always 0,
`failBits_lane_no0`).

$$\begin{aligned} \forall x, A:\quad \operatorname{f0}(x, A) = \{&\mathrm{kind}{:}\,\texttt{stage},\ \mathrm{test}{:}\,\texttt{F0},\ \mathrm{scenario}{:}\,x,\ \mathrm{ref}{:}\,\texttt{rest},\ \mathrm{mode}{:}\,\texttt{lane},\ \mathrm{stage}{:}\,\texttt{comp}, \\ &\mathrm{counts}{:}\,[\texttt{trace.Animation.compositeFailedBits.bit0}],\ v{:}\,\operatorname{bitCount}(0, A),\ o{:}\,\operatorname{bitCount}(0, \mathrm{fxRest}), \\ &\mathrm{vUnits}{:}\,0,\ \mathrm{oUnits}{:}\,0,\ \mathrm{pred}{:}\,(\texttt{=0} \text{ if } \operatorname{bitCount}(0, A) = 0 \text{ else } \texttt{any})\} \end{aligned}$$
-/
def f0Row (x : String) (ax : List CrAnim) : Lean.Json :=
  Lean.Json.mkObj [("kind", "stage"), ("test", "F0"), ("scenario", .str x), ("ref", "rest"), ("mode", "lane"),
    ("stage", "comp"), ("counts", Lean.toJson ["trace.Animation.compositeFailedBits.bit0"]),
    ("v", Lean.toJson (bitCount 0 ax)), ("o", Lean.toJson (bitCount 0 fxRest)), ("vUnits", Lean.toJson (0 : Nat)),
    ("oUnits", Lean.toJson (0 : Nat)), ("pred", .str (if bitCount 0 ax = 0 then Pred.zero else Pred.any).str)]

/-- One signature row per level: its rank, its stages, and every (plain property, layer state) pair `keyLevel` maps
to it.

$$\operatorname{sig}(\ell) = \{\mathrm{level}{:}\,\ell,\ \mathrm{rank}{:}\,\operatorname{rank}(\ell),\ \mathrm{stages}{:}\,\operatorname{stages}(\ell),\ \mathrm{members}{:}\,[\,\operatorname{name}(k) \mathbin{+\!\!+} \texttt{"@"} \mathbin{+\!\!+} \operatorname{name}(l) \mid k \in \mathrm{CrKey.all},\ l \in [\mathrm{none}, \mathrm{layer}, \mathrm{own}],\ \operatorname{lvl}(k, l) = \ell\,]\}$$
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

$$\mathrm{rows} = [\operatorname{sig}(\ell) \mid \ell \in \mathrm{CrLevel.all}] \mathbin{+\!\!+} [\operatorname{modeRow}(\mathrm{lane}), \operatorname{modeRow}(\mathrm{realChrome})] \mathbin{+\!\!+} [\operatorname{f0}(\mathrm{rest}, \mathrm{rest}), \operatorname{f0}(\mathrm{animComp}, \mathrm{animComp}), \operatorname{f0}(\mathrm{animLayout}, \mathrm{animLayout})] \mathbin{+\!\!+} [\operatorname{row}(\mathrm{F1}, \mathrm{animComp}, \mathrm{rest}, s) \mid s \in \mathrm{Stage.all}] \mathbin{+\!\!+} [\operatorname{row}(\mathrm{F2}, \mathrm{animComp}, \mathrm{animLayout}, s) \mid s \in \mathrm{Stage.all}]$$
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

$$\operatorname{goldenRun}(r, \mathrm{true}) = 0 \text{ after writing } \mathrm{goldenText} \text{ to } r / \mathrm{goldenPath},\qquad \operatorname{goldenRun}(r, \mathrm{false}) = [\operatorname{read}(r / \mathrm{goldenPath}) \ne \mathrm{goldenText}] \text{ (a missing or unreadable file reads as the empty string)}$$
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

/-! ## Engine mechanisms (why-engines)

Each section below closes one ledger statement (`research/findings/ledger.json`, `missingWhy` of
`Fw.Engine.Chromium`) with the mechanism read from Chromium source @f842f52 (`B/` = `third_party/blink/renderer/`).
The tables above stay unchanged (the golden rows and `Fw.Parts` read them); a corrected rule is a new definition with
a bridge theorem back to the old one, as `frameWorkE` does in `Fw.Engine.Core`. -/

/-! ### Hit tests run PrePaint (ledger n=3) -/

/-- **Frame work with hit tests on PrePaint** (ledger n=3). A hit test (`elementFromPoint`, `TreeScope::HitTestPoint`,
`B/core/dom/tree_scope.cc:246-281, 421-437`) calls `LayoutView::HitTest`, which first runs
`UpdateAllLifecyclePhasesExceptPaint` (`B/core/layout/layout_view.cc:149-151`), i.e. the lifecycle up to
`kPrePaintClean` (`B/core/frame/local_frame_view.cc:2199-2203`). That path has no "already clean" early return
(`:2395-2452`) and emits the `PrePaint` trace event on every run (`:2570-2593`). So each hit test costs one PrePaint
(`props`) pass on top of the frame's own lifecycle. CONFIRMED.

$$\operatorname{crWorkH}(m, f) = \Big(s \mapsto \operatorname{frameWork}_{\operatorname{chromiumAt}(m)}(f).\mathrm{passes}(s) + [s = \mathrm{props}]\cdot f.\mathrm{hits},\ \ \operatorname{frameWork}_{\operatorname{chromiumAt}(m)}(f).\mathrm{units},\ \ f.\mathrm{hits}\Big)$$

Chromium's frame work in which every hit test also pays one PrePaint pass. -/
def crWorkH (m : CrMode) (f : FrameIn CrProp) : Work where
  passes s := (frameWork (chromiumAt m) f).passes s + (if s = .props then f.hits else 0)
  units s := (frameWork (chromiumAt m) f).units s
  hits := f.hits

/-- **PrePaint passes are at least the hit tests.**

$$\forall m \in \mathrm{CrMode},\ \forall f \in \mathrm{FrameIn}(\mathrm{CrProp}):\ f.\mathrm{hits} \le \operatorname{crWorkH}(m, f).\mathrm{passes}(\mathrm{props})$$

Every hit test in a frame shows up as a PrePaint pass. -/
theorem crWorkH_props_ge_hits (m : CrMode) (f : FrameIn CrProp) : f.hits ≤ (crWorkH m f).passes .props := by
  simp [crWorkH]

/-- **The old frame work is a lower bound.**

$$\forall m \in \mathrm{CrMode},\ \forall f \in \mathrm{FrameIn}(\mathrm{CrProp}):\ \operatorname{frameWork}_{\operatorname{chromiumAt}(m)}(f) \preceq \operatorname{crWorkH}(m, f)$$

Adding the PrePaint pass of each hit test only raises the work. -/
theorem crWorkH_ge (m : CrMode) (f : FrameIn CrProp) : (frameWork (chromiumAt m) f).le (crWorkH m f) :=
  ⟨fun _ => ⟨Nat.le_add_right _ _, Nat.le_refl _⟩, Nat.le_refl _⟩

/-- **No hit test, no change.**

$$\forall m \in \mathrm{CrMode},\ \forall f \in \mathrm{FrameIn}(\mathrm{CrProp}):\ f.\mathrm{hits} = 0 \Rightarrow \forall s \in \mathrm{Stage}:\ \operatorname{crWorkH}(m, f).\mathrm{passes}(s) = \operatorname{frameWork}_{\operatorname{chromiumAt}(m)}(f).\mathrm{passes}(s)$$

Without hit tests the corrected and the old pass counts agree. -/
theorem crWorkH_no_hits (m : CrMode) (f : FrameIn CrProp) (h : f.hits = 0) (s : Stage) :
    (crWorkH m f).passes s = (frameWork (chromiumAt m) f).passes s := by
  simp [crWorkH, h]

/-- **Skipping one hit test removes exactly one PrePaint pass** (the hit-skip variant of `nav.hitTest`).

$$\forall m \in \mathrm{CrMode},\ \forall f \in \mathrm{FrameIn}(\mathrm{CrProp}):\ \operatorname{crWorkH}(m, f[\mathrm{hits} := f.\mathrm{hits} + 1]).\mathrm{passes}(\mathrm{props}) = \operatorname{crWorkH}(m, f).\mathrm{passes}(\mathrm{props}) + 1$$

A frame that skips one probe runs one PrePaint fewer, whatever else it does. -/
theorem hitSkip_props (m : CrMode) (f : FrameIn CrProp) :
    (crWorkH m { f with hits := f.hits + 1 }).passes .props = (crWorkH m f).passes .props + 1 := by
  simp [crWorkH, frameWork, touched, forcedPasses, FrameIn.updates]
  omega

/-! ### Hit-test units: single point vs list (ledger n=4, first statement) -/

/-- The kind of a hit test: a single point (`elementFromPoint`) or a list-based one (`elementsFromPoint`).

$$\mathrm{HitKind} = \{\mathrm{single}, \mathrm{list}\}$$ -/
inductive HitKind where
  | single | list
deriving Repr, DecidableEq

/-- **Which hit tests the cache may serve.** `HitTestCache::LookupCachedResult` and `AddCachedResult` return early for
list-based (and rect-based) requests (`B/core/layout/hit_test_cache.cc:54-56`, `B/core/layout/hit_test_request.h:146-152`
`AvoidCache`). CONFIRMED.

$$\operatorname{cacheable}(\mathrm{single}) = \mathrm{true},\qquad \operatorname{cacheable}(\mathrm{list}) = \mathrm{false}$$

Only a single-point hit test can be answered from the hit-test cache. -/
def HitKind.cacheable : HitKind → Bool
  | .single => true
  | .list => false

/-- **Hit-test units**: the boxes a hit test visits among `n` candidate boxes in paint order, when the first hit is
at depth `d`. A cached single-point test visits none; an uncached one stops at the first hit; a list-based test is
never cached and keeps going past every hit (`HitTestResult::AddNodeToListBasedTestResult` returns "continue" for a
penetrating list, `B/core/layout/hit_test_result.cc:565-586`), so it visits all `n`. CONFIRMED.

$$\operatorname{hitUnits}(k, c, d, n) = \begin{cases} 0 & k = \mathrm{single} \land c \\ \min(d + 1, n) & k = \mathrm{single} \land \lnot c \\ n & k = \mathrm{list} \end{cases}$$

The boxes one hit test walks: none on a cache hit, up to the first hit for a single point, all for a list. -/
def hitUnits (k : HitKind) (cacheHit : Bool) (d n : Nat) : Nat :=
  match k with
  | .single => if cacheHit then 0 else min (d + 1) n
  | .list => n

/-- **A single-point test never visits more than a list-based one.**

$$\forall c, c' \in \mathbb{B},\ \forall d, n \in \mathbb{N}:\ \operatorname{hitUnits}(\mathrm{single}, c, d, n) \le \operatorname{hitUnits}(\mathrm{list}, c', d, n)$$

Whatever the cache does, the list-based test walks at least as many boxes. -/
theorem single_le_list (c c' : Bool) (d n : Nat) : hitUnits .single c d n ≤ hitUnits .list c' d n := by
  cases c <;> simp [hitUnits]; omega

/-- **When the list costs strictly more.** Uncached, the list-based test walks strictly more boxes iff the first hit
lies before the last candidate.

$$\forall d, n \in \mathbb{N}:\ \operatorname{hitUnits}(\mathrm{single}, \mathrm{false}, d, n) < \operatorname{hitUnits}(\mathrm{list}, \mathrm{false}, d, n) \iff d + 1 < n$$

The trade is strict exactly when boxes lie behind the first hit. -/
theorem single_lt_list_iff (d n : Nat) : hitUnits .single false d n < hitUnits .list false d n ↔ d + 1 < n := by
  simp [hitUnits]; omega

/-- **A list-based test ignores the cache.**

$$\forall c \in \mathbb{B},\ \forall d, n \in \mathbb{N}:\ \operatorname{cacheable}(\mathrm{list}) = \mathrm{false} \land \operatorname{hitUnits}(\mathrm{list}, c, d, n) = n$$

The list-based answer is never served from the cache and always walks every candidate. -/
theorem list_uncached (c : Bool) (d n : Nat) : HitKind.cacheable .list = false ∧ hitUnits .list c d n = n :=
  ⟨rfl, rfl⟩

#guard hitUnits .single true 2 9 == 0 && hitUnits .single false 2 9 == 3 && hitUnits .list true 2 9 == 9
#guard hitUnits .single false 12 9 == 9 && HitKind.cacheable .single && !HitKind.cacheable .list

/-! ### Paint fan-out of an inherited pointer-events write (ledger n=4, second statement) -/

/-- Duplicate-free copy of a list, keeping the last occurrence of each value.

$$\operatorname{nub}([\,]) = [\,],\qquad \operatorname{nub}(x :: L) = \begin{cases} \operatorname{nub}(L) & x \in L \\ x :: \operatorname{nub}(L) & x \notin L \end{cases}$$

The list with repeated values removed. -/
def nub {α : Type} [DecidableEq α] : List α → List α
  | [] => []
  | x :: l => if x ∈ l then nub l else x :: nub l

/-- `nub` keeps exactly the members.

$$\forall L \in \alpha^{*},\ \forall y \in \alpha:\ y \in \operatorname{nub}(L) \iff y \in L$$

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

$$\forall L \in \alpha^{*}:\ |\operatorname{nub}(L)| \le |L|$$

Dropping duplicates gives at most as many values. -/
theorem nub_length_le {α : Type} [DecidableEq α] (l : List α) : (nub l).length ≤ l.length := by
  induction l with
  | nil => simp [nub]
  | cons x l ih =>
    by_cases hx : x ∈ l <;> simp [nub, hx] <;> omega

/-- `nub` of a non-empty list is non-empty.

$$\forall L \in \alpha^{*}:\ L \ne [\,] \Rightarrow 1 \le |\operatorname{nub}(L)|$$

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

$$\forall L \in \alpha^{*}:\ \operatorname{nodup}(L) \Rightarrow \operatorname{nub}(L) = L$$

A list with no repeated value is left as it is. -/
theorem nub_eq_of_nodup {α : Type} [DecidableEq α] (l : List α) (h : l.Nodup) : nub l = l := by
  induction l with
  | nil => rfl
  | cons x l ih =>
    rw [List.nodup_cons] at h
    simp [nub, h.1, ih h.2]

/-- `nub` of a non-empty list of one repeated value is that value once.

$$\forall L \in \alpha^{*},\ \forall y \in \alpha:\ L \ne [\,] \land (\forall x \in L:\ x = y) \Rightarrow \operatorname{nub}(L) = [y]$$

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

$$\operatorname{pePaintUnits}(L, I) = \big|\operatorname{nub}([\,L(b) \mid b \in I\,])\big|$$

One repaint per painting layer reached by the inherited value. -/
def pePaintUnits (layerOf : Nat → Nat) (inh : List Nat) : Nat := (nub (inh.map layerOf)).length

/-- **Bounds of the fan-out.** At least one layer repaints when some box inherits the value, and never more than one
per inheriting box.

$$\forall L : \mathbb{N} \to \mathbb{N},\ \forall I \in \mathbb{N}^{*}:\ \operatorname{pePaintUnits}(L, I) \le |I| \ \land\ \big(I \ne [\,] \Rightarrow 1 \le \operatorname{pePaintUnits}(L, I)\big)$$

The old row's "one unit per inheriting box" is only an upper bound. -/
theorem pePaintUnits_bounds (layerOf : Nat → Nat) (inh : List Nat) :
    pePaintUnits layerOf inh ≤ inh.length ∧ (inh ≠ [] → 1 ≤ pePaintUnits layerOf inh) := by
  refine ⟨?_, fun h => ?_⟩
  · have := nub_length_le (inh.map layerOf)
    simpa [pePaintUnits] using this
  · apply nub_length_pos
    simpa using h

/-- **One layer per box: the old count holds.**

$$\forall L : \mathbb{N} \to \mathbb{N},\ \forall I \in \mathbb{N}^{*}:\ \operatorname{nodup}([\,L(b) \mid b \in I\,]) \Rightarrow \operatorname{pePaintUnits}(L, I) = |I|$$

When every inheriting box paints into its own layer, each costs one repaint. -/
theorem pePaintUnits_distinct (layerOf : Nat → Nat) (inh : List Nat) (h : (inh.map layerOf).Nodup) :
    pePaintUnits layerOf inh = inh.length := by
  simp [pePaintUnits, nub_eq_of_nodup _ h]

/-- **One shared layer: one repaint.**

$$\forall L : \mathbb{N} \to \mathbb{N},\ \forall I \in \mathbb{N}^{*},\ \forall \ell \in \mathbb{N}:\ I \ne [\,] \land (\forall b \in I:\ L(b) = \ell) \Rightarrow \operatorname{pePaintUnits}(L, I) = 1$$

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

$$\operatorname{lvl}_{\times 1}(o, l) = \begin{cases} \operatorname{lvl}(\mathrm{opacity}, l) & o \\ \mathrm{layoutFull} & \lnot o \end{cases}$$

Crossing 1 relays out the box unless it is a stacking context for another reason. -/
def opacityCross1Level (otherSC : Bool) (l : LayerState) : CrLevel :=
  if otherSC then keyLevel .opacity l else .layoutFull

/-- **A stacking-context flip lays out.**

$$\forall l \in \mathrm{LayerState}:\ \mathrm{layout} \in \operatorname{stages}(\operatorname{lvl}_{\times 1}(\mathrm{false}, l))$$

Without another stacking-context reason, crossing 1 costs a layout. -/
theorem opacityCross1_layout (l : LayerState) : Stage.layout ∈ (opacityCross1Level false l).stages := by
  simp [opacityCross1Level, CrLevel.stages]

/-- **No flip, no new row.**

$$\forall l \in \mathrm{LayerState}:\ \operatorname{lvl}_{\times 1}(\mathrm{true}, l) = \operatorname{lvl}(\mathrm{opacity}, l)$$

A box that stays a stacking context pays the plain opacity row. -/
theorem opacityCross1_otherSC (l : LayerState) : opacityCross1Level true l = keyLevel .opacity l := rfl

/-- **Resting at 0.999 never lays out** (the `people.carousel` rest at opacity 0.999): an opacity change that stays
below 1 is the plain opacity row, which is at most the crossing row and has no layout.

$$\forall o \in \mathbb{B},\ \forall l \in \mathrm{LayerState}:\ \operatorname{lvl}(\mathrm{opacity}, l) \le \operatorname{lvl}_{\times 1}(o, l) \ \land\ \mathrm{layout} \notin \operatorname{stages}(\operatorname{lvl}(\mathrm{opacity}, l))$$

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

$$\mathrm{CrPropX} = \{\mathrm{base}(p) \mid p \in \mathrm{CrProp}\} \cup \{\mathrm{opacityCross1}(o) \mid o \in \mathbb{B}\} \cup \{\mathrm{pointerEvents}, \mathrm{svgPaintServerAttr}\}$$

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

$$\operatorname{stagesOf}^{X}_{\mathrm{cr}}(e, x, l) = \begin{cases} \operatorname{stagesOf}_{\mathrm{cr}}(e, p, l) & x = \mathrm{base}(p) \\ \operatorname{stages}(\operatorname{lvl}_{\times 1}(o, l)) & x = \mathrm{opacityCross1}(o) \\ [\mathrm{style}, \mathrm{props}, \mathrm{paint}, \mathrm{commit}] & x = \mathrm{pointerEvents} \\ [\mathrm{props}, \mathrm{paint}, \mathrm{raster}, \mathrm{commit}] & x = \mathrm{svgPaintServerAttr} \end{cases}$$

The stages each extended Chromium change dirties. -/
def crStagesOfX (c : Change CrPropX) : List Stage :=
  match c.prop with
  | .base p => crStagesOf ⟨c.elem, p, c.layer⟩
  | .opacityCross1 o => (opacityCross1Level o c.layer).stages
  | .pointerEvents => [.style, .props, .paint, .commit]
  | .svgPaintServerAttr => [.props, .paint, .raster, .commit]

/-- **The extended Chromium engine in mode `m`**: `chromiumAt m` with the extended rows.

$$\operatorname{chromiumX}(m) = \big(m,\ \operatorname{stagesOf}^{X}_{\mathrm{cr}},\ \operatorname{compStages}(m),\ [\,]\big)$$

The Chromium engine over the extended property type. -/
def chromiumX (m : CrMode) : Engine CrPropX CrMode where
  mode := m
  stagesOf := crStagesOfX
  compStages := crCompStages m
  base := []

/-- A table change as an extended change.

$$\operatorname{lift}(e, p, l) = (e, \mathrm{base}(p), l)$$

Wraps an old Chromium change in the extended type. -/
def liftCr (c : Change CrProp) : Change CrPropX := ⟨c.elem, .base c.prop, c.layer⟩

/-- A frame of table changes as an extended frame.

$$\operatorname{liftF}(f) = f[\mathrm{changes} := [\,\operatorname{lift}(c) \mid c \in f.\mathrm{changes}\,]]$$

Wraps every change of an old Chromium frame. -/
def liftCrFrame (f : FrameIn CrProp) : FrameIn CrPropX :=
  ⟨f.script, f.forcedStyle, f.forcedLayout, f.hits, f.changes.map liftCr, f.compAnims⟩

/-- **The extension keeps the old table.** A lifted frame has the same passes, units and hit tests under the
extended engine.

$$\forall m \in \mathrm{CrMode},\ \forall f \in \mathrm{FrameIn}(\mathrm{CrProp}),\ \forall s \in \mathrm{Stage}:\ W^{X}.\mathrm{passes}(s) = W.\mathrm{passes}(s) \land W^{X}.\mathrm{units}(s) = W.\mathrm{units}(s) \land W^{X}.\mathrm{hits} = W.\mathrm{hits}$$
$$\text{where } W^{X} = \operatorname{frameWork}_{\operatorname{chromiumX}(m)}(\operatorname{liftF}(f)),\ W = \operatorname{frameWork}_{\operatorname{chromiumAt}(m)}(f)$$

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

$$\forall m \in \mathrm{CrMode},\ \forall e \in \mathbb{N},\ \forall l \in \mathrm{LayerState}:\ W.\mathrm{passes}(\mathrm{layout}) = 0 \land W.\mathrm{passes}(\mathrm{style}) = 0 \land W.\mathrm{passes}(\mathrm{paint}) = 1$$
$$\text{where } W = \operatorname{frameWork}_{\operatorname{chromiumX}(m)}\big((0, 0, 0, 0, [(e, \mathrm{svgPaintServerAttr}, l)], 0)\big)$$

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

$$\operatorname{bits}^{V}(m, a, v) = \operatorname{bits}(m, a) \mathbin{+\!\!+} [17 \mid \lnot v]$$

The modelled failure bits plus the no-visible-change bit. -/
def failBitsV (m : CrMode) (a : CrAnim) (vis : Bool) : List Nat :=
  failBits m a ++ (if vis then [] else [17])

/-- Where a running animation is serviced: on the compositor, on the main thread every frame, or nowhere.

$$\mathrm{CrRun} = \{\mathrm{comp}, \mathrm{main}, \mathrm{idle}\}$$ -/
inductive CrRun where
  | comp | main | idle
deriving Repr, DecidableEq

/-- **The thread rule with bit 17.** `Animation::animation_has_no_effect_` is set iff the failure reasons are exactly
`kAnimationHasNoVisibleChange` (`B/core/animation/animation.cc:860-865`), and such an animation is not ticked on the
main thread (`:3389-3393`) nor started on the compositor: it idles. Otherwise the old rule applies. CONFIRMED.

$$\operatorname{run}(m, a, v) = \begin{cases} \mathrm{idle} & \operatorname{bits}^{V}(m, a, v) = [17] \\ \mathrm{comp} & \operatorname{bits}^{V}(m, a, v) \ne [17] \land \operatorname{crThread}(m, a) = \mathrm{comp} \\ \mathrm{main} & \text{otherwise} \end{cases}$$

An animation that can change no pixel and has no other failure is neither ticked nor composited. -/
def crRunV (m : CrMode) (a : CrAnim) (vis : Bool) : CrRun :=
  if failBitsV m a vis = [17] then .idle else if crThread m a = .comp then .comp else .main

/-- **Bit 17 is not among the modelled bits.**

$$\forall m \in \mathrm{CrMode},\ \forall a \in \mathrm{CrAnim}:\ 17 \notin \operatorname{bits}(m, a)$$

The old bit list never contains the no-visible-change bit. -/
theorem failBits_no17 (m : CrMode) (a : CrAnim) : 17 ∉ failBits m a := by
  simp only [failBits, List.mem_append]
  split <;> split <;> split <;> split <;> split <;> simp

/-- **A visible animation keeps the old rule.**

$$\forall m \in \mathrm{CrMode},\ \forall a \in \mathrm{CrAnim}:\ \operatorname{run}(m, a, \mathrm{true}) = \begin{cases} \mathrm{comp} & \operatorname{crThread}(m, a) = \mathrm{comp} \\ \mathrm{main} & \text{otherwise} \end{cases}$$

For an animation that changes pixels, the bit-17 rule is `crThread`. -/
theorem crRunV_visible (m : CrMode) (a : CrAnim) :
    crRunV m a true = if crThread m a = .comp then .comp else .main := by
  have h : failBitsV m a true ≠ [17] := by
    intro h
    have : 17 ∈ failBits m a := by simp [failBitsV] at h; simp [h]
    exact failBits_no17 m a this
  simp [crRunV, h]

/-- **When an invisible animation idles.**

$$\forall m \in \mathrm{CrMode},\ \forall a \in \mathrm{CrAnim}:\ \operatorname{run}(m, a, \mathrm{false}) = \mathrm{idle} \iff \operatorname{bits}(m, a) = [\,]$$

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

$$\operatorname{animFrame}^{V}(m, A) = \Big(0, 0, 0, 0,\ \mathop{+\!\!+}_{(a, v) \in A,\ \operatorname{run}(m, a, v) = \mathrm{main}} \operatorname{changes}(a),\ \big|[\,(a, v) \in A \mid \operatorname{run}(m, a, v) = \mathrm{comp}\,]\big|\Big)$$

The frame of running animations once idle ones are dropped. -/
def animFrameV (m : CrMode) (as : List (CrAnim × Bool)) : FrameIn CrProp where
  script := 0
  forcedStyle := 0
  forcedLayout := 0
  hits := 0
  changes := (as.filter fun x => decide (crRunV m x.1 x.2 = .main)).flatMap fun x => x.1.changes
  compAnims := (as.filter fun x => decide (crRunV m x.1 x.2 = .comp)).length

/-- **All visible: the old frame.**

$$\forall m \in \mathrm{CrMode},\ \forall A \in \mathrm{CrAnim}^{*}:\ \operatorname{animFrame}^{V}(m, [\,(a, \mathrm{true}) \mid a \in A\,]) = \operatorname{animFrame}(m, A)$$

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

$$\forall m \in \mathrm{CrMode},\ \forall a \in \mathrm{CrAnim},\ \forall v \in \mathbb{B},\ \forall A \in (\mathrm{CrAnim} \times \mathbb{B})^{*}:\ \operatorname{run}(m, a, v) = \mathrm{idle} \Rightarrow \operatorname{animFrame}^{V}(m, (a, v) :: A) = \operatorname{animFrame}^{V}(m, A)$$

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

$$\operatorname{maxOf}(f, [\,]) = 0,\qquad \operatorname{maxOf}(f, x :: L) = \max(f(x), \operatorname{maxOf}(f, L))$$

The maximum of a measure over a list. -/
def maxOf {β : Type} (f : β → Nat) : List β → Nat
  | [] => 0
  | x :: l => max (f x) (maxOf f l)

/-- `maxOf` is monotone in the measure.

$$\forall f, g : \beta \to \mathbb{N},\ \forall L \in \beta^{*}:\ (\forall x \in L:\ f(x) \le g(x)) \Rightarrow \operatorname{maxOf}(f, L) \le \operatorname{maxOf}(g, L)$$

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

$$\forall f : \beta \to \mathbb{N},\ \forall L \in \beta^{*},\ \forall x \in L:\ f(x) \le \operatorname{maxOf}(f, L)$$

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

$$\forall f : \gamma \to \mathbb{N},\ \forall h : \beta \to \gamma,\ \forall L \in \beta^{*}:\ \operatorname{maxOf}(f, [\,h(x) \mid x \in L\,]) = \operatorname{maxOf}(f \circ h, L)$$

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

$$\operatorname{crRounds}(\mathcal{C}) = 1 + \operatorname{maxOf}\big(\mathit{ch} \mapsto |[\,(i, d) \in \mathit{ch} \mid d\,]|,\ \mathcal{C}\big)$$

Chromium recalculates style once more per layout-dirty container nesting level. -/
def crRounds (chains : List (List (Nat × Bool))) : Nat :=
  1 + maxOf (fun ch => (ch.filter fun x => x.2).length) chains

/-- **Rounds are bounded by nesting depth.**

$$\forall \mathcal{C} \in ((\mathbb{N} \times \mathbb{B})^{*})^{*}:\ \operatorname{crRounds}(\mathcal{C}) \le 1 + \operatorname{maxOf}(|\cdot|, \mathcal{C})$$

Only layout-dirty containers add a round, so the count is at most one more than the deepest chain. -/
theorem crRounds_le_depth (chains : List (List (Nat × Bool))) :
    crRounds chains ≤ 1 + maxOf List.length chains := by
  have := maxOf_le (fun ch : List (Nat × Bool) => (ch.filter fun x => x.2).length) List.length chains
    (fun ch _ => List.length_filter_le _ _)
  simp only [crRounds]; omega

/-- **Removing a container never adds a round** (Chromium).

$$\forall \mathcal{C},\ \forall c \in \mathbb{N}:\ \operatorname{crRounds}\big([\,[\,(i, d) \in \mathit{ch} \mid i \ne c\,] \mid \mathit{ch} \in \mathcal{C}\,]\big) \le \operatorname{crRounds}(\mathcal{C})$$

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

end Fw.Engine.Chromium
