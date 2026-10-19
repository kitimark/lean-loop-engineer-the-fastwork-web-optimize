import Fw.Measure.ZoneBaseline
import Fw.Engine.Chromium
/-! F6 composition check: per (stage, count type, zone) a combined arm's delta against the sum of its
single-flag deltas, within the class margin; unit types are judged, pass types are reported. -/
namespace Fw.Measure.Compose
open Fw.Measure Fw.Measure.EngineCheck Fw.Engine

/-- Whether a count type counts work units (judged) or pipeline passes (reported only). -/
inductive Kind where
  | units
  | passes
deriving Repr, DecidableEq

/-- The count types judged as units; every other type is a pass type. -/
def unitTypes : List String :=
  ["trace.FireAnimationFrame", "trace.FunctionCall", "trace.Layout.dirtyObjects",
   "raster.invalidationAreaPx", "raster.invalidationRects", "census.layers"]

/-- The kind of a count type. -/
def kindOf (ty : String) : Kind := if unitTypes.contains ty then .units else .passes

#guard kindOf "trace.Layout.dirtyObjects" == .units && kindOf "census.layers" == .units
#guard kindOf "trace.Layout" == .passes && kindOf "trace.Paint" == .passes && kindOf "x.unknown" == .passes

/-- The (stage, count type) cells, from `Chromium.stageCounts` in stage order. -/
def cells : List (Stage × String) := Stage.all.flatMap fun s => (Chromium.stageCounts s).map (s, ·)

#guard cells.length == 13 && cells.head? == some (.script, "trace.FireAnimationFrame")

/-! ## Runs and pairs -/

/-- One counts run: its non-faithful variants as `part:variant` and its zone sums. -/
structure Run where
  flags : List String
  zones : List Zone

/-- The non-faithful variants of a run as `part:variant`. -/
def flagsOf (variants : List (String × String)) : List String :=
  (variants.filter (·.2 != "faithful")).map fun (p, v) => p ++ ":" ++ v

#guard flagsOf [("a", "faithful"), ("b", "shell"), ("c.d", "mq")] == ["b:shell", "c.d:mq"]

/-- A measured comparison: base runs and arm runs, with the CI run ids. -/
structure Runs where
  id : String
  baseId : String
  base : List Run
  arm : List Run

/-- The zone shape of a comparison: that of its first base run. -/
def Runs.shape (r : Runs) : List (String × Nat × Int × Nat × Nat) :=
  ((r.base.head?).map fun x => x.zones.map ZoneBaseline.shape).getD []

/-- The flags of the first base run. -/
def Runs.baseFlags (r : Runs) : List String := ((r.base.head?).map (·.flags)).getD []

/-- The flags of the first arm run. -/
def Runs.armFlags (r : Runs) : List String := ((r.arm.head?).map (·.flags)).getD []

/-- The flags the arm adds to the base. -/
def Runs.flags (r : Runs) : List String := r.armFlags.filter (· ∉ r.baseFlags)

/-- A comparison is usable: both sides measured, one zone shape, one flag set per side, no base flag dropped. -/
def Runs.clean (r : Runs) : Bool :=
  !r.base.isEmpty && !r.arm.isEmpty &&
  (r.base ++ r.arm).all (fun x => x.zones.map ZoneBaseline.shape == r.shape) &&
  r.base.all (·.flags == r.baseFlags) && r.arm.all (·.flags == r.armFlags) &&
  r.baseFlags.all (· ∈ r.armFlags)

/-- The single-flag comparison for `f`: same base runs, same zone shape, arm adds exactly `f`. -/
def armFor (c : Runs) (singles : List Runs) (f : String) : Option Runs :=
  singles.find? fun s => s.clean && s.flags == [f] && s.baseId == c.baseId && s.shape == c.shape

