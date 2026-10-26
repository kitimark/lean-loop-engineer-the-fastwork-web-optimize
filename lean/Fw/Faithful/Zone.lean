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

def evidence (as rs : List ZBase) (Z : String) : Bool :=
  match findZ as Z, findZ rs Z with
  | some a, some r => a.frames != 0 && r.frames != 0 && !(typesOf a r).isEmpty
  | _, _ => false

inductive Judged where
  | pass | fail | undecided
deriving Repr, DecidableEq, Inhabited

def zoneJudged (tb : Freeze.Table) (as rs : List ZBase) (Z : String) : Judged :=
  if (zoneVerdict tb as rs Z).pass then (if evidence as rs Z then .pass else .undecided) else .fail

def judged (tb : Freeze.Table) (as rs : List ZBase) (zs : List String) : Judged :=
  let os := zs.map (zoneJudged tb as rs)
  if os.contains .fail then .fail else if os.isEmpty || os.contains .undecided then .undecided else .pass

def unguarded (tb : Freeze.Table) (as rs : List ZBase) (zs : List String) : Judged :=
  if zs.all fun Z => (zoneVerdict tb as rs Z).pass then .pass else .fail

#guard judged [] [] [] [] == .undecided
#guard judged [] [⟨"tail", 0, 0, []⟩] [⟨"tail", 0, 0, []⟩] ["tail"] == .undecided
#guard judged [] [⟨"tail", 0, 0, [⟨"x", 1, 1, 1⟩]⟩] [⟨"tail", 0, 0, [⟨"x", 1, 1, 1⟩]⟩] ["tail"] == .undecided
#guard judged [] [⟨"tail", 3, 0, []⟩] [⟨"tail", 3, 0, []⟩] ["tail"] == .undecided
#guard judged [] [⟨"tail", 3, 0, [⟨"x", 1, 1, 1⟩]⟩] [⟨"tail", 3, 0, [⟨"x", 1, 1, 1⟩]⟩] ["tail"] == .pass
#guard judged [] [⟨"tail", 3, 0, [⟨"x", 1, 1, 1⟩]⟩] [⟨"tail", 4, 0, [⟨"x", 1, 1, 1⟩]⟩] ["tail"] == .fail
#guard judged [] [⟨"tail", 3, 0, [⟨"x", 1, 1, 1⟩]⟩] [] ["tail"] == .fail
#guard judged [] [⟨"tail", 3, 0, [⟨"x", 1, 1, 1⟩]⟩, ⟨"y", 0, 0, []⟩] [⟨"tail", 4, 0, []⟩, ⟨"y", 0, 0, []⟩] ["y", "tail"] == .fail
#guard evidence [⟨"tail", 3, 0, []⟩] [⟨"tail", 3, 0, [⟨"x", 1, 1, 1⟩]⟩] "tail"
#guard !evidence [⟨"tail", 3, 0, [⟨"x", 1, 1, 1⟩]⟩] [⟨"tail", 0, 0, [⟨"x", 1, 1, 1⟩]⟩] "tail"
#guard zoneJudged [] [⟨"tail", 0, 0, []⟩] [⟨"tail", 0, 0, []⟩] "tail" == .undecided
#guard unguarded [] [] [] [] == .pass

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

theorem zoneVerdict_id (tb : Freeze.Table) (as rs : List ZBase) (Z : String) : (zoneVerdict tb as rs Z).id = Z := by
  unfold zoneVerdict; split <;> rfl

theorem not_evidence_of_absent (as rs : List ZBase) (Z : String) (h : findZ as Z = none ∨ findZ rs Z = none) :
    evidence as rs Z = false := by
  rcases h with h | h <;> simp [evidence, h]

theorem not_evidence_of_frames_a (as rs : List ZBase) (Z : String) {a : ZBase} (ha : findZ as Z = some a)
    (h : a.frames = 0) : evidence as rs Z = false := by
  simp only [evidence, ha]; split <;> simp_all

theorem not_evidence_of_frames_r (as rs : List ZBase) (Z : String) {r : ZBase} (hr : findZ rs Z = some r)
    (h : r.frames = 0) : evidence as rs Z = false := by
  simp only [evidence, hr]; split <;> simp_all

theorem not_evidence_of_no_types (as rs : List ZBase) (Z : String) {a r : ZBase} (ha : findZ as Z = some a)
    (hr : findZ rs Z = some r) (h : a.cells = [] ∧ r.cells = []) : evidence as rs Z = false := by
  simp [evidence, ha, hr, typesOf, h.1, h.2]

theorem zoneJudged_pass_iff (tb : Freeze.Table) (as rs : List ZBase) (Z : String) :
    zoneJudged tb as rs Z = .pass ↔ (zoneVerdict tb as rs Z).pass = true ∧ evidence as rs Z = true := by
  unfold zoneJudged
  cases (zoneVerdict tb as rs Z).pass <;> cases evidence as rs Z <;> simp

theorem zoneJudged_fail_iff (tb : Freeze.Table) (as rs : List ZBase) (Z : String) :
    zoneJudged tb as rs Z = .fail ↔ (zoneVerdict tb as rs Z).pass = false := by
  unfold zoneJudged
  cases (zoneVerdict tb as rs Z).pass <;> cases evidence as rs Z <;> simp

