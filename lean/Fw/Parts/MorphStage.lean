import Fw.Parts.MorphTween
import Fw.Parts.MorphTweenOpt
namespace Fw.Parts.MorphStage
open Fw.Parts.MorphTween
open Fw.Parts.MorphTweenOpt (AttrReader Cmp attrReaders band band_ne pointerNone_eq)

def flagId : String := "morph.stage"
def attr : String := "data-fw-stage"
def onV : String := "on"
def faithfulV : String := "faithful"

def jackOn (v : String) : Bool := v != onV

theorem jack_off_iff (v : String) : jackOn v = false ↔ v = onV := by
  simp [jackOn]

def jackAnchors : List (String × String) :=
  [("morph.mount", "morph-mount"), ("morph.tween", "morph-tween")]

def anchorMounted (v anchor : String) : Bool :=
  !(jackAnchors.any fun pa => pa.2 == anchor) || jackOn v

theorem stage_unmounts_anchors :
    anchorMounted onV "morph-mount" = false ∧ anchorMounted onV "morph-tween" = false := by
  decide +kernel

theorem stage_keeps_others (v anchor : String) (h : (jackAnchors.any fun pa => pa.2 == anchor) = false) :
    anchorMounted v anchor = true := by
  simp [anchorMounted, h]

theorem faithful_mounts_anchors :
    anchorMounted faithfulV "morph-mount" = true ∧ anchorMounted faithfulV "morph-tween" = true := by
  decide +kernel

theorem divmul (x t : Rat) (ht : 0 < t) : x / t * t = x := by grind

theorem lt_div_iff' (x θ t : Rat) (ht : 0 < t) : θ < x / t ↔ θ * t < x := by
  constructor
  · intro h
    have := Rat.mul_lt_mul_of_pos_right h ht
    rw [divmul x t ht] at this; exact this
  · intro h
    refine Classical.byContradiction fun hc => ?_
    have h2 : x / t ≤ θ := by grind
    have := Rat.mul_le_mul_of_nonneg_right h2 (show 0 ≤ t by grind)
    rw [divmul x t ht] at this; grind

theorem div_lt_iff' (x θ t : Rat) (ht : 0 < t) : x / t < θ ↔ x < θ * t := by
  constructor
  · intro h
    have := Rat.mul_lt_mul_of_pos_right h ht
    rw [divmul x t ht] at this; exact this
  · intro h
    refine Classical.byContradiction fun hc => ?_
    have h2 : θ ≤ x / t := by grind
    have := Rat.mul_le_mul_of_nonneg_right h2 (show 0 ≤ t by grind)
    rw [divmul x t ht] at this; grind

theorem div_le_iff' (x θ t : Rat) (ht : 0 < t) : x / t ≤ θ ↔ x ≤ θ * t := by
  constructor
  · intro h
    have := Rat.mul_le_mul_of_nonneg_right h (show 0 ≤ t by grind)
    rw [divmul x t ht] at this; exact this
  · intro h
    refine Classical.byContradiction fun hc => ?_
    have h2 : θ < x / t := by grind
    have := Rat.mul_lt_mul_of_pos_right h2 ht
    rw [divmul x t ht] at this; grind

theorem le_div_iff' (x θ t : Rat) (ht : 0 < t) : θ ≤ x / t ↔ θ * t ≤ x := by
  constructor
  · intro h
    have := Rat.mul_le_mul_of_nonneg_right h (show 0 ≤ t by grind)
    rw [divmul x t ht] at this; exact this
  · intro h
    refine Classical.byContradiction fun hc => ?_
    have h2 : x / t < θ := by grind
    have := Rat.mul_lt_mul_of_pos_right h2 ht
    rw [divmul x t ht] at this; grind