/-- A cell's value in one run: zone `Z`, or the whole-run total for `none`. -/
def valAt (zs : List Zone) (z : Option String) (ty : String) : Int :=
  match z with
  | some Z => sumAt zs Z ty
  | none => ZoneBaseline.total zs ty

/-- The per-run values of one cell on both sides of a comparison. -/
structure Pair where
  id : String
  base : List Int
  arm : List Int
deriving Repr, DecidableEq

/-- The cell of a comparison at zone `z` and type `ty`. -/
def pairAt (r : Runs) (z : Option String) (ty : String) : Pair :=
  { id := r.id, base := r.base.map (valAt ·.zones z ty), arm := r.arm.map (valAt ·.zones z ty) }

/-- The delta of a pair: lower median of the arm minus lower median of the base. -/
def Pair.delta (p : Pair) : Int := ZoneBaseline.base p.arm - ZoneBaseline.base p.base

/-- Every run of each side gives the same value. -/
def Pair.steady (p : Pair) : Bool :=
  ZoneBaseline.lo p.base == ZoneBaseline.hi p.base && ZoneBaseline.lo p.arm == ZoneBaseline.hi p.arm

#guard ({ id := "a", base := [10, 12, 11], arm := [7, 9, 8] } : Pair).delta == -3
#guard ({ id := "a", base := [4, 4], arm := [1, 1] } : Pair).steady
#guard !({ id := "a", base := [4, 5], arm := [1, 1] } : Pair).steady

/-! ## The verdict of one cell -/

/-- One (stage, type, zone) cell: kind, frozen class, whole-run or zone, combined pair, and per flag its single pair. -/
structure Cell where
  kind : Kind
  cls : Class
  whole : Bool
  combined : Pair
  parts : List (String × Option Pair)

/-- The flags with no comparable single-flag arm. -/
def Cell.missing (c : Cell) : List String := c.parts.filterMap fun (f, p) => if p.isNone then some f else none

/-- The flags with a single-flag arm, each with its pair. -/
def Cell.found (c : Cell) : List (String × Pair) := c.parts.filterMap fun (f, p) => p.map (f, ·)

/-- The sum of the single-flag deltas. -/
def Cell.sum (c : Cell) : Int := (c.found.map (·.2.delta)).sum

/-- The combined delta minus the sum of the single-flag deltas. -/
def Cell.residual (c : Cell) : Int := c.combined.delta - c.sum

/-- The margin: each of the `n + 1` deltas may move by twice the class slack. -/
def Cell.margin (c : Cell) : Nat := 2 * slack c.cls * (c.parts.length + 1)

/-- The flags whose single-flag delta is nonzero. -/
def Cell.acting (c : Cell) : List String := (c.found.filter (·.2.delta != 0)).map (·.1)

/-- The combined pair and every single pair are steady. -/
def Cell.steady (c : Cell) : Bool := c.combined.steady && c.found.all (·.2.steady)

/-- Why a cell is not comparable. -/
inductive Why where
  | missing (flags : List String)
  | quarantined
  | noZoneMargin
  | drift
deriving Repr, DecidableEq

/-- The verdict of one cell. -/
inductive Verdict where
  | composes
  | coupled (parts : List String)
  | notComparable (why : Why)
  | reported
deriving Repr, DecidableEq

/-- The verdict before the margin test: passes reported; then missing arm, quarantined, zone cell of a non-exact class, drift. -/
def pre (c : Cell) : Option Verdict :=
  if c.kind = .passes then some .reported
  else if c.missing ≠ [] then some (.notComparable (.missing c.missing))
  else if c.cls = .quarantined then some (.notComparable .quarantined)
  else if !exact c.cls && !c.whole then some (.notComparable .noZoneMargin)
  else if exact c.cls && !c.steady then some (.notComparable .drift)
  else none

/-- The verdict: `pre`, else `composes` when the residual is within the margin, else `coupled` naming the acting flags. -/
def verdict (c : Cell) : Verdict :=
  match pre c with
  | some v => v
  | none => if c.residual.natAbs ≤ c.margin then .composes else .coupled c.acting

