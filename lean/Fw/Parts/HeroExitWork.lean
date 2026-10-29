import Fw.Parts.HeroExitOpt

/-!
# Hero exit: the original's inherited fan-out and the variant's edge frames

Two work facts of `hero-exit-threaded` (ledger n = 6) that `Fw.Parts.HeroExitOpt` left open.

* **Fan-out (gap R2).** The original writes the inherited `--exit-opacity` on `.hero`, so Chromium resolves the whole
  hero subtree, `crFull (heroTree ℓ)` elements, not one per consumer. The consumers are counted from the golden-linked
  `heroTree`. With that count the variant's scrolled frame keeps the original's single style pass but does strictly
  fewer style units, in every mode (`cr_style_saving`).
* **Edge frames (WebKit).** On the frame where the timeline progress leaves 0 or returns to 0, an opacity crosses 1
  and a blur radius crosses 0. WebKit lays out on both, so that frame of the variant pays layout
  (`wk_edge_layout`), while its other scrolled frames do not. Along a run of frames the edge frames are exactly the
  starts plus the parks, and at most `2 · starts + 1` (`edgeFrames_le_starts`).
-/
namespace Fw.Parts.HeroExitWork

open Fw.Engine Fw.Parts.HeroExitOpt Fw.Engine.Restyle Fw.Engine.Restyle.Node

/-! ## The consumers shown in each band -/

mutual
/-- The names of the nodes that read the exit values and have a box: `display: none` hides its whole subtree. -/
def shown : Node → List String
  | mk n f ks => if f.hidden then [] else (if f.reads then [n] else []) ++ shownL ks
/-- `shown` over a list of siblings. -/
def shownL : List Node → List String
  | [] => []
  | k :: ks => shown k ++ shownL ks
end

/-- The cards shown in band `ℓ`: the deck's cards in the phone band, the orbit's above it. -/
def cardsShown (l : Bool) : Nat := (shown (heroTree l)).count "hero.orbit/card"

#guard cardsShown true == 4
#guard cardsShown false == 10

/-- **The shown consumers are the cards, the copy and the cue**, in both bands: 4 cards in the phone band, 10 above.

Each band shows its cards plus the copy and the cue, and nothing else reads the exit values. -/
theorem shown_consumers (l : Bool) :
    shown (heroTree l) = List.replicate (cardsShown l) "hero.orbit/card" ++ ["hero/copy", "hero.cue/cue"] ∧
      cardsShown l = (if l then 4 else 10) := by
  cases l <;> decide +kernel

/-! ## Chromium: the original's inherited fan-out (R2) -/

section Fan
open Fw.Engine.Chromium

/-- The elements the original's write resolves beyond the hero and its consumers: the rest of the hero subtree. -/
def fanOut (l : Bool) : Nat := crFull (heroTree l) - (cardsShown l + 3)

#guard fanOut true == 92
#guard fanOut false == 159

/-- The hero, its consumers and the fan-out make up the whole resolved subtree.

The fan-out is the subtree count minus the hero and its consumers, with nothing cut off. -/
theorem fanOut_add (l : Bool) : cardsShown l + 3 + fanOut l = crFull (heroTree l) := by
  cases l <;> decide +kernel

/-- One resolved element of the fan-out: an inherited change that no property of the element reads. -/
def fanC (lo : LayerState) (i : Nat) : Change CrProp := ⟨100 + i, .custom exitVar [], lo⟩

/-- **The original's scrolled frame with the fan-out**: the per-consumer changes of `crOrig`, for the shown cards,
plus one style-only change per further element of the hero subtree. -/
def crOrigR2 (l : Bool) (lo : LayerState) (r : Bool) : FrameIn CrProp :=
  jsWrite 1 (crOrigChanges l (cardsShown l) lo r ++ (List.range (fanOut l)).map (fanC lo))

/-- Appending changes that dirty only `style` to a frame that already dirties `style` adds style units and nothing
else.

