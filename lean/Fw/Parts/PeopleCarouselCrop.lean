import Lean.Data.Json
import Fw.Parts.PeopleCarousel
import Fw.Engine.Chromium
import Fw.Engine.WebKit
namespace Fw.Parts.PeopleCarouselCrop
open Fw.Engine Fw.Parts.PeopleCarousel

/-- Animated properties of the swap row's keyframes (CSS 2866-2915). -/
inductive P where
  | opacity | transform | translate | flexBasis | width | marginRight | borderWidth
deriving Repr, DecidableEq

/-- The original `avatars-exit` properties. -/
def avatarsExit : List P := [.opacity, .flexBasis, .width, .marginRight, .borderWidth, .transform]

/-- The crop leaver: opacity and scale only. -/
def cropExit : List P := [.opacity, .transform]

/-- The crop shift of a follower and of the entering avatar: the `translate` property alone. -/
def cropShift : List P := [.translate]

/-- The unchanged `avatars-pop` properties. -/
def popProps : List P := [.opacity, .transform]

/-- Properties that change the box the flex row lays out. -/
def P.isLayout : P → Bool
  | .flexBasis | .width | .marginRight | .borderWidth => true
  | _ => false

/-- WebKit's property class of each property (`.size` stands for every box-size property, layout in `rawDiff`). -/
def P.wk : P → Fw.Engine.WebKit.CssProp
  | .opacity => .opacity | .transform => .transform | .translate => .translate
  | .flexBasis | .width | .marginRight | .borderWidth => .size

/-- WebKit's change class of each property. -/
def P.wkChange : P → Fw.Engine.WebKit.WkProp
  | .opacity => .opacity | .transform => .transform | .translate => .transform
  | .flexBasis | .width | .marginRight | .borderWidth => .size

/-- Chromium's key of each property (flex-basis and border-width take the width key, both `layoutFull`). -/
def P.cr : P → Fw.Engine.Chromium.CrKey
  | .opacity => .opacity | .transform => .transform | .translate => .translate
  | .width | .flexBasis | .borderWidth => .width
  | .marginRight => .margin

theorem avatarsExit_layout : avatarsExit.filter P.isLayout = [.flexBasis, .width, .marginRight, .borderWidth] := by decide

theorem cropExit_no_layout : cropExit.all (fun q => !q.isLayout) = true := by decide

theorem cropShift_no_layout : cropShift.all (fun q => !q.isLayout) = true := by decide

section Wk
open Fw.Engine.WebKit

/-- A keyframe effect of the given properties with no other disqualifier (`WkAnim.clean`). -/
def wkAnim (g : List P) : WkAnim := .clean (g.map P.wk) .time

/-- Every layout property is unaccelerated on both paths. -/
theorem layout_not_accelerated (q : P) (h : q.isLayout = true) (path : Path) : accelerated path q.wk = false := by
  cases q <;> simp_all [P.isLayout, P.wk, accelerated]

/-- **A piece with a layout property ticks on main**, in every mode. -/
theorem piece_main (m : WkMode) (g : List P) (q : P) (hq : q ∈ g) (hl : q.isLayout = true) :
    wkThread m (wkAnim g) = .main := by
  have : (wkAnim g).props.all (accelerated (pathOf m (wkAnim g))) = false := by
    rw [List.all_eq_false]
    exact ⟨q.wk, by simp [wkAnim, WkAnim.clean]; exact ⟨q, hq, rfl⟩, by simp [layout_not_accelerated q hl]⟩
  simp [wkThread, this]

/-- **The crop pieces run in the UI process**, in every mode. -/
theorem crop_comp (m : WkMode) (g : List P) (hg : g = cropExit ∨ g = cropShift ∨ g = popProps) :
    wkThread m (wkAnim g) = .comp := by
  obtain ⟨tsd, ttb, p⟩ := m
  rcases hg with rfl | rfl | rfl <;> cases tsd <;> cases ttb <;> cases p <;> decide +kernel

end Wk


/-- A split of `avatars-exit` into effects: every property of the keyframes is in some piece. -/
def Covers (parts : List (List P)) : Prop := ∀ q ∈ avatarsExit, ∃ g ∈ parts, q ∈ g