theorem div_nonneg' (x t : Rat) (hx : 0 ≤ x) (ht : 0 < t) : 0 ≤ x / t := by
  have := (le_div_iff' x 0 t ht).2 (by grind)
  exact this

theorem div_mono' (x y t : Rat) (ht : 0 < t) (h : x ≤ y) : x / t ≤ y / t := by
  have := (le_div_iff' y (x / t) t ht).2 (by rw [divmul x t ht]; exact h)
  exact this

structure Win where
  vw : Rat
  vh : Rat
  narrow : Bool
deriving Repr, DecidableEq

def narrowOf (vw : Rat) : Bool := decide (vw ≤ 640)

def pillW (w : Win) : Rat := min 984 (w.vw - if w.narrow then 32 else 48)
def pillH (w : Win) : Rat := if w.narrow then 52 else 64
def panelW (w : Win) : Rat := if w.narrow then w.vw - 24 else min 1398 (w.vw - 40)
def panelH (w : Win) : Rat := if w.narrow then w.vh - 24 else min 820 (w.vh - 40)

def spanW (w : Win) : Rat := panelW w - pillW w
def spanH (w : Win) : Rat := panelH w - pillH w
def blurSpan : Rat := 20

def trackT (w : Win) : Rat := max (max (spanH w) (spanW w)) blurSpan

theorem trackT_ge (w : Win) : spanH w ≤ trackT w ∧ spanW w ≤ trackT w ∧ blurSpan ≤ trackT w := by
  unfold trackT; grind

theorem trackT_least (w : Win) (t : Rat) (hh : spanH w ≤ t) (hw : spanW w ≤ t) (hb : blurSpan ≤ t) : trackT w ≤ t := by
  unfold trackT; grind

theorem trackT_pos (w : Win) : 0 < trackT w := by
  have := (trackT_ge w).2.2
  unfold blurSpan at this; grind

theorem trackT_mem (w : Win) : trackT w = spanH w ∨ trackT w = spanW w ∨ trackT w = blurSpan := by
  unfold trackT; grind

theorem slope_le_one (w : Win) (s p q : Rat) (hst : s ≤ trackT w) (hpq : p ≤ q) :
    s * ((q - p) / trackT w) ≤ q - p := by
  have ht := trackT_pos w
  have h1 : s * ((q - p) / trackT w) ≤ trackT w * ((q - p) / trackT w) := by
    apply Rat.mul_le_mul_of_nonneg_right hst
    exact div_nonneg' _ _ (by grind) (by grind)
  have h2 : trackT w * ((q - p) / trackT w) = q - p := by
    rw [Rat.mul_comm, Rat.div_mul_cancel (by grind)]
  grind

def trackCss (narrow : Bool) : String :=
  if narrow then "max(100vh - 76px,100vw - 24px - min(984px,100vw - 32px),20px)"
  else "max(min(820px,100vh - 40px) - 64px,min(1398px,100vw - 40px) - min(984px,100vw - 48px),20px)"

def rangeCss : String := "calc(100% - var(--stage-t)) 100%"

def progress (y maxY t : Rat) : Rat := clamp01 ((y - (maxY - t)) / t)

theorem progress_below (y maxY t : Rat) (ht : 0 < t) (h : y ≤ maxY - t) : progress y maxY t = 0 := by
  have : (y - (maxY - t)) / t ≤ 0 := (div_le_iff' _ _ t ht).2 (by grind)
  unfold progress clamp01; grind

theorem progress_above (y maxY t : Rat) (ht : 0 < t) (h : maxY ≤ y) : progress y maxY t = 1 := by
  have : 1 ≤ (y - (maxY - t)) / t := by
    exact (le_div_iff' _ _ t ht).2 (by grind)
  unfold progress clamp01; grind

theorem progress_inside (y maxY t : Rat) (ht : 0 < t) (h1 : maxY - t ≤ y) (h2 : y ≤ maxY) :
    progress y maxY t = (y - (maxY - t)) / t := by
  have h0 : 0 ≤ (y - (maxY - t)) / t := div_nonneg' _ _ (by grind) (by grind)
  have h1' : (y - (maxY - t)) / t ≤ 1 := by
    exact (div_le_iff' _ _ t ht).2 (by grind)
  unfold progress clamp01; grind

theorem progress_mem (y maxY t : Rat) : 0 ≤ progress y maxY t ∧ progress y maxY t ≤ 1 := clamp01_mem _

theorem progress_mono (a b maxY t : Rat) (ht : 0 < t) (hab : a ≤ b) : progress a maxY t ≤ progress b maxY t := by
  have : (a - (maxY - t)) / t ≤ (b - (maxY - t)) / t := div_mono' _ _ t ht (by grind)
  unfold progress clamp01; grind

theorem range_len (maxY t : Rat) : maxY - (maxY - t) = t := by grind

def maxY (platformBottom t vh : Rat) : Rat := platformBottom + t - vh

theorem range_start_eq (pb t vh : Rat) : maxY pb t vh - t = pb - vh := by unfold maxY; grind

def sceneBottom (pb t vh y : Rat) : Rat := min (max (pb - y) vh) (pb + t - y)

theorem scene_natural_before (pb t vh y : Rat) (ht : 0 ≤ t) (h : y ≤ pb - vh) : sceneBottom pb t vh y = pb - y := by
  unfold sceneBottom; grind

theorem scene_held (pb t vh y : Rat) (h1 : pb - vh ≤ y) (h2 : y ≤ maxY pb t vh) : sceneBottom pb t vh y = vh := by
  unfold sceneBottom maxY at *; grind

theorem armed_from_range_start (pb t vh h : Rat) (hh : vh * (9 / 20) ≤ h) (y : Rat) (hy : maxY pb t vh - t ≤ y) :
    armed h (sceneBottom pb t vh y) vh = true := by
  have hs := range_start_eq pb t vh
  unfold armed bottomSlack sceneBottom fillRatio
  simp only [Bool.and_eq_true, decide_eq_true_eq]
  constructor
  · grind
  · grind

def lerpSeg (o0 v0 o1 v1 p : Rat) : Rat := v0 + (v1 - v0) * ((p - o0) / (o1 - o0))

def morphKf (p : Rat) : Rat := lerpSeg 0 0 1 1 p

def fadeKf (p : Rat) : Rat := if p ≤ fadeEnd then lerpSeg 0 1 fadeEnd 0 p else 0

theorem morphKf_eq (p : Rat) : morphKf p = p := by unfold morphKf lerpSeg; grind

theorem fadeKf_eq_fade (p : Rat) : fadeKf p = fade p := by
  have hk : p / fadeEnd = p * (20 / 11) := by unfold fadeEnd; grind
  unfold fadeKf fade lerpSeg
  rw [hk]
  by_cases hp : p ≤ fadeEnd
  · have : p * (20 / 11) ≤ 1 := by unfold fadeEnd at hp; grind
    have h2 : (p - 0) / (fadeEnd - 0) = p * (20 / 11) := by unfold fadeEnd; grind
    simp only [hp, ite_true, h2]
    grind
  · have : 1 ≤ p * (20 / 11) := by unfold fadeEnd at hp; grind
    simp only [hp, ite_false]
    grind

theorem keyframes_start : morphKf 0 = (rest.value) ∧ fadeKf 0 = fade rest.value := by
  refine ⟨?_, ?_⟩
  · rw [morphKf_eq]; rfl
  · rw [fadeKf_eq_fade 0]; rfl

theorem keyframes_end (e : Rat) (he : 680 ≤ e) :
    morphKf 1 = (tween 0 1 e).value ∧ fadeKf 1 = fade (tween 0 1 e).value := by
  rw [tween_end 0 1 e he]
  refine ⟨morphKf_eq 1, fadeKf_eq_fade 1⟩

theorem keyframes_begin (e : Rat) (he : e ≤ 0) :
    morphKf 0 = (tween 0 1 e).value ∧ fadeKf 0 = fade (tween 0 1 e).value := by
  rw [tween_start 0 1 e he]
  refine ⟨morphKf_eq 0, fadeKf_eq_fade 0⟩

def key (m : Rat) : List Bool := pointerNone m :: band m

def pxTest (r : AttrReader) (y maxY t : Rat) : Bool :=
  match r.cmp with
  | .gt => decide (maxY - t + r.θ * t < y)
  | .lt => decide (y < maxY - t + r.θ * t)

def pxPointer (y maxY t : Rat) : Bool := decide (maxY - t + (209 / 400) * t < y)

def pxKey (y maxY t : Rat) : List Bool := pxPointer y maxY t :: attrReaders.map (pxTest · y maxY t)

theorem clamp_gt_iff (y s t θ : Rat) (ht : 0 < t) (h0 : 0 < θ) (h1 : θ < 1) :
    decide (θ < clamp01 ((y - s) / t)) = decide (s + θ * t < y) := by
  have e1 : θ < clamp01 ((y - s) / t) ↔ θ < (y - s) / t := by unfold clamp01; grind
  have e2 := lt_div_iff' (y - s) θ t ht
  have e3 : θ < clamp01 ((y - s) / t) ↔ s + θ * t < y := by
    rw [e1, e2]; constructor <;> intro h <;> grind
  exact decide_eq_decide.2 e3

theorem clamp_lt_iff (y s t θ : Rat) (ht : 0 < t) (h0 : 0 < θ) (h1 : θ < 1) :
    decide (clamp01 ((y - s) / t) < θ) = decide (y < s + θ * t) := by
  have e1 : clamp01 ((y - s) / t) < θ ↔ (y - s) / t < θ := by unfold clamp01; grind
  have e2 := div_lt_iff' (y - s) θ t ht
  have e3 : clamp01 ((y - s) / t) < θ ↔ y < s + θ * t := by
    rw [e1, e2]; constructor <;> intro h <;> grind
  exact decide_eq_decide.2 e3

def Valid (r : AttrReader) : Prop := 0 < r.θ ∧ r.θ < 1

theorem attrReaders_valid : ∀ r ∈ attrReaders, Valid r := by
  intro r hr
  simp only [attrReaders, List.mem_cons, List.not_mem_nil, or_false] at hr
  rcases hr with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> unfold Valid <;> constructor <;> grind

theorem reader_cut (r : AttrReader) (hv : Valid r) (y maxY t : Rat) (ht : 0 < t) :
    r.test (progress y maxY t) = pxTest r y maxY t := by
  unfold AttrReader.test pxTest progress
  cases hc : r.cmp
  · have := clamp_gt_iff y (maxY - t) t r.θ ht hv.1 hv.2
    simpa [hc] using this
  · have := clamp_lt_iff y (maxY - t) t r.θ ht hv.1 hv.2
    simpa [hc] using this

theorem pointer_cut (y maxY t : Rat) (ht : 0 < t) :
    pointerNone (progress y maxY t) = pxPointer y maxY t := by
  rw [pointerNone_eq]
  unfold pxPointer progress
  exact clamp_gt_iff y (maxY - t) t (209 / 400) ht (by grind) (by grind)

theorem key_eq_tween (y maxY t : Rat) (ht : 0 < t) : pxKey y maxY t = key (progress y maxY t) := by
  unfold pxKey key band
  rw [pointer_cut y maxY t ht]
  congr 1
  apply List.map_congr_left
  intro r hr
  exact (reader_cut r (attrReaders_valid r hr) y maxY t ht).symm

theorem active_cut (y maxY t : Rat) (ht : 0 < t) :
    active (progress y maxY t) (progress y maxY t) = decide (maxY - t + (1 / 1000) * t < y) := by
  unfold active activeCut
  have := clamp_gt_iff y (maxY - t) t (1 / 1000) ht (by grind) (by grind)
  unfold progress
  simpa using this

def writes (last : List Bool) (m : Rat) : Bool := decide (key m ≠ last)

theorem no_write_same_key (u v : Rat) (h : key u = key v) : writes (key u) v = false := by
  simp [writes, h]

theorem write_at_crossing (u v : Rat) (h : writes (key u) v = true) :
    pointerNone u ≠ pointerNone v ∨ ∃ r ∈ attrReaders, r.test u ≠ r.test v := by
  have h' : key v ≠ key u := of_decide_eq_true h
  by_cases hp : pointerNone u = pointerNone v
  · right
    apply band_ne
    intro hb
    exact h' (by simp only [key, hp, hb])
  · left; exact hp

theorem no_write_below_range (y y' maxY t : Rat) (ht : 0 < t) (h : y ≤ maxY - t) (h' : y' ≤ maxY - t) :
    writes (key (progress y maxY t)) (progress y' maxY t) = false := by
  rw [progress_below y maxY t ht h, progress_below y' maxY t ht h']
  simp [writes]

theorem no_write_above_range (y y' maxY t : Rat) (ht : 0 < t) (h : maxY ≤ y) (h' : maxY ≤ y') :
    writes (key (progress y maxY t)) (progress y' maxY t) = false := by
  rw [progress_above y maxY t ht h, progress_above y' maxY t ht h']
  simp [writes]

#guard key 0 == [false, false, false, false, false, false, false, true, true, false]
#guard key 1 == [true, true, true, true, true, true, true, false, false, true]
#guard active 0 0 == false && active 1 1 == true

theorem stage_start_eq_tween (y maxY t e : Rat) (ht : 0 < t) (hy : y ≤ maxY - t) (he : e ≤ 0) :
    key (progress y maxY t) = key (tween 0 1 e).value := by
  rw [progress_below y maxY t ht hy, tween_start 0 1 e he]

theorem stage_end_eq_tween (y maxY t e : Rat) (ht : 0 < t) (hy : maxY ≤ y) (he : 680 ≤ e) :
    key (progress y maxY t) = key (tween 0 1 e).value := by
  rw [progress_above y maxY t ht hy, tween_end 0 1 e he]

inductive Op where
  | observe (kind : String)
  | listen (type : String) (passive : Bool)
  | setAttr (el attr : String)
  | setStyle (el prop : String)
  | scrollTo
deriving Repr, DecidableEq

def ops : List Op :=
  [.observe "IntersectionObserver", .observe "ResizeObserver", .listen "scroll" true, .listen "resize" true,
    .setAttr "nav" "data-fw-morph", .setStyle "platform" "pointer-events", .setStyle "platform" "--stage-h"]

theorem no_scrollTo : ∀ o ∈ ops, o ≠ Op.scrollTo := by
  intro o ho
  simp only [ops, List.mem_cons, List.not_mem_nil, or_false] at ho
  rcases ho with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> simp

theorem no_nonpassive : ∀ o ∈ ops, ∀ ty, o ≠ Op.listen ty false := by
  intro o ho ty
  simp only [ops, List.mem_cons, List.not_mem_nil, or_false] at ho
  rcases ho with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> simp

end Fw.Parts.MorphStage
