/-!
# Properties first: a never-happen property is a predicate over the implementation

Task `lfg-props-shape` (research/notes/2026/10-18-lean-first-gate.md, rule 1 and rule 4). Ten incidents came from
properties nobody stated (for example `inc-land-dry-no-verdict`: an empty branch printed no `VERDICT` line). The
convention here makes a property a first-class value that exists *before* the code:

* **Property over the signature.** A never-happen property of a task is a `Prop`-valued def over the type of the
  implementation, `P : Impl → Prop` (`Property Impl`), never a statement about one fixed def. So the same `P` can be
  proved of the real implementation and refuted for a bad one.
* **The kill target is a registered incident, not an author-made bad.** A bad implementation written per property
  proves little: its author picks both the bad and the inputs it differs on, so an unrelated property (for example
  "the exit code is at most 100") can reject it. So an `Incident` row pins, once per incident and reviewed with the
  incident, its ledger `id` (docs/team/incidents/ledger.json), its `pred` (the incident inputs) and its `replay` (the
  implementation that reproduces the real bug). A `Registry` holds the rows of one signature, each with a non-empty
  id, distinct ids and a strict predicate (`Strict`: some input is not an incident input).
* **One canonical registry.** Every `Incident` and `Registry` value lives in `Fw.Spec.Incidents`, and only there:
  `Incidents.registryFor s` is the registry of the signature `s` (a closed inductive `Incidents.Sig`), and the gate's
  `Incidents.Convention s impl P` takes no registry argument. The generic `KillsAt R P` and `ConventionAt R impl P`
  here are its building blocks; a property module never names an `R` of its own. The lint
  `lean/scripts/PropsLint.lean` (a check.sh stage) fails on any `Incident`/`Registry` construction outside
  `Fw.Spec.Incidents`, on any `ConventionAt` statement outside it, and on any row whose ledger entry does not name the
  row's `leanPred` and `leanReplay`.
* **Kill-witness naming.** For a property `P`, the real implementation `impl` and a registered incident `i`:
  `theorem P_impl : P impl` and `theorem P_rejects_<i> : ¬ P i.replay` (`implName`, `killName`; the id's `-` become
  `_`). A property counts as killing only through a registered row (`KillsAt R P`: some row of `R` has a replay that
  `P` rejects), and the full convention for one property is `Incidents.Convention s impl P` (`P impl`, a kill of a
  row of `registryFor s`, and that registry faithful to `impl`). The gate decides by the *type*; the names are for
  readers.
* **What a kill means, and what it does not.** `KillsAt R P` says that `P` *separates* `impl` from a registered
  replay: `P` holds of one and fails for the other. It does not prove that `P` is *about* the incident: a property
  that pins `impl` itself, or one that reads an unrelated part of the output the replay happens to change, separates
  too. The lint rejects the first kind syntactically: the body of a property in a `Convention` statement may not
  mention `impl` or a name `impl` unfolds to, minus the signature's spec vocabulary `Incidents.vocab s`. The second
  kind is a stated limit, not a bug: the reviewer checks the math of `P` against the ledger entry's `leanReason`.
* **The replay is checked against the real implementation.** `Registry.Faithful impl R`: every row's replay equals
  `impl` on every input that is not an incident input of that row (`AgreesOff`). This checks the replay, not a
  property. For a pointwise property whose check reads the implementation at one point (`ReadsAt`), if the property
  holds of `impl` then the replay fails the check only on incident inputs (`failures_on_incident`), and if the
  property also rejects the replay, on at least one (`fails_on_incident`).
* **Extra bad implementations** (mutants such as a `done` verdict on an empty branch) may still get `¬ P bad`
  theorems, for example to show that one property is blind to a bug, but they do not count as kills.
* **Pointwise form.** A property that is a `∀` over inputs of a `Bool` check (`Pointwise`) is what `Fw.Search` can
  search before any proof (`rejects_of_counterexample`).
* **Premises are visible.** `Assume p claim` holds exactly when `claim` does (`assume_iff`), but it is a structure:
  a proof of it is built only with the explicit `Assume.intro`, and it names the premise `p` (its kind and registry
  id) in the statement. So a theorem that takes `(h : Assume p claim)` says in its type that it rests on the engine,
  the shell, the file system or CI, and a checker can list the ids. A `Premise` id must be non-empty
  (`Premise.id_ne`, filled by `decide` in `{ kind := …, id := … }`).