theorem covers_width {parts : List (List P)} (h : Covers parts) : ∃ g ∈ parts, P.width ∈ g :=
  h .width (by decide)

section WkFrames
open Fw.Engine.WebKit

/-- **Any split of `avatars-exit` keeps layout in WebKit.** Some piece holds `width`; it ticks on main in every mode
and its frame runs a layout pass, on any layer state. -/
theorem split_keeps_layout_wk {parts : List (List P)} (h : Covers parts) (m : WkMode) (e : Nat) (l : LayerState) :
    ∃ g ∈ parts, wkThread m (wkAnim g) = .main ∧
      1 ≤ (frameWork (webkitAt m) (animFrame m (wkAnim g) (g.map fun q => ⟨e, q.wkChange, l⟩))).passes .layout := by
  obtain ⟨g, hg, hw⟩ := covers_width h
  have hm : wkThread m (wkAnim g) = .main := piece_main m g .width hw rfl
  refine ⟨g, hg, hm, ?_⟩
  have hn : (wkThread m (wkAnim g) = .comp) = False := by simp [hm]
  have hmem : (⟨e, P.width.wkChange, l⟩ : Change WkProp) ∈ g.map (fun q => (⟨e, q.wkChange, l⟩ : Change WkProp)) :=
    List.mem_map.mpr ⟨.width, hw, rfl⟩
  have hl : Stage.layout ∈ (webkitAt m).stagesOf ⟨e, P.width.wkChange, l⟩ := by
    have key : ∀ l' : LayerState, Stage.layout ∈ wkStages ⟨0, WkProp.size, l'⟩ := by intro l'; cases l' <;> decide +kernel
    exact key l
  have ht : Stage.layout ∈ touched (webkitAt m) (animFrame m (wkAnim g) (g.map fun q => ⟨e, q.wkChange, l⟩)) := by
    simp only [touched, animFrame, hn, ite_false, FrameIn.updates, List.mem_append]
    exact Or.inl (Or.inl (Or.inl (List.mem_flatMap.mpr ⟨_, hmem, hl⟩)))
  simp only [frameWork, ht, ite_true]
  omega

end WkFrames

section CrFrames
open Fw.Engine.Chromium

/-- The Chromium animation of a piece on element `e`. -/
def crAnim (e : Nat) (g : List P) (l : LayerState) : CrAnim := ⟨e, g.map fun q => .css q.cr, l, true, .document⟩

theorem layout_not_eligible (q : P) (h : q.isLayout = true) : CrProp.eligible (.css q.cr) = false := by
  cases q <;> simp_all [P.isLayout, P.cr, CrProp.eligible]

/-- **Any split of `avatars-exit` keeps layout in Chromium**: the piece with `width` ticks on main in every mode and its
frame runs a layout pass, on any layer state. -/
theorem split_keeps_layout_cr {parts : List (List P)} (h : Covers parts) (m : CrMode) (e : Nat) (l : LayerState) :
    ∃ g ∈ parts, crThread m (crAnim e g l) = .main ∧
      1 ≤ (frameWork (chromiumAt m) (Chromium.animFrame m [crAnim e g l])).passes .layout := by
  obtain ⟨g, hg, hw⟩ := covers_width h
  have hel : (crAnim e g l).props.all CrProp.eligible = false := by
    rw [List.all_eq_false]
    exact ⟨.css P.width.cr, by simp [crAnim]; exact ⟨.width, hw, rfl⟩, by simp [layout_not_eligible .width rfl]⟩
  have hm : crThread m (crAnim e g l) = .main := by simp [crThread, hel]
  refine ⟨g, hg, hm, ?_⟩
  have hmem : (⟨e, .css P.width.cr, l⟩ : Change CrProp) ∈ (crAnim e g l).changes :=
    List.mem_map.mpr ⟨.css P.width.cr, by simp [crAnim]; exact ⟨.width, hw, rfl⟩, rfl⟩
  have hl : Stage.layout ∈ (chromiumAt m).stagesOf ⟨e, .css P.width.cr, l⟩ := by
    have key : ∀ l' : LayerState, Stage.layout ∈ crStagesOf ⟨0, .css CrKey.width, l'⟩ := by intro l'; cases l' <;> decide +kernel
    exact key l
  have ht : Stage.layout ∈ touched (chromiumAt m) (Chromium.animFrame m [crAnim e g l]) := by
    simp only [touched, Chromium.animFrame, FrameIn.updates, List.mem_append]
    refine Or.inl (Or.inl (Or.inl (List.mem_flatMap.mpr ⟨_, ?_, hl⟩)))
    exact List.mem_flatMap.mpr ⟨crAnim e g l, by simp [hm], hmem⟩
  simp only [frameWork, ht, ite_true]
  omega

