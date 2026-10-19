import Fw.Faithful.Band
/-!
# The PL5 verdict of a scroll zone and of the end-of-page region (task faithful-checks)

A zone (`y04000`, `y04500`, `tail`) of the rewrite R is compared with the same zone of the original A, cell by cell
(`Fw.Faithful.status`). The zone **passes** exactly when it is present in both arms, has the same number of frames and
the same scrolled pixels in both, and no cell fails. The region passes when its three zones pass. Skipped and
unbanded cells are listed in the report and never gate.

Proved: the pass condition (`pass_iff`); a zone missing in either arm never passes (`not_pass_of_absent`);
a differing frame count never passes (`not_pass_of_frames`); no type of either arm is dropped from the cells
(`mem_types`, `cell_of_mem`); a cell carries the verdict of its type (`cell_status`); the region passes exactly when
each of its zones does (`region_pass_iff`).
-/
namespace Fw.Faithful
open Fw.Measure

/-- One cell of a zone baseline: A's envelope and median over the shards, or R's. -/
structure ZCell where
  type : String
  lo : Int
  hi : Int
  base : Int
deriving Repr, DecidableEq

/-- A zone of a baseline: id, frames, scrolled pixels and the cell of every type. -/
structure ZBase where
  id : String
  frames : Nat
  scrolledPx : Int
  cells : List ZCell
deriving Repr, DecidableEq

/-- The cell of a type in a zone; a type the zone does not list counts `0`. -/
def ZBase.cell (z : ZBase) (ty : String) : ZCell :=
  (z.cells.find? (·.type == ty)).getD ⟨ty, 0, 0, 0⟩

/-- The types compared: A's types in A's order, then R's types A lacks, in R's order. -/
def typesOf (a r : ZBase) : List String :=
  let ta := a.cells.map (·.type)
  ta ++ (r.cells.map (·.type)).filter (fun t => !ta.contains t)

/-- One compared cell: the type, its family, its verdict and the numbers behind it. -/
structure CellOut where
  type : String
  family : Family
  status : Status
  obs : Obs
deriving Repr, DecidableEq

/-- The compared cell of a type: A's envelope and median against R's median, A's class table `T` for the class. -/
def cellOut (tb : Freeze.Table) (a r : ZBase) (ty : String) : CellOut :=
  let ca := a.cell ty
  let cr := r.cell ty
  let o : Obs := ⟨ca.lo, ca.hi, ca.base, cr.base⟩
  { type := ty, family := familyOf ty, status := status (Freeze.entry? tb ty) ty o, obs := o }

/-- The verdict of a zone. -/
structure ZoneVerdict where
  id : String
  present : Bool
  shape : Bool
  cells : List CellOut
deriving Repr, DecidableEq

/-- The zone `Z` of a list of zones. -/
def findZ (zs : List ZBase) (Z : String) : Option ZBase := zs.find? (·.id == Z)

/-- The verdict of zone `Z` of R's zones `rs` against A's zones `as`: absent in either arm gives no cells; else the
shape is "same frames and same scrolled pixels" and the cells are those of `typesOf`.
-/
def zoneVerdict (tb : Freeze.Table) (as rs : List ZBase) (Z : String) : ZoneVerdict :=
  match findZ as Z, findZ rs Z with
  | some a, some r =>
    { id := Z, present := true, shape := a.frames == r.frames && a.scrolledPx == r.scrolledPx,
      cells := (typesOf a r).map (cellOut tb a r) }
  | _, _ => { id := Z, present := false, shape := false, cells := [] }

/-- The types whose cell fails. -/
def ZoneVerdict.failed (v : ZoneVerdict) : List String :=
  (v.cells.filter (·.status == .fail)).map (·.type)

/-- A zone passes when it is present, has the same shape in both arms and no cell fails. -/
def ZoneVerdict.pass (v : ZoneVerdict) : Bool := v.present && v.shape && v.failed.isEmpty