* **What Lean does not catch here.** The marker only labels a premise; it enforces nothing about its content. A
  marked premise of `False` proves anything (`assume_false_elim`), so premise contents are reviewed with the premise
  registry. Nothing in this module stops a theorem from taking an outside fact as a bare, unmarked hypothesis, and
  a non-empty `Premise.id` that is not a registry row still elaborates. Those holes are closed only by the tasks
  `lfg-premise-registry` (every premise id must be a registry row) and `lfg-mathview-facts` (MathView lists the
  hypotheses of each theorem, so an unmarked outside fact is visible in review). The ledger check of `Incident.id`
  is the lint's, not this module's.

Worked example: `Fw.Spec.Props.LandDryDemo`; how-to: docs/team/tools/lean-first.md.
-/
namespace Fw.Spec.Props

universe u v w

/-- A property of implementations of the signature `I`: a predicate on implementations, so it can be stated before
any implementation exists. -/
abbrev Property (Impl : Type u) : Type u := Impl → Prop

/-- A kill witness: the property rejects the bad implementation `b`. -/
def Rejects {Impl : Type u} (P : Property Impl) (bad : Impl) : Prop := ¬ P bad

/-- A property is non-vacuous when some implementation of the signature fails it. -/
def Nonvacuous {Impl : Type u} (P : Property Impl) : Prop := ∃ bad, ¬ P bad

/-- **A kill witness makes the property non-vacuous.** For every property and every implementation the property
rejects, the property is not true of every implementation. -/
theorem nonvacuous_of_rejects {Impl : Type u} (P : Property Impl) (bad : Impl) (h : ¬ P bad) : Nonvacuous P :=
  ⟨bad, h⟩

/-- `Rejects` is the negation, so `P_rejects_<i>` may be stated either way. -/
theorem rejects_iff {Impl : Type u} (P : Property Impl) (bad : Impl) : Rejects P bad ↔ ¬ P bad := Iff.rfl

/-- The pointwise property of a Boolean check `Q`: the check passes on every input `x` of type `A`. -/
def Pointwise {Impl : Type u} {α : Type v} (Q : Impl → α → Bool) : Property Impl := fun i => ∀ x, Q i x = true

/-- **One counterexample refutes a pointwise property.** For every check `Q`, implementation `i` and input `x`: if the
check fails on `x`, the pointwise property fails for `i`. -/
theorem rejects_of_counterexample {Impl : Type u} {α : Type v} (Q : Impl → α → Bool) (i : Impl) (x : α)
    (h : Q i x = false) : ¬ Pointwise Q i :=
  fun hp => by simp [hp x] at h

/-- **The bad implementation differs only on the incident.** For implementations that are functions from `A` to `B`
and an incident predicate `E` on `A`: `bad` equals `impl` on every input that is not an incident input. -/
def AgreesOff {α : Type v} {β : Type w} (impl bad : α → β) (incident : α → Prop) : Prop :=
  ∀ a, ¬ incident a → impl a = bad a

/-- **The check reads one point.** The check `Q` at input `y : C` looks at an implementation `i : A → B` only
through its value at the point `π(y)`: two implementations with the same value there get the same answer. -/
def ReadsAt {α : Type v} {β : Type w} {γ : Type u} (Q : (α → β) → γ → Bool) (pt : γ → α) : Prop :=
  ∀ (i j : α → β) (y : γ), i (pt y) = j (pt y) → Q i y = Q j y

/-- **Every failure of the bad implementation is an incident input.** For every check `Q` and point map `π` with
`ReadsAt(Q, π)`, all implementations `i, b : A → B` and every incident predicate `E`: if the pointwise
property of `Q` holds of `i` and `b` agrees with `i` off `E`, then every input `y` on which `Q` fails for `b` has
`E(π(y))`. -/
theorem failures_on_incident {α : Type v} {β : Type w} {γ : Type u} (Q : (α → β) → γ → Bool) (pt : γ → α)
    (hQ : ReadsAt Q pt) (impl bad : α → β) (incident : α → Prop) (hi : Pointwise Q impl)
    (ha : AgreesOff impl bad incident) (y : γ) (hy : Q bad y = false) : incident (pt y) :=
  Classical.byContradiction fun hn => by
    have h1 : Q impl y = Q bad y := hQ impl bad y (ha (pt y) hn)
    rw [hi y, hy] at h1
    exact Bool.noConfusion h1

