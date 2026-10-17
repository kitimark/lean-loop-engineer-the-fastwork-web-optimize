import Fw.Measure.Zones
import Fw.Measure.Freeze
/-!
# The cross-run zone baseline (op `measure.zoneBaseline`, task zone-baseline-lean)

The counts lane records each run of the original as per-zone sums (`zoneSums`). A *baseline*
combines `n ≥ 3` such runs, one cell per zone and count type, and one whole-run cell per type:

* `perRun`: the cell's value in each run, in run order (a type a zone of a run does not list is 0);
* `lo`, `hi`: the smallest and largest of them;
* `base`: the value at index `⌊(n − 1)/2⌋` (0-based) of the ascending sort, the lower median, which
  is one of the observed values (`base_mem`);
* `cls`: the type's entry in the frozen class table (`none` = *unlisted*, which the rule treats as
  quarantined, as `Freeze.levelIn` does).

A cell whose type is frozen `deterministic` but whose runs disagree (`lo ≠ hi`) is listed in
`detDrift` (zone cells) or `detDriftTotals` (whole-run cells).

Runs are refused (`refusal`) when there are fewer than 3, when two share an id, when a run lists a
zone id twice, or when the zone structure differs (id, frames, scrolled px, first and last frame of
every zone, in order).

Proved: a deterministic cell has `lo = hi` or is in the drift list (`det_lo_eq_hi_or_drift`,
`det_total_lo_eq_hi_or_drift`), and runs with equal zones have no drift (`detDrift_nil_of_equal`);
the whole-run total of each run is the sum of its zone cells (`totals_eq_sum_zones`) and, for zones
built by `zoneSums`, the sum over its frames (`total_zoneSums`); `lo ≤ base ≤ hi` (`lo_le_base`,
`base_le_hi`); and the baseline does not depend on the order of the runs (`baseline_perm`).
-/
namespace Fw.Measure.ZoneBaseline
open Fw.Measure Fw.Measure.Freeze

/-! ## Order statistics of one cell -/