theorem zoneJudged_undecided_iff (tb : Freeze.Table) (as rs : List ZBase) (Z : String) :
    zoneJudged tb as rs Z = .undecided ↔ (zoneVerdict tb as rs Z).pass = true ∧ evidence as rs Z = false := by
  unfold zoneJudged
  cases (zoneVerdict tb as rs Z).pass <;> cases evidence as rs Z <;> simp

theorem judged_eq (tb : Freeze.Table) (as rs : List ZBase) (zs : List String) :
    judged tb as rs zs =
      if ∃ Z ∈ zs, zoneJudged tb as rs Z = .fail then .fail
      else if zs = [] ∨ ∃ Z ∈ zs, zoneJudged tb as rs Z = .undecided then .undecided else .pass := by
  simp [judged]

theorem judged_fail_iff (tb : Freeze.Table) (as rs : List ZBase) (zs : List String) :
    judged tb as rs zs = .fail ↔ ∃ Z ∈ zs, zoneJudged tb as rs Z = .fail := by
  rw [judged_eq]
  by_cases h1 : ∃ Z ∈ zs, zoneJudged tb as rs Z = .fail
  · simp only [h1, ↓reduceIte]
  · by_cases h2 : zs = [] ∨ ∃ Z ∈ zs, zoneJudged tb as rs Z = .undecided <;> simp only [h1, h2, ↓reduceIte] <;> simp

theorem judged_nil (tb : Freeze.Table) (as rs : List ZBase) : judged tb as rs [] = .undecided := rfl

theorem judged_undecided_of_zone (tb : Freeze.Table) (as rs : List ZBase) (zs : List String)
    (hf : ∀ Z ∈ zs, zoneJudged tb as rs Z ≠ .fail) {Z : String} (hZ : Z ∈ zs) (hu : zoneJudged tb as rs Z = .undecided) :
    judged tb as rs zs = .undecided := by
  have h1 : ¬∃ Z ∈ zs, zoneJudged tb as rs Z = .fail := fun ⟨Y, hY, e⟩ => hf Y hY e
  have h2 : zs = [] ∨ ∃ Z ∈ zs, zoneJudged tb as rs Z = .undecided := .inr ⟨Z, hZ, hu⟩
  rw [judged_eq]; simp only [h1, h2, ↓reduceIte]

theorem judged_pass_iff (tb : Freeze.Table) (as rs : List ZBase) (zs : List String) :
    judged tb as rs zs = .pass ↔ zs ≠ [] ∧ ∀ Z ∈ zs, zoneJudged tb as rs Z = .pass := by
  rw [judged_eq]
  by_cases h1 : ∃ Z ∈ zs, zoneJudged tb as rs Z = .fail
  · obtain ⟨Z, hZ, e⟩ := h1
    simp only [show ∃ Z ∈ zs, zoneJudged tb as rs Z = .fail from ⟨Z, hZ, e⟩, ↓reduceIte, reduceCtorEq, false_iff,
      not_and]
    exact fun _ hp => absurd (hp Z hZ) (by simp [e])
  by_cases h2 : zs = [] ∨ ∃ Z ∈ zs, zoneJudged tb as rs Z = .undecided
  · simp only [h1, h2, ↓reduceIte, reduceCtorEq, false_iff, not_and]
    intro hne hp
    rcases h2 with h2 | ⟨Z, hZ, e⟩
    · exact absurd h2 hne
    · exact absurd (hp Z hZ) (by simp [e])
  · simp only [h1, h2, ↓reduceIte, true_iff]
    simp only [not_or, not_exists, not_and] at h1 h2
    refine ⟨h2.1, fun Z hZ => ?_⟩
    cases e : zoneJudged tb as rs Z
    · rfl
    · exact absurd e (h1 Z hZ)
    · exact absurd e (h2.2 Z hZ)

theorem evidence_of_judged_pass (tb : Freeze.Table) (as rs : List ZBase) (zs : List String)
    (h : judged tb as rs zs = .pass) :
    zs ≠ [] ∧ ∀ Z ∈ zs, evidence as rs Z = true ∧ (zoneVerdict tb as rs Z).pass = true := by
  obtain ⟨hne, hp⟩ := (judged_pass_iff tb as rs zs).1 h
  exact ⟨hne, fun Z hZ => ((zoneJudged_pass_iff tb as rs Z).1 (hp Z hZ)).symm⟩

theorem zoneJudged_of_evidence (tb : Freeze.Table) (as rs : List ZBase) (Z : String) (h : evidence as rs Z = true) :
    zoneJudged tb as rs Z = if (zoneVerdict tb as rs Z).pass then .pass else .fail := by
  simp [zoneJudged, h]

theorem judged_eq_unguarded (tb : Freeze.Table) (as rs : List ZBase) (zs : List String) (hne : zs ≠ [])
    (he : ∀ Z ∈ zs, evidence as rs Z = true) : judged tb as rs zs = unguarded tb as rs zs := by
  unfold unguarded
  split
  · next hp =>
    refine (judged_pass_iff tb as rs zs).2 ⟨hne, fun Z hZ => ?_⟩
    rw [zoneJudged_of_evidence tb as rs Z (he Z hZ)]
    simp [List.all_eq_true.1 hp Z hZ]
  · next hp =>
    obtain ⟨Z, hZ, hf⟩ : ∃ Z ∈ zs, (zoneVerdict tb as rs Z).pass = false := by simpa using hp
    exact (judged_fail_iff tb as rs zs).2 ⟨Z, hZ, (zoneJudged_fail_iff tb as rs Z).2 hf⟩

end Fw.Faithful