/-- **The kill is on the incident.** For every check `Q` and point map `π` with `ReadsAt(Q, π)`, all
implementations `i, b : A → B` and every incident predicate `E`: if the pointwise property of `Q` holds of `i`, `b`
agrees with `i` off `E`, and the property rejects `b`, then some input `y` with `E(π(y))` makes `Q` fail for `b`. -/
theorem fails_on_incident {α : Type v} {β : Type w} {γ : Type u} (Q : (α → β) → γ → Bool) (pt : γ → α)
    (hQ : ReadsAt Q pt) (impl bad : α → β) (incident : α → Prop) (hi : Pointwise Q impl)
    (ha : AgreesOff impl bad incident) (hb : ¬ Pointwise Q bad) : ∃ y, incident (pt y) ∧ Q bad y = false := by
  have : ∃ y, Q bad y = false := Classical.byContradiction fun hn =>
    hb fun y => by cases hy : Q bad y; exact absurd ⟨y, hy⟩ hn; rfl
  obtain ⟨y, hy⟩ := this
  exact ⟨y, failures_on_incident Q pt hQ impl bad incident hi ha y hy, hy⟩

/-! ## The incident registry: the kill target -/

/-- An incident predicate is strict when some input is not an incident input. This rules out only the everywhere-true
predicate (a predicate true on all inputs but one is strict); the real bound on a row's predicate is the review of the
one registry, `Fw.Spec.Incidents`. -/
def Strict {α : Type v} (incident : α → Prop) : Prop := ∃ a, ¬ incident a

/-- **A registered incident.** One row per incident of docs/team/incidents/ledger.json, for implementations
`A → B`: its ledger id, its incident inputs `E`, and its replay `r`, the implementation that reproduces the real bug.
The row is written once per incident and reviewed with the incident, never per property. -/
structure Incident (α : Type v) (β : Type w) where
  /-- The ledger id, for example `inc-land-dry-no-verdict`. -/
  id : String
  /-- The incident inputs. -/
  pred : α → Prop
  /-- The implementation that reproduces the real bug. -/
  replay : α → β

/-- **A registry of incidents** for one signature `A → B`: a list of rows, every id non-empty, the ids pairwise
distinct, and every incident predicate strict. -/
structure Registry (α : Type v) (β : Type w) where
  /-- The registered incidents. -/
  rows : List (Incident α β)
  /-- Every id is non-empty. -/
  ids_ne : ∀ i ∈ rows, i.id ≠ ""
  /-- No id appears twice. -/
  ids_nodup : (rows.map Incident.id).Nodup
  /-- Every incident predicate is strict. -/
  strict : ∀ i ∈ rows, Strict i.pred

/-- **The replays are faithful to the real implementation.** For an implementation `f : A → B`, every row's replay
equals `f` on every input that is not an incident input of that row. -/
def Registry.Faithful {α : Type v} {β : Type w} (impl : α → β) (R : Registry α β) : Prop :=
  ∀ i ∈ R.rows, AgreesOff impl i.replay i.pred

/-- **A property kills a row of a registry.** Some row of the registry `R` has a replay that the property rejects. It
says that `P` separates that replay from every implementation `P` holds of, not that `P` is about the incident (see
the module doc). The gate uses it only through `Fw.Spec.Incidents.Kills`, at the one registry. -/
def KillsAt {α : Type v} {β : Type w} (R : Registry α β) (P : Property (α → β)) : Prop :=
  ∃ i ∈ R.rows, ¬ P i.replay

/-- **The convention for one property, at a given registry.** For a registry `R`, a real implementation `f` and a
property `P`: `P` holds of `f`, `P` kills a row of `R`, and the replays of `R` are faithful to `f`. The gate uses it
only through `Fw.Spec.Incidents.Convention`, at the one registry; the lint rejects a `ConventionAt` statement outside
`Fw.Spec.Incidents`. -/
structure ConventionAt {α : Type v} {β : Type w} (R : Registry α β) (impl : α → β) (P : Property (α → β)) : Prop where
  /-- `P_impl`. -/
  holds : P impl
  /-- From a `P_rejects_<i>` theorem. -/
  kills : KillsAt R P
  /-- The replays are checked against the real implementation. -/
  faithful : R.Faithful impl

/-- **A kill witness for a row is a kill.** For every registry `R`, property `P` and row `i ∈ R`: if `P` rejects
`i`'s replay, then `P` kills a row of `R`. -/
theorem kills_of_rejects {α : Type v} {β : Type w} (R : Registry α β) (P : Property (α → β)) (i : Incident α β)
    (hi : i ∈ R.rows) (h : ¬ P i.replay) : KillsAt R P :=
  ⟨i, hi, h⟩

