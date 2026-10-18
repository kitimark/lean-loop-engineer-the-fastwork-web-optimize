import Fw.Spec.MathFacts
import Fw.Spec.Props.LandDryDemo
import Fw.Spec.Null
import Fw.Console.PreviewTable
import Fw.Console.Alert
import Fw.Sched.Admit
import Fw.Obs.Stale
import Fw.Ci.Budget
import Fw.Wire
import Fw.Engine.Core
import Fw.Parts.MorphMountOpt
/-!
# The math-view facts on real declarations (task `lfg-mathview-facts`)

`#guard`s over `facts%` (`Fw.Spec.MathFacts`): each fact the math view emits, checked on `Fw` theorems whose answer is
known: a closed data lint, a defining equation, a general proof with binders, a property of an implementation, a
convention, a kill of a registered incident, a theorem under a named premise, and a statement without a head constant.
`wire%` and `wireOf%` check the wire reach and `reachFromWire` (true, false and null), `defEqAt%` the budget edge of
the `defEq` class.
-/
open Fw.Spec.MathFacts

-- class: a closed statement proved by `decide` / reflexivity is a data lint
#guard (facts% Fw.Null.land_null_prob).cls == .closed
#guard (facts% Fw.Console.PreviewTable.table_size).cls == .closed
-- class: `decide` with binders is a general proof
#guard (facts% Fw.Console.Alert.digit_val).cls == .general
-- class: reflexivity with binders is a defining equation (`Eq` and `Iff`)
#guard (facts% Fw.Sched.Admit.Reads.admits_nil).cls == .rfl
#guard (facts% Fw.Spec.Props.rejects_iff).cls == .rfl
#guard (facts% Fw.Obs.covers_self).cls == .general
-- class: proved by `simp [wsum]`, but the two sides unfold to the same term
#guard (facts% Fw.Ci.Budget.wsum_single).cls == .defEq

-- a property of an implementation: head, implementation argument 0, its subject, no kill
#guard (facts% Fw.Spec.Props.LandDryDemo.NoSilentExit_impl).headConst ==
  some "Fw.Spec.Props.LandDryDemo.NoSilentExit"
#guard (facts% Fw.Spec.Props.LandDryDemo.NoSilentExit_impl).implIdx == some 0
#guard (facts% Fw.Spec.Props.LandDryDemo.NoSilentExit_impl).implExpr == some "Fw.Spec.Props.LandDryDemo.dryOut"
#guard (facts% Fw.Spec.Props.LandDryDemo.NoSilentExit_impl).subjects == ["Fw.Spec.Props.LandDryDemo.dryOut"]
#guard (facts% Fw.Spec.Props.LandDryDemo.NoSilentExit_impl).killOf == none
#guard (facts% Fw.Spec.Props.LandDryDemo.NoSilentExit_impl).cls == .general
#guard (facts% Fw.Spec.Props.LandDryDemo.NoSilentExit_impl).reach.contains "Fw.Spec.Props.LandDryDemo.dryOut"
#guard !(facts% Fw.Spec.Props.LandDryDemo.NoSilentExit_impl).reach.contains
  "Fw.Spec.Props.LandDryDemo.NoSilentExit_impl"

-- a convention: head `Convention`, the implementation is argument 1
#guard (facts% Fw.Spec.Props.LandDryDemo.NoSilentExit_convention).headConst == some "Fw.Spec.Incidents.Convention"
#guard (facts% Fw.Spec.Props.LandDryDemo.NoSilentExit_convention).implIdx == some 1

-- a kill: `¬ P i.replay` of a registered row names the row's ledger id; a kill of an unregistered replay names none
#guard (facts% Fw.Spec.Props.LandDryDemo.NoSilentExit_rejects_inc_land_dry_no_verdict).killOf ==
  some "inc-land-dry-no-verdict"
#guard (facts% Fw.Spec.Props.LandDryDemo.NoSilentExit_rejects_inc_land_dry_no_verdict).headConst ==
  some "Fw.Spec.Props.LandDryDemo.NoSilentExit"
#guard (facts% Fw.Spec.Props.LandDryDemo.NoSilentExit_rejects_exnNoVerdict).killOf == none

-- a theorem under a named premise
#guard (facts% Fw.Spec.Props.LandDryDemo.stdout_one_verdict).assumes == ["land.dryPrintsOutVerbatim"]
#guard (facts% Fw.Spec.Props.LandDryDemo.NoSilentExit_impl).assumes == []

-- a statement whose result type has no head constant
#guard (facts% Fw.Spec.Props.assume_false_elim).headConst == none
#guard (facts% Fw.Spec.Props.assume_false_elim).implIdx == none

-- the wire reach: the dispatcher is in it; the incident's dead helper `taskAdmitted` (inc-proof-of-dead-code) is not
#guard wire% Fw.Wire.handle
#guard !(wire% Fw.Wire.Sched.taskAdmitted)
-- a theorem about a wired op
#guard (wireOf% Fw.Sched.Admit.writes_disjoint) == some true
-- the alias `Fw.Screen.Counts` and the predicate `Work.lt` are not subjects; the op `toCounts` is not wired
#guard (facts% Fw.Engine.toCounts_ne_of_lt).subjects == ["Fw.Engine.toCounts"]
#guard (wireOf% Fw.Engine.toCounts_ne_of_lt) == some false
-- a statement over the inductive predicate `Reachable`: its subjects are the ops its constructors name
#guard (facts% Fw.Sched.Admit.deps_respected).subjects == ["Fw.Sched.Admit.step"]
#guard (wireOf% Fw.Sched.Admit.deps_respected) == some true
-- a statement without an op has no subjects, so `reachFromWire` is null
#guard (facts% Fw.Spec.Props.assume_false_elim).subjects == []
#guard (wireOf% Fw.Spec.Props.assume_false_elim) == none

-- reach keeps only names with a math-view entry: no generated `ctorIdx` or `noConfusionType`
#guard (facts% Fw.Ci.Budget.wsum_single).reach.contains "Fw.Ci.Budget.Kind"
#guard !(facts% Fw.Ci.Budget.wsum_single).reach.any fun s =>
  s.endsWith ".ctorIdx" || s.endsWith ".noConfusionType" || s.endsWith ".ctorElimType"

-- the defEq class sits on a heartbeat budget: `cr_swipe_mixed` is defEq within `defEqBudget`, not within 1k
#guard (facts% Fw.Parts.MorphMountOpt.cr_swipe_mixed).cls == .defEq
#guard !(defEqAt% Fw.Parts.MorphMountOpt.cr_swipe_mixed 1)
