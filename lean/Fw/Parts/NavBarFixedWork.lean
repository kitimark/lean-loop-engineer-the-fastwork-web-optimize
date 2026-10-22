import Fw.Parts.NavBarFixed
import Fw.Engine.WebKitSimple
namespace Fw.Parts.NavBarFixedWork
open Fw.Engine Fw.Engine.WebKit Fw.Engine.WebKitSimple Fw.Parts.Nav Fw.Parts.NavClipBox Fw.Parts.NavBarFixed

inductive Arm where
  | faithful | clipBox | barFixed | logo3d
deriving Repr, DecidableEq

def Arm.rank : Arm → Nat
  | .faithful => 0 | .clipBox => 1 | .barFixed => 2 | .logo3d => 3

def Arm.has (a b : Arm) : Bool := decide (b.rank ≤ a.rank)

theorem requires_chain :
    Arm.has .barFixed .clipBox = true ∧ Arm.has .logo3d .barFixed = true ∧ Arm.has .logo3d .clipBox = true ∧
      Arm.has .clipBox .barFixed = false ∧ Arm.has .barFixed .logo3d = false := by decide

def writerOut (_ : Arm) (ms : List Rat) : List Rat := ms

theorem writer_unchanged (a : Arm) (ms : List Rat) : writerOut a ms = writerOut .faithful ms := rfl

def allocs : Option Rat → Nat → List Rat → Nat
  | _, _, [] => 0
  | prev, held, s :: rest =>
    if prev == some s then
      (if held < 2 then 1 else 0) + allocs (some s) (if held < 2 then held + 1 else held) rest
    else 1 + allocs (some s) 1 rest

theorem allocs_steady (s : Rat) (n : Nat) : allocs (some s) 2 (List.replicate n s) = 0 := by
  induction n with
  | zero => rfl
  | succ n ih => simp [List.replicate_succ, allocs, ih]

theorem allocs_cold (s : Rat) (n : Nat) : allocs none 0 (List.replicate n s) = min n 2 := by
  cases n with
  | zero => rfl
  | succ n =>
    cases n with
    | zero => simp [allocs]
    | succ n =>
      have h : allocs (some s) 1 (List.replicate (n + 1) s) = 1 + allocs (some s) 2 (List.replicate n s) := by
        simp [List.replicate_succ, allocs]
      simp [List.replicate_succ, allocs, allocs_steady]

def growing (k : Nat) : Nat → List Rat
  | 0 => []
  | n + 1 => (k : Rat) :: growing (k + 1) n