Extra style-only changes cost units on `style`, never a new pass. -/
theorem frameWork_append_style {P M : Type} (E : Engine P M) (f : FrameIn P) (ext : List (Change P))
    (hx : ∀ c ∈ ext, E.stagesOf c = [.style]) (hs : Stage.style ∈ f.changes.flatMap E.stagesOf) (s : Stage) :
    (frameWork E { f with changes := f.changes ++ ext }).passes s = (frameWork E f).passes s ∧
      (frameWork E { f with changes := f.changes ++ ext }).units s =
        (frameWork E f).units s + (if s = .style then ext.length else 0) := by
  have hne : f.changes ≠ [] := by
    intro h; simp [h] at hs
  have hu : FrameIn.updates { f with changes := f.changes ++ ext } = f.updates := by
    cases hc : f.changes with
    | nil => exact absurd hc hne
    | cons c cs => simp [FrameIn.updates, hc]
  have hmem : s ∈ ext.flatMap E.stagesOf → s ∈ f.changes.flatMap E.stagesOf := by
    intro h
    simp only [List.mem_flatMap] at h
    obtain ⟨c, hc, h⟩ := h
    rw [hx c hc] at h
    simp at h
    subst h
    exact hs
  have hcnt : ext.countP (fun c => decide (s ∈ E.stagesOf c)) = if s = .style then ext.length else 0 := by
    split
    · subst_vars
      exact List.countP_eq_length.mpr fun c hc => by simp [hx c hc]
    · exact List.countP_eq_zero.mpr fun c hc => by simp [hx c hc]; assumption
  constructor
  · simp only [frameWork, touched, hu, forcedPasses, List.flatMap_append, List.mem_append]
    congr 1
    by_cases h : s ∈ ext.flatMap E.stagesOf
    · simp [h, hmem h]
    · simp [h]
  · simp only [frameWork, stageUnits, List.countP_append, hcnt]
    omega

/-- Appending a nonempty list of changes that all dirty the stages `L` to an updating frame runs every stage of `L`
once and adds one unit per change on each.

