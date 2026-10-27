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

end Fw.Parts.MorphGeom
