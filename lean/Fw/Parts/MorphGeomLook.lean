import Fw.Parts.MorphGeomRect
import Fw.Parts.MorphGeomAnim
namespace Fw.Parts.MorphGeom
open Fw.Parts.Nav

def lookFn (as : List Anim) (el : String) (p : AnimProp) (key : Nat × Nat) (idx : Nat) : Option (Rat → Rat) :=
  (as.find? fun a => a.el == el && a.prop == p && a.key == key).bind fun a => a.fns[idx]?

theorem find_map_none {α} (l : List α) (f : α → Anim) (p : Anim → Bool) (h : ∀ x, p (f x) = false) :
    (l.map f).find? p = none := by
  simp [List.find?_eq_none, h]

theorem find_false {α} (l : List α) : l.find? (fun _ => false) = none := by simp [List.find?_eq_none]

theorem look_bar (v : Vp) (c : Ctx) : lookFn (anims v c) "bar" .translate (0, 0) 1 = some (y0 v) := by
  unfold lookFn anims
  by_cases h1 : padRuns c.eng = true <;> by_cases h2 : v.w ≤ 720 <;> simp [anim, h1, h2, List.find?_append, List.find?_map, find_map_none, find_false, Function.comp_def]
theorem look_actions (v : Vp) (c : Ctx) :
    lookFn (anims v c) "actions" .translate (0, 0) 0 = some (fun x => -x0 v x) := by
  unfold lookFn anims
  by_cases h1 : padRuns c.eng = true <;> by_cases h2 : v.w ≤ 720 <;> simp [anim, h1, h2, List.find?_append, List.find?_map, find_map_none, find_false, Function.comp_def]
theorem look_centre (v : Vp) (c : Ctx) : lookFn (anims v c) "centre" .translate (0, 0) 1 = some (dP v) := by
  unfold lookFn anims
  by_cases h1 : padRuns c.eng = true <;> by_cases h2 : v.w ≤ 720 <;> simp [anim, h1, h2, List.find?_append, List.find?_map, find_map_none, find_false, Function.comp_def]
theorem look_footer_x (v : Vp) (c : Ctx) : lookFn (anims v c) "footer" .translate (0, 0) 0 = some (x0 v) := by
  unfold lookFn anims
  by_cases h1 : padRuns c.eng = true <;> by_cases h2 : v.w ≤ 720 <;> simp [anim, h1, h2, List.find?_append, List.find?_map, find_map_none, find_false, Function.comp_def]
theorem look_footer_y (v : Vp) (c : Ctx) :
    lookFn (anims v c) "footer" .translate (0, 0) 1 = some (fun x => y0 v x + ht v x - hp v) := by
  unfold lookFn anims
  by_cases h1 : padRuns c.eng = true <;> by_cases h2 : v.w ≤ 720 <;> simp [anim, h1, h2, List.find?_append, List.find?_map, find_map_none, find_false, Function.comp_def]
theorem look_footerGrad (v : Vp) (c : Ctx) :
    lookFn (anims v c) "footerGrad" .scale (0, 0) 0 = some (fun x => wd v x / wp v) := by
  unfold lookFn anims
  by_cases h1 : padRuns c.eng = true <;> by_cases h2 : v.w ≤ 720 <;> simp [anim, h1, h2, List.find?_append, List.find?_map, find_map_none, find_false, Function.comp_def]
theorem look_footerEnd (v : Vp) (c : Ctx) :
    lookFn (anims v c) "footerEnd" .translate (0, 0) 0 = some (fun x => -2 * x0 v x) := by
  unfold lookFn anims
  by_cases h1 : padRuns c.eng = true <;> by_cases h2 : v.w ≤ 720 <;> simp [anim, h1, h2, List.find?_append, List.find?_map, find_map_none, find_false, Function.comp_def]
theorem look_bc_x (v : Vp) (c : Ctx) :
    lookFn (anims v c) "backdropClip" .translate (0, 0) 0 = some (fun x => 53 / 50 * x0 v x) := by
  unfold lookFn anims
  by_cases h1 : padRuns c.eng = true <;> by_cases h2 : v.w ≤ 720 <;> simp [anim, h1, h2, List.find?_append, List.find?_map, find_map_none, find_false, Function.comp_def]
theorem look_bc_y (v : Vp) (c : Ctx) : lookFn (anims v c) "backdropClip" .translate (0, 0) 1 = some (y0 v) := by
  unfold lookFn anims
  by_cases h1 : padRuns c.eng = true <;> by_cases h2 : v.w ≤ 720 <;> simp [anim, h1, h2, List.find?_append, List.find?_map, find_map_none, find_false, Function.comp_def]