/-- The values of one cell sorted ascending (core's merge sort with `≤`).

$$\forall v \in \mathbb{Z}^{*}:\quad \operatorname{sort}(v) = \text{the ascending rearrangement of } v$$
-/
def sortInts (l : List Int) : List Int := l.mergeSort (fun a b => decide (a ≤ b))

/-- The smallest value of a cell (0 for no runs).

$$\forall v \in \mathbb{Z}^{*}:\quad \operatorname{lo}(v) = \begin{cases} s_0 & |v| \ge 1 \\ 0 & |v| = 0 \end{cases},\quad (s_0, \dots, s_{|v|-1}) = \operatorname{sort}(v)$$
-/
def lo (l : List Int) : Int := (sortInts l).headD 0

/-- The largest value of a cell (0 for no runs).

$$\forall v \in \mathbb{Z}^{*}:\quad \operatorname{hi}(v) = \begin{cases} s_{|v|-1} & |v| \ge 1 \\ 0 & |v| = 0 \end{cases},\quad (s_0, \dots, s_{|v|-1}) = \operatorname{sort}(v)$$
-/
def hi (l : List Int) : Int := (sortInts l).reverse.headD 0

/-- **The base value** of a cell: the sorted value at index `⌊(n − 1)/2⌋` (the lower median; 0 for no
runs).

$$\forall v \in \mathbb{Z}^{*}:\quad \operatorname{base}(v) = \begin{cases} s_{\lfloor (|v| - 1)/2 \rfloor} & |v| \ge 1 \\ 0 & |v| = 0 \end{cases},\quad (s_0, \dots, s_{|v|-1}) = \operatorname{sort}(v)$$
-/
def base (l : List Int) : Int := (sortInts l).getD ((l.length - 1) / 2) 0

#guard lo [5, 3, 9] == 3 && hi [5, 3, 9] == 9 && base [5, 3, 9] == 5
#guard base [4, 1, 3, 2] == 2 && base [7] == 7 && base [] == 0 && lo [] == 0 && hi [] == 0

/-- The sorted list is sorted.

$$\forall v:\quad \operatorname{sort}(v) = (s_0, \dots, s_{m}) \;\Rightarrow\; \forall i < j \le m:\ s_i \le s_j$$
-/
theorem sortInts_pairwise (l : List Int) : (sortInts l).Pairwise (· ≤ ·) :=
  (List.pairwise_mergeSort (le := fun a b : Int => decide (a ≤ b))
    (by intro a b c h1 h2; simp only [decide_eq_true_eq] at *; omega)
    (by intro a b; simp only [Bool.or_eq_true, decide_eq_true_eq]; omega) l).imp
    (by intro a b h; simpa using h)

/-- Sorting rearranges.

$$\forall v:\quad \operatorname{sort}(v) \text{ is a permutation of } v$$
-/
theorem sortInts_perm (l : List Int) : (sortInts l).Perm l := List.mergeSort_perm _ _

/-- **Sorting forgets the order.** Two rearrangements of each other sort to the same list.

$$\forall v, w:\quad v \text{ is a permutation of } w \;\Rightarrow\; \operatorname{sort}(v) = \operatorname{sort}(w)$$
-/
theorem sortInts_eq_of_perm {l₁ l₂ : List Int} (h : l₁.Perm l₂) : sortInts l₁ = sortInts l₂ :=
  List.Perm.eq_of_pairwise (le := (· ≤ ·)) (fun _ _ _ _ h1 h2 => Int.le_antisymm h1 h2)
    (sortInts_pairwise _) (sortInts_pairwise _)
    ((sortInts_perm _).trans (h.trans (sortInts_perm _).symm))

/-- The head of a list sorted by a reflexive relation is related to every member.

$$\forall R, s:\quad (\forall a:\ a \mathrel{R} a) \land (\forall i < j:\ s_i \mathrel{R} s_j) \;\Rightarrow\; \forall x \in s:\ \operatorname{headD}(s, 0) \mathrel{R} x$$
-/
theorem headD_rel {R : Int → Int → Prop} (refl : ∀ a, R a a) :
    ∀ {s : List Int}, s.Pairwise R → ∀ x ∈ s, R (s.headD 0) x
  | [], _, x, hx => by simp at hx
  | a :: t, hp, x, hx => by
    show R a x
    rcases List.mem_cons.mp hx with rfl | h
    · exact refl _
    · exact List.rel_of_pairwise_cons hp h

/-- `lo` is at most every value.

$$\forall v, x:\quad x \in v \;\Rightarrow\; \operatorname{lo}(v) \le x$$
-/
theorem lo_le {l : List Int} {x : Int} (hx : x ∈ l) : lo l ≤ x :=
  headD_rel (fun a => Int.le_refl a) (sortInts_pairwise l) x ((sortInts_perm l).mem_iff.mpr hx)

/-- `hi` is at least every value.

$$\forall v, x:\quad x \in v \;\Rightarrow\; x \le \operatorname{hi}(v)$$
-/
theorem le_hi {l : List Int} {x : Int} (hx : x ∈ l) : x ≤ hi l :=
  headD_rel (R := fun a b => b ≤ a) (fun a => Int.le_refl a)
    (List.pairwise_reverse.mpr (sortInts_pairwise l)) x
    (List.mem_reverse.mpr ((sortInts_perm l).mem_iff.mpr hx))

/-- The head of a non-empty list is a member.

$$\forall s:\quad s \ne [\,] \;\Rightarrow\; \operatorname{headD}(s, 0) \in s$$
-/
theorem headD_mem : ∀ {s : List Int}, s ≠ [] → s.headD 0 ∈ s
  | [], h => absurd rfl h
  | _ :: _, _ => List.mem_cons_self

/-- `lo` is an observed value when there is one.

$$\forall v:\quad v \ne [\,] \;\Rightarrow\; \operatorname{lo}(v) \in v$$
-/
theorem lo_mem {l : List Int} (h : l ≠ []) : lo l ∈ l := by
  have hs : sortInts l ≠ [] := fun e => h (List.Perm.eq_nil ((sortInts_perm l).symm.trans (e ▸ List.Perm.refl _)))
  exact (sortInts_perm l).mem_iff.mp (headD_mem hs)

/-- `hi` is an observed value when there is one.

$$\forall v:\quad v \ne [\,] \;\Rightarrow\; \operatorname{hi}(v) \in v$$
-/
theorem hi_mem {l : List Int} (h : l ≠ []) : hi l ∈ l := by
  have hs : (sortInts l).reverse ≠ [] := by
    intro e
    exact h (List.Perm.eq_nil ((sortInts_perm l).symm.trans (List.reverse_eq_nil_iff.mp e ▸ List.Perm.refl _)))
  exact (sortInts_perm l).mem_iff.mp (List.mem_reverse.mp (headD_mem hs))

/-- **`base` is an observed value** when there is one (a real run total, not an interpolation).

$$\forall v:\quad v \ne [\,] \;\Rightarrow\; \operatorname{base}(v) \in v$$
-/
theorem base_mem {l : List Int} (h : l ≠ []) : base l ∈ l := by
  have hlen : (sortInts l).length = l.length := (sortInts_perm l).length_eq
  have hpos : 0 < l.length := List.length_pos_iff.mpr h
  have hi' : (l.length - 1) / 2 < (sortInts l).length := by omega
  unfold base
  rw [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hi']
  exact (sortInts_perm l).mem_iff.mp (List.getElem_mem hi')

/-- **`lo ≤ base`.**

$$\forall v \in \mathbb{Z}^{*}:\quad \operatorname{lo}(v) \le \operatorname{base}(v)$$
-/
theorem lo_le_base (l : List Int) : lo l ≤ base l := by
  by_cases h : l = []
  · subst h; simp [lo, base, sortInts]
  · exact lo_le (base_mem h)

/-- **`base ≤ hi`.**

$$\forall v \in \mathbb{Z}^{*}:\quad \operatorname{base}(v) \le \operatorname{hi}(v)$$
-/
theorem base_le_hi (l : List Int) : base l ≤ hi l := by
  by_cases h : l = []
  · subst h; simp [hi, base, sortInts]
  · exact le_hi (base_mem h)

/-- **`lo = hi` exactly when all runs agree.**

$$\forall v \in \mathbb{Z}^{*}:\quad \operatorname{lo}(v) = \operatorname{hi}(v) \iff \forall x, y \in v:\ x = y$$
-/
theorem lo_eq_hi_iff (l : List Int) : lo l = hi l ↔ ∀ x ∈ l, ∀ y ∈ l, x = y := by
  constructor
  · intro h x hx y hy
    have := lo_le hx; have := le_hi hx; have := lo_le hy; have := le_hi hy; omega
  · intro h
    by_cases hl : l = []
    · subst hl; simp [lo, hi, sortInts]
    · exact h _ (lo_mem hl) _ (hi_mem hl)

/-- **The order statistics do not depend on the run order.**

$$\forall v, w:\quad v \text{ is a permutation of } w \;\Rightarrow\; \operatorname{lo}(v) = \operatorname{lo}(w) \land \operatorname{hi}(v) = \operatorname{hi}(w) \land \operatorname{base}(v) = \operatorname{base}(w)$$
-/
theorem stats_perm {l₁ l₂ : List Int} (h : l₁.Perm l₂) :
    lo l₁ = lo l₂ ∧ hi l₁ = hi l₂ ∧ base l₁ = base l₂ := by
  have e := sortInts_eq_of_perm h
  refine ⟨by simp [lo, e], by simp [hi, e], ?_⟩
  simp [base, e, h.length_eq]

/-! ## Runs, cells and the baseline -/

/-- One run: its id and its zone records (the output of `zoneSums` for that run).

$$\mathrm{ZRun} = \Sigma^{*} \times \mathrm{Zone}^{*}$$
-/
structure ZRun where
  id : String
  zones : List Zone
deriving Repr, DecidableEq

/-- The structure of a zone: id, frames, scrolled px, first and last frame (no sums).

$$\forall z:\quad \operatorname{shape}(z) = (z.\mathrm{id}, z.\mathrm{frames}, z.\mathrm{scrolledPx}, z.\mathrm{firstFrame}, z.\mathrm{lastFrame})$$
-/
def shape (z : Zone) : String × Nat × Int × Nat × Nat := (z.id, z.frames, z.scrolledPx, z.firstFrame, z.lastFrame)

/-- All runs have the same zone structure (the same shapes in the same order).

$$\forall \mathcal{R}:\quad \operatorname{Uniform}(\mathcal{R}) \iff \forall r, r' \in \mathcal{R}:\ [\operatorname{shape}(z)]_{z \in r.\mathrm{zones}} = [\operatorname{shape}(z)]_{z \in r'.\mathrm{zones}}$$
-/
def Uniform (rs : List ZRun) : Prop := ∀ r ∈ rs, ∀ r' ∈ rs, r.zones.map shape = r'.zones.map shape

/-- The values of zone `Z` and type `τ` in each run, in run order (`sumAt`: 0 when the zone or the
type is missing).

$$\forall \mathcal{R}, Z, \tau:\quad \operatorname{vals}(\mathcal{R}, Z, \tau) = [\operatorname{sumAt}(r.\mathrm{zones}, Z, \tau)]_{r \in \mathcal{R}}$$
-/
def vals (rs : List ZRun) (Z ty : String) : List Int := rs.map fun r => sumAt r.zones Z ty

/-- The whole-run total of type `τ` in a run's zone list: the sum over its zones.

$$\forall Zs, \tau:\quad \operatorname{total}(Zs, \tau) = \sum_{z \in Zs} \operatorname{sum}(z, \tau)$$
-/
def total (zs : List Zone) (ty : String) : Int := sumBy (·.sum ty) zs

/-- The whole-run totals of type `τ`, in run order.

$$\forall \mathcal{R}, \tau:\quad \operatorname{tvals}(\mathcal{R}, \tau) = [\operatorname{total}(r.\mathrm{zones}, \tau)]_{r \in \mathcal{R}}$$
-/
def totalVals (rs : List ZRun) (ty : String) : List Int := rs.map fun r => total r.zones ty

/-- The sums listed by zone `Z` of a run's zone list (none if the zone is missing).

$$\forall Zs, Z:\quad \operatorname{sumsAt}(Zs, Z) = \begin{cases} z.\mathrm{sums} & \operatorname{find}(Zs, Z) = z \\ [\,] & \text{none} \end{cases}$$
-/
def sumsAt (zs : List Zone) (Z : String) : List (String × Int) := ((findZone zs Z).map (·.sums)).getD []

/-- The types of zone `Z`: those listed by zone `Z` in at least one run (sorted, distinct).

$$\forall \mathcal{R}, Z:\quad \operatorname{types}(\mathcal{R}, Z) = \operatorname{keys}\big([\operatorname{sumsAt}(r.\mathrm{zones}, Z)]_{r \in \mathcal{R}}\big)$$
-/
def zoneTypes (rs : List ZRun) (Z : String) : List String := keysOf (rs.map fun r => sumsAt r.zones Z)

/-- The types of the whole runs: those listed by any zone of any run (sorted, distinct).

$$\forall \mathcal{R}:\quad \operatorname{types}(\mathcal{R}) = \operatorname{keys}\big([z.\mathrm{sums}]_{r \in \mathcal{R},\ z \in r.\mathrm{zones}}\big)$$
-/
def allTypes (rs : List ZRun) : List String := keysOf (rs.flatMap fun r => r.zones.map (·.sums))

/-- The zone ids of the baseline: those of the first run (all runs share them under `Uniform`).

$$\forall r, \mathcal{R}:\quad \operatorname{ids}([\,]) = [\,],\quad \operatorname{ids}(r :: \mathcal{R}) = [z.\mathrm{id}]_{z \in r.\mathrm{zones}}$$
-/
def ids : List ZRun → List String
  | [] => []
  | r :: _ => zoneIds r.zones

/-- One cell of the baseline: type, frozen-table entry (`none` = unlisted), values per run in run
order, `lo`, `hi`, `base`.

$$\mathrm{Row} = \Sigma^{*} \times (\mathrm{Entry} \cup \{\bot\}) \times \mathbb{Z}^{*} \times \mathbb{Z} \times \mathbb{Z} \times \mathbb{Z}$$
-/
structure Row where
  type : String
  cls : Option Entry
  perRun : List Int
  lo : Int
  hi : Int
  base : Int
deriving Repr, DecidableEq

/-- The cell of type `τ` with values `v`, its class looked up in the frozen table `T`.

$$\forall T, v, \tau:\quad \operatorname{row}_T(v, \tau) = (\tau,\ \operatorname{entry}(T, \tau),\ v,\ \operatorname{lo}(v),\ \operatorname{hi}(v),\ \operatorname{base}(v))$$
-/
def row (tb : Table) (vs : List Int) (ty : String) : Row :=
  { type := ty, cls := entry? tb ty, perRun := vs, lo := lo vs, hi := hi vs, base := base vs }

/-- A row without its per-run values (what does not depend on the run order).

$$\forall \rho:\quad \operatorname{summary}(\rho) = (\rho.\mathrm{type}, \rho.\mathrm{cls}, \rho.\mathrm{lo}, \rho.\mathrm{hi}, \rho.\mathrm{base})$$
-/
def Row.summary (r : Row) : String × Option Entry × Int × Int × Int := (r.type, r.cls, r.lo, r.hi, r.base)

/-- Whether a class-table entry is deterministic (an unlisted type is not).

$$\forall o:\quad \operatorname{isDet}(o) \iff \exists e:\ o = \mathrm{some}(e) \land e.\mathrm{cls} = \mathrm{det}$$
-/
def isDet : Option Entry → Bool
  | some e => e.cls == .det
  | none => false

/-- **Drift**: a deterministic cell whose runs disagree.

$$\forall \rho:\quad \operatorname{drifts}(\rho) \iff \operatorname{isDet}(\rho.\mathrm{cls}) \land \rho.\mathrm{lo} \ne \rho.\mathrm{hi}$$
-/
def drifts (r : Row) : Bool := isDet r.cls && r.lo != r.hi

/-- The cells of zone `Z`, one per type of the zone.

$$\forall T, \mathcal{R}, Z:\quad \operatorname{rows}_T(\mathcal{R}, Z) = [\operatorname{row}_T(\operatorname{vals}(\mathcal{R}, Z, \tau), \tau)]_{\tau \in \operatorname{types}(\mathcal{R}, Z)}$$
-/
def zoneRows (tb : Table) (rs : List ZRun) (Z : String) : List Row :=
  (zoneTypes rs Z).map fun ty => row tb (vals rs Z ty) ty

/-- The whole-run cells, one per type of the runs.

$$\forall T, \mathcal{R}:\quad \operatorname{totals}_T(\mathcal{R}) = [\operatorname{row}_T(\operatorname{tvals}(\mathcal{R}, \tau), \tau)]_{\tau \in \operatorname{types}(\mathcal{R})}$$
-/
def totalRows (tb : Table) (rs : List ZRun) : List Row :=
  (allTypes rs).map fun ty => row tb (totalVals rs ty) ty

/-- The baseline: the cells of every zone, the whole-run cells and the drifting cells.

$$\mathrm{Baseline} = (\Sigma^{*} \times \mathrm{Row}^{*})^{*} \times \mathrm{Row}^{*} \times (\Sigma^{*} \times \Sigma^{*})^{*} \times (\Sigma^{*})^{*}$$
-/
structure Baseline where
  zones : List (String × List Row)
  totals : List Row
  detDrift : List (String × String)
  detDriftTotals : List String
deriving Repr, DecidableEq

/-- **The zone baseline** of runs `𝓡` against the frozen table `T`.

$$\forall T, \mathcal{R}:\quad \operatorname{baseline}_T(\mathcal{R}) = \Big(\big[(Z, \operatorname{rows}_T(\mathcal{R}, Z))\big]_{Z \in \operatorname{ids}(\mathcal{R})},\ \operatorname{totals}_T(\mathcal{R}),\ \big[(Z, \rho.\mathrm{type}) \mid Z \in \operatorname{ids}(\mathcal{R}),\ \rho \in \operatorname{rows}_T(\mathcal{R}, Z),\ \operatorname{drifts}(\rho)\big],\ \big[\rho.\mathrm{type} \mid \rho \in \operatorname{totals}_T(\mathcal{R}),\ \operatorname{drifts}(\rho)\big]\Big)$$
-/
def baseline (tb : Table) (rs : List ZRun) : Baseline :=
  { zones := (ids rs).map fun Z => (Z, zoneRows tb rs Z),
    totals := totalRows tb rs,
    detDrift := (ids rs).flatMap fun Z => ((zoneRows tb rs Z).filter drifts).map fun r => (Z, r.type),
    detDriftTotals := ((totalRows tb rs).filter drifts).map (·.type) }

/-- Why the runs are refused, if they are: fewer than 3 runs, a repeated run id, a repeated zone id
in the first run, or a run whose zone structure differs from the first run's.

$$\forall \mathcal{R}:\quad \operatorname{refusal}(\mathcal{R}) = \bot \iff |\mathcal{R}| \ge 3 \land [r.\mathrm{id}]_{r \in \mathcal{R}} \text{ distinct} \land \operatorname{ids}(\mathcal{R}) \text{ distinct} \land \forall r \in \mathcal{R}:\ [\operatorname{shape}(z)]_{z \in r.\mathrm{zones}} = [\operatorname{shape}(z)]_{z \in \mathcal{R}_1.\mathrm{zones}}$$
-/
def refusal : List ZRun → Option String
  | [] => some "need at least three runs"
  | r :: rest =>
    if rest.length < 2 then some "need at least three runs"
    else if !((r :: rest).map (·.id)).Nodup then some "run ids must be distinct"
    else if !(zoneIds r.zones).Nodup then some s!"run {r.id}: a zone id occurs twice"
    else match rest.find? (fun r' => r'.zones.map shape != r.zones.map shape) with
      | some r' => some s!"run {r'.id}: zone structure (id, frames, scrolledPx, firstFrame, lastFrame) differs from run {r.id}"
      | none => none

/-- **The op**: the baseline, or the refusal.

$$\forall T, \mathcal{R}:\quad \operatorname{zoneBaseline}_T(\mathcal{R}) = \begin{cases} \operatorname{error}(e) & \operatorname{refusal}(\mathcal{R}) = e \\ \operatorname{baseline}_T(\mathcal{R}) & \operatorname{refusal}(\mathcal{R}) = \bot \end{cases}$$
-/
def zoneBaseline (tb : Table) (rs : List ZRun) : Except String Baseline :=
  match refusal rs with
  | some e => .error e
  | none => .ok (baseline tb rs)

private def z (id : String) (s : List (String × Int)) : Zone := ⟨id, 1, 0, 0, 0, s⟩
private def tbl : Table := [("a", ⟨.det, 0, 0, none⟩), ("b", ⟨.stable, 1, 1, none⟩)]

#guard (refusal [⟨"1", [z "rest" []]⟩, ⟨"2", [z "rest" []]⟩]).isSome
#guard (refusal [⟨"1", [z "rest" []]⟩, ⟨"1", [z "rest" []]⟩, ⟨"3", [z "rest" []]⟩]).isSome
#guard (refusal [⟨"1", [z "rest" []]⟩, ⟨"2", [z "rest" []]⟩, ⟨"3", [z "tail" []]⟩]).isSome
#guard (refusal [⟨"1", [z "rest" [], z "rest" []]⟩, ⟨"2", [z "rest" [], z "rest" []]⟩, ⟨"3", [z "rest" [], z "rest" []]⟩]).isSome
#guard (refusal [⟨"1", [z "rest" [("a", 1)]]⟩, ⟨"2", [z "rest" [("a", 2)]]⟩, ⟨"3", [z "rest" []]⟩]).isNone
#guard (baseline tbl [⟨"1", [z "rest" [("a", 1), ("b", 5)]]⟩, ⟨"2", [z "rest" [("a", 2), ("b", 4)]]⟩,
    ⟨"3", [z "rest" [("a", 1), ("c", 9)]]⟩]).detDrift == [("rest", "a")]
