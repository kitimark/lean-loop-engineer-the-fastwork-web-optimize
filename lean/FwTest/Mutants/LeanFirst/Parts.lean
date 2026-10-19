import Fw.Ops.LeanFirstSearch

/-!
# Tier-K kills of the lean-first part properties (`discharges`, `isNew` mutants)

Task `lfg-spec`. Mutants of the two helpers whose properties are stated over their own signature.
-/
namespace FwTest.Mutants.LeanFirst

open Fw.Search Fw.Ops.LeanFirst

/-- `discharges` without the exemption test: a lemma can discharge a property. -/
def dischargesExempt : Facts → ThmFact → PropFact → Bool := fun F t P =>
  t.proves == some P.name && t.axiomsOk && untestedOk F t P

/-- Every theorem is new (the baseline is ignored). -/
def newAll : Facts → ThmFact → Bool := fun _ _ => true

/-- New by name only: a changed statement of an old theorem is not new. -/
def newByName : Facts → ThmFact → Bool := fun F t => !F.baseline.any (·.1 == t.name)

#guard (searchUpTo 0 (qExemptNotDischarge dischargesExempt)).isSome
#guard (searchUpTo 0 (qBaselineNotNew newAll)).isSome
#guard (searchUpTo 0 (qChangedIsNew newByName)).isSome

/-- **Kill of `exempt_not_discharge`**.
A lemma that proves the property must not count as its proof, and the mutant that lets it is caught. -/
theorem ExemptNotDischarge_rejects_dischargesExempt : ¬ ExemptNotDischarge dischargesExempt :=
  refutes_of_search _ _ _ [(factsOf [.lemmaProves], { lemmaThm with proves := some "P" }, baseProp)]
    (fun h => (qExemptNotDischarge_iff _).mp h) (by decide +kernel)

/-- **Kill of `baseline_not_new`**.
Gating every old theorem is caught. -/
theorem BaselineNotNew_rejects_newAll : ¬ BaselineNotNew newAll :=
  refutes_of_search _ _ _ [(factsOf [.oldThm], oldThmFact)] (fun h => (qBaselineNotNew_iff _).mp h)
    (by decide +kernel)

/-- **Kill of `changed_is_new`**.
Letting an edited old theorem through ungated is caught. -/
theorem ChangedIsNew_rejects_newByName : ¬ ChangedIsNew newByName :=
  refutes_of_search _ _ _ [(factsOf [.changedOld], changedThmFact)] (fun h => (qChangedIsNew_iff _).mp h)
    (by decide +kernel)

end FwTest.Mutants.LeanFirst