theorem look_Kb (v : Vp) (c : Ctx) :
    lookFn (anims v c) "Kb" .translate (0, 0) 0 = some (fun x => -(106 / 50) * x0 v x) := by
  unfold lookFn anims
  by_cases h1 : padRuns c.eng = true <;> by_cases h2 : v.w ≤ 720 <;> simp [anim, h1, h2, List.find?_append, List.find?_map, find_map_none, find_false, Function.comp_def]
theorem look_Kb_y (v : Vp) (c : Ctx) : lookFn (anims v c) "Kb" .translate (0, 0) 1 = some (fun x => ht v x - hp v) := by
  unfold lookFn anims
  by_cases h1 : padRuns c.eng = true <;> by_cases h2 : v.w ≤ 720 <;> simp [anim, h1, h2, List.find?_append, List.find?_map, find_map_none, find_false, Function.comp_def]

theorem look_veil_x (v : Vp) (c : Ctx) : lookFn (anims v c) "veil" .transformList (0, 0) 0 = some (x0 v) := by
  unfold lookFn anims
  by_cases h1 : padRuns c.eng = true <;> by_cases h2 : v.w ≤ 720 <;> simp [anim, h1, h2, List.find?_append, List.find?_map, find_map_none, find_false, Function.comp_def]
theorem look_veil_y (v : Vp) (c : Ctx) : lookFn (anims v c) "veil" .transformList (0, 0) 1 = some (y0 v) := by
  unfold lookFn anims
  by_cases h1 : padRuns c.eng = true <;> by_cases h2 : v.w ≤ 720 <;> simp [anim, h1, h2, List.find?_append, List.find?_map, find_map_none, find_false, Function.comp_def]
theorem look_veil_sx (v : Vp) (c : Ctx) :
    lookFn (anims v c) "veil" .transformList (0, 0) 2 = some (fun x => wd v x / wp v) := by
  unfold lookFn anims
  by_cases h1 : padRuns c.eng = true <;> by_cases h2 : v.w ≤ 720 <;> simp [anim, h1, h2, List.find?_append, List.find?_map, find_map_none, find_false, Function.comp_def]
theorem look_veil_sy (v : Vp) (c : Ctx) :
    lookFn (anims v c) "veil" .transformList (0, 0) 3 = some (fun x => ht v x / hp v) := by
  unfold lookFn anims
  by_cases h1 : padRuns c.eng = true <;> by_cases h2 : v.w ≤ 720 <;> simp [anim, h1, h2, List.find?_append, List.find?_map, find_map_none, find_false, Function.comp_def]

theorem veil_rect_base (v : Vp) (hv : Valid v) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    composed v m .veil = faithful v m .veil := rect_eq v hv m h0 h1 .veil

theorem veil_no_opacity (v : Vp) (c : Ctx) : ∀ a ∈ anims v c, a.el = "veil" → a.prop = .transformList := by
  intro a ha hel
  unfold anims at ha
  split at ha <;> split at ha <;> simp only [List.mem_append, List.mem_map, List.mem_cons, List.not_mem_nil, or_false] at ha <;>
    grind (splits := 400) [anim]

theorem look_column (v : Vp) (c : Ctx) (i : Nat) (hi : i < (nCols v).floor.toNat) :
    ∃ a ∈ anims v c, a.el = "column" ∧ a.key = (i, 0) ∧ a.prop = .translate ∧ a.fns[0]? = some (colTx v i) := by
  refine ⟨anim "column" .translate .unit [colTx v i, fun _ => 0] (i, 0), ?_, rfl, rfl, rfl, rfl⟩
  have hw : anim "column" .translate .unit [colTx v i, fun _ => 0] (i, 0) ∈
      (List.range (nCols v).floor.toNat).map fun i => anim "column" .translate .unit [colTx v i, fun _ => 0] (i, 0) :=
    List.mem_map.mpr ⟨i, List.mem_range.mpr hi, rfl⟩
  unfold anims
  split <;> split <;> simp only [List.mem_append] <;> grind

