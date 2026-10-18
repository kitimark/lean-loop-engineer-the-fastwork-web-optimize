import Fw.Spec.MathFacts
import Fw.Spec.Props.LandDryDemo
import Fw.Spec.Null
import Fw.Console.PreviewTable
import Fw.Console.Alert
import Fw.Sched.Admit
import Fw.Obs.Stale
import Fw.Ci.Budget
/-!
# The math-view facts on real declarations (task `lfg-mathview-facts`)

`#guard`s over `facts%` (`Fw.Spec.MathFacts`): each fact the math view emits, checked on `Fw` theorems whose answer is
known: a closed data lint, a defining equation, a general proof with binders, a property of an implementation, a
convention, a kill of a registered incident, a theorem under a named premise, and a statement without a head constant.
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