#guard (baseline tbl [⟨"1", [z "rest" [("a", 1), ("b", 5)]]⟩, ⟨"2", [z "rest" [("a", 2), ("b", 4)]]⟩,
    ⟨"3", [z "rest" [("a", 1), ("c", 9)]]⟩]).totals.map (fun r => (r.type, r.perRun, r.base)) ==
    [("a", [1, 2, 1], 1), ("b", [5, 4, 0], 4), ("c", [0, 0, 9], 0)]

/-! ## Laws -/

/-- What `refusal` checks, when it does not refuse.

$$\forall \mathcal{R}:\quad \operatorname{refusal}(\mathcal{R}) = \bot \;\Rightarrow\; |\mathcal{R}| \ge 3 \land [r.\mathrm{id}]_{r \in \mathcal{R}} \text{ distinct} \land \operatorname{Uniform}(\mathcal{R}) \land \forall r \in \mathcal{R}:\ [z.\mathrm{id}]_{z \in r.\mathrm{zones}} \text{ distinct}$$
-/
theorem refusal_none {rs : List ZRun} (h : refusal rs = none) :
    3 ≤ rs.length ∧ (rs.map (·.id)).Nodup ∧ Uniform rs ∧ ∀ r ∈ rs, (zoneIds r.zones).Nodup := by
  match rs, h with
  | r :: rest, h =>
    simp only [refusal] at h
    split at h
    · exact absurd h (by simp)
    split at h
    · exact absurd h (by simp)
    split at h
    · exact absurd h (by simp)
    split at h
    · exact absurd h (by simp)
    rename_i hlen hid hz _ hf
    simp only [Bool.not_eq_true', decide_eq_false_iff_not, Classical.not_not] at hid hz
    have same : ∀ r' ∈ r :: rest, r'.zones.map shape = r.zones.map shape := by
      intro r' hr'
      rcases List.mem_cons.mp hr' with rfl | hr'
      · rfl
      · have := List.find?_eq_none.mp hf r' hr'
        simpa using this
    refine ⟨by simp; omega, hid, fun a ha b hb => (same a ha).trans (same b hb).symm, ?_⟩
    intro r' hr'
    have e : zoneIds r'.zones = zoneIds r.zones := by
      have := congrArg (List.map (·.1)) (same r' hr')
      simpa [zoneIds, shape, List.map_map, Function.comp_def] using this
    rw [e]; exact hz

/-- **The op answers exactly the baseline** when it does not refuse.

$$\forall T, \mathcal{R}, B:\quad \operatorname{zoneBaseline}_T(\mathcal{R}) = \operatorname{ok}(B) \;\Rightarrow\; B = \operatorname{baseline}_T(\mathcal{R}) \land |\mathcal{R}| \ge 3 \land [r.\mathrm{id}]_{r \in \mathcal{R}} \text{ distinct} \land \operatorname{Uniform}(\mathcal{R}) \land \forall r \in \mathcal{R}:\ [z.\mathrm{id}]_{z \in r.\mathrm{zones}} \text{ distinct}$$
-/
theorem zoneBaseline_ok {tb : Table} {rs : List ZRun} {b : Baseline} (h : zoneBaseline tb rs = .ok b) :
    b = baseline tb rs ∧ 3 ≤ rs.length ∧ (rs.map (·.id)).Nodup ∧ Uniform rs ∧
      ∀ r ∈ rs, (zoneIds r.zones).Nodup := by
  unfold zoneBaseline at h
  split at h
  · cases h
  · rename_i hr
    cases h
    exact ⟨rfl, refusal_none hr⟩

/-! ### Deterministic cells -/

/-- Membership in the zone drift list.

$$\forall T, \mathcal{R}, Z, \tau:\quad (Z, \tau) \in \operatorname{baseline}_T(\mathcal{R}).\mathrm{detDrift} \iff Z \in \operatorname{ids}(\mathcal{R}) \land \exists \rho \in \operatorname{rows}_T(\mathcal{R}, Z):\ \rho.\mathrm{type} = \tau \land \operatorname{drifts}(\rho)$$
-/
theorem mem_detDrift (tb : Table) (rs : List ZRun) (Z ty : String) :
    (Z, ty) ∈ (baseline tb rs).detDrift ↔
      Z ∈ ids rs ∧ ∃ r ∈ zoneRows tb rs Z, r.type = ty ∧ drifts r = true := by
  simp only [baseline, List.mem_flatMap, List.mem_map, List.mem_filter, Prod.mk.injEq]
  constructor
  · rintro ⟨Z', hZ', r, ⟨hr, hd⟩, rfl, rfl⟩
    exact ⟨hZ', r, hr, rfl, hd⟩
  · rintro ⟨hZ, r, hr, rfl, hd⟩
    exact ⟨Z, hZ, r, ⟨hr, hd⟩, rfl, rfl⟩

/-- **Deterministic zone cells: `lo = hi` or listed.** Every zone cell whose type the frozen table
lists as deterministic has `lo = hi`, or its (zone, type) is in `detDrift`.

$$\forall T, \mathcal{R}:\ \forall (Z, P) \in \operatorname{baseline}_T(\mathcal{R}).\mathrm{zones}:\ \forall \rho \in P:\quad \operatorname{isDet}(\rho.\mathrm{cls}) \;\Rightarrow\; \rho.\mathrm{lo} = \rho.\mathrm{hi} \lor (Z, \rho.\mathrm{type}) \in \operatorname{baseline}_T(\mathcal{R}).\mathrm{detDrift}$$
-/
theorem det_lo_eq_hi_or_drift (tb : Table) (rs : List ZRun) :
    ∀ zr ∈ (baseline tb rs).zones, ∀ r ∈ zr.2, isDet r.cls = true →
      r.lo = r.hi ∨ (zr.1, r.type) ∈ (baseline tb rs).detDrift := by
  intro zr hzr r hr hdet
  by_cases e : r.lo = r.hi
  · exact Or.inl e
  · right
    have hzr' := hzr
    simp only [baseline, List.mem_map] at hzr'
    obtain ⟨Z, hZ, rfl⟩ := hzr'
    rw [mem_detDrift]
    exact ⟨hZ, r, hr, rfl, by simp [drifts, hdet, e]⟩

/-- **Deterministic whole-run cells: `lo = hi` or listed.**

$$\forall T, \mathcal{R}:\ \forall \rho \in \operatorname{baseline}_T(\mathcal{R}).\mathrm{totals}:\quad \operatorname{isDet}(\rho.\mathrm{cls}) \;\Rightarrow\; \rho.\mathrm{lo} = \rho.\mathrm{hi} \lor \rho.\mathrm{type} \in \operatorname{baseline}_T(\mathcal{R}).\mathrm{detDriftTotals}$$
-/
theorem det_total_lo_eq_hi_or_drift (tb : Table) (rs : List ZRun) :
    ∀ r ∈ (baseline tb rs).totals, isDet r.cls = true →
      r.lo = r.hi ∨ r.type ∈ (baseline tb rs).detDriftTotals := by
  intro r hr hdet
  by_cases e : r.lo = r.hi
  · exact Or.inl e
  · right
    simp only [baseline, List.mem_map, List.mem_filter]
    exact ⟨r, ⟨hr, by simp [drifts, hdet, e]⟩, rfl⟩

/-- A list of copies of one value has `lo = hi`.

$$\forall v, c:\quad (\forall x \in v:\ x = c) \;\Rightarrow\; \operatorname{lo}(v) = \operatorname{hi}(v)$$
-/
theorem lo_eq_hi_of_const {l : List Int} {c : Int} (h : ∀ x ∈ l, x = c) : lo l = hi l :=
  (lo_eq_hi_iff l).mpr fun x hx y hy => (h x hx).trans (h y hy).symm

/-- **Equal runs never drift.** When every run has the same zone list, no cell drifts.

$$\forall T, \mathcal{R}, Zs:\quad (\forall r \in \mathcal{R}:\ r.\mathrm{zones} = Zs) \;\Rightarrow\; \operatorname{baseline}_T(\mathcal{R}).\mathrm{detDrift} = [\,] \land \operatorname{baseline}_T(\mathcal{R}).\mathrm{detDriftTotals} = [\,]$$
-/
theorem detDrift_nil_of_equal (tb : Table) (rs : List ZRun) (zs : List Zone) (h : ∀ r ∈ rs, r.zones = zs) :
    (baseline tb rs).detDrift = [] ∧ (baseline tb rs).detDriftTotals = [] := by
  constructor
  · apply List.eq_nil_iff_forall_not_mem.mpr
    rintro ⟨Z, ty⟩ hm
    obtain ⟨_, r, hr, _, hd⟩ := (mem_detDrift tb rs Z ty).mp hm
    simp only [zoneRows, List.mem_map] at hr
    obtain ⟨ty', _, rfl⟩ := hr
    have : lo (vals rs Z ty') = hi (vals rs Z ty') := lo_eq_hi_of_const (c := sumAt zs Z ty') (by
      intro x hx
      simp only [vals, List.mem_map] at hx
      obtain ⟨r, hr, rfl⟩ := hx
      rw [h r hr])
    simp [drifts, row, this] at hd
  · apply List.eq_nil_iff_forall_not_mem.mpr
    intro ty hm
    simp only [baseline, List.mem_map, List.mem_filter, totalRows] at hm
    obtain ⟨_, ⟨⟨ty', _, rfl⟩, hd⟩, _⟩ := hm
    have : lo (totalVals rs ty') = hi (totalVals rs ty') := lo_eq_hi_of_const (c := total zs ty') (by
      intro x hx
      simp only [totalVals, List.mem_map] at hx
      obtain ⟨r, hr, rfl⟩ := hx
      rw [h r hr])
    simp [drifts, row, this] at hd

/-! ### Totals are sums over zones -/

/-- With distinct zone ids, summing `sumAt` over the ids is summing over the zones.

$$\forall Zs, \tau:\quad [z.\mathrm{id}]_{z \in Zs} \text{ distinct} \;\Rightarrow\; \sum_{Z \in [z.\mathrm{id}]_{z \in Zs}} \operatorname{sumAt}(Zs, Z, \tau) = \sum_{z \in Zs} \operatorname{sum}(z, \tau)$$
-/
theorem sumBy_sumAt_ids (ty : String) : ∀ zs : List Zone, (zoneIds zs).Nodup →
    sumBy (fun Z => sumAt zs Z ty) (zoneIds zs) = sumBy (·.sum ty) zs
  | [], _ => rfl
  | z :: zs, hn => by
    simp only [zoneIds, List.map_cons, List.nodup_cons] at hn
    have ih := sumBy_sumAt_ids ty zs hn.2
    simp only [zoneIds, List.map_cons, sumBy]
    have h1 : sumAt (z :: zs) z.id ty = z.sum ty := by simp [sumAt, findZone]
    have h2 : sumBy (fun Z => sumAt (z :: zs) Z ty) (zs.map (·.id)) = sumBy (fun Z => sumAt zs Z ty) (zs.map (·.id)) := by
      apply sumBy_congr
      intro Z hZ
      have hne : (z.id == Z) = false := by
        simp only [beq_eq_false_iff_ne]; intro e; exact hn.1 (e ▸ hZ)
      simp [sumAt, findZone, hne]
    rw [h1, h2]
    simp only [zoneIds] at ih
    rw [ih]

/-- Under `Uniform`, every run has the baseline's zone ids.

$$\forall \mathcal{R}:\quad \operatorname{Uniform}(\mathcal{R}) \;\Rightarrow\; \forall r \in \mathcal{R}:\ [z.\mathrm{id}]_{z \in r.\mathrm{zones}} = \operatorname{ids}(\mathcal{R})$$
-/
theorem zoneIds_eq_ids {rs : List ZRun} (hu : Uniform rs) : ∀ r ∈ rs, zoneIds r.zones = ids rs := by
  intro r hr
  match rs, hu, hr with
  | r₀ :: rest, hu, hr =>
    have := congrArg (List.map (·.1)) (hu r hr r₀ List.mem_cons_self)
    simpa [ids, zoneIds, shape, List.map_map, Function.comp_def] using this

/-- **Totals are sums over the zones.** For runs the op accepts, each run's whole-run total of a
type is the sum, over the baseline's zone ids, of that run's zone values.

$$\forall \mathcal{R}, \tau:\quad \operatorname{Uniform}(\mathcal{R}) \land (\forall r \in \mathcal{R}:\ [z.\mathrm{id}]_{z \in r.\mathrm{zones}} \text{ distinct}) \;\Rightarrow\; \operatorname{tvals}(\mathcal{R}, \tau) = \Big[\sum_{Z \in \operatorname{ids}(\mathcal{R})} \operatorname{sumAt}(r.\mathrm{zones}, Z, \tau)\Big]_{r \in \mathcal{R}}$$
-/
theorem totals_eq_sum_zones {rs : List ZRun} (hu : Uniform rs) (hn : ∀ r ∈ rs, (zoneIds r.zones).Nodup)
    (ty : String) :
    totalVals rs ty = rs.map fun r => sumBy (fun Z => sumAt r.zones Z ty) (ids rs) := by
  unfold totalVals
  apply List.map_congr_left
  intro r hr
  rw [← zoneIds_eq_ids hu r hr, sumBy_sumAt_ids ty r.zones (hn r hr)]
  rfl

/-- **Totals are frame sums** for zones built by `zoneSums`.

$$\forall h, F, \tau:\quad \operatorname{total}(\operatorname{zoneSums}_h(F), \tau) = \sum_{f \in F} c_f(\tau)$$
-/
theorem total_zoneSums (h : Nat) (fs : List Frame) (ty : String) :
    total (zoneSums h fs) ty = sumBy (fun f => f.count ty) fs :=
  zones_sum_total h 0 fs ty

/-- Membership in `keysOf`: a key occurs in one of the lists.

$$\forall C_1, \dots, C_m, x:\quad x \in \operatorname{keys}(C_1, \dots, C_m) \iff \exists i:\ x \in [j]_{(j, v) \in C_i}$$
-/
theorem mem_keysOf (x : String) : ∀ css : List Counts, x ∈ keysOf css ↔ ∃ cs ∈ css, x ∈ cs.map (·.1)
  | [] => by simp [keysOf]
  | cs :: css => by
    have hf : ∀ (l : Counts) (acc : List String),
        x ∈ l.foldr (fun p a => insKey p.1 a) acc ↔ x ∈ l.map (·.1) ∨ x ∈ acc := by
      intro l acc
      induction l with
      | nil => simp
      | cons p ps ih =>
        simp only [List.foldr_cons, mem_insKey, ih, List.map_cons, List.mem_cons]
        constructor
        · rintro (h | h | h) <;> simp [h]
        · rintro ((h | h) | h) <;> simp [h]
    simp only [keysOf, hf, mem_keysOf x css, List.mem_cons]
    constructor
    · rintro (h | ⟨c, hc, h⟩)
      · exact ⟨cs, Or.inl rfl, h⟩
      · exact ⟨c, Or.inr hc, h⟩
    · rintro ⟨c, (rfl | hc), h⟩
      · exact Or.inl h
      · exact Or.inr ⟨c, hc, h⟩

/-- `keysOf` membership is unchanged by reordering the lists.

$$\forall L, L', x:\quad L \text{ is a permutation of } L' \;\Rightarrow\; (x \in \operatorname{keys}(L) \iff x \in \operatorname{keys}(L'))$$
-/
theorem mem_keysOf_perm {css css' : List Counts} (h : css.Perm css') (x : String) :
    x ∈ keysOf css ↔ x ∈ keysOf css' := by
  rw [mem_keysOf, mem_keysOf]
  constructor
  · rintro ⟨c, hc, hx⟩; exact ⟨c, h.mem_iff.mp hc, hx⟩
  · rintro ⟨c, hc, hx⟩; exact ⟨c, h.mem_iff.mpr hc, hx⟩

/-- A type a zone lists in no run has the value 0 there in every run (so the zone cells of
`zoneRows` cover every nonzero value).

$$\forall \mathcal{R}, Z, \tau:\quad \tau \notin \operatorname{types}(\mathcal{R}, Z) \;\Rightarrow\; \forall x \in \operatorname{vals}(\mathcal{R}, Z, \tau):\ x = 0$$
-/
theorem vals_eq_zero_of_not_mem {rs : List ZRun} {Z ty : String} (h : ty ∉ zoneTypes rs Z) :
    ∀ x ∈ vals rs Z ty, x = 0 := by
  intro x hx
  simp only [vals, List.mem_map] at hx
  obtain ⟨r, hr, rfl⟩ := hx
  unfold sumAt
  cases hf : findZone r.zones Z with
  | none => rfl
  | some zz =>
    simp only [Option.map_some, Option.getD_some, Zone.sum]
    have hnot : ty ∉ zz.sums.map (·.1) := by
      intro hm
      apply h
      unfold zoneTypes
      rw [mem_keysOf]
      exact ⟨sumsAt r.zones Z, List.mem_map.mpr ⟨r, hr, rfl⟩, by simpa [sumsAt, hf] using hm⟩
    have hl : zz.sums.lookup ty = none := by
      rw [List.lookup_eq_none_iff]
      intro p hp
      simp only [bne_iff_ne, ne_eq]
      intro e
      exact hnot (List.mem_map.mpr ⟨p, hp, e.symm⟩)
    rw [hl]
    rfl

/-! ### Order independence -/

/-- The cell of zone `Z` and type `τ` in a baseline, if there is one.

$$\forall B, Z, \tau:\quad \operatorname{cellAt}(B, Z, \tau) = \text{the first } \rho \in P \text{ with } \rho.\mathrm{type} = \tau, \text{ for the first } (Z, P) \in B.\mathrm{zones};\ \bot \text{ if there is none}$$
-/
def cellAt (b : Baseline) (Z ty : String) : Option Row :=
  (b.zones.find? (·.1 == Z)).bind fun zr => zr.2.find? (·.type == ty)

/-- The whole-run cell of type `τ` in a baseline, if there is one.

$$\forall B, \tau:\quad \operatorname{totalAt}(B, \tau) = \text{the first } \rho \in B.\mathrm{totals} \text{ with } \rho.\mathrm{type} = \tau;\ \bot \text{ if there is none}$$
-/
def totalAt (b : Baseline) (ty : String) : Option Row := b.totals.find? (·.type == ty)

/-- Finding a string in a list by equality.

$$\forall L, x:\quad \operatorname{find}(L, x) = \begin{cases} x & x \in L \\ \bot & x \notin L \end{cases}$$
-/
theorem find?_beq (x : String) : ∀ l : List String, l.find? (· == x) = if x ∈ l then some x else none
  | [] => by simp
  | y :: ys => by
    by_cases e : y = x
    · subst e; simp
    · have : (y == x) = false := by simp [e]
      simp only [List.find?_cons, this, find?_beq x ys, List.mem_cons]
      by_cases hx : x ∈ ys
      · simp [hx]
      · simp [hx, Ne.symm e]

/-- A cell of a baseline is the row of its zone and type.

$$\forall T, \mathcal{R}, Z, \tau:\quad \operatorname{cellAt}(\operatorname{baseline}_T(\mathcal{R}), Z, \tau) = \begin{cases} \operatorname{row}_T(\operatorname{vals}(\mathcal{R}, Z, \tau), \tau) & Z \in \operatorname{ids}(\mathcal{R}) \land \tau \in \operatorname{types}(\mathcal{R}, Z) \\ \bot & \text{otherwise} \end{cases}$$
-/
theorem cellAt_baseline (tb : Table) (rs : List ZRun) (Z ty : String) :
    cellAt (baseline tb rs) Z ty =
      if Z ∈ ids rs ∧ ty ∈ zoneTypes rs Z then some (row tb (vals rs Z ty) ty) else none := by
  simp only [cellAt, baseline, List.find?_map, Function.comp_def]
  have h1 := find?_beq Z (ids rs)
  rw [h1]
  by_cases hZ : Z ∈ ids rs
  · simp only [hZ, ite_true, Option.map_some, Option.bind_some, zoneRows, List.find?_map, Function.comp_def,
      true_and]
    have h2 : (zoneTypes rs Z).find? (fun ty' => (row tb (vals rs Z ty') ty').type == ty) =
        (zoneTypes rs Z).find? (· == ty) := by
      congr 1
    rw [h2, find?_beq ty]
    by_cases hT : ty ∈ zoneTypes rs Z <;> simp [hT]
  · simp [hZ]

/-- A whole-run cell of a baseline is the row of its type.

$$\forall T, \mathcal{R}, \tau:\quad \operatorname{totalAt}(\operatorname{baseline}_T(\mathcal{R}), \tau) = \begin{cases} \operatorname{row}_T(\operatorname{tvals}(\mathcal{R}, \tau), \tau) & \tau \in \operatorname{types}(\mathcal{R}) \\ \bot & \text{otherwise} \end{cases}$$
-/
theorem totalAt_baseline (tb : Table) (rs : List ZRun) (ty : String) :
    totalAt (baseline tb rs) ty =
      if ty ∈ allTypes rs then some (row tb (totalVals rs ty) ty) else none := by
  simp only [totalAt, baseline, totalRows, List.find?_map, Function.comp_def]
  have h2 : (allTypes rs).find? (fun ty' => (row tb (totalVals rs ty') ty').type == ty) =
      (allTypes rs).find? (· == ty) := by
    congr 1
  rw [h2, find?_beq ty]
  by_cases hT : ty ∈ allTypes rs <;> simp [hT]

/-- The summary of a row depends on its values only up to their order.

$$\forall T, v, w, \tau:\quad v \text{ is a permutation of } w \;\Rightarrow\; \operatorname{summary}(\operatorname{row}_T(v, \tau)) = \operatorname{summary}(\operatorname{row}_T(w, \tau))$$
-/
theorem summary_row_perm (tb : Table) {v w : List Int} (h : v.Perm w) (ty : String) :
    (row tb v ty).summary = (row tb w ty).summary := by
  obtain ⟨a, b, c⟩ := stats_perm h
  simp [Row.summary, row, a, b, c]

/-- Under `Uniform`, the zone ids do not depend on which run comes first.

$$\forall \mathcal{R}, \mathcal{R}':\quad \mathcal{R} \text{ is a permutation of } \mathcal{R}' \land \operatorname{Uniform}(\mathcal{R}) \;\Rightarrow\; \operatorname{ids}(\mathcal{R}) = \operatorname{ids}(\mathcal{R}')$$
-/
theorem ids_perm {rs rs' : List ZRun} (h : rs.Perm rs') (hu : Uniform rs) : ids rs = ids rs' := by
  have hu' : Uniform rs' := fun a ha b hb => hu a (h.mem_iff.mpr ha) b (h.mem_iff.mpr hb)
  match rs', h with
  | [], h => rw [List.Perm.eq_nil h]
  | r' :: rest', h =>
    have hr : r' ∈ rs := h.mem_iff.mpr List.mem_cons_self
    rw [← zoneIds_eq_ids hu r' hr]
    rfl

/-- **Order independence.** Reordering accepted runs changes no zone id, no cell's presence, type,
class, `lo`, `hi` or `base`, and no drift-list membership; each cell's per-run values are reordered
the same way.

$$\forall T, \mathcal{R}, \mathcal{R}':\quad \mathcal{R} \text{ is a permutation of } \mathcal{R}' \land \operatorname{Uniform}(\mathcal{R}) \;\Rightarrow\; \operatorname{ids}(\mathcal{R}) = \operatorname{ids}(\mathcal{R}') \land \forall Z, \tau:\ \Big(\operatorname{summary}(\operatorname{cellAt}(B, Z, \tau)) = \operatorname{summary}(\operatorname{cellAt}(B', Z, \tau)) \land \operatorname{vals}(\mathcal{R}, Z, \tau) \text{ is a permutation of } \operatorname{vals}(\mathcal{R}', Z, \tau) \land \operatorname{summary}(\operatorname{totalAt}(B, \tau)) = \operatorname{summary}(\operatorname{totalAt}(B', \tau)) \land \operatorname{tvals}(\mathcal{R}, \tau) \text{ is a permutation of } \operatorname{tvals}(\mathcal{R}', \tau) \land \big((Z, \tau) \in B.\mathrm{detDrift} \iff (Z, \tau) \in B'.\mathrm{detDrift}\big) \land \big(\tau \in B.\mathrm{detDriftTotals} \iff \tau \in B'.\mathrm{detDriftTotals}\big)\Big),\quad B = \operatorname{baseline}_T(\mathcal{R}),\ B' = \operatorname{baseline}_T(\mathcal{R}'),\ \operatorname{summary}(\bot) = \bot$$
-/
theorem baseline_perm (tb : Table) {rs rs' : List ZRun} (h : rs.Perm rs') (hu : Uniform rs) :
    ids rs = ids rs' ∧ ∀ Z ty : String,
      (cellAt (baseline tb rs) Z ty).map Row.summary = (cellAt (baseline tb rs') Z ty).map Row.summary ∧
      (vals rs Z ty).Perm (vals rs' Z ty) ∧
      (totalAt (baseline tb rs) ty).map Row.summary = (totalAt (baseline tb rs') ty).map Row.summary ∧
      (totalVals rs ty).Perm (totalVals rs' ty) ∧
      ((Z, ty) ∈ (baseline tb rs).detDrift ↔ (Z, ty) ∈ (baseline tb rs').detDrift) ∧
      (ty ∈ (baseline tb rs).detDriftTotals ↔ ty ∈ (baseline tb rs').detDriftTotals) := by
  have hids := ids_perm h hu
  have htypes : ∀ Z ty, ty ∈ zoneTypes rs Z ↔ ty ∈ zoneTypes rs' Z := fun Z ty =>
    mem_keysOf_perm (h.map _) ty
  have hall : ∀ ty, ty ∈ allTypes rs ↔ ty ∈ allTypes rs' := fun ty =>
    mem_keysOf_perm (h.flatMap_right _) ty
  have hv : ∀ Z ty, (vals rs Z ty).Perm (vals rs' Z ty) := fun Z ty => h.map _
  have ht : ∀ ty, (totalVals rs ty).Perm (totalVals rs' ty) := fun ty => h.map _
  refine ⟨hids, fun Z ty => ⟨?_, hv Z ty, ?_, ht ty, ?_, ?_⟩⟩
  · rw [cellAt_baseline, cellAt_baseline, ← hids]
    by_cases hc : Z ∈ ids rs ∧ ty ∈ zoneTypes rs Z
    · have hc' : Z ∈ ids rs ∧ ty ∈ zoneTypes rs' Z := ⟨hc.1, (htypes Z ty).mp hc.2⟩
      simp only [hc, hc', and_self, ite_true, Option.map_some]
      rw [summary_row_perm tb (hv Z ty)]
    · have hc' : ¬ (Z ∈ ids rs ∧ ty ∈ zoneTypes rs' Z) := fun e => hc ⟨e.1, (htypes Z ty).mpr e.2⟩
      simp only [hc, hc', ite_false]
  · rw [totalAt_baseline, totalAt_baseline]
    by_cases hc : ty ∈ allTypes rs
    · simp only [hc, (hall ty).mp hc, ite_true, Option.map_some]
      rw [summary_row_perm tb (ht ty)]
    · have hc' : ty ∉ allTypes rs' := fun e => hc ((hall ty).mpr e)
      simp only [hc, hc', ite_false]
  · -- drift membership: a cell drifts iff its summary says so
    have key : ∀ (qs : List ZRun), (Z, ty) ∈ (baseline tb qs).detDrift ↔
        Z ∈ ids qs ∧ ty ∈ zoneTypes qs Z ∧ drifts (row tb (vals qs Z ty) ty) = true := by
      intro qs
      rw [mem_detDrift]
      simp only [zoneRows, List.mem_map]
      constructor
      · rintro ⟨hZ, _, ⟨ty', hty', rfl⟩, e, hd⟩
        simp only [row] at e; subst e
        exact ⟨hZ, hty', hd⟩
      · rintro ⟨hZ, hty, hd⟩
        exact ⟨hZ, _, ⟨ty, hty, rfl⟩, rfl, hd⟩
    have hd : drifts (row tb (vals rs Z ty) ty) = drifts (row tb (vals rs' Z ty) ty) := by
      obtain ⟨a, b, _⟩ := stats_perm (hv Z ty)
      simp [drifts, row, a, b]
    rw [key, key, ← hids, htypes, hd]
  · have key : ∀ (qs : List ZRun), ty ∈ (baseline tb qs).detDriftTotals ↔
        ty ∈ allTypes qs ∧ drifts (row tb (totalVals qs ty) ty) = true := by
      intro qs
      simp only [baseline, totalRows, List.mem_map, List.mem_filter]
      constructor
      · rintro ⟨_, ⟨⟨ty', hty', rfl⟩, hd⟩, e⟩
        simp only [row] at e; subst e
        exact ⟨hty', hd⟩
      · rintro ⟨hty, hd⟩
        exact ⟨_, ⟨⟨ty, hty, rfl⟩, hd⟩, rfl⟩
    have hd : drifts (row tb (totalVals rs ty) ty) = drifts (row tb (totalVals rs' ty) ty) := by
      obtain ⟨a, b, _⟩ := stats_perm (ht ty)
      simp [drifts, row, a, b]
    rw [key, key, hall, hd]

end Fw.Measure.ZoneBaseline