theorem look_image (v : Vp) (c : Ctx) (i j : Nat) (p : Pic) (hm : ((i, j), p) ∈ imgRows c) :
    ∃ a ∈ anims v c, a.el = "image" ∧ a.key = (i, j) ∧ a.prop = .transformList ∧ a.ks = .kink (qImg v p) ∧
      a.fns[0]? = some (imgTx v) ∧ a.fns[1]? = some (fun _ => 0) ∧ a.fns[2]? = some (uImg v p) ∧
      a.fns[3]? = some (uImg v p) := by
  refine ⟨anim "image" .transformList (.kink (qImg v p)) [imgTx v, fun _ => 0, uImg v p, uImg v p] (i, j), ?_,
    rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
  have hw : anim "image" .transformList (.kink (qImg v p)) [imgTx v, fun _ => 0, uImg v p, uImg v p] (i, j) ∈
      (imgRows c).map fun ((i, j), p) =>
        anim "image" .transformList (.kink (qImg v p)) [imgTx v, fun _ => 0, uImg v p, uImg v p] (i, j) :=
    List.mem_map.mpr ⟨((i, j), p), hm, rfl⟩
  unfold anims
  split <;> split <;> simp only [List.mem_append] <;> grind

theorem look_Kc (v : Vp) (c : Ctx) (i : Nat) (hi : i ∈ List.range (nCols v).floor.toNat) :
    ∃ a ∈ anims v c, a.el = "Kc" ∧ a.key = (i, 0) ∧ a.prop = .translate ∧ a.fns[0]? = some (kcTx v) := by
  refine ⟨anim "Kc" .translate .unit [kcTx v, fun _ => 0] (i, 0), ?_, rfl, rfl, rfl, rfl⟩
  have hw : anim "Kc" .translate .unit [kcTx v, fun _ => 0] (i, 0) ∈
      (List.range (nCols v).floor.toNat).map fun i => anim "Kc" .translate .unit [kcTx v, fun _ => 0] (i, 0) :=
    List.mem_map.mpr ⟨i, hi, rfl⟩
  unfold anims
  split <;> split <;> simp only [List.mem_append] <;> grind

theorem look_Uc (v : Vp) (c : Ctx) (i : Nat) (hi : i ∈ List.range (nCols v).floor.toNat) :
    ∃ a ∈ anims v c, a.el = "Uc" ∧ a.key = (i, 0) ∧ a.prop = .translate ∧ a.fns[0]? = some (fun x => -kcTx v x) := by
  refine ⟨anim "Uc" .translate .unit [fun x => -kcTx v x, fun _ => 0] (i, 0), ?_, rfl, rfl, rfl, rfl⟩
  have hw : anim "Uc" .translate .unit [fun x => -kcTx v x, fun _ => 0] (i, 0) ∈
      (List.range (nCols v).floor.toNat).map fun i => anim "Uc" .translate .unit [fun x => -kcTx v x, fun _ => 0] (i, 0) :=
    List.mem_map.mpr ⟨i, hi, rfl⟩
  unfold anims
  split <;> split <;> simp only [List.mem_append] <;> grind

inductive GapRule where
  | px (n : Rat)
  | inherit

def GapRule.val (r : GapRule) (parent : Rat) : Rat :=
  match r with
  | .px n => n
  | .inherit => parent

def backdropGap (v : Vp) : Rat := if v.w ≤ 640 then 8 else 12

theorem backdropGap_eq (v : Vp) : backdropGap v = colGap v := by
  unfold backdropGap colGap phone
  by_cases h : v.w ≤ 640 <;> simp [h]

def flipRowGap : GapRule := .inherit

def flipGap (v : Vp) : Rat := flipRowGap.val (flipRowGap.val (backdropGap v))

def rowLeft (w g : Rat) (i : Nat) : Rat := (i : Rat) * (w + g)

def stackLeft (_w _g : Rat) (_i : Nat) : Rat := 0

theorem flipGap_eq (v : Vp) : flipGap v = colGap v := by
  unfold flipGap flipRowGap GapRule.val
  exact backdropGap_eq v

theorem flip_column_left (v : Vp) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) (i : Nat) :
    rowLeft (cw v 1) (flipGap v) i + ev (colTx v i) m = (i : Rat) * (cw v m + colGap v) := by
  have et := ev_eq _ (aff_colTx v i) m h0 h1
  rw [et, flipGap_eq]
  unfold rowLeft colTx
  grind

theorem flip_columns_ordered (v : Vp) (hv : Valid v) (i : Nat) :
    rowLeft (cw v 1) (flipGap v) i < rowLeft (cw v 1) (flipGap v) (i + 1) := by
  have hc := cw1_pos v hv
  rw [flipGap_eq]
  unfold rowLeft colGap
  have : (0 : Rat) ≤ (if phone v.w = true then 8 else 12) := by split <;> decide
  push_cast
  grind