/-- The cell conditions under which the margin test decides. -/
def Comparable (c : Cell) : Prop :=
  c.kind = .units ∧ c.missing = [] ∧ c.cls ≠ .quarantined ∧ (exact c.cls = true ∨ c.whole = true) ∧
    (exact c.cls = true → c.steady = true)

private def pr (b a : List Int) : Pair := { id := "r", base := b, arm := a }
private def cellOf (k : Kind) (cls : Class) (w : Bool) (c : Pair) (ps : List (String × Option Pair)) : Cell :=
  { kind := k, cls := cls, whole := w, combined := c, parts := ps }

#guard verdict (cellOf .passes .deterministic false (pr [1] [2]) []) == .reported
#guard verdict (cellOf .units .deterministic false (pr [5] [2]) [("a", some (pr [5] [4])), ("b", some (pr [5] [3]))])
  == .composes
#guard verdict (cellOf .units .deterministic false (pr [5] [1]) [("a", some (pr [5] [4])), ("b", some (pr [5] [3]))])
  == .coupled ["a", "b"]
#guard verdict (cellOf .units .deterministic false (pr [5] [2]) [("a", some (pr [5] [4])), ("b", none)])
  == .notComparable (.missing ["b"])
#guard verdict (cellOf .units .quarantined true (pr [5] [2]) []) == .notComparable .quarantined
#guard verdict (cellOf .units (.stable 2 3) false (pr [5] [2]) []) == .notComparable .noZoneMargin
#guard verdict (cellOf .units .deterministic true (pr [5, 6] [2, 2]) []) == .notComparable .drift
#guard verdict (cellOf .units (.stable 2 3) true (pr [50] [40]) [("a", some (pr [50] [45]))]) == .composes
#guard verdict (cellOf .units (.stable 2 3) true (pr [50] [30]) [("a", some (pr [50] [45]))]) == .coupled ["a"]
#guard (cellOf .units (.stable 2 3) true (pr [50] [30]) [("a", some (pr [50] [45]))]).margin == 12

/-! ## Each branch of the verdict -/

/-- The margin test decides exactly on comparable cells. -/
theorem pre_eq_none_iff (c : Cell) : pre c = none ↔ Comparable c := by
  unfold pre Comparable
  cases hk : c.kind <;> cases he : exact c.cls <;> cases hw : c.whole <;> cases hs : c.steady <;>
    by_cases hm : c.missing = [] <;> by_cases hq : c.cls = .quarantined <;> simp_all

/-- `pre` yields nothing, `reported` exactly on a pass type, or a not-comparable reason. -/
theorem pre_cases (c : Cell) :
    (pre c = some .reported ↔ c.kind = .passes) ∧ (pre c = none ∨ pre c = some .reported ∨ ∃ w, pre c = some (.notComparable w)) := by
  unfold pre
  cases hk : c.kind <;> cases he : exact c.cls <;> cases hw : c.whole <;> cases hs : c.steady <;>
    by_cases hm : c.missing = [] <;> by_cases hq : c.cls = .quarantined <;> simp_all

/-- `pre` never yields `composes`. -/
theorem pre_ne_composes (c : Cell) : pre c ≠ some .composes := by
  rcases (pre_cases c).2 with h | h | ⟨w, h⟩ <;> simp [h]

/-- `pre` never yields `coupled`. -/
theorem pre_ne_coupled (c : Cell) (ps : List String) : pre c ≠ some (.coupled ps) := by
  rcases (pre_cases c).2 with h | h | ⟨w, h⟩ <;> simp [h]

/-- A pass type is reported, and only a pass type. -/
theorem verdict_reported_iff (c : Cell) : verdict c = .reported ↔ c.kind = .passes := by
  rw [← (pre_cases c).1]
  unfold verdict
  cases hp : pre c with
  | some v => simp
  | none => by_cases hr : c.residual.natAbs ≤ c.margin <;> simp [hr]