/-- **A property that passes every replay kills nothing.** For every registry `R` and property `P`: if `P` holds of
every row's replay, then `P` kills no row of `R`. -/
theorem not_kills_of_passes {α : Type v} {β : Type w} (R : Registry α β) (P : Property (α → β))
    (h : ∀ i ∈ R.rows, P i.replay) : ¬ KillsAt R P :=
  fun ⟨i, hi, hn⟩ => hn (h i hi)

/-- **A kill makes the property non-vacuous.** For every registry `R` and property `P`: if `P` kills a row of `R`,
some implementation fails `P`. -/
theorem nonvacuous_of_kills {α : Type v} {β : Type w} (R : Registry α β) (P : Property (α → β)) (h : KillsAt R P) :
    Nonvacuous P :=
  let ⟨i, _, hn⟩ := h; ⟨i.replay, hn⟩

/-- The kinds of premise a property may rest on: a browser engine, the shell, the file system, CI, the platform
(OS, toolchain) or the DOM. The registry `Fw.Ops.Premise` gives each premise one kind. -/
inductive PremiseKind where
  | engine | shell | fs | ci | platform | dom
deriving DecidableEq, Repr

/-- A named premise: its kind and its registry id (an `id` of `Fw.Ops.Premise.registry` or of a module's premise
rows, for example `land.dryStagesAreLandStages`), which must be non-empty. That the id is a registry row is left to
`lfg-premise-registry`. -/
structure Premise where
  /-- The kind of outside fact. -/
  kind : PremiseKind
  /-- The registry id. -/
  id : String
  /-- The id is non-empty; `decide` proves it for a literal. -/
  id_ne : id ≠ "" := by decide
deriving DecidableEq, Repr

/-- **The premise marker.** An opaque wrapper around the claim: a proof of `Assume p claim` is built only with the
explicit `Assume.intro` and read only with `Assume.elim`, so a bare proof of the claim does not elaborate where the
marker is expected, and a theorem that takes `(h : Assume p claim)` shows in its type which outside fact (engine,
shell, fs, CI) it rests on. The marker only labels the premise and enforces nothing about its content: a marked
premise of `False` proves anything (`assume_false_elim`), so premise contents are reviewed with the premise registry.
A bare, unmarked hypothesis is still possible elsewhere; `lfg-mathview-facts` and `lfg-premise-registry` catch that,
not this type. -/
structure Assume (p : Premise) (claim : Prop) : Prop where
  /-- Introduce a premise: a proof of the claim, marked with the premise `p`. -/
  intro ::
  /-- Use a premise: the marked claim gives the claim. -/
  elim : claim

/-- The marker adds no logical content: for every premise and every claim, the marked claim is equivalent to the
claim. -/
theorem assume_iff (p : Premise) (c : Prop) : Assume p c ↔ c := ⟨Assume.elim, Assume.intro⟩

/-- **A marked premise of `False` proves anything.** For every premise and every claim, a marked `False` gives the
claim; the marker does not stop it, so the content of every premise is reviewed with the registry. -/
theorem assume_false_elim (p : Premise) (c : Prop) (h : Assume p False) : c := h.elim.elim

-- the marker is opaque: a bare proof of the claim is not a marked claim, only `Assume.intro` builds one
example (c : Prop) (h : c) : Assume { kind := .shell, id := "example.id" } c := by
  fail_if_success exact h
  exact Assume.intro h

-- an empty premise id does not elaborate
example : True := by
  fail_if_success have : Premise := { kind := .shell, id := "" }
  trivial

/-- The name of the theorem that proves property `P` of the real implementation. -/
def implName (prop : String) : String := prop ++ "_impl"

/-- The name of the kill witness of property `P` against the registered incident with ledger id `i`: every `-` of
the id becomes `_`, so the name is a Lean identifier. -/
def killName (prop incidentId : String) : String :=
  prop ++ "_rejects_" ++ incidentId.map fun c => if c = '-' then '_' else c

#guard implName "NoSilentExit" == "NoSilentExit_impl"
#guard killName "NoSilentExit" "inc-land-dry-no-verdict" == "NoSilentExit_rejects_inc_land_dry_no_verdict"
#guard killName "TruthfulVerdict" "inc-land-dry-no-verdict" == "TruthfulVerdict_rejects_inc_land_dry_no_verdict"
#guard killName "P" "" == "P_rejects_"

end Fw.Spec.Props