/-- The zones of the end-of-page region (PLAN §6.6: the shells' zones are reported, not gated). -/
def regionZones : List String := ["y04000", "y04500", "tail"]

/-- The region passes when every zone of `regionZones` passes. -/
def regionPass (tb : Freeze.Table) (as rs : List ZBase) : Bool :=
  regionZones.all fun Z => (zoneVerdict tb as rs Z).pass

/-! ## Theorems -/

/-- **The pass condition.** A zone passes exactly when it is present, its shape agrees and no cell has status fail. -/
theorem pass_iff (v : ZoneVerdict) :
    v.pass = true ↔ v.present = true ∧ v.shape = true ∧ ∀ c ∈ v.cells, c.status ≠ .fail := by
  simp only [ZoneVerdict.pass, ZoneVerdict.failed, Bool.and_eq_true, List.isEmpty_iff]
  constructor
  · rintro ⟨⟨h1, h2⟩, h3⟩
    refine ⟨h1, h2, fun c hc hf => ?_⟩
    have : c.type ∈ (v.cells.filter (·.status == .fail)).map (·.type) :=
      List.mem_map.2 ⟨c, List.mem_filter.2 ⟨hc, by simp [hf]⟩, rfl⟩
    rw [h3] at this; simp at this
  · rintro ⟨h1, h2, h3⟩
    refine ⟨⟨h1, h2⟩, ?_⟩
    apply List.eq_nil_iff_forall_not_mem.2
    intro x hx
    obtain ⟨c, hc, rfl⟩ := List.mem_map.1 hx
    obtain ⟨hc1, hc2⟩ := List.mem_filter.1 hc
    exact h3 c hc1 (by simpa using hc2)

/-- A zone missing in either arm never passes. -/
theorem not_pass_of_absent (tb : Freeze.Table) (as rs : List ZBase) (Z : String)
    (h : findZ as Z = none ∨ findZ rs Z = none) : (zoneVerdict tb as rs Z).pass = false := by
  rcases h with h | h <;> simp [zoneVerdict, ZoneVerdict.pass, h]
  all_goals split <;> simp [ZoneVerdict.pass]

/-- A zone whose frame count differs between the arms never passes. -/
theorem not_pass_of_frames (tb : Freeze.Table) (as rs : List ZBase) (Z : String) {a r : ZBase}
    (ha : findZ as Z = some a) (hr : findZ rs Z = some r) (h : a.frames ≠ r.frames) :
    (zoneVerdict tb as rs Z).pass = false := by
  simp [zoneVerdict, ZoneVerdict.pass, ha, hr, h]

/-- Every type of either arm is compared. -/
theorem mem_types {a r : ZBase} {ty : String} (h : ty ∈ a.cells.map (·.type) ∨ ty ∈ r.cells.map (·.type)) :
    ty ∈ typesOf a r := by
  unfold typesOf
  rcases h with h | h
  · exact List.mem_append.2 (Or.inl h)
  · by_cases ha : ty ∈ a.cells.map (·.type)
    · exact List.mem_append.2 (Or.inl ha)
    · exact List.mem_append.2 (Or.inr (List.mem_filter.2 ⟨h, by simp [ha]⟩))

/-- A compared type has a cell in the verdict, with its own type name. -/
theorem cell_of_mem (tb : Freeze.Table) (a r : ZBase) {ty : String} (h : ty ∈ typesOf a r) :
    cellOut tb a r ty ∈ (typesOf a r).map (cellOut tb a r) := List.mem_map.2 ⟨ty, h, rfl⟩

/-- A cell carries the verdict of its type's table entry and numbers. -/
theorem cell_status (tb : Freeze.Table) (a r : ZBase) (ty : String) :
    (cellOut tb a r ty).status =
      status (Freeze.entry? tb ty) ty ⟨(a.cell ty).lo, (a.cell ty).hi, (a.cell ty).base, (r.cell ty).base⟩ := rfl

/-- **The region.** It passes exactly when each of its three zones does. -/
theorem region_pass_iff (tb : Freeze.Table) (as rs : List ZBase) :
    regionPass tb as rs = true ↔ ∀ Z ∈ regionZones, (zoneVerdict tb as rs Z).pass = true := by
  simp [regionPass]

end Fw.Faithful
