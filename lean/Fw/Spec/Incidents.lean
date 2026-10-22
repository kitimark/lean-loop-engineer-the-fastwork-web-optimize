import Fw.Spec.Props
import Fw.Spec.LandDrySig
/-!
# The one incident registry

Task `lfg-props-shape`. Every `Fw.Spec.Props.Incident` and `Fw.Spec.Props.Registry` value lives in this module and
nowhere else (the lint `lean/scripts/PropsLint.lean`, a check.sh stage, fails on a construction anywhere else). A row
is written once per incident of docs/team/incidents/ledger.json and reviewed with that incident: the ledger entry
names the row's predicate and replay in its `leanPred` and `leanReplay` fields, and the lint checks that they match.

* **Signatures are closed.** `Sig` lists the implementation signatures that have incidents; `Sig.Dom` and `Sig.Cod`
  give the input and output types, and `registryFor s` is the one registry of `s`. A property module cannot add a
  signature or a registry, so it cannot choose its own kill target.
* **The gate's types take no registry.** `Kills s P` and `Convention s impl P` are `KillsAt` and `ConventionAt` at
  `registryFor s`.
* **Spec vocabulary.** `vocab s` lists the names that a property over `s` may use although the real implementation
  unfolds to them (for the dry run: the verdict kind, its exit code and its verdict line). Every other name the
  implementation unfolds to is an internal, and the lint rejects a property in a `Convention` statement that mentions
  one. The list is reviewed with the registry.

Worked example: `Fw.Spec.Props.LandDryDemo`; how-to: docs/team/tools/lean-first.md.
-/
namespace Fw.Spec.Incidents
open Fw.Spec.Props

/-! ## `fw land --dry`: incident `inc-land-dry-no-verdict` -/

namespace LandDry
open Fw.Console.LandVerdict Fw.Console.LandDry Fw.Spec.LandDrySig

/-- Does the outcome describe an empty branch: no exception, the branch contains main, and it has no commit of its own? -/
def isEmptyBranch (o : Outcome) : Bool := !o.threw && o.fresh && !o.own

#guard isEmptyBranch ⟨false, true, false, false, false, false, false, false⟩
#guard !isEmptyBranch ⟨true, true, false, false, false, false, false, false⟩
#guard !isEmptyBranch ⟨false, false, false, false, false, false, false, false⟩
#guard !isEmptyBranch ⟨false, true, true, true, true, true, true, true⟩

/-- The incident inputs of `inc-land-dry-no-verdict`: the outcome is an empty branch. The ledger says only "a branch
with no own commits"; the `fresh` conjunct (the branch contains main) is INFERRED from the stage order of
`Fw.Console.LandDry.dryKind`, which reports `stale` before `empty` (lean/Fw/Console/LandDry.lean:78), and from the
ledger's repro, a branch at main. -/
def emptyIncident (o : Outcome) : Prop := isEmptyBranch o = true

/-- The one line the incident run printed. The ledger says only that it was "a path"; which path it was is not
recorded (INFERRED), so the replay prints this placeholder. It is not a verdict line, which is all the replay needs. -/
def pathLine : String := "<worktree path>"

#guard !isVerdict pathLine