theorem allocs_growing (n k : Nat) (p : Option Rat) (held : Nat) (hp : p ≠ some (k : Rat)) :
    allocs p held (growing k n) = n := by
  induction n generalizing k p held with
  | zero => rfl
  | succ n ih =>
    have hne : ((k : Rat) == ((k + 1 : Nat) : Rat)) = false := by
      simp only [beq_eq_false_iff_ne]; intro h; have : (k : Rat) + 1 = k := by simpa using h.symm
      grind
    have h1 : (p == some (k : Rat)) = false := by simpa using hp
    have hp' : some (k : Rat) ≠ some ((k + 1 : Nat) : Rat) := by
      intro h; apply (beq_eq_false_iff_ne.mp hne); simpa using h
    simp only [growing, allocs, h1]
    simp [ih (k + 1) (some (k : Rat)) 1 hp']
    omega

theorem wk_allocs_push (n : Nat) (s : Rat) (h : 3 ≤ n) :
    allocs none 0 (List.replicate n s) = 2 ∧ allocs none 0 (growing 0 n) = n ∧ allocs none 0 (List.replicate n s) < n := by
  have a := allocs_cold s n
  have b := allocs_growing n 0 none 0 (by simp)
  refine ⟨by omega, b, by omega⟩

def resizeCount : List Rat → Nat
  | a :: b :: rest => (if a == b then 0 else 1) + resizeCount (b :: rest)
  | _ => 0

theorem resizeCount_const (ms : List Rat) (c : Rat) : resizeCount (ms.map fun _ => c) = 0 := by
  induction ms with
  | nil => rfl
  | cons m t ih =>
    cases t with
    | nil => rfl
    | cons m' t' => simp_all [resizeCount]

def pushResizePaint (draws delegates : Bool) (a : Nat) (sizes : List Rat) : Nat :=
  resizeCount sizes * resizePaint draws delegates true a

theorem bar_resizePaint_zero (v : Vp) (ms : List Rat) (a : Nat) :
    pushResizePaint true false a (ms.map (barW v)) = 0 := by
  have : ms.map (barW v) = ms.map fun _ => unionW v := rfl
  simp [pushResizePaint, this, resizeCount_const]

theorem bar_orig_resizes (a : Nat) (x y : Rat) (h : x ≠ y) :
    pushResizePaint true false a [x, y] = a := by
  simp [pushResizePaint, resizeCount, resizePaint, usesBacking, h]

def logoLeftFrame : FrameIn WkProp := ⟨0, 0, 0, 0, [⟨1, .insetAbs, .none⟩], 0⟩

def logoLayer (p : Policy) : LayerState := if composites p .transform3DFlat then .own else .layer

def logo3dFrame (p : Policy) : FrameIn WkProp := ⟨0, 0, 0, 0, [⟨1, .transform, logoLayer p⟩], 0⟩

def layoutUnits (f : FrameIn WkProp) : Nat := stageUnits webkit f .layout

theorem logo3d_layout_normal : layoutUnits logoLeftFrame = 1 ∧ layoutUnits (logo3dFrame .normal) = 0 := by
  decide +kernel

theorem logo3d_layout_conservative : layoutUnits (logo3dFrame .conservative) = 1 := by
  decide +kernel

theorem logo_translate_layout : layoutUnits ⟨0, 0, 0, 0, [⟨1, .transform, .layer⟩], 0⟩ = 1 := by
  decide +kernel

def barComposited (p : Policy) : Bool := composites p .willChange

theorem bar_normal_only : barComposited .normal = true ∧ barComposited .conservative = false := by decide

theorem conservative_not_simple (b : Box) (h : b.barComposited = barComposited .conservative) : drawsContent b = true :=
  bar_premise_needed b (h.trans bar_normal_only.2)

def barInsetFrame : FrameIn WkProp := ⟨0, 0, 0, 0, [⟨1, .insetAbs, .layer⟩], 0⟩

def barTranslateFrame (p : Policy) : FrameIn WkProp :=
  ⟨0, 0, 0, 0, [⟨1, .transform, if barComposited p then .own else .layer⟩], 0⟩

theorem bar_layout_normal : layoutUnits barInsetFrame = 1 ∧ layoutUnits (barTranslateFrame .normal) = 0 := by
  decide +kernel

theorem bar_layout_conservative : layoutUnits (barTranslateFrame .conservative) = 1 := by
  decide +kernel

def area (w h : Rat) : Rat := w * h

theorem area_trade (v : Vp) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) (hv : pillH v ≤ panelH v) (hw0 : 0 ≤ pillW v) :
    area (navWidth v false m) (navHeight v m) ≤ area (unionW v) (unionH v) := by
  have hw := panel_ge_pill v
  have hph : 0 ≤ pillH v := by unfold pillH; cases phone v.w <;> simp <;> grind
  have a := Rat.mul_nonneg (show 0 ≤ panelW v - pillW v by grind) (show 0 ≤ 1 - m by grind)
  have a2 := Rat.mul_nonneg (show 0 ≤ panelW v - pillW v by grind) h0
  have b := Rat.mul_nonneg (show 0 ≤ panelH v - pillH v by grind) (show 0 ≤ 1 - m by grind)
  have b2 := Rat.mul_nonneg (show 0 ≤ panelH v - pillH v by grind) h0
  have wle : navWidth v false m ≤ unionW v := by unfold navWidth unionW expand; grind
  have wpos : 0 ≤ navWidth v false m := by unfold navWidth expand; grind
  have hle : navHeight v m ≤ unionH v := by
    unfold navHeight unionH; cases phone v.w <;> simp <;> grind
  have hpos : 0 ≤ navHeight v m := by unfold navHeight; grind
  unfold area
  have e1 := Rat.mul_le_mul_of_nonneg_left hle wpos
  have e2 := Rat.mul_le_mul_of_nonneg_left wle (show 0 ≤ unionH v by grind)
  grind

structure Row where
  name : String
  kpx : Nat
deriving Repr, DecidableEq

def added (a : Arm) (barKpx logoKpx : Nat) : List Row :=
  (if a.has .clipBox then [⟨"nav mask", 0⟩] else []) ++ (if a.has .barFixed then [⟨"nav bar", barKpx⟩] else []) ++
    (if a.has .logo3d then [⟨"logo", logoKpx⟩] else [])

def addedKpx (a : Arm) (barKpx logoKpx : Nat) : Nat := ((added a barKpx logoKpx).map Row.kpx).sum

theorem layer_budget (barKpx logoKpx : Nat) :
    ((added .clipBox barKpx logoKpx).length = 1 ∧ addedKpx .clipBox barKpx logoKpx = 0) ∧
    ((added .barFixed barKpx logoKpx).length = 2 ∧ addedKpx .barFixed barKpx logoKpx = barKpx) ∧
    ((added .logo3d barKpx logoKpx).length = 3 ∧ addedKpx .logo3d barKpx logoKpx = barKpx + logoKpx) := by
  simp [added, addedKpx, Arm.has, Arm.rank]

theorem nav_backing (a : Nat) :
    residentKpx (drawsContent navOrig) false a = a ∧ residentKpx (drawsContent navClip) false a = 0 :=
  ⟨(navClip_vs_orig false a).2.2.1, (navClip_vs_orig false a).1⟩

end Fw.Parts.NavBarFixedWork