/-- A unit cell with a missing arm is not comparable, naming the missing flags. -/
theorem verdict_missing {c : Cell} (hk : c.kind = .units) (hm : c.missing ≠ []) :
    verdict c = .notComparable (.missing c.missing) := by
  simp [verdict, pre, hk, hm]

/-- A quarantined unit cell with every arm present is not comparable. -/
theorem verdict_quarantined {c : Cell} (hk : c.kind = .units) (hm : c.missing = [])
    (hq : c.cls = .quarantined) : verdict c = .notComparable .quarantined := by
  simp [verdict, pre, hk, hm, hq]

/-- A zone cell of a class that is not frame exact has no margin. -/
theorem verdict_noZoneMargin {c : Cell} (hk : c.kind = .units) (hm : c.missing = [])
    (hq : c.cls ≠ .quarantined) (he : exact c.cls = false) (hw : c.whole = false) :
    verdict c = .notComparable .noZoneMargin := by
  simp [verdict, pre, hk, hm, hq, he, hw]

/-- A frame-exact cell whose runs disagree is drift. -/
theorem verdict_drift {c : Cell} (hk : c.kind = .units) (hm : c.missing = [])
    (hq : c.cls ≠ .quarantined) (he : exact c.cls = true) (hs : c.steady = false) :
    verdict c = .notComparable .drift := by
  simp [verdict, pre, hk, hm, hq, he, hs]

/-- **The verdict is `composes` exactly when** the cell is comparable and the residual is within the margin. -/
theorem verdict_composes_iff (c : Cell) :
    verdict c = .composes ↔ Comparable c ∧ c.residual.natAbs ≤ c.margin := by
  rw [← pre_eq_none_iff]
  unfold verdict
  cases hp : pre c with
  | some v => have := pre_ne_composes c; simp_all
  | none => by_cases hr : c.residual.natAbs ≤ c.margin <;> simp [hr]

/-- **The verdict is `coupled` exactly when** the cell is comparable and the residual exceeds the margin. -/
theorem verdict_coupled_iff (c : Cell) :
    (∃ ps, verdict c = .coupled ps) ↔ Comparable c ∧ c.margin < c.residual.natAbs := by
  rw [← pre_eq_none_iff]
  unfold verdict
  cases hp : pre c with
  | some v =>
    simp only [reduceCtorEq, false_and, iff_false, not_exists]
    intro ps h
    exact pre_ne_coupled c ps (h ▸ hp)
  | none => by_cases hr : c.residual.natAbs ≤ c.margin <;> simp [hr] <;> omega

/-- A missing arm is never `composes`. -/
theorem missing_not_composes {c : Cell} (hm : c.missing ≠ []) : verdict c ≠ .composes := by
  intro h
  exact hm ((verdict_composes_iff c).mp h).1.2.1

/-- A missing arm is never `coupled`. -/
theorem missing_not_coupled {c : Cell} (hm : c.missing ≠ []) (ps : List String) : verdict c ≠ .coupled ps := by
  intro h
  exact hm ((verdict_coupled_iff c).mp ⟨ps, h⟩).1.2.1

/-- A coupled verdict names the acting flags. -/
theorem verdict_coupled_parts {c : Cell} {ps : List String} (h : verdict c = .coupled ps) : ps = c.acting := by
  unfold verdict at h
  cases hp : pre c with
  | some v => rw [hp] at h; subst h; exact absurd hp (pre_ne_coupled c ps)
  | none => rw [hp] at h; by_cases hr : c.residual.natAbs ≤ c.margin <;> simp [hr] at h; exact h.symm

/-- A frame-exact class has no slack. -/
theorem slack_exact {c : Class} (h : exact c = true) : slack c = 0 := by
  cases c with
  | deterministic => rfl
  | stable k t => cases k with
    | zero => rfl
    | succ k => simp [exact] at h
  | quarantined => simp [exact] at h