end CrFrames


section Work
open Fw.Engine.WebKit

/-- The original swap frame in WebKit on layer state `l`: the exit effect ticks on main (one change per property), the
pop effect is the one compositor animation. -/
def wkOrig (l : LayerState) : FrameIn WkProp := ⟨0, 0, 0, 0, avatarsExit.map fun q => ⟨0, q.wkChange, l⟩, 1⟩

/-- The crop swap frame in WebKit: six effects (leaver exit, three follower shifts, pop and shift of the entering
avatar), all in the UI process. -/
def wkCrop : FrameIn WkProp := compFrame 6

theorem wk_orig_exit_main (m : WkMode) : wkThread m (wkAnim avatarsExit) = .main :=
  piece_main m avatarsExit .width (by decide) rfl

theorem wk_crop_all_comp (m : WkMode) :
    wkThread m (wkAnim cropExit) = .comp ∧ wkThread m (wkAnim cropShift) = .comp ∧ wkThread m (wkAnim popProps) = .comp :=
  ⟨crop_comp m _ (Or.inl rfl), crop_comp m _ (Or.inr (Or.inl rfl)), crop_comp m _ (Or.inr (Or.inr rfl))⟩

/-- **The crop frame has no pass and no unit off the compositor stage** in WebKit. -/
theorem wk_crop_zero (m : WkMode) (s : Stage) (hs : s ≠ .comp) :
    (frameWork (webkitAt m) wkCrop).passes s = 0 ∧ (frameWork (webkitAt m) wkCrop).units s = 0 :=
  compFrame_zero m 6 s hs

/-- **Layout falls to zero in WebKit**: the original frame pays a layout pass and four or more layout units on a
non-layer box, the crop frame none. -/
theorem wk_layout (m : WkMode) :
    (frameWork (webkitAt m) wkCrop).units .layout = 0 ∧ (frameWork (webkitAt m) wkCrop).passes .layout = 0 ∧
      1 ≤ (frameWork (webkitAt m) (wkOrig .none)).passes .layout ∧
      4 ≤ (frameWork (webkitAt m) (wkOrig .none)).units .layout := by
  obtain ⟨a, b, c⟩ := m
  cases a <;> cases b <;> cases c <;> decide +kernel

/-- **The trade**: the crop frame has six compositor units against one. -/
theorem wk_comp_trade (m : WkMode) :
    (frameWork (webkitAt m) wkCrop).units .comp = 6 ∧ (frameWork (webkitAt m) (wkOrig .none)).units .comp = 1 := by
  obtain ⟨a, b, c⟩ := m
  cases a <;> cases b <;> cases c <;> decide +kernel

/-- **Main-thread work does not grow in WebKit** off the compositor stage. -/
theorem wk_crop_main_le (m : WkMode) (s : Stage) (hs : s ≠ .comp) :
    (frameWork (webkitAt m) wkCrop).passes s ≤ (frameWork (webkitAt m) (wkOrig .none)).passes s ∧
      (frameWork (webkitAt m) wkCrop).units s ≤ (frameWork (webkitAt m) (wkOrig .none)).units s := by
  have h := wk_crop_zero m s hs
  omega

end Work

section CrWork
open Fw.Engine.Chromium

/-- The original swap frame in Chromium: exit on main, pop on the compositor. -/
def crOrig (m : CrMode) (l : LayerState) : FrameIn CrProp :=
  Chromium.animFrame m [crAnim 0 avatarsExit l, crAnim 4 popProps l]