Extra changes with one shared stage list cost one pass and their count in units on each of those stages. -/
theorem frameWork_append_uniform {P M : Type} (E : Engine P M) (f : FrameIn P) (ext : List (Change P))
    (L : List Stage) (hx : ∀ c ∈ ext, E.stagesOf c = L) (hne : ext ≠ []) (hu : f.updates = true) (s : Stage) :
    (frameWork E { f with changes := f.changes ++ ext }).passes s =
        (if s ∈ L then 1 + forcedPasses f s else (frameWork E f).passes s) ∧
      (frameWork E { f with changes := f.changes ++ ext }).units s =
        (frameWork E f).units s + (if s ∈ L then ext.length else 0) := by
  have hu' : FrameIn.updates { f with changes := f.changes ++ ext } = true := by
    cases hc : ext with
    | nil => exact absurd hc hne
    | cons c cs => simp [FrameIn.updates]
  have hmem : s ∈ ext.flatMap E.stagesOf ↔ s ∈ L := by
    constructor
    · intro h
      simp only [List.mem_flatMap] at h
      obtain ⟨c, hc, h⟩ := h
      rwa [hx c hc] at h
    · intro h
      obtain ⟨c, hc⟩ := List.exists_mem_of_ne_nil _ hne
      exact List.mem_flatMap.mpr ⟨c, hc, by rw [hx c hc]; exact h⟩
  have hcnt : ext.countP (fun c => decide (s ∈ E.stagesOf c)) = if s ∈ L then ext.length else 0 := by
    split
    · exact List.countP_eq_length.mpr fun c hc => by simp [hx c hc]; assumption
    · exact List.countP_eq_zero.mpr fun c hc => by simp [hx c hc]; assumption
  constructor
  · simp only [frameWork, touched, hu, hu', List.flatMap_append, List.mem_append, hmem, forcedPasses]
    by_cases hs : s ∈ L <;> simp [hs]
  · simp only [frameWork, stageUnits, List.countP_append, hcnt]
    omega

/-- **Exact work of the original's scrolled frame with the fan-out**: `crOrig`'s passes, and its units with the style
units raised to the whole resolved subtree.

What one scrolled frame of the original costs Chromium once the inherited fan-out is counted. -/
theorem cr_orig_r2 (m : CrMode) (l : Bool) (lo : LayerState) (r : Bool) (s : Stage) :
    (frameWork (chromiumAt m) (crOrigR2 l lo r)).passes s = crOrigPasses r s ∧
      (frameWork (chromiumAt m) (crOrigR2 l lo r)).units s =
        if s = .style then crFull (heroTree l) else crOrigUnits l (cardsShown l) lo r s := by
  have hx : ∀ c ∈ (List.range (fanOut l)).map (fanC lo), (chromiumAt m).stagesOf c = [.style] := by
    intro c hc
    simp only [List.mem_map] at hc
    obtain ⟨i, _, rfl⟩ := hc
    cases lo <;> rfl
  have hs : Stage.style ∈ (crOrig l (cardsShown l) lo r).changes.flatMap (chromiumAt m).stagesOf := by
    simp only [crOrig, jsWrite, crOrigChanges, List.flatMap_append, List.flatMap_cons, List.mem_append]
    have h1 : (chromiumAt m).stagesOf ⟨1, .custom exitVar [], lo⟩ = [.style] := by cases lo <;> rfl
    simp [h1]
  have h := frameWork_append_style (chromiumAt m) (crOrig l (cardsShown l) lo r) _ hx hs s
  have ho := cr_orig_exact m l (cardsShown l) lo r s
  have he : crOrigR2 l lo r = { crOrig l (cardsShown l) lo r with
      changes := (crOrig l (cardsShown l) lo r).changes ++ (List.range (fanOut l)).map (fanC lo) } := rfl
  rw [he, h.1, h.2, ho.1, ho.2]
  refine ⟨rfl, ?_⟩
  have hf := fanOut_add l
  by_cases hst : s = .style
  · subst hst; simp [crOrigUnits]; omega
  · simp [hst]

/-- **The style saving, in every mode** (threaded animation on): the variant's scrolled frame runs the original's
single style pass, but its style units are at most its `animCount ℓ N` animations, below the `crFull (heroTree ℓ)` elements
the original's inherited write resolves (`99` in the phone band, `172` above). In the CI lane the variant's units
are exactly the animation count.

On Chromium the variant restyles each animated consumer, the original the whole hero subtree. -/
theorem cr_style_saving (m : CrMode) (hm : m.threadedAnim = true) (l : Bool) (lo : LayerState) (r : Bool) :
    let V := frameWork (chromiumAt m) (crVar m l (cardsShown l) r)
    let O := frameWork (chromiumAt m) (crOrigR2 l lo r)
    V.passes .style = O.passes .style ∧ V.units .style ≤ (crAnims l (cardsShown l)).length ∧
      (crAnims l (cardsShown l)).length < O.units .style ∧ O.units .style = crFull (heroTree l) := by
  intro V O
  have hv := cr_var_exact m l (cardsShown l) r hm .style
  have ho := cr_orig_r2 m l lo r .style
  have hn : (crAnims l (cardsShown l)).length = animCount l (cardsShown l) := by
    cases l <;> simp [crAnims, animCount]
  have hf := fanOut_add l
  have hlt : animCount l (cardsShown l) < crFull (heroTree l) := by cases l <;> decide +kernel
  refine ⟨?_, ?_, ?_, ?_⟩
  · show (frameWork _ _).passes _ = (frameWork _ _).passes _
    rw [hv.1, ho.1]; rfl
  · show (frameWork _ _).units _ ≤ _
    rw [hv.2, hn]
    cases l <;> cases he : m.everyBeginFrameIsMainFrame <;> simp [crVarUnits, he, animCount] <;> omega
  · show _ < (frameWork _ _).units _
    rw [ho.2, hn]; simpa using hlt
  · show (frameWork _ _).units _ = _
    rw [ho.2]; simp

/-- **The lane's style saving**: in the CI lane both arms run one style pass, the variant with exactly its
`animCount ℓ N` animations as units and the original with the whole resolved subtree.

The CI lane sees the same style pass count in both arms and a unit saving it cannot read from pass counts. -/
theorem cr_lane_style_saving (l : Bool) (lo : LayerState) (r : Bool) :
    let V := frameWork (chromiumAt lane) (crVar lane l (cardsShown l) r)
    let O := frameWork (chromiumAt lane) (crOrigR2 l lo r)
    V.passes .style = O.passes .style ∧ V.units .style = (crAnims l (cardsShown l)).length ∧
      V.units .style < O.units .style := by
  intro V O
  obtain ⟨hp, _, hlt, _⟩ := cr_style_saving lane rfl l lo r
  have hv := cr_var_exact lane l (cardsShown l) r rfl .style
  have heq : V.units .style = (crAnims l (cardsShown l)).length := by
    show (frameWork _ _).units _ = _
    rw [hv.2]; cases l <;> simp [crVarUnits, crAnims, lane] <;> omega
  exact ⟨hp, heq, heq ▸ hlt⟩

end Fan

/-! ## WebKit: the edge frames -/

section Edge
open Fw.Engine.WebKit
open Fw.Parts.HeroExit (exitRange)

/-- Whether the consumers show their rest values at timeline progress `p`. -/
def restAt (p : Rat) : Bool := p == 0

#guard restAt 0 && !restAt (1 / 100)

/-- **Under RG11 the consumers rest exactly before the range**: progress is 0 iff the scroll offset is at or above
the track top `T`.

The rest frames are the scroll offsets up to `T`. -/
theorem rest_iff_before (prog : Rat → Rat) (T h v : Rat) (hrg : RG11 prog T h v) (y : Rat) :
    restAt (prog y) = decide (y ≤ T) := by
  have hn := HeroExit.exitRange_pos h v
  rw [hrg y]
  unfold restAt timelineProgress clamp01
  by_cases h1 : y ≤ T
  · have hd := HeroExit.div_mono (y - T) 0 (exitRange h v) hn (by grind)
    have h0 : (0 : Rat) / exitRange h v = 0 := by grind
    simp only [h1, decide_true, beq_iff_eq]
    grind
  · have hq := HeroExit.div_mul_pos (y - T) (exitRange h v) hn
    have hp : 0 < (y - T) / exitRange h v := by
      by_cases h2 : (y - T) / exitRange h v ≤ 0
      · have := Rat.mul_le_mul_of_nonneg_right h2 (Rat.le_of_lt hn)
        grind
      · grind
    simp only [h1, decide_false, beq_eq_false_iff_ne, ne_eq]
    grind

/-- **A moving consumer leaves its rest value at every progress but 0.**

An animated value equals its rest value only at progress 0. -/
theorem anim_rest_iff (k : Consumer) (hk : k.val 1 ≠ k.val 0) (p : Rat) : k.anim p = k.anim 0 ↔ p = 0 := by
  unfold Consumer.anim lerp
  constructor
  · intro h
    have h0 : (k.val 0 - k.val 1) * p = 0 := by grind
    rcases Rat.mul_eq_zero.mp h0 with h1 | h1
    · exact absurd (by grind) hk
    · exact h1
  · rintro rfl; rfl

/-- The opacity consumers rest at `1` and the blurred ones at radius `0`, and each of them moves (settled copy,
`c = 1`; the copy's blur above 600 px only).

The rest values the edge frames leave and return to. -/
theorem rest_values :
    (Consumer.copyOpacity 1).anim 0 = 1 ∧ Consumer.cardOpacity.anim 0 = 1 ∧ Consumer.cueBlur.anim 0 = 0 ∧
      (Consumer.copyBlur 1 false).anim 0 = 0 ∧
    (Consumer.copyOpacity 1).val 1 ≠ (Consumer.copyOpacity 1).val 0 ∧
      Consumer.cardOpacity.val 1 ≠ Consumer.cardOpacity.val 0 ∧ Consumer.cueBlur.val 1 ≠ Consumer.cueBlur.val 0 ∧
      (Consumer.copyBlur 1 false).val 1 ≠ (Consumer.copyBlur 1 false).val 0 := by
  simp only [Consumer.anim, lerp, Consumer.val, HeroExit.copyOpacity, HeroExit.cardOpacity, HeroExit.cueBlurPx,
    HeroExit.copyBlurPx, HeroExit.exitScatter]
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> simp <;> grind

/-- **The opacity row of a value change** on WebKit: a flip of `isOpaque` (value `1`) is `opacityCross1`
(`StyleDifference.cpp:208-214`, `StyleOpacity.h:66`@862f17d), another change `opacity`, no change no row. -/
def opacityRow (a b : Rat) : Option WkProp :=
  if (a == 1) != (b == 1) then some .opacityCross1 else if a == b then none else some .opacity

#guard opacityRow 1 (99 / 100) == some .opacityCross1
#guard opacityRow (1 / 2) 1 == some .opacityCross1
#guard opacityRow (1 / 2) (1 / 3) == some .opacity
#guard opacityRow 1 1 == none

/-- A computed `filter`: `none`, or one `blur()` with its radius. -/
inductive Filter where
  | none
  | blur (r : Rat)
deriving DecidableEq

/-- `hasFilters`: any value but `none`, so `blur(0px)` counts (`StyleNonInheritedMiscData.cpp:161-164`,
`StyleFilter.h:94`@862f17d). -/
def Filter.present : Filter → Bool
  | .none => false
  | .blur _ => true

/-- Zero outsets: a blur kernel is empty iff its radius is 0 (`FEGaussianBlur.cpp:107,112-120,158-162`@862f17d). -/
def Filter.zeroOutsets : Filter → Bool
  | .none => true
  | .blur r => r == 0

/-- **The edge row of a filter change** on WebKit: a flip of `hasFilters` is `filterToggle`
(`StyleDifference.cpp:217`@862f17d), else a flip of zero outsets is `filter` (outsets compared at
`StyleDifference.cpp:68-83`, layout at `:452-453`@862f17d), else no edge row. A change between two nonzero radii
is an interior change, outside this function. -/
def filterEdgeRow (a b : Filter) : Option WkProp :=
  if a.present != b.present then some .filterToggle
  else if a.zeroOutsets != b.zeroOutsets then some .filter
  else none

#guard filterEdgeRow .none (.blur 0) == some .filterToggle
#guard filterEdgeRow (.blur 0) (.blur (1 / 10)) == some .filter
#guard filterEdgeRow (.blur 2) (.blur 3) == none
#guard filterEdgeRow .none .none == none

/-- The cue's opacity rests at `1` and moves. -/
theorem cue_rest : Consumer.cueOpacity.anim 0 = 1 ∧ Consumer.cueOpacity.val 1 ≠ Consumer.cueOpacity.val 0 := by
  refine ⟨?_, ?_⟩ <;> simp only [Consumer.anim, lerp, Consumer.val, HeroExit.cueOpacity] <;> grind

/-- **Opacity edge (the three opacity consumers)**: between two frames the copy's, the cue's or a card's animated
opacity takes the `opacityCross1` row exactly when one frame rests and the other does not.

An opacity consumer crosses 1 on the frames that leave or reach progress 0. -/
theorem opacity_edge (p q : Rat) :
    (opacityRow ((Consumer.copyOpacity 1).anim p) ((Consumer.copyOpacity 1).anim q) = some .opacityCross1 ↔
      restAt p != restAt q) ∧
    (opacityRow (Consumer.cardOpacity.anim p) (Consumer.cardOpacity.anim q) = some .opacityCross1 ↔
      restAt p != restAt q) ∧
    (opacityRow (Consumer.cueOpacity.anim p) (Consumer.cueOpacity.anim q) = some .opacityCross1 ↔
      restAt p != restAt q) := by
  obtain ⟨r1, r2, _, _, m1, m2, _, _⟩ := rest_values
  obtain ⟨r5, m5⟩ := cue_rest
  have e1 := anim_rest_iff _ m1
  have e2 := anim_rest_iff _ m2
  have e5 := anim_rest_iff _ m5
  rw [r1] at e1
  rw [r2] at e2
  rw [r5] at e5
  have b1 : ∀ x, ((Consumer.copyOpacity 1).anim x == 1) = restAt x :=
    fun x => Bool.eq_iff_iff.mpr (by simp [restAt, e1 x])
  have b2 : ∀ x, (Consumer.cardOpacity.anim x == 1) = restAt x :=
    fun x => Bool.eq_iff_iff.mpr (by simp [restAt, e2 x])
  have b5 : ∀ x, (Consumer.cueOpacity.anim x == 1) = restAt x :=
    fun x => Bool.eq_iff_iff.mpr (by simp [restAt, e5 x])
  refine ⟨?_, ?_, ?_⟩ <;> unfold opacityRow <;> simp only [b1, b2, b5] <;>
    cases restAt p <;> cases restAt q <;> simp <;> split <;> simp

/-- **Filter presence (start and park frames)**: the variant's blur keyframes are `blur(0px)` to `blur(18px)`, so
between any two frames the cue's and the wide copy's filter never flips `hasFilters` (no `filterToggle`), and takes
the `filter` edge row exactly when one frame rests and the other does not. The phone-band copy keeps `filter: none`
in both arms and has no edge row.

The variant's blurs stay present, and their outsets flip only on the frames that leave or reach progress 0. -/
theorem filter_edge (p q : Rat) :
    filterEdgeRow (.blur (Consumer.cueBlur.anim p)) (.blur (Consumer.cueBlur.anim q)) =
        (if restAt p != restAt q then some .filter else none) ∧
      filterEdgeRow (.blur ((Consumer.copyBlur 1 false).anim p)) (.blur ((Consumer.copyBlur 1 false).anim q)) =
        (if restAt p != restAt q then some .filter else none) ∧
      filterEdgeRow .none .none = none := by
  obtain ⟨_, _, r3, r4, _, _, m3, m4⟩ := rest_values
  have e3 := anim_rest_iff _ m3
  have e4 := anim_rest_iff _ m4
  rw [r3] at e3
  rw [r4] at e4
  have b3 : ∀ x, (Consumer.cueBlur.anim x == 0) = restAt x :=
    fun x => Bool.eq_iff_iff.mpr (by simp [restAt, e3 x])
  have b4 : ∀ x, ((Consumer.copyBlur 1 false).anim x == 0) = restAt x :=
    fun x => Bool.eq_iff_iff.mpr (by simp [restAt, e4 x])
  refine ⟨?_, ?_, rfl⟩ <;> unfold filterEdgeRow Filter.present Filter.zeroOutsets <;> simp only [b3, b4] <;>
    rfl

/-- The edge row an animated property of the variant adds on an edge frame: opacity crosses 1, a blur flips its zero
outsets, a transform has none (its value change is already the compositor's). -/
def edgeProp : CssProp → Option WkProp
  | .opacity => some .opacityCross1
  | .filter => some .filter
  | _ => none

#guard edgeProp .opacity == some .opacityCross1
#guard edgeProp .filter == some .filter
#guard edgeProp .transform == none

/-- The edge rows of the variant on an edge frame, one per animated opacity or blur, on each animation's target. -/
def wkEdgeChanges (l : Bool) (N : Nat) : List (Change WkPropX) :=
  ((wkTargets l N).zip (wkAnims l N)).flatMap fun p =>
    p.2.props.filterMap fun c => (edgeProp c).map fun q => ⟨p.1, .base q, .own⟩

/-- **The variant's edge frame on WebKit**: its scrolled frame plus the edge rows. -/
def wkEdge (m : WkMode) (l : Bool) (N : Nat) : FrameIn WkPropX :=
  { wkVar m l N with changes := (wkVar m l N).changes ++ wkEdgeChanges l N }

/-- The number of edge rows: the copy's opacity, the cue's opacity and blur, each card's opacity, and the copy's blur
above 600 px. -/
def edgeCount (l : Bool) (N : Nat) : Nat := if l then N + 3 else N + 4

/-- The stages of an edge row on an own layer: layout, with its style, compositing update and paint. -/
def edgeStages : List Stage := [.style, .layout, .props, .paint]

#guard edgeCount true 4 == 7 && edgeCount false 10 == 14

/-- The edge rows, written out: the copy's opacity, the cue's opacity in the phone band, the copy's blur and the cue's
opacity above 600 px, the cue's blur, each card's opacity.

What `wkEdgeChanges` lists in each band. -/
theorem wkEdgeChanges_eq (l : Bool) (N : Nat) :
    wkEdgeChanges l N = [⟨2, .base .opacityCross1, .own⟩] ++
      (if l then [⟨3, .base .opacityCross1, .own⟩] else [⟨2, .base .filter, .own⟩, ⟨3, .base .opacityCross1, .own⟩]) ++
      [⟨3, .base .filter, .own⟩] ++ (List.range N).map (fun i => ⟨4 + i, .base .opacityCross1, .own⟩) := by
  have hz : ((List.range N).map (4 + ·)).zip ((List.range N).map fun _ => wkAnim [.opacity, .transform]) =
      (List.range N).map fun i => (4 + i, wkAnim [.opacity, .transform]) := by
    rw [List.zip_map]
    induction N with
    | zero => rfl
    | succ n ih => simp [List.range_succ, List.zip_append, ih]
  have hc : ((List.range N).map fun i => (4 + i, wkAnim [.opacity, .transform])).flatMap (fun p =>
      p.2.props.filterMap fun c => (edgeProp c).map fun q => (⟨p.1, .base q, .own⟩ : Change WkPropX)) =
      (List.range N).map (fun i => ⟨4 + i, .base .opacityCross1, .own⟩) := by
    clear hz
    induction N with
    | zero => rfl
    | succ n ih =>
      rw [List.range_succ, List.map_append, List.flatMap_append, ih, List.map_append]
      rfl
  cases l <;> simp only [wkEdgeChanges, wkTargets, wkAnims, List.cons_append, List.nil_append, List.zip_cons_cons, hz,
    List.flatMap_cons, hc, ite_true, ite_false, Bool.false_eq_true] <;> rfl

/-- Every edge row dirties exactly the edge stages.

An opacity crossing 1 and a blur outset flip cost the same stages on an own layer. -/
theorem edge_stages (l : Bool) (N : Nat) : ∀ c ∈ wkEdgeChanges l N, wkStagesOfX c = edgeStages := by
  intro c hc
  simp only [wkEdgeChanges, List.mem_flatMap, List.mem_filterMap, Option.map_eq_some_iff] at hc
  obtain ⟨_, _, x, _, q, hq, rfl⟩ := hc
  cases x <;> simp [edgeProp] at hq <;> subst hq <;> rfl

/-- There are `edgeCount` edge rows.

One edge row per animated opacity or blur. -/
theorem wkEdgeChanges_length (l : Bool) (N : Nat) : (wkEdgeChanges l N).length = edgeCount l N := by
  rw [wkEdgeChanges_eq]; cases l <;> simp [edgeCount] <;> omega

/-- **The variant's scrolled frame never lays out on WebKit** (threaded scroll-driven on).

Away from the edges the variant's web process does no layout. -/
theorem wk_var_no_layout (m : WkMode) (hm : m.threadedScrollDriven = true) (l : Bool) (N : Nat) :
    (frameWork (webkitX m) (wkVar m l N)).passes .layout = 0 ∧
      (frameWork (webkitX m) (wkVar m l N)).units .layout = 0 := by
  have h0 : wkStages ⟨0, .scrollPos, .none⟩ = [] := scrollPos_stages m 0 .none
  have hl : Stage.layout ∉ touched (webkitX m) (wkVar m l N) := by
    rw [wkVar_eq m hm l N]
    simp [touched, webkitX, wkStagesOfX, h0, FrameIn.updates]
  constructor
  · simp only [frameWork, hl, ite_false, forcedPasses]
    rw [wkVar_eq m hm l N]
    rfl
  · simp only [frameWork, stageUnits]
    rw [wkVar_eq m hm l N]
    simp [webkitX, wkStagesOfX, h0]

/-- **Exact work of the variant's edge frame on WebKit** (threaded scroll-driven on): the edge stages run once and
gain `edgeCount ℓ N` units each; every other stage is the scrolled frame's.

On the frame that leaves or reaches progress 0 the variant pays one layout, compositing update and paint. -/
theorem wk_edge_work (m : WkMode) (hm : m.threadedScrollDriven = true) (l : Bool) (N : Nat) (s : Stage) :
    (frameWork (webkitX m) (wkEdge m l N)).passes s =
        (if s ∈ edgeStages then 1 else (frameWork (webkitX m) (wkVar m l N)).passes s) ∧
      (frameWork (webkitX m) (wkEdge m l N)).units s =
        (frameWork (webkitX m) (wkVar m l N)).units s + (if s ∈ edgeStages then edgeCount l N else 0) := by
  have hne : wkEdgeChanges l N ≠ [] := by rw [wkEdgeChanges_eq]; cases l <;> simp
  have hu : (wkVar m l N).updates = true := by rw [wkVar_eq m hm l N]; rfl
  have hf : forcedPasses (wkVar m l N) s = 0 := by rw [wkVar_eq m hm l N]; cases s <;> rfl
  have h := frameWork_append_uniform (webkitX m) (wkVar m l N) _ edgeStages (edge_stages l N) hne hu s
  rw [hf, wkEdgeChanges_length] at h
  exact h

/-- **The edge cost on WebKit, as a trade fact**: the variant's scrolled frame does no layout, its edge frame one
layout pass with `edgeCount ℓ N` units (`N + 3` in the phone band, `N + 4` above).

The variant's layout is confined to the frames that leave or reach progress 0. -/
theorem wk_edge_layout (m : WkMode) (hm : m.threadedScrollDriven = true) (l : Bool) (N : Nat) :
    (frameWork (webkitX m) (wkVar m l N)).passes .layout = 0 ∧
      (frameWork (webkitX m) (wkEdge m l N)).passes .layout = 1 ∧
      (frameWork (webkitX m) (wkEdge m l N)).units .layout = edgeCount l N := by
  have h0 := wk_var_no_layout m hm l N
  have he := wk_edge_work m hm l N .layout
  refine ⟨h0.1, ?_, ?_⟩
  · rw [he.1]; rfl
  · rw [he.2, h0.2]; simp [edgeStages]

/-! ### Edge frames along a run of frames -/

/-- The frame pairs of a run: each frame with the next one. -/
def steps (ps : List Rat) : List (Rat × Rat) := ps.zip ps.tail

/-- The starts of a run: a rest frame followed by a moving one. -/
def startsOf (ps : List Rat) : Nat := (steps ps).countP fun q => restAt q.1 && !restAt q.2

/-- The parks of a run: a moving frame followed by a rest frame. -/
def parksOf (ps : List Rat) : Nat := (steps ps).countP fun q => !restAt q.1 && restAt q.2

/-- The edge frames of a run: the frames whose rest state differs from the previous frame's. -/
def edgeFrames (ps : List Rat) : Nat := (steps ps).countP fun q => restAt q.1 != restAt q.2

#guard startsOf [0, 0, 1 / 10, 1 / 2, 0, 0, 1 / 5] == 2
#guard parksOf [0, 0, 1 / 10, 1 / 2, 0, 0, 1 / 5] == 1
#guard edgeFrames [0, 0, 1 / 10, 1 / 2, 0, 0, 1 / 5] == 3
#guard edgeFrames [1 / 2, 0] == 1 && edgeFrames [] == 0

/-- **The edge frames are the starts plus the parks.**

Every edge frame either leaves rest or reaches it. -/
theorem edgeFrames_eq (ps : List Rat) : edgeFrames ps = startsOf ps + parksOf ps := by
  unfold edgeFrames startsOf parksOf
  induction steps ps with
  | nil => rfl
  | cons q qs ih =>
    simp only [List.countP_cons, ih]
    cases restAt q.1 <;> cases restAt q.2 <;> simp <;> omega

/-- **Starts and parks alternate**: over a nonempty run, the starts plus a final rest equal the parks plus an initial
rest.

Between two starts the run parks exactly once. -/
theorem starts_parks_balance (a : Rat) (ps : List Rat) :
    startsOf (a :: ps) + (if restAt ((a :: ps).getLast (by simp)) then 1 else 0) =
      parksOf (a :: ps) + (if restAt a then 1 else 0) := by
  induction ps generalizing a with
  | nil =>
    simp only [startsOf, parksOf, steps, List.tail_cons, List.zip_nil_right, List.countP_nil,
      List.getLast_singleton]
    rfl
  | cons b bs ih =>
    have h := ih b
    simp only [startsOf, parksOf, steps, List.tail_cons, List.zip_cons_cons, List.countP_cons] at h ⊢
    rw [List.getLast_cons (by simp)]
    cases ha : restAt a <;> cases hb : restAt b <;> simp_all <;> omega

/-- **Edge frames per start are bounded**: a run has at most `2 · starts + 1` edge frames, and at most `2 · starts`
when it begins at rest; each start is one edge frame.

At most one park per start, plus one if the run begins moving. -/
theorem edgeFrames_le_starts (ps : List Rat) :
    startsOf ps ≤ edgeFrames ps ∧ edgeFrames ps ≤ 2 * startsOf ps + 1 ∧
      (∀ a qs, ps = a :: qs → restAt a = true → edgeFrames ps ≤ 2 * startsOf ps) := by
  rw [edgeFrames_eq]
  refine ⟨by omega, ?_, ?_⟩
  · cases ps with
    | nil => simp [startsOf, parksOf, steps]
    | cons a qs =>
      have := starts_parks_balance a qs
      split at this <;> split at this <;> omega
  · rintro a qs rfl ha
    have := starts_parks_balance a qs
    rw [ha] at this
    split at this <;> simp at this <;> omega

/-- A run has fewer edge frames than frames.

Each edge frame is a step between two frames. -/
theorem edgeFrames_lt_length (ps : List Rat) (h : ps ≠ []) : edgeFrames ps < ps.length := by
  have hc := List.countP_le_length (p := fun q : Rat × Rat => restAt q.1 != restAt q.2) (l := steps ps)
  have hl : (steps ps).length = ps.length - 1 := by simp [steps]
  have hp : 0 < ps.length := List.length_pos_iff.mpr h
  unfold edgeFrames
  omega

end Edge

end Fw.Parts.HeroExitWork