/-- On a frame-exact class, `composes` means the residual is zero. -/
theorem composes_exact {c : Cell} (he : exact c.cls = true) (h : verdict c = .composes) : c.residual = 0 := by
  have hr := ((verdict_composes_iff c).mp h).2
  simp [Cell.margin, slack_exact he] at hr
  exact hr

/-! ## Soundness of a coupled verdict -/

/-- Two delta lists of one length, each entry within `m` of its partner. -/
inductive Near (m : Nat) : List Int → List Int → Prop
  | nil : Near m [] []
  | cons {d e : Int} {ds es : List Int} : (d - e).natAbs ≤ m → Near m ds es → Near m (d :: ds) (e :: es)

/-- Near lists have sums within `length · m`. -/
theorem sum_gap {m : Nat} : ∀ {ds es : List Int}, Near m ds es → (ds.sum - es.sum).natAbs ≤ ds.length * m
  | [], [], .nil => by simp
  | _ :: _, _ :: _, .cons h hs => by
    have ih := sum_gap hs
    simp only [List.sum_cons, List.length_cons, Nat.succ_mul]
    omega

/-- If each unseen delta is within twice the slack of the observed one, a residual beyond the margin stays nonzero. -/
theorem coupled_sound {s : Nat} {d₀ e₀ : Int} {ds es : List Int} (h₀ : (d₀ - e₀).natAbs ≤ 2 * s)
    (hs : Near (2 * s) ds es) (hgap : 2 * s * (ds.length + 1) < (d₀ - ds.sum).natAbs) : e₀ - es.sum ≠ 0 := by
  have hg := sum_gap hs
  rw [Nat.mul_succ, Nat.mul_comm (2 * s)] at hgap
  omega

/-- With no flag missing, every flag has its pair. -/
theorem found_length_of (l : List (String × Option Pair))
    (hm : l.filterMap (fun (f, p) => if p.isNone then some f else none) = []) :
    (l.filterMap fun (f, p) => p.map (f, ·)).length = l.length := by
  induction l with
  | nil => rfl
  | cons x xs ih =>
    obtain ⟨f, p⟩ := x
    cases p with
    | none => simp at hm
    | some p =>
      simp only [Option.isNone_some, Bool.false_eq_true, ite_false, Option.map_some,
        List.filterMap_cons] at hm ⊢
      simp [ih hm]

/-- Every flag of a cell with no missing arm has its pair. -/
theorem found_length {c : Cell} (hm : c.missing = []) : c.found.length = c.parts.length :=
  found_length_of c.parts hm

/-- **A coupled cell is coupled in every unseen run** whose deltas each move by at most twice the class slack. -/
theorem coupled_cell_sound {c : Cell} {ps : List String} (h : verdict c = .coupled ps) {e₀ : Int} {es : List Int}
    (h₀ : (c.combined.delta - e₀).natAbs ≤ 2 * slack c.cls)
    (hs : Near (2 * slack c.cls) (c.found.map (·.2.delta)) es) :
    e₀ - es.sum ≠ 0 := by
  obtain ⟨⟨_, hm, _⟩, hr⟩ := (verdict_coupled_iff c).mp ⟨ps, h⟩
  apply coupled_sound h₀ hs
  simpa [Cell.margin, Cell.residual, Cell.sum, found_length hm] using hr

/-! ## The table of one combined comparison -/

/-- The class of a type in a class list; an unlisted type is quarantined. -/
def classIn (tb : List (String × Class)) (ty : String) : Class := ((tb.find? (·.1 == ty)).map (·.2)).getD .quarantined

/-- The cell of a combined comparison at zone `z` (`none`: the whole run) and type `ty`. -/
def cellAt (tb : List (String × Class)) (c : Runs) (singles : List Runs) (z : Option String) (ty : String) : Cell :=
  { kind := kindOf ty, cls := classIn tb ty, whole := z.isNone, combined := pairAt c z ty,
    parts := c.flags.map fun f => (f, (armFor c singles f).map (pairAt · z ty)) }

