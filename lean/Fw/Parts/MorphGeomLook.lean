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

theorem look_column (v : Vp) (c : Ctx) (i : Nat) (hi : i < (nCols v).floor.toNat) :
    ∃ a ∈ anims v c, a.el = "column" ∧ a.key = (i, 0) ∧ a.prop = .translate ∧ a.fns[0]? = some (colTx v i) := by
  refine ⟨anim "column" .translate .unit [colTx v i, fun _ => 0] (i, 0), ?_, rfl, rfl, rfl, rfl⟩
  have hw : anim "column" .translate .unit [colTx v i, fun _ => 0] (i, 0) ∈
      (List.range (nCols v).floor.toNat).map fun i => anim "column" .translate .unit [colTx v i, fun _ => 0] (i, 0) :=
    List.mem_map.mpr ⟨i, List.mem_range.mpr hi, rfl⟩
  unfold anims
  split <;> split <;> simp only [List.mem_append] <;> grind

theorem look_image (v : Vp) (c : Ctx) (i j : Nat) (Y h : Rat) (hm : ((i, j), Y, h) ∈ imgRows c) :
    ∃ a ∈ anims v c, a.el = "image" ∧ a.key = (i, j) ∧ a.prop = .transformList ∧ a.fns[1]? = some (imgTy v j Y 0) ∧
      a.fns[2]? = some (sImg v) := by
  refine ⟨anim "image" .transformList .unit [fun _ => 0, imgTy v j Y 0, sImg v, sImg v] (i, j), ?_, rfl, rfl, rfl, rfl, rfl⟩
  have hw : anim "image" .transformList .unit [fun _ => 0, imgTy v j Y 0, sImg v, sImg v] (i, j) ∈
      (imgRows c).map fun ((i, j), y, _) => anim "image" .transformList .unit [fun _ => 0, imgTy v j y 0, sImg v, sImg v] (i, j) :=
    List.mem_map.mpr ⟨((i, j), Y, h), hm, rfl⟩
  unfold anims
  split <;> split <;> simp only [List.mem_append] <;> grind

/-! Flip-state layout (task geom-flip-fix): the layout rules that make the layers' boxes equal the base boxes. -/

/-- The gap of a flip layer as a CSS rule: a length, or `inherit` (the parent's computed gap). -/
inductive GapRule where
  | px (n : Rat)
  | inherit

def GapRule.val (r : GapRule) (parent : Rat) : Rat :=
  match r with
  | .px n => n
  | .inherit => parent

/-- The panel backdrop's own gap (morph.panel `.backdrop`: 12 px, 8 px at width <= 640). -/
def backdropGap (v : Vp) : Rat := if v.w ≤ 640 then 8 else 12

theorem backdropGap_eq (v : Vp) : backdropGap v = colGap v := by
  unfold backdropGap colGap phone
  by_cases h : v.w ≤ 640 <;> simp [h]

/-- The flip rule of Kb and Ub: a flex row whose gap is inherited (A1). Ub sits in Kb sits in the backdrop. -/
def flipRowGap : GapRule := .inherit

def flipGap (v : Vp) : Rat := flipRowGap.val (flipRowGap.val (backdropGap v))

/-- Left edge of flex item `i` in a row of equal items of width `w` and gap `g`. -/
def rowLeft (w g : Rat) (i : Nat) : Rat := (i : Rat) * (w + g)

/-- Left edge of every child of a block box: they stack (the A1 bug, Ub had no flex row). -/
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

/-- Vertical offset of the earn button under `.is-flip`: its base transform plus the track's own translate. The base
transform is `translateY(earnOut * -8px)` with `--morph` held at 1 (A3b). -/
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

/-- Top of the actions content in bar coordinates, for content of height `h` in a bar of height `barH`. Base:
`top: 50%; translate: 0 -50%`. Old flip rule: `top: calc(50% - 24px)`, no translate. Fix: the box fills the bar
(`top: 0; bottom: 0`) and `align-items: center` centres the content (A3c). -/
def actionsTopBase (barH h : Rat) : Rat := barH / 2 - h / 2

def actionsTopOld (barH _h : Rat) : Rat := barH / 2 - 24

def actionsTopFix (barH h : Rat) : Rat := 0 + (barH - h) / 2

/-- The height of the nav buttons: 48, or 36 at width <= 640. -/
def btnH (v : Vp) : Rat := if phone v.w then 36 else 48

theorem actions_fix_eq (barH h : Rat) : actionsTopFix barH h = actionsTopBase barH h := by
  unfold actionsTopFix actionsTopBase; grind

theorem actions_old_phone (v : Vp) (barH : Rat) (hp : phone v.w = true) :
    actionsTopOld barH (btnH v) - actionsTopBase barH (btnH v) = -6 := by
  unfold actionsTopOld actionsTopBase btnH; simp [hp]; grind

theorem actions_old_desktop (v : Vp) (barH : Rat) (hp : phone v.w = false) :
    actionsTopOld barH (btnH v) = actionsTopBase barH (btnH v) := by
  unfold actionsTopOld actionsTopBase btnH; simp [hp]; grind

/-- The steps of `leave()` against transitions (A4). A transition starts at a style flush when transitions are on and
a computed value changed since the last flush. -/
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

/-- Before the fix: the class goes, the next frame's flush starts the width and background transitions. -/
def leaveOld : List LeaveOp := [.removeFlip, .flush]

/-- The fix: the steps of `leave()`. The browser's own flush at the next frame follows (`leaveNew ++ [.flush]`). -/
def leaveNew : List LeaveOp := [.suppress, .removeFlip, .flush, .restore]

theorem leave_old_starts : (leaveRun leaveOld).started = true := by decide

theorem leave_new_quiet : (leaveRun (leaveNew ++ [.flush])).started = false := by decide

theorem leave_new_restores : (leaveRun (leaveNew ++ [.flush])).trans = true := by decide

/-- The time of a CSS animation across a re-parent (A3a): detaching cancels it and the new one starts at 0. -/
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