/-- The crop swap frame in Chromium: the same six effects, each on its own layer. -/
def crCrop (m : CrMode) : FrameIn CrProp :=
  Chromium.animFrame m [crAnim 0 cropExit .own, crAnim 1 cropShift .own, crAnim 2 cropShift .own,
    crAnim 3 cropShift .own, crAnim 4 popProps .own, crAnim 4 cropShift .own]

theorem cr_crop_all_comp (m : CrMode) (hm : m.threadedAnim = true) :
    ∀ a ∈ [crAnim 0 cropExit .own, crAnim 1 cropShift .own, crAnim 2 cropShift .own,
      crAnim 3 cropShift .own, crAnim 4 popProps .own, crAnim 4 cropShift .own], crThread m a = .comp := by
  intro a ha
  simp only [List.mem_cons, List.mem_nil_iff, or_false] at ha
  rcases ha with rfl | rfl | rfl | rfl | rfl | rfl <;>
    simp [crThread, failBits, hm, crAnim, cropExit, cropShift, popProps, CrProp.eligible, CrProp.movesPixels, P.cr]

/-- **The crop frame runs no layout, paint, raster or commit in Chromium**, in the lane and in real Chrome. -/
theorem cr_crop_zero (m : CrMode) (hm : m = lane ∨ m = realChrome) :
    ∀ s ∈ [Stage.layout, .paint, .raster, .commit],
      (frameWork (chromiumAt m) (crCrop m)).passes s = 0 ∧ (frameWork (chromiumAt m) (crCrop m)).units s = 0 := by
  have ht : m.threadedAnim = true := by rcases hm with rfl | rfl <;> rfl
  exact compAnim_no_layout_paint m _ (cr_crop_all_comp m ht)

/-- **The original frame lays out in Chromium**: one layout pass and four layout units, on any layer state. -/
theorem cr_orig_layout (m : CrMode) (hm : m = lane ∨ m = realChrome) (l : LayerState) :
    (frameWork (chromiumAt m) (crOrig m l)).passes .layout = 1 ∧ (frameWork (chromiumAt m) (crOrig m l)).units .layout = 4 := by
  rcases hm with rfl | rfl <;> cases l <;> decide +kernel

/-- **The trade in Chromium**: six compositor units against one. -/
theorem cr_comp_trade (m : CrMode) (hm : m = lane ∨ m = realChrome) :
    (frameWork (chromiumAt m) (crCrop m)).units .comp = 6 ∧ (frameWork (chromiumAt m) (crOrig m .none)).units .comp = 1 := by
  rcases hm with rfl | rfl <;> decide +kernel

end CrWork

/-- Frames in one 220 ms swap at `hz` frames per second, whole frames. -/
def swapFrames (hz : Nat) : Nat := swapMs * hz / 1000

theorem swapFrames_60 : swapFrames 60 = 13 := by decide

theorem swapFrames_120 : swapFrames 120 = 26 := by decide

/-- Layout passes in one swap: frames times the layout passes of a frame. -/
def layoutFrames (hz passes : Nat) : Nat := swapFrames hz * passes

/-- **Layout frames per swap**: zero for the crop, the whole swap for the original. -/
theorem layoutFrames_swap (hz : Nat) : layoutFrames hz 0 = 0 ∧ layoutFrames 60 1 = 13 := by
  simp [layoutFrames, swapFrames_60]


/-! ## Look (class L) -/

/-- The leaver's box width at progress `p`: the original collapses it, the crop keeps it. -/
def origLeaverW (p : Rat) : Rat := 32 * (1 - p)

def cropLeaverW (_p : Rat) : Rat := 32

/-- **Not the same look**: at half progress the leaver boxes differ, so the variant is class L and never VisSame. -/
theorem leaver_box_differs : origLeaverW (1 / 2) ≠ cropLeaverW (1 / 2) := by decide +kernel

/-- **The differing region is the leaver slot**: both leaver boxes lie in the 32 px slot, so the leaver's differing
region is at most `avatarPx * avatarPx` square CSS px. -/
theorem leaver_region (p : Rat) (h0 : 0 ≤ p) :
    origLeaverW p ≤ avatarPx ∧ cropLeaverW p = avatarPx := by
  unfold origLeaverW cropLeaverW avatarPx
  constructor <;> grind

