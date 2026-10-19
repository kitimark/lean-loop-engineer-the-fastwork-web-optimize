import Fw.Measure.Classes
import Fw.Measure.Tolerance
/-!
# Count reduction and the verdict of one measured arm pair (`store.reduce`)

`fw run` brings home the per-frame counts of a baseline arm (`base`, at least two runs, so a
determinism class exists) and a variant arm (`var`, at least one run) on one engine. This module
reduces them to the verdict, reusing `Fw.Measure` (`classifyU`, `typeOk`, `noMoreWork`):

* every count type that occurs in **either** arm gets a row (a type only the variant has is new
  work and must be judged, not skipped);
* the class of a type is the unit-aware class of its series over the baseline runs;
* the compared series are the first baseline run and the first variant run;
* the arm pair passes when `noMoreWork` holds over the rows, so `noMoreWork_sound` carries over.
-/
namespace Fw.Store
open Fw.Measure

/-- The rows of an arm pair: type name and its `TypeObs` (class from the baseline runs, series of
the first baseline run and the first variant run).
-/
def obsOf (p : Policy) (q : PxTol) (base var : List (List Counts)) : List (String × TypeObs) :=
  (keysOf (base ++ var).flatten).map fun k =>
    (k, ⟨classifyU p q (unitOf k) (base.map (seriesOf k)),
         seriesOf k (base.headD []), seriesOf k (var.headD [])⟩)

/-- The verdict of an arm pair: no more work in every row. -/
def reduceOk (p : Policy) (q : PxTol) (base var : List (List Counts)) : Bool :=
  noMoreWork ((obsOf p q base var).map (·.2))

/-- The types whose test fails (their names, in key order). -/
def failing (p : Policy) (q : PxTol) (base var : List (List Counts)) : List String :=
  ((obsOf p q base var).filter fun r => !typeOk r.2.cls r.2.base r.2.var).map (·.1)

/-- **One row per type of either arm.** The rows name exactly the sorted distinct count types of
the baseline and the variant runs together.
-/
theorem obsOf_types (p : Policy) (q : PxTol) (base var : List (List Counts)) :
    (obsOf p q base var).map (·.1) = keysOf (base ++ var).flatten := by
  simp [obsOf, Function.comp_def]

/-- **The verdict is the conjunction of the row tests.** -/
theorem reduceOk_iff (p : Policy) (q : PxTol) (base var : List (List Counts)) :
    reduceOk p q base var = true ↔
      ∀ r ∈ obsOf p q base var, typeOk r.2.cls r.2.base r.2.var = true := by
  simp [reduceOk, noMoreWork, List.all_eq_true]

/-- **The failing list is empty exactly when the arm pair passes.** -/
theorem failing_eq_nil_iff (p : Policy) (q : PxTol) (base var : List (List Counts)) :
    failing p q base var = [] ↔ reduceOk p q base var = true := by
  rw [reduceOk_iff]
  simp [failing, List.filter_eq_nil_iff]

/-- **Soundness of the verdict.** If an arm pair passes, then for every count type and every
unseen pair of runs within the type's class of the observed first runs, the variant does no more
work than the baseline (frame by frame for deterministic types, in total for stable types).
-/
theorem reduceOk_sound (p : Policy) (q : PxTol) (base var : List (List Counts))
    (h : reduceOk p q base var = true) :
    ∀ r ∈ obsOf p q base var, ∀ b' v' : Series, Within r.2.cls r.2.base b' →
      Within r.2.cls r.2.var v' → Promise r.2.cls b' v' := by
  intro r hr b' v' hb hv
  exact noMoreWork_sound h r.2 (List.mem_map_of_mem hr) b' v' hb hv

/-- The verdict across engines: at least one engine was measured and every one passes. Nothing
measured is never a pass.
-/
def overall (oks : List Bool) : Bool := !oks.isEmpty && oks.all id

/-- **Overall passes exactly when something was measured and nothing failed.** -/
theorem overall_iff (oks : List Bool) :
    overall oks = true ↔ oks ≠ [] ∧ ∀ o ∈ oks, o = true := by
  simp [overall, List.all_eq_true]

#guard !overall []
#guard overall [true, true]
#guard !overall [true, false]
#guard reduceOk ⟨4, 24⟩ pxTolDefault [[[("a", 3)]], [[("a", 3)]]] [[[("a", 2)]]]
-- a type only the variant has is new work: base series 0, variant 5, deterministic class (all zero)
#guard !reduceOk ⟨4, 24⟩ pxTolDefault [[[("a", 3)]], [[("a", 3)]]] [[[("a", 3), ("b", 5)]]]
#guard failing ⟨4, 24⟩ pxTolDefault [[[("a", 3)]], [[("a", 3)]]] [[[("a", 3), ("b", 5)]]] == ["b"]

end Fw.Store
