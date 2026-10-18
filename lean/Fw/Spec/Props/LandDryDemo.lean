import Fw.Console.LandDry
import Fw.Spec.Props
import Fw.Search
/-!
# Worked example: properties first for `fw land --dry` (incident `inc-land-dry-no-verdict`)

The incident: on a branch with no commits of its own, `fw land --dry` printed a path and no `VERDICT` line, so a
script reading the verdict found none. This module replays the property-first workflow on that decision
(docs/team/tools/lean-first.md walks through it):

1. **Signature.** `DryImpl := Outcome → String → Out`: stage outcomes and task in, stdout lines and exit code out.
2. **Properties over the signature** (no implementation needed): `NoSilentExit` (exactly one `VERDICT` line) and
   `TruthfulVerdict` (the last line is the verdict of the first failing stage, and the exit code is that kind's code).
3. **The registered incident and its replay.** The ledger has one incident for this decision, so the registry
   `landDryRegistry` has one row, `incLandDryNoVerdict`: id `inc-land-dry-no-verdict`, incident inputs
   `emptyIncident` (an empty branch; strict, `emptyIncident_strict`), replay `emptyNoVerdict` (the empty branch
   returns before the verdict). The replay is checked against the real run (`landDryRegistry_faithful`). Two extra
   mutants, not registered incidents: `exnNoVerdict` (a top-level catch prints the error and exits 1) and
   `emptyDone` (the empty branch says `done`).
4. **Search before proof.** Pointwise checks `qOneVerdict`, `qTruthful` with `*_sound` lemmas; `#guard`s run the
   search over all 128 outcomes ($\mathbb B^7$, exhaustive) and find the bug in each bad implementation. The
   `emptyDone` guard shows that `NoSilentExit` alone is blind to that bug, which is why `TruthfulVerdict` exists.
5. **Kill witnesses** against the registered replay, `P_rejects_inc_land_dry_no_verdict : ¬ P
   incLandDryNoVerdict.replay`, proved by running the search (`Fw.Search.refutes_of_search`), and so `Kills
   landDryRegistry P` (`*_kills`). The mutants get `¬ P bad` theorems too, but those are not kills.
6. **Proof of the real implementation** `dryOut` (`NoSilentExit_impl`, `TruthfulVerdict_impl`), from
   `Fw.Console.LandDry.dryRun_one_verdict`, and the whole convention (`*_convention`).
   **6b. The kills are on the incident** (`*_on_incident`, from `Fw.Spec.Props.failures_on_incident` and
   `fails_on_incident`): the replay fails each check only on incident inputs, and on at least one. The search
   result holds for every task name, not only `"x"` (`emptyNoVerdict_search`, `exnNoVerdict_search`).
   **6c. An unrelated property is not a kill.** `Silly` (the exit code is at most 100) holds of `dryOut` and rejects a
   made-up bad (`sillyBad`), but it passes the registered replay (`Silly_passes_replay`), so it kills no registered
   incident (`Silly_not_kill`) and does not meet the convention (`Silly_not_convention`).
7. **Premise visible**: `stdout_one_verdict` carries `Assume` for the step Lean cannot see, that `land.ts` prints
   `dryOut`'s lines verbatim.
-/
namespace Fw.Spec.Props.LandDryDemo
open Fw.Console.LandVerdict Fw.Console.LandDry Fw.Search Fw.Spec.Props

/-- What a dry run hands to the process: its stdout lines and its exit code.
$$\mathrm{Out} = \mathrm{List}(\mathrm{String}) \times \mathbb N$$ -/
structure Out where
  lines : List String
  exit : Nat

/-- The signature of a dry-run implementation: the stage outcomes and the task name in, the output out.
$$\mathrm{DryImpl} = \mathrm{Outcome} \to \mathrm{String} \to \mathrm{Out}$$ -/
abbrev DryImpl := Outcome → String → Out

/-- Is a line a verdict line? It starts with `VERDICT ` (with the space).
$$\operatorname{isV}(\ell) \iff \ell \text{ starts with } \texttt{VERDICT }$$ -/
def isVerdict (l : String) : Bool := l.startsWith "VERDICT "

/-- The number of verdict lines in a list of lines.
$$\operatorname{nV}(L) = |[\ell \in L : \operatorname{isV}(\ell)]|$$ -/
def verdictCount (ls : List String) : Nat := (ls.filter isVerdict).length

/-! ## Step 2: the properties, over the signature -/

/-- **Never a silent exit.** For every stage outcome and every task, the run prints exactly one verdict line.
$$\mathrm{NoSilentExit}(r) \iff \forall O\, t,\ \operatorname{nV}(r(O, t).\mathrm{lines}) = 1$$ -/
def NoSilentExit (run : DryImpl) : Prop := ∀ o t, verdictCount (run o t).lines = 1

/-- **The verdict tells the truth.** For every stage outcome and every task, the last line is the verdict line of the
first failing stage's kind (`Outcome.kind`, specified by `kind_spec`) and the exit code is that kind's code.
$$\mathrm{TruthfulVerdict}(r) \iff \forall O\, t,\ \operatorname{last}(r(O, t).\mathrm{lines}) = \mathrm{some}(\operatorname{line}(\operatorname{kind}(O), t)) \wedge r(O, t).\mathrm{exit} = \operatorname{code}(\operatorname{kind}(O))$$ -/
def TruthfulVerdict (run : DryImpl) : Prop :=
  ∀ o t, (run o t).lines.getLast? = some (verdictLine o.kind t) ∧ (run o t).exit = o.kind.exitCode

/-! ## Step 3: bad implementations (incident classes) and the real one -/

/-- Does the outcome describe an empty branch: no exception, the branch contains main, and it has no commit of its own?
$$\operatorname{empty}(O) \iff \lnot\mathit{threw} \wedge \mathit{fresh} \wedge \lnot\mathit{own}$$ -/
def isEmptyBranch (o : Outcome) : Bool := !o.threw && o.fresh && !o.own

/-- **The replay of `inc-land-dry-no-verdict`.** On an empty branch the run returns after the log, before the
verdict line (exit 0); otherwise it is the real run.
$$\mathrm{emptyNoVerdict}(O, t) = \begin{cases} (\operatorname{log}(O), 0) & \operatorname{empty}(O) \\ (\operatorname{run}(O, t), \operatorname{code}(\operatorname{kind}(O))) & \text{otherwise} \end{cases}$$ -/
def emptyNoVerdict : DryImpl := fun o t =>
  if isEmptyBranch o then ⟨o.log, 0⟩ else ⟨dryRun o t, o.kind.exitCode⟩

/-- **Mutant: an exception with no verdict** (no ledger incident, so not a registry row). A top-level catch prints
the error message and exits 1; otherwise it is the real run.
$$\mathrm{exnNoVerdict}(O, t) = \begin{cases} ([\texttt{Error: land failed}], 1) & \mathit{threw} \\ (\operatorname{run}(O, t), \operatorname{code}(\operatorname{kind}(O))) & \text{otherwise} \end{cases}$$ -/
def exnNoVerdict : DryImpl := fun o t =>
  if o.threw then ⟨["Error: land failed"], 1⟩ else ⟨dryRun o t, o.kind.exitCode⟩

/-- **Mutant: an empty branch says `done`** (no ledger incident, so not a registry row). One verdict line, but the
wrong kind: nothing was landed.
$$\mathrm{emptyDone}(O, t) = \begin{cases} (\operatorname{log}(O) \mathbin{+\!\!+} [\operatorname{line}(\mathrm{done}, t)], 0) & \operatorname{empty}(O) \\ (\operatorname{run}(O, t), \operatorname{code}(\operatorname{kind}(O))) & \text{otherwise} \end{cases}$$ -/
def emptyDone : DryImpl := fun o t =>
  if isEmptyBranch o then ⟨o.log ++ [verdictLine .done t], 0⟩ else ⟨dryRun o t, o.kind.exitCode⟩

/-- **The real implementation**: the Lean dry run (`Fw.Console.LandDry.dryRun`) and the exit code of its kind.
$$\mathrm{dryOut}(O, t) = (\operatorname{run}(O, t), \operatorname{code}(\operatorname{kind}(O)))$$ -/
def dryOut : DryImpl := fun o t => ⟨dryRun o t, o.kind.exitCode⟩

/-- The incident inputs of `inc-land-dry-no-verdict`: the outcome is an empty branch.
$$E_{\mathrm{empty}}(O) \iff \operatorname{empty}(O)$$ -/
def emptyIncident (o : Outcome) : Prop := isEmptyBranch o = true

/-- **The incident predicate is strict**: some outcome (every stage false) is not an empty branch.
$$\exists O,\ \lnot\operatorname{empty}(O)$$ -/
theorem emptyIncident_strict : Strict emptyIncident :=
  ⟨⟨false, false, false, false, false, false, false⟩, by unfold emptyIncident; decide⟩

/-- **The registry row of `inc-land-dry-no-verdict`** (docs/team/incidents/ledger.json): incident inputs
$E_{\mathrm{empty}}$, replay `emptyNoVerdict`.
$$i_{\mathrm{dry}} = (\texttt{inc-land-dry-no-verdict},\ E_{\mathrm{empty}},\ \mathrm{emptyNoVerdict})$$ -/
def incLandDryNoVerdict : Incident Outcome (String → Out) where
  id := "inc-land-dry-no-verdict"
  pred := emptyIncident
  replay := emptyNoVerdict

/-- **The incident registry of the dry-run signature**: the one ledger incident of this decision. The mutants
`exnNoVerdict` and `emptyDone` are not rows: the ledger has no incident for them.
$$R_{\mathrm{dry}} = [i_{\mathrm{dry}}]$$ -/
def landDryRegistry : Registry Outcome (String → Out) where
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

#guard landDryRegistry.rows.map (·.id) == ["inc-land-dry-no-verdict"]

/-- **`emptyNoVerdict` is the real run off the empty branch.** For every outcome that is not an empty branch, and
every task, `emptyNoVerdict` and `dryOut` give the same output.
$$\mathrm{AgreesOff}(\mathrm{dryOut}, \mathrm{emptyNoVerdict}, E_{\mathrm{empty}})$$ -/
theorem emptyNoVerdict_agrees_off : AgreesOff dryOut emptyNoVerdict emptyIncident := by
  intro o h
  funext t
  simp only [emptyIncident, Bool.not_eq_true] at h
  simp only [emptyNoVerdict, dryOut, h, Bool.false_eq_true, ite_false]

/-- **The registry is faithful to the real run**: every row's replay equals `dryOut` off that row's incident inputs.
$$\mathrm{Faithful}(\mathrm{dryOut}, R_{\mathrm{dry}})$$ -/
theorem landDryRegistry_faithful : landDryRegistry.Faithful dryOut := fun i hi => by
  simp only [landDryRegistry, List.mem_singleton] at hi
  subst hi
  exact emptyNoVerdict_agrees_off

/-! ## Step 4: pointwise checks and the search, before any proof -/

/-- All 128 stage outcomes, through $\mathbb B^7$.
$$\mathrm{all}_{\mathrm{Outcome}} = [(a_1, \dots, a_7) : a_i \in \{\mathrm{false}, \mathrm{true}\}]$$ -/
instance instEnumAllOutcome : EnumAll Outcome :=
  EnumAll.ofEquiv (β := Bool × Bool × Bool × Bool × Bool × Bool × Bool)
    (fun ⟨a, b, c, d, e, f, g⟩ => ⟨a, b, c, d, e, f, g⟩)
    (fun o => (o.threw, o.fresh, o.own, o.scope, o.merges, o.reads, o.lints)) (fun _ => rfl)

/-- The pointwise check of `NoSilentExit` at task $t$ and outcome $O$.
$$q_1(r, t, O) \iff \operatorname{nV}(r(O, t).\mathrm{lines}) = 1$$ -/
def qOneVerdict (run : DryImpl) (t : String) (o : Outcome) : Bool := verdictCount (run o t).lines == 1

/-- The pointwise check of `TruthfulVerdict` at task $t$ and outcome $O$.
$$q_2(r, t, O) \iff \operatorname{last}(r(O, t).\mathrm{lines}) = \mathrm{some}(\operatorname{line}(\operatorname{kind}(O), t)) \wedge r(O, t).\mathrm{exit} = \operatorname{code}(\operatorname{kind}(O))$$ -/
def qTruthful (run : DryImpl) (t : String) (o : Outcome) : Bool :=
  (run o t).lines.getLast? == some (verdictLine o.kind t) && (run o t).exit == o.kind.exitCode

/-- **`P_iff` for `NoSilentExit`.** For every implementation, the property is the check passing at every task and
every outcome.
$$\forall r,\ \mathrm{NoSilentExit}(r) \iff \forall t\, O,\ q_1(r, t, O) = \mathrm{true}$$ -/
theorem NoSilentExit_iff (run : DryImpl) : NoSilentExit run ↔ ∀ t o, qOneVerdict run t o = true := by
  simp only [NoSilentExit, qOneVerdict, beq_iff_eq]
  exact ⟨fun h t o => h o t, fun h o t => h t o⟩

/-- **`P_iff` for `TruthfulVerdict`.** For every implementation, the property is the check passing at every task and
every outcome.
$$\forall r,\ \mathrm{TruthfulVerdict}(r) \iff \forall t\, O,\ q_2(r, t, O) = \mathrm{true}$$ -/
theorem TruthfulVerdict_iff (run : DryImpl) : TruthfulVerdict run ↔ ∀ t o, qTruthful run t o = true := by
  simp only [TruthfulVerdict, qTruthful, Bool.and_eq_true, beq_iff_eq]
  exact ⟨fun h t o => h o t, fun h o t => h t o⟩

/-- The `NoSilentExit` check at one task is sound: for every implementation and task, the property implies the check
at that task on every outcome.
$$\forall r\, t,\ \mathrm{NoSilentExit}(r) \Rightarrow \forall O,\ q_1(r, t, O) = \mathrm{true}$$ -/
theorem qOneVerdict_sound (run : DryImpl) (t : String) : NoSilentExit run → ∀ o, qOneVerdict run t o = true :=
  fun h => (NoSilentExit_iff run).mp h t

/-- The `TruthfulVerdict` check at one task is sound: for every implementation and task, the property implies the
check at that task on every outcome.
$$\forall r\, t,\ \mathrm{TruthfulVerdict}(r) \Rightarrow \forall O,\ q_2(r, t, O) = \mathrm{true}$$ -/
theorem qTruthful_sound (run : DryImpl) (t : String) : TruthfulVerdict run → ∀ o, qTruthful run t o = true :=
  fun h => (TruthfulVerdict_iff run).mp h t

-- the search over all 128 outcomes, task `x`: clean on the real run, a counterexample for each bad run
#guard (EnumAll.all : List Outcome).length == 128
#guard (search EnumAll.all (qOneVerdict dryOut "x")).isNone
#guard (search EnumAll.all (qTruthful dryOut "x")).isNone
#guard (search EnumAll.all (qOneVerdict emptyNoVerdict "x")).isSome
#guard (search EnumAll.all (qOneVerdict exnNoVerdict "x")).isSome
-- what it found: the empty branch (threw, fresh, own) = (false, true, false), and the first exception outcome
-- (for task "x"; `emptyNoVerdict_search` and `exnNoVerdict_search` in step 6b prove it for every task)
#guard ((search EnumAll.all (qOneVerdict emptyNoVerdict "x")).map fun o => (o.threw, o.fresh, o.own)) ==
  some (false, true, false)
#guard ((search EnumAll.all (qOneVerdict exnNoVerdict "x")).map (·.threw)) == some true
-- NoSilentExit is blind to emptyDone (one verdict line, the wrong one); TruthfulVerdict sees it
#guard (search EnumAll.all (qOneVerdict emptyDone "x")).isNone
#guard (search EnumAll.all (qTruthful emptyDone "x")).isSome
#guard (search EnumAll.all (qTruthful emptyNoVerdict "x")).isSome
#guard (search EnumAll.all (qTruthful exnNoVerdict "x")).isSome

/-! ## Step 5: kill witnesses, proved by the search -/

/-- **`NoSilentExit` rejects the registered incident.** The replay of `inc-land-dry-no-verdict` (it returns before
the verdict on an empty branch) fails the property.
$$\lnot\,\mathrm{NoSilentExit}(i_{\mathrm{dry}}.r)$$ -/
theorem NoSilentExit_rejects_inc_land_dry_no_verdict : ¬ NoSilentExit incLandDryNoVerdict.replay :=
  refutes_of_search _ _ _ EnumAll.all (qOneVerdict_sound incLandDryNoVerdict.replay "x") (by decide +kernel)

/-- **`TruthfulVerdict` rejects the registered incident.** The replay of `inc-land-dry-no-verdict` fails the
property.
$$\lnot\,\mathrm{TruthfulVerdict}(i_{\mathrm{dry}}.r)$$ -/
theorem TruthfulVerdict_rejects_inc_land_dry_no_verdict : ¬ TruthfulVerdict incLandDryNoVerdict.replay :=
  refutes_of_search _ _ _ EnumAll.all (qTruthful_sound incLandDryNoVerdict.replay "x") (by decide +kernel)

/-- **`NoSilentExit` kills a registered incident.**
$$\mathrm{Kills}(R_{\mathrm{dry}}, \mathrm{NoSilentExit})$$ -/
theorem NoSilentExit_kills : Kills landDryRegistry NoSilentExit :=
  kills_of_rejects _ _ incLandDryNoVerdict (List.mem_singleton.mpr rfl) NoSilentExit_rejects_inc_land_dry_no_verdict

/-- **`TruthfulVerdict` kills a registered incident.**
$$\mathrm{Kills}(R_{\mathrm{dry}}, \mathrm{TruthfulVerdict})$$ -/
theorem TruthfulVerdict_kills : Kills landDryRegistry TruthfulVerdict :=
  kills_of_rejects _ _ incLandDryNoVerdict (List.mem_singleton.mpr rfl)
    TruthfulVerdict_rejects_inc_land_dry_no_verdict

/-- **`NoSilentExit` rejects the exception mutant** (not a registered incident, so not a kill).
$$\lnot\,\mathrm{NoSilentExit}(\mathrm{exnNoVerdict})$$ -/
theorem NoSilentExit_rejects_exnNoVerdict : ¬ NoSilentExit exnNoVerdict :=
  refutes_of_search _ _ _ EnumAll.all (qOneVerdict_sound exnNoVerdict "x") (by decide +kernel)

/-- **`TruthfulVerdict` rejects the `done` mutant** (not a registered incident, so not a kill).
$$\lnot\,\mathrm{TruthfulVerdict}(\mathrm{emptyDone})$$ -/
theorem TruthfulVerdict_rejects_emptyDone : ¬ TruthfulVerdict emptyDone :=
  refutes_of_search _ _ _ EnumAll.all (qTruthful_sound emptyDone "x") (by decide +kernel)

/-- No verdict line comes from the log: every log line starts with `dry: `, so for every outcome the log has no
verdict line.
$$\forall O,\ \operatorname{nV}(\operatorname{log}(O)) = 0$$ -/
theorem log_no_verdict (o : Outcome) : verdictCount o.log = 0 := by
  simp only [verdictCount, List.length_eq_zero_iff, List.filter_eq_nil_iff]
  intro l hl
  simp only [Outcome.log, List.mem_map] at hl
  obtain ⟨s, _, rfl⟩ := hl
  cases s <;> decide +kernel

/-- Every verdict line is a verdict line: for every kind and task, `verdictLine` starts with `VERDICT `.
$$\forall k\, t,\ \operatorname{isV}(\operatorname{line}(k, t))$$ -/
theorem verdictLine_isVerdict (k : Kind) (t : String) : isVerdict (verdictLine k t) = true := by
  simp only [isVerdict, verdictLine, String.startsWith_string_iff, String.toList_append, List.append_assoc]
  exact List.prefix_append _ _

/-- **One property is not enough.** `NoSilentExit` holds of `emptyDone`: it prints one verdict line on every path, just
the wrong one. So `emptyDone` needs the second property's kill witness.
$$\mathrm{NoSilentExit}(\mathrm{emptyDone})$$ -/
theorem NoSilentExit_blind_emptyDone : NoSilentExit emptyDone := by
  intro o t
  simp only [emptyDone]
  split
  · simp only [verdictCount, List.filter_append, List.length_append]
    have := log_no_verdict o
    simp only [verdictCount] at this
    rw [this, List.filter_cons_of_pos (verdictLine_isVerdict .done t)]
    rfl
  · exact (dryRun_one_verdict o t).1

/-! ## Step 6: the proofs of the real implementation -/

/-- **The real dry run never exits silently.** For every outcome and task, `dryOut` prints exactly one verdict line.
$$\mathrm{NoSilentExit}(\mathrm{dryOut})$$ -/
theorem NoSilentExit_impl : NoSilentExit dryOut := fun o t => (dryRun_one_verdict o t).1

/-- **The real dry run tells the truth.** For every outcome and task, `dryOut`'s last line is the verdict of the
outcome's kind and its exit code is that kind's code.
$$\mathrm{TruthfulVerdict}(\mathrm{dryOut})$$ -/
theorem TruthfulVerdict_impl : TruthfulVerdict dryOut := fun o t => ⟨(dryRun_one_verdict o t).2, rfl⟩

/-- **`NoSilentExit` meets the convention**: it holds of `dryOut`, kills a registered incident, and the registry is
faithful to `dryOut`.
$$\mathrm{Convention}(R_{\mathrm{dry}}, \mathrm{dryOut}, \mathrm{NoSilentExit})$$ -/
theorem NoSilentExit_convention : Convention landDryRegistry dryOut NoSilentExit :=
  ⟨NoSilentExit_impl, NoSilentExit_kills, landDryRegistry_faithful⟩

/-- **`TruthfulVerdict` meets the convention**: it holds of `dryOut`, kills a registered incident, and the registry
is faithful to `dryOut`.
$$\mathrm{Convention}(R_{\mathrm{dry}}, \mathrm{dryOut}, \mathrm{TruthfulVerdict})$$ -/
theorem TruthfulVerdict_convention : Convention landDryRegistry dryOut TruthfulVerdict :=
  ⟨TruthfulVerdict_impl, TruthfulVerdict_kills, landDryRegistry_faithful⟩

/-! ## Step 6b: every kill is on the incident, for every task

The kill witnesses of step 5 only say that some input fails. With `landDryRegistry_faithful` (step 3) and the proofs
of step 6, `Fw.Spec.Props.failures_on_incident` / `fails_on_incident` show that the replay fails each check only on
incident inputs and on at least one of them. -/

/-- The `NoSilentExit` check on a (task, outcome) pair.
$$q_1'(r, (t, O)) = q_1(r, t, O)$$ -/
def qOneVerdictAt (run : DryImpl) (y : String × Outcome) : Bool := qOneVerdict run y.1 y.2

/-- The `TruthfulVerdict` check on a (task, outcome) pair.
$$q_2'(r, (t, O)) = q_2(r, t, O)$$ -/
def qTruthfulAt (run : DryImpl) (y : String × Outcome) : Bool := qTruthful run y.1 y.2

/-- `NoSilentExit` is the pointwise property of the pair check: for every implementation.
$$\forall r,\ \mathrm{NoSilentExit}(r) \iff \mathrm{Pointwise}(q_1')(r)$$ -/
theorem NoSilentExit_iff_pointwise (run : DryImpl) : NoSilentExit run ↔ Pointwise qOneVerdictAt run :=
  (NoSilentExit_iff run).trans ⟨fun h y => h y.1 y.2, fun h t o => h (t, o)⟩

/-- `TruthfulVerdict` is the pointwise property of the pair check: for every implementation.
$$\forall r,\ \mathrm{TruthfulVerdict}(r) \iff \mathrm{Pointwise}(q_2')(r)$$ -/
theorem TruthfulVerdict_iff_pointwise (run : DryImpl) : TruthfulVerdict run ↔ Pointwise qTruthfulAt run :=
  (TruthfulVerdict_iff run).trans ⟨fun h y => h y.1 y.2, fun h t o => h (t, o)⟩

/-- The `NoSilentExit` pair check at $(t, O)$ reads the implementation only at the outcome $O$.
$$\mathrm{ReadsAt}(q_1', (t, O) \mapsto O)$$ -/
theorem qOneVerdictAt_readsAt : ReadsAt qOneVerdictAt Prod.snd := by
  intro i j y h
  simp only [qOneVerdictAt, qOneVerdict, h]

/-- The `TruthfulVerdict` pair check at $(t, O)$ reads the implementation only at the outcome $O$.
$$\mathrm{ReadsAt}(q_2', (t, O) \mapsto O)$$ -/
theorem qTruthfulAt_readsAt : ReadsAt qTruthfulAt Prod.snd := by
  intro i j y h
  simp only [qTruthfulAt, qTruthful, h]

/-- **`NoSilentExit` kills the replay on the empty branch.** Every task and outcome on which the check fails for the
replay of `inc-land-dry-no-verdict` is an incident input (an empty branch), and some task and incident input make it
fail.
$$(\forall t\, O,\ q_1(i_{\mathrm{dry}}.r, t, O) = \mathrm{false} \Rightarrow E_{\mathrm{empty}}(O)) \wedge \exists t\, O,\ E_{\mathrm{empty}}(O) \wedge q_1(i_{\mathrm{dry}}.r, t, O) = \mathrm{false}$$ -/
theorem NoSilentExit_rejects_inc_land_dry_no_verdict_on_incident :
    (∀ t o, qOneVerdict incLandDryNoVerdict.replay t o = false → incLandDryNoVerdict.pred o) ∧
      ∃ t o, incLandDryNoVerdict.pred o ∧ qOneVerdict incLandDryNoVerdict.replay t o = false := by
  have hi := (NoSilentExit_iff_pointwise dryOut).mp NoSilentExit_impl
  have ha := landDryRegistry_faithful incLandDryNoVerdict (List.mem_singleton.mpr rfl)
  refine ⟨fun t o h => failures_on_incident qOneVerdictAt Prod.snd qOneVerdictAt_readsAt dryOut
    incLandDryNoVerdict.replay incLandDryNoVerdict.pred hi ha (t, o) h, ?_⟩
  obtain ⟨⟨t, o⟩, he, hq⟩ := fails_on_incident qOneVerdictAt Prod.snd qOneVerdictAt_readsAt dryOut
    incLandDryNoVerdict.replay incLandDryNoVerdict.pred hi ha
    (fun h => NoSilentExit_rejects_inc_land_dry_no_verdict ((NoSilentExit_iff_pointwise _).mpr h))
  exact ⟨t, o, he, hq⟩

/-- **`TruthfulVerdict` kills the replay on the empty branch.** Every task and outcome on which the check fails for
the replay of `inc-land-dry-no-verdict` is an incident input (an empty branch), and some task and incident input make
it fail.
$$(\forall t\, O,\ q_2(i_{\mathrm{dry}}.r, t, O) = \mathrm{false} \Rightarrow E_{\mathrm{empty}}(O)) \wedge \exists t\, O,\ E_{\mathrm{empty}}(O) \wedge q_2(i_{\mathrm{dry}}.r, t, O) = \mathrm{false}$$ -/
theorem TruthfulVerdict_rejects_inc_land_dry_no_verdict_on_incident :
    (∀ t o, qTruthful incLandDryNoVerdict.replay t o = false → incLandDryNoVerdict.pred o) ∧
      ∃ t o, incLandDryNoVerdict.pred o ∧ qTruthful incLandDryNoVerdict.replay t o = false := by
  have hi := (TruthfulVerdict_iff_pointwise dryOut).mp TruthfulVerdict_impl
  have ha := landDryRegistry_faithful incLandDryNoVerdict (List.mem_singleton.mpr rfl)
  refine ⟨fun t o h => failures_on_incident qTruthfulAt Prod.snd qTruthfulAt_readsAt dryOut
    incLandDryNoVerdict.replay incLandDryNoVerdict.pred hi ha (t, o) h, ?_⟩
  obtain ⟨⟨t, o⟩, he, hq⟩ := fails_on_incident qTruthfulAt Prod.snd qTruthfulAt_readsAt dryOut
    incLandDryNoVerdict.replay incLandDryNoVerdict.pred hi ha
    (fun h => TruthfulVerdict_rejects_inc_land_dry_no_verdict ((TruthfulVerdict_iff_pointwise _).mpr h))
  exact ⟨t, o, he, hq⟩

/-- On every task the `NoSilentExit` check of `emptyNoVerdict` fails exactly on the empty branch: for every task and
outcome.
$$\forall t\, O,\ q_1(\mathrm{emptyNoVerdict}, t, O) = \lnot\operatorname{empty}(O)$$ -/
theorem qOneVerdict_emptyNoVerdict (t : String) (o : Outcome) :
    qOneVerdict emptyNoVerdict t o = !isEmptyBranch o := by
  have h1 : verdictCount (dryRun o t) = 1 := (dryRun_one_verdict o t).1
  cases h : isEmptyBranch o <;> simp [qOneVerdict, emptyNoVerdict, h, h1, log_no_verdict]

/-- On every task the `NoSilentExit` check of `exnNoVerdict` fails exactly when the run threw: for every task and
outcome.
$$\forall t\, O,\ q_1(\mathrm{exnNoVerdict}, t, O) = \lnot\mathit{threw}(O)$$ -/
theorem qOneVerdict_exnNoVerdict (t : String) (o : Outcome) :
    qOneVerdict exnNoVerdict t o = !o.threw := by
  have h1 : verdictCount (dryRun o t) = 1 := (dryRun_one_verdict o t).1
  have h0 : verdictCount ["Error: land failed"] = 0 := by decide +kernel
  cases h : o.threw <;> simp [qOneVerdict, exnNoVerdict, h, h1, h0]

/-- **The search finds the empty branch, on every task.** For every task $t$, the first outcome on which the
`NoSilentExit` check of `emptyNoVerdict` fails is the empty branch with every later stage false.
$$\forall t,\ \operatorname{search}(\mathrm{all}, q_1(\mathrm{emptyNoVerdict}, t)) = \mathrm{some}(\mathrm{false}, \mathrm{true}, \mathrm{false}, \mathrm{false}, \mathrm{false}, \mathrm{false}, \mathrm{false})$$ -/
theorem emptyNoVerdict_search (t : String) :
    search EnumAll.all (qOneVerdict emptyNoVerdict t) = some ⟨false, true, false, false, false, false, false⟩ := by
  rw [show qOneVerdict emptyNoVerdict t = fun o => !isEmptyBranch o from funext (qOneVerdict_emptyNoVerdict t)]
  rfl

/-- **The search finds an exception, on every task.** For every task $t$, the first outcome on which the
`NoSilentExit` check of `exnNoVerdict` fails is the one that threw with every other stage false.
$$\forall t,\ \operatorname{search}(\mathrm{all}, q_1(\mathrm{exnNoVerdict}, t)) = \mathrm{some}(\mathrm{true}, \mathrm{false}, \mathrm{false}, \mathrm{false}, \mathrm{false}, \mathrm{false}, \mathrm{false})$$ -/
theorem exnNoVerdict_search (t : String) :
    search EnumAll.all (qOneVerdict exnNoVerdict t) = some ⟨true, false, false, false, false, false, false⟩ := by
  rw [show qOneVerdict exnNoVerdict t = fun o => !o.threw from funext (qOneVerdict_exnNoVerdict t)]
  rfl

/-! ## Step 6c: an unrelated property is not a kill

The round-2 loophole: with a bad implementation and an incident predicate chosen per property, an unrelated property
met every rule. `Silly` (exit code at most 100) holds of `dryOut` and rejects a made-up `sillyBad` that differs from
`dryOut` only on the empty branch, yet it passes the registered replay, so it kills no registered incident. -/

/-- **An unrelated property**: for every outcome and task, the exit code is at most 100.
$$\mathrm{Silly}(r) \iff \forall O\, t,\ r(O, t).\mathrm{exit} \le 100$$ -/
def Silly (run : DryImpl) : Prop := ∀ o t, (run o t).exit ≤ 100

/-- **A made-up bad implementation**: on an empty branch the real lines with exit code 200; otherwise the real run.
$$\mathrm{sillyBad}(O, t) = \begin{cases} (\operatorname{run}(O, t), 200) & \operatorname{empty}(O) \\ \mathrm{dryOut}(O, t) & \text{otherwise} \end{cases}$$ -/
def sillyBad : DryImpl := fun o t => if isEmptyBranch o then ⟨dryRun o t, 200⟩ else dryOut o t

/-- `Silly` holds of the real run: every kind's exit code is at most 100.
$$\mathrm{Silly}(\mathrm{dryOut})$$ -/
theorem Silly_impl : Silly dryOut := by
  intro o t
  simp only [dryOut]
  cases o.kind <;> decide

/-- `Silly` rejects the made-up bad implementation, which counted as a kill in round 2 and counts for nothing now.
$$\lnot\,\mathrm{Silly}(\mathrm{sillyBad})$$ -/
theorem Silly_rejects_sillyBad : ¬ Silly sillyBad := fun h => by
  have := h ⟨false, true, false, false, false, false, false⟩ "x"
  simp [sillyBad, isEmptyBranch] at this

/-- **`Silly` passes the registered replay**: it is not a kill witness for `inc-land-dry-no-verdict`.
$$\lnot\lnot\,\mathrm{Silly}(i_{\mathrm{dry}}.r)$$ -/
theorem Silly_passes_replay : ¬ ¬ Silly incLandDryNoVerdict.replay := fun hn => hn (by
  intro o t
  show (emptyNoVerdict o t).exit ≤ 100
  simp only [emptyNoVerdict]
  split
  · show 0 ≤ 100
    omega
  · exact Silly_impl o t)

/-- **`Silly` kills no registered incident.**
$$\lnot\,\mathrm{Kills}(R_{\mathrm{dry}}, \mathrm{Silly})$$ -/
theorem Silly_not_kill : ¬ Kills landDryRegistry Silly :=
  not_kills_of_passes _ _ fun i hi => by
    simp only [landDryRegistry, List.mem_singleton] at hi
    subst hi
    exact Classical.not_not.mp Silly_passes_replay

/-- **`Silly` does not meet the convention**, although it holds of `dryOut`.
$$\lnot\,\mathrm{Convention}(R_{\mathrm{dry}}, \mathrm{dryOut}, \mathrm{Silly})$$ -/
theorem Silly_not_convention : ¬ Convention landDryRegistry dryOut Silly := fun h => Silly_not_kill h.kills

/-! ## Step 7: the premise Lean cannot see, in the statement -/

/-- The premise that `land.ts` writes `dryOut`'s lines to stdout unchanged (a process boundary, kind shell). It is an
example id: the registry entry is task `lfg-premise-registry`.
$$p_{\mathrm{out}} = (\mathrm{shell}, \texttt{land.dryPrintsOutVerbatim})$$ -/
def printsVerbatim : Premise := { kind := .shell, id := "land.dryPrintsOutVerbatim" }

/-- **The real stdout has one verdict line, under a named premise.** For every stdout function $s$: if (premise
$p_{\mathrm{out}}$) $s$ is `dryOut`'s lines for every outcome and task, then for every outcome and task $s$ has exactly
one verdict line.
$$\forall s,\ \mathrm{Assume}\big(p_{\mathrm{out}},\ \forall O\, t,\ s(O, t) = \mathrm{dryOut}(O, t).\mathrm{lines}\big) \Rightarrow \forall O\, t,\ \operatorname{nV}(s(O, t)) = 1$$ -/
theorem stdout_one_verdict (stdout : Outcome → String → List String)
    (h : Assume printsVerbatim (∀ o t, stdout o t = (dryOut o t).lines)) (o : Outcome) (t : String) :
    verdictCount (stdout o t) = 1 := by
  rw [h.elim o t]
  exact NoSilentExit_impl o t

end Fw.Spec.Props.LandDryDemo
