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

$$\operatorname{obs}_{p,q}(B, V) = \big[\,(k,\ \operatorname{classify}_{p,q}(\operatorname{unit}(k), [\operatorname{series}_k(r)]_{r \in B}),\ \operatorname{series}_k(\operatorname{hd}_{[]}(B)),\ \operatorname{series}_k(\operatorname{hd}_{[]}(V)))\,\big]_{k \in \operatorname{keys}(\operatorname{flatten}(B \mathbin{+\!\!+} V))},\quad \text{where } \operatorname{hd}_{[]}(r_1 :: \dots) = r_1,\ \operatorname{hd}_{[]}([\,]) = [\,] \text{ (the empty run, whose series is empty)}$$
-/
def obsOf (p : Policy) (q : PxTol) (base var : List (List Counts)) : List (String × TypeObs) :=
  (keysOf (base ++ var).flatten).map fun k =>
    (k, ⟨classifyU p q (unitOf k) (base.map (seriesOf k)),
         seriesOf k (base.headD []), seriesOf k (var.headD [])⟩)

/-- The verdict of an arm pair: no more work in every row.

$$\operatorname{reduceOk}_{p,q}(B, V) = \operatorname{noMoreWork}\big([\,o \mid (k, o) \in \operatorname{obs}_{p,q}(B, V)\,]\big)$$
-/
def reduceOk (p : Policy) (q : PxTol) (base var : List (List Counts)) : Bool :=
  noMoreWork ((obsOf p q base var).map (·.2))

/-- The types whose test fails (their names, in key order).

$$\operatorname{failing}_{p,q}(B, V) = [\,k \mid (k, o) \in \operatorname{obs}_{p,q}(B, V),\ \neg\operatorname{ok}(o.\mathrm{cls}, o.\mathrm{base}, o.\mathrm{var})\,]$$
-/
def failing (p : Policy) (q : PxTol) (base var : List (List Counts)) : List String :=
  ((obsOf p q base var).filter fun r => !typeOk r.2.cls r.2.base r.2.var).map (·.1)

/-- **One row per type of either arm.** The rows name exactly the sorted distinct count types of
the baseline and the variant runs together.

$$\forall p, q, B, V:\ [\,k \mid (k, \cdot) \in \operatorname{obs}_{p,q}(B, V)\,] = \operatorname{keys}(B \mathbin{+\!\!+} V)$$
-/
theorem obsOf_types (p : Policy) (q : PxTol) (base var : List (List Counts)) :
    (obsOf p q base var).map (·.1) = keysOf (base ++ var).flatten := by
  simp [obsOf, Function.comp_def]

/-- **The verdict is the conjunction of the row tests.**

$$\forall p, q, B, V:\ \operatorname{reduceOk}_{p,q}(B, V) = \top \iff \forall (k, o) \in \operatorname{obs}_{p,q}(B, V):\ \operatorname{ok}(o.\mathrm{cls}, o.\mathrm{base}, o.\mathrm{var}) = \top$$
-/
theorem reduceOk_iff (p : Policy) (q : PxTol) (base var : List (List Counts)) :
    reduceOk p q base var = true ↔
      ∀ r ∈ obsOf p q base var, typeOk r.2.cls r.2.base r.2.var = true := by
  simp [reduceOk, noMoreWork, List.all_eq_true]

/-- **The failing list is empty exactly when the arm pair passes.**

$$\forall p, q, B, V:\ \operatorname{failing}_{p,q}(B, V) = [\,] \iff \operatorname{reduceOk}_{p,q}(B, V) = \top$$
-/
theorem failing_eq_nil_iff (p : Policy) (q : PxTol) (base var : List (List Counts)) :
    failing p q base var = [] ↔ reduceOk p q base var = true := by
  rw [reduceOk_iff]
  simp [failing, List.filter_eq_nil_iff]

/-- **Soundness of the verdict.** If an arm pair passes, then for every count type and every
unseen pair of runs within the type's class of the observed first runs, the variant does no more
work than the baseline (frame by frame for deterministic types, in total for stable types).

$$\forall p, q, B, V:\ \operatorname{reduceOk}_{p,q}(B, V) \Rightarrow \forall r \in \operatorname{obs}_{p,q}(B, V),\ \forall b', v' \in \mathrm{Series}:\ \operatorname{Within}(o.\mathrm{cls}, o.\mathrm{base}, b') \land \operatorname{Within}(o.\mathrm{cls}, o.\mathrm{var}, v') \Rightarrow \operatorname{Promise}(o.\mathrm{cls}, b', v'),\quad \text{where } r = (k, o) \text{ is a row: a type name } k \text{ and its observation } o$$
-/
theorem reduceOk_sound (p : Policy) (q : PxTol) (base var : List (List Counts))
    (h : reduceOk p q base var = true) :
    ∀ r ∈ obsOf p q base var, ∀ b' v' : Series, Within r.2.cls r.2.base b' →
      Within r.2.cls r.2.var v' → Promise r.2.cls b' v' := by
  intro r hr b' v' hb hv
  exact noMoreWork_sound h r.2 (List.mem_map_of_mem hr) b' v' hb hv

/-- The verdict across engines: at least one engine was measured and every one passes. Nothing
measured is never a pass.

$$\operatorname{overall}(O) = (O \ne [\,]) \land \bigwedge_{o \in O} o$$
-/
def overall (oks : List Bool) : Bool := !oks.isEmpty && oks.all id

/-- **Overall passes exactly when something was measured and nothing failed.**

$$\forall O:\ \operatorname{overall}(O) = \top \iff O \ne [\,] \land \forall o \in O:\ o = \top$$
-/
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