/-- **The replay of `inc-land-dry-no-verdict`** (ledger `leanReplay`). On an empty branch the run printed only a path
and no `VERDICT` line (the ledger's symptom, as `[pathLine]`); otherwise it is the real run. The ledger records no exit
code, so the replay keeps the real run's code on every input: it differs from the real run only in what the ledger
records. -/
def emptyNoVerdict : DryImpl := fun o t =>
  if isEmptyBranch o then ⟨[pathLine], o.kind.exitCode⟩ else ⟨dryRun o t, o.kind.exitCode⟩

#guard (emptyNoVerdict ⟨false, true, false, false, false, false, false, false⟩ "x").lines == [pathLine]
#guard (emptyNoVerdict ⟨false, true, true, true, true, true, true, true⟩ "x").lines ==
  dryRun ⟨false, true, true, true, true, true, true, true⟩ "x"

/-- **The incident predicate is strict**: some outcome (every stage false) is not an empty branch. -/
theorem emptyIncident_strict : Strict emptyIncident :=
  ⟨⟨false, false, false, false, false, false, false, false⟩, by unfold emptyIncident; decide⟩

/-- **The registry row of `inc-land-dry-no-verdict`** (docs/team/incidents/ledger.json): incident inputs
`E_empty` (ledger `leanPred`), replay `emptyNoVerdict` (ledger `leanReplay`). -/
def incLandDryNoVerdict : Incident Outcome (String → Out) where
  id := "inc-land-dry-no-verdict"
  pred := emptyIncident
  replay := emptyNoVerdict

/-- **The incident registry of the dry-run signature**: the one ledger incident of this decision. Mutants such as a
top-level catch with no verdict are not rows: the ledger has no incident for them. -/
def registry : Registry Outcome (String → Out) where
  rows := [incLandDryNoVerdict]
  ids_ne := fun i hi => by
    simp only [List.mem_singleton] at hi
    subst hi
    decide
  ids_nodup := by simp
  strict := fun i hi => by
    simp only [List.mem_singleton] at hi
    subst hi
    exact emptyIncident_strict

#guard registry.rows.map (·.id) == ["inc-land-dry-no-verdict"]

end LandDry

/-! ## The closed list of signatures and the one registry of each -/

/-- The implementation signatures that have registered incidents (closed: a property module cannot add one). -/
inductive Sig where
  | landDry
deriving DecidableEq, Repr

/-- The input type of a signature. -/
def Sig.Dom : Sig → Type
  | .landDry => Fw.Console.LandDry.Outcome

/-- The output type of a signature. -/
def Sig.Cod : Sig → Type
  | .landDry => String → Fw.Spec.LandDrySig.Out

/-- **The one registry of each signature.** -/
def registryFor : (s : Sig) → Registry s.Dom s.Cod
  | .landDry => LandDry.registry

/-- **The spec vocabulary of each signature**: the full names a property over the signature may mention although the
real implementation unfolds to them. For the dry run: the kind of an outcome, the exit code of a kind and the verdict
line (the module doc of `Fw.Console.LandVerdict` specifies them; `Fw.Console.LandDry.kind_spec` specifies the kind). -/
def vocab : Sig → List String
  | .landDry => ["Fw.Console.LandDry.Outcome.kind", "Fw.Console.LandVerdict.Kind.exitCode",
      "Fw.Console.LandVerdict.verdictLine"]

#guard (vocab .landDry).length == 3

/-- **A property kills a registered incident of the signature** `s`: some row of the one registry of `s` has a replay
that `P` rejects. -/
abbrev Kills (s : Sig) (P : Property (s.Dom → s.Cod)) : Prop := KillsAt (registryFor s) P

/-- **The replays of the signature** `s` **are faithful** to the implementation `f`: every row of the one registry
of `s` agrees with `f` off its incident inputs. -/
abbrev Faithful (s : Sig) (impl : s.Dom → s.Cod) : Prop := (registryFor s).Faithful impl

/-- **The convention the gate checks** for one property: `P` holds of `f`, kills a row of the one registry of `s`,
and that registry is faithful to `f`. No registry argument: the kill target is never the property author's. -/
abbrev Convention (s : Sig) (impl : s.Dom → s.Cod) (P : Property (s.Dom → s.Cod)) : Prop :=
  ConventionAt (registryFor s) impl P

/-- **The rows of the dry-run registry**: a row is in it exactly when it is the row of `inc-land-dry-no-verdict`. Use
this instead of unfolding the registry outside this module. -/
theorem mem_landDry (i : Incident (Sig.Dom .landDry) (Sig.Cod .landDry)) :
    i ∈ (registryFor .landDry).rows ↔ i = LandDry.incLandDryNoVerdict :=
  List.mem_singleton

/-- The row of `inc-land-dry-no-verdict` is in the dry-run registry. -/
theorem incLandDryNoVerdict_mem : LandDry.incLandDryNoVerdict ∈ (registryFor .landDry).rows :=
  (mem_landDry _).mpr rfl

end Fw.Spec.Incidents