/-- The follower shift of the original (`follower_shift`) equals the crop translate at every progress. -/
def cropTranslate (p : Rat) : Rat := 24 * p

theorem shift_eq_translate (p : Rat) : leaverAdvance 0 - leaverAdvance p = cropTranslate p := follower_shift p

/-- The device pixel a position snaps to: nearest device pixel in CSS px. -/
def snapDev (dpr x : Rat) : Rat := ((x * dpr + 1 / 2).floor : Rat) / dpr

/-- **A snapped position is within half a device pixel.** -/
theorem snap_err (dpr x : Rat) (h : 0 < dpr) :
    -(1 / 2) < (snapDev dpr x - x) * dpr ∧ (snapDev dpr x - x) * dpr ≤ 1 / 2 := by
  have h1 := Rat.floor_le (x * dpr + 1 / 2)
  have h2 := Rat.lt_floor_add_one (x * dpr + 1 / 2)
  have e : snapDev dpr x * dpr = ((x * dpr + 1 / 2).floor : Rat) := by
    unfold snapDev
    exact Rat.div_mul_cancel (Rat.ne_of_gt h)
  have h2' : x * dpr + 1 / 2 < ((x * dpr + 1 / 2).floor : Rat) + 1 := by simpa using h2
  constructor <;> grind

/-- **Followers land within one device pixel.** The original paints a follower snapped to a device pixel, the crop
paints the translated layer at most half a device pixel from the exact position; the two differ by at most one device
pixel. LayoutUnit rounding (1/64 CSS px) is not modelled. -/
theorem follower_within_one (dpr x a b : Rat) (ha : (a - x) * dpr ≤ 1 / 2 ∧ -(1 / 2) ≤ (a - x) * dpr)
    (hb : (b - x) * dpr ≤ 1 / 2 ∧ -(1 / 2) ≤ (b - x) * dpr) : (a - b) * dpr ≤ 1 ∧ -1 ≤ (a - b) * dpr := by
  have : (a - b) * dpr = (a - x) * dpr - (b - x) * dpr := by grind
  grind

/-! ## Layer budget -/

/-- Bytes of one avatar layer at `dpr`: a 32 px square, four bytes a device pixel. -/
def layerBytes (dpr : Nat) : Nat := (avatarPx * dpr) * (avatarPx * dpr) * 4

/-- Animated elements of a crop swap: leaver, three followers, entering avatar. -/
def cropLayers : Nat := shown + 1

/-- Animated elements of an original swap that get a layer: the entering avatar. -/
def origLayers : Nat := 1

theorem layer_budget : layerBytes 3 = 36864 ∧ cropLayers * layerBytes 3 = 184320 ∧
    (cropLayers - origLayers) * layerBytes 3 = 147456 := by decide

/-! ## Golden rows -/

private def jrat (q : Rat) : Lean.Json := Lean.Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

def progresses : List Rat := (List.range 9).map fun (i : Nat) => (i : Rat) / 8

def dprs : List Rat := [1, 2, 3]

def rows (_ : Unit := ()) : List String :=
  dprs.flatMap fun dpr => progresses.map fun p =>
    let x := 24 - cropTranslate p
    (Lean.Json.mkObj [("dpr", jrat dpr), ("p", jrat p), ("shiftOrig", jrat (leaverAdvance 0 - leaverAdvance p)),
      ("shiftCrop", jrat (cropTranslate p)), ("leaverOrig", jrat (origLeaverW p)), ("leaverCrop", jrat (cropLeaverW p)),
      ("snapped", jrat (snapDev dpr x)), ("devErr", jrat ((snapDev dpr x - x) * dpr))]).compress

def jsonl (_ : Unit := ()) : String := String.join ((rows ()).map (· ++ "\n"))

#guard (rows ()).length == 27

#guard jsonl () == include_str "../../../packages/contracts/golden/parts/people-carousel-crop.jsonl"

end Fw.Parts.PeopleCarouselCrop