theorem stack_columns_collide (v : Vp) (hv : Valid v) (i : Nat) (hi : 1 ≤ i) :
    stackLeft (cw v 1) (flipGap v) i + ev (colTx v i) 1 ≠ (i : Rat) * (cw v 1 + colGap v) := by
  have hc := cw1_pos v hv
  have et := ev_eq _ (aff_colTx v i) 1 (by decide) (by decide)
  have h0 : (0 : Rat) ≤ colGap v := by unfold colGap; split <;> decide
  have : (1 : Rat) ≤ i := by exact_mod_cast hi
  have hp : 0 < (i : Rat) * (cw v 1 + colGap v) := Rat.mul_pos (by grind) (by grind)
  unfold stackLeft colTx at *
  rw [et]
  grind

def earnTyFlip (base m : Rat) : Rat := base + Track.eval (mk earnShift earnKnots) m

theorem earn_flip_fixed (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) : earnTyFlip 0 m = earnShift m := by
  unfold earnTyFlip
  rw [earnShift_pw m h0 h1]
  grind

theorem earn_flip_old_off : earnTyFlip (earnShift 1) 1 - earnShift 1 = -8 := by
  have h := earnShift_pw 1 (by decide) (by decide)
  unfold earnTyFlip
  rw [h]
  unfold earnShift earnOut Fw.Parts.MorphTween.clamp01 darkCut
  decide +kernel

def actionsTopBase (barH h : Rat) : Rat := barH / 2 - h / 2

def actionsTopOld (barH _h : Rat) : Rat := barH / 2 - 24

def actionsTopFix (barH h : Rat) : Rat := 0 + (barH - h) / 2

def btnH (v : Vp) : Rat := if phone v.w then 36 else 48

theorem actions_fix_eq (barH h : Rat) : actionsTopFix barH h = actionsTopBase barH h := by
  unfold actionsTopFix actionsTopBase; grind

theorem actions_old_phone (v : Vp) (barH : Rat) (hp : phone v.w = true) :
    actionsTopOld barH (btnH v) - actionsTopBase barH (btnH v) = -6 := by
  unfold actionsTopOld actionsTopBase btnH; simp [hp]; grind

theorem actions_old_desktop (v : Vp) (barH : Rat) (hp : phone v.w = false) :
    actionsTopOld barH (btnH v) = actionsTopBase barH (btnH v) := by
  unfold actionsTopOld actionsTopBase btnH; simp [hp]; grind

inductive LeaveOp where
  | suppress
  | removeFlip
  | flush
  | restore
  deriving DecidableEq

def LeaveOp.name : LeaveOp → String
  | .suppress => "suppress" | .removeFlip => "removeFlip" | .flush => "flush" | .restore => "restore"

structure LeaveSt where
  trans : Bool
  dirty : Bool
  started : Bool

def LeaveSt.step (s : LeaveSt) : LeaveOp → LeaveSt
  | .suppress => { s with trans := false }
  | .removeFlip => { s with dirty := true }
  | .flush => { s with started := s.started || (s.trans && s.dirty), dirty := false }
  | .restore => { s with trans := true }

def leaveRun (ops : List LeaveOp) : LeaveSt := ops.foldl LeaveSt.step ⟨true, false, false⟩

def leaveOld : List LeaveOp := [.removeFlip, .flush]

def leaveNew : List LeaveOp := [.suppress, .removeFlip, .flush, .restore]

theorem leave_old_starts : (leaveRun leaveOld).started = true := by decide

theorem leave_new_quiet : (leaveRun (leaveNew ++ [.flush])).started = false := by decide

theorem leave_new_restores : (leaveRun (leaveNew ++ [.flush])).trans = true := by decide

inductive MoveOp where
  | save
  | reparent
  | restore
  deriving DecidableEq

def MoveOp.name : MoveOp → String
  | .save => "save" | .reparent => "reparent" | .restore => "restore"

structure MoveSt where
  t : Rat
  saved : Option Rat

def MoveSt.step (s : MoveSt) : MoveOp → MoveSt
  | .save => { s with saved := some s.t }
  | .reparent => { s with t := 0 }
  | .restore => { s with t := s.saved.getD s.t }

def moveRun (ops : List MoveOp) (t : Rat) : MoveSt := ops.foldl MoveSt.step ⟨t, none⟩

def moveOld : List MoveOp := [.reparent]

def moveNew : List MoveOp := [.save, .reparent, .restore]

theorem move_old_restarts (t : Rat) (ht : 0 < t) : (moveRun moveOld t).t ≠ t := by
  simp [moveRun, moveOld, MoveSt.step]; grind

theorem move_new_keeps (t : Rat) : (moveRun moveNew t).t = t := by
  simp [moveRun, moveNew, MoveSt.step]


end Fw.Parts.MorphGeom