/-- The zones of a table: the combined comparison's zone ids, then the whole run. -/
def zonesOf (c : Runs) : List (Option String) := c.shape.map (some ·.1) ++ [none]

/-- One row of the table. -/
structure Row where
  stage : Stage
  type : String
  zone : Option String
  cell : Cell

/-- The table: per (stage, type) cell, per zone of the combined comparison. -/
def table (tb : List (String × Class)) (c : Runs) (singles : List Runs) : List Row :=
  cells.flatMap fun (s, ty) => (zonesOf c).map fun z => { stage := s, type := ty, zone := z, cell := cellAt tb c singles z ty }

/-- A matched single-flag arm has the same base run id and zone shape and adds exactly that flag. -/
theorem armFor_spec {c s : Runs} {singles : List Runs} {f : String} (h : armFor c singles f = some s) :
    s ∈ singles ∧ s.clean = true ∧ s.flags = [f] ∧ s.baseId = c.baseId ∧ s.shape = c.shape := by
  have hm := List.mem_of_find?_eq_some h
  have hp := List.find?_some h
  simp only [Bool.and_eq_true, beq_iff_eq] at hp
  exact ⟨hm, hp.1.1.1, hp.1.1.2, hp.1.2, hp.2⟩

/-- A cell's missing flags are the combined flags with no matched single-flag arm. -/
theorem cellAt_missing (tb : List (String × Class)) (c : Runs) (singles : List Runs) (z : Option String) (ty : String) :
    (cellAt tb c singles z ty).missing = c.flags.filter fun f => (armFor c singles f).isNone := by
  simp only [cellAt, Cell.missing]
  induction c.flags with
  | nil => rfl
  | cons f fs ih =>
    cases h : armFor c singles f <;> simp_all

private def zone1 (id : String) (v : Int) : Zone :=
  { id := id, frames := 1, scrolledPx := 0, firstFrame := 0, lastFrame := 0, sums := [("trace.Layout.dirtyObjects", v)] }
private def run1 (fl : List String) (v : Int) : Run := { flags := fl, zones := [zone1 "y0" v] }
private def base0 : List Run := [run1 ["s"] 10, run1 ["s"] 10]
private def comb : Runs := { id := "C", baseId := "B", base := base0, arm := [run1 ["s", "a", "b"] 4, run1 ["s", "a", "b"] 4] }
private def sA : Runs := { id := "A", baseId := "B", base := base0, arm := [run1 ["s", "a"] 7, run1 ["s", "a"] 7] }
private def sB : Runs := { id := "Bf", baseId := "B", base := base0, arm := [run1 ["a", "b"] 7] }
private def tb0 : List (String × Class) := [("trace.Layout.dirtyObjects", .deterministic)]

#guard comb.clean && comb.flags == ["a", "b"] && sA.flags == ["a"] && !sB.clean
#guard (armFor comb [sA, sB] "a").map (·.id) == some "A" && (armFor comb [sA, sB] "b").isNone
#guard (table tb0 comb [sA, sB]).length == 26
#guard ((table tb0 comb [sA, sB]).filter (·.type == "trace.Layout.dirtyObjects")).map (verdict ·.cell)
  == [.notComparable (.missing ["b"]), .notComparable (.missing ["b"])]
#guard (verdict (cellAt tb0 comb [sA, { sA with id := "B2", arm := [run1 ["s", "b"] 7] }] (some "y0")
  "trace.Layout.dirtyObjects")) == .composes
#guard (verdict (cellAt tb0 comb [sA] (some "y0") "trace.Layout.dirtyObjects")) == .notComparable (.missing ["b"])
#guard classIn tb0 "trace.Paint" == .quarantined

end Fw.Measure.Compose
