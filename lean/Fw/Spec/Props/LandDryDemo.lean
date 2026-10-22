import Fw.Console.LandDry
import Fw.Spec.Incidents
import Fw.Search
/-!
# Worked example: properties first for `fw land --dry` (incident `inc-land-dry-no-verdict`)

The incident: on a branch with no commits of its own, `fw land --dry` printed a path and no `VERDICT` line, so a
script reading the verdict found none. This module replays the property-first workflow on that decision
(docs/team/tools/lean-first.md walks through it):

1. **Signature.** `Fw.Spec.LandDrySig.DryImpl := Outcome → String → Out`: stage outcomes and task in, stdout lines
   and exit code out; `Fw.Spec.Incidents.Sig.landDry` names it for the registry.
2. **Properties over the signature** (no implementation needed): `NoSilentExit` (exactly one `VERDICT` line) and
   `TruthfulVerdict` (the last line is the verdict of the first failing stage, and the exit code is that kind's code).
3. **The registered incident and its replay** live in `Fw.Spec.Incidents` (the one registry), not here: row
   `incLandDryNoVerdict` with incident inputs `emptyIncident` (an empty branch) and replay `emptyNoVerdict` (on an
   empty branch it prints only a path line). This module only checks the replay against the real run
   (`landDryRegistry_faithful`). Two extra mutants, not registered incidents: `exnNoVerdict` (a top-level catch
   prints the error and exits 1) and `emptyDone` (the empty branch says `done`).
4. **Search before proof.** Pointwise checks `qOneVerdict`, `qTruthful` with `*_sound` lemmas; `#guard`s run the
   search over all 256 outcomes (`𝔹^8`, exhaustive) and find the bug in each bad implementation. The
   `emptyDone` guard shows that `NoSilentExit` alone is blind to that bug, which is why `TruthfulVerdict` exists.
5. **Kill witnesses** against the registered replay, `P_rejects_inc_land_dry_no_verdict : ¬ P
   incLandDryNoVerdict.replay`, proved by running the search (`Fw.Search.refutes_of_search`), and so
   `Kills .landDry P` (`*_kills`). The mutants get `¬ P bad` theorems too, but those are not kills.
6. **Proof of the real implementation** `dryOut` (`NoSilentExit_impl`, `TruthfulVerdict_impl`), from
   `Fw.Console.LandDry.dryRun_one_verdict`, and the whole convention `Convention .landDry dryOut P`
   (`*_convention`). The lint `lean/scripts/PropsLint.lean` checks that neither property mentions `dryOut` or a name
   it unfolds to outside `Fw.Spec.Incidents.vocab .landDry`.
   **6b. The kills are on the incident** (`*_on_incident`, from `Fw.Spec.Props.failures_on_incident` and
   `fails_on_incident`): the replay fails each check only on incident inputs, and on at least one. The search
   result holds for every task name, not only `"x"` (`emptyNoVerdict_search`, `exnNoVerdict_search`).
   **6c. An unrelated property is not a kill.** `Silly` (the exit code is at most 100) holds of `dryOut` and rejects a
   made-up bad (`sillyBad`), but it passes the registered replay (`Silly_passes_replay`), so it kills no registered
   incident (`Silly_not_kill`) and does not meet the convention (`Silly_not_convention`). A kill still only means
   "separates `dryOut` from the replay"; that the math of `NoSilentExit` matches the ledger's `leanReason`
   (`|lines_VERDICT| = 1`) is the reviewer's check.
7. **Premise visible**: `stdout_one_verdict` carries `Assume` for the step Lean cannot see, that `land.ts` prints
   `dryOut`'s lines verbatim.
-/
namespace Fw.Spec.Props.LandDryDemo
open Fw.Console.LandVerdict Fw.Console.LandDry Fw.Search Fw.Spec.Props Fw.Spec.LandDrySig Fw.Spec.Incidents
  Fw.Spec.Incidents.LandDry

/-! ## Step 2: the properties, over the signature -/

/-- **Never a silent exit.** For every stage outcome and every task, the run prints exactly one verdict line. -/
def NoSilentExit (run : DryImpl) : Prop := ∀ o t, verdictCount (run o t).lines = 1

/-- **The verdict tells the truth.** For every stage outcome and every task, the last line is the verdict line of the
first failing stage's kind (`Outcome.kind`, specified by `kind_spec`) and the exit code is that kind's code. -/
def TruthfulVerdict (run : DryImpl) : Prop :=
  ∀ o t, (run o t).lines.getLast? = some (verdictLine o.kind t) ∧ (run o t).exit = o.kind.exitCode

/-! ## Step 3: bad implementations (mutants) and the real one; the registered replay is in `Fw.Spec.Incidents` -/

/-- **Mutant: an exception with no verdict** (no ledger incident, so not a registry row). A top-level catch prints
the error message and exits 1; otherwise it is the real run. -/
def exnNoVerdict : DryImpl := fun o t =>
  if o.threw then ⟨["Error: land failed"], 1⟩ else ⟨dryRun o t, o.kind.exitCode⟩

/-- **Mutant: an empty branch says `done`** (no ledger incident, so not a registry row). One verdict line, but the
wrong kind: nothing was landed. -/
def emptyDone : DryImpl := fun o t =>
  if isEmptyBranch o then ⟨o.log ++ [verdictLine .done t], 0⟩ else ⟨dryRun o t, o.kind.exitCode⟩

/-- **The real implementation**: the Lean dry run (`Fw.Console.LandDry.dryRun`) and the exit code of its kind. -/
def dryOut : DryImpl := fun o t => ⟨dryRun o t, o.kind.exitCode⟩

/-- **`emptyNoVerdict` is the real run off the empty branch.** For every outcome that is not an empty branch, and
every task, `emptyNoVerdict` and `dryOut` give the same output. -/
theorem emptyNoVerdict_agrees_off : AgreesOff dryOut emptyNoVerdict emptyIncident := by
  intro o h
  funext t
  simp only [emptyIncident, Bool.not_eq_true] at h
  simp only [emptyNoVerdict, dryOut, h, Bool.false_eq_true, ite_false]

/-- **The one registry is faithful to the real run**: every row of the dry-run registry agrees with `dryOut` off
that row's incident inputs. -/
theorem landDryRegistry_faithful : Faithful .landDry dryOut := fun i hi => by
  rw [mem_landDry] at hi
  subst hi
  exact emptyNoVerdict_agrees_off


/-! ## Step 4: pointwise checks and the search, before any proof -/

/-- All 256 stage outcomes, through `𝔹^8`. -/
instance instEnumAllOutcome : EnumAll Outcome :=
  EnumAll.ofEquiv (β := Bool × Bool × Bool × Bool × Bool × Bool × Bool × Bool)
    (fun ⟨a, b, c, d, e, f, g, h⟩ => ⟨a, b, c, d, e, f, g, h⟩)
    (fun o => (o.threw, o.fresh, o.own, o.scope, o.merges, o.installs, o.reads, o.lints)) (fun _ => rfl)

/-- The pointwise check of `NoSilentExit` at task `t` and outcome `O`. -/
def qOneVerdict (run : DryImpl) (t : String) (o : Outcome) : Bool := verdictCount (run o t).lines == 1

/-- The pointwise check of `TruthfulVerdict` at task `t` and outcome `O`. -/
def qTruthful (run : DryImpl) (t : String) (o : Outcome) : Bool :=
  (run o t).lines.getLast? == some (verdictLine o.kind t) && (run o t).exit == o.kind.exitCode

/-- **`P_iff` for `NoSilentExit`.** For every implementation, the property is the check passing at every task and
every outcome. -/
theorem NoSilentExit_iff (run : DryImpl) : NoSilentExit run ↔ ∀ t o, qOneVerdict run t o = true := by
  simp only [NoSilentExit, qOneVerdict, beq_iff_eq]
  exact ⟨fun h t o => h o t, fun h o t => h t o⟩

/-- **`P_iff` for `TruthfulVerdict`.** For every implementation, the property is the check passing at every task and
every outcome. -/
theorem TruthfulVerdict_iff (run : DryImpl) : TruthfulVerdict run ↔ ∀ t o, qTruthful run t o = true := by
  simp only [TruthfulVerdict, qTruthful, Bool.and_eq_true, beq_iff_eq]
  exact ⟨fun h t o => h o t, fun h o t => h t o⟩

/-- The `NoSilentExit` check at one task is sound: for every implementation and task, the property implies the check
at that task on every outcome. -/
theorem qOneVerdict_sound (run : DryImpl) (t : String) : NoSilentExit run → ∀ o, qOneVerdict run t o = true :=
  fun h => (NoSilentExit_iff run).mp h t

/-- The `TruthfulVerdict` check at one task is sound: for every implementation and task, the property implies the
check at that task on every outcome. -/
theorem qTruthful_sound (run : DryImpl) (t : String) : TruthfulVerdict run → ∀ o, qTruthful run t o = true :=
  fun h => (TruthfulVerdict_iff run).mp h t

-- the search over all 256 outcomes, task `x`: clean on the real run, a counterexample for each bad run
#guard (EnumAll.all : List Outcome).length == 256
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
the verdict on an empty branch) fails the property. -/
theorem NoSilentExit_rejects_inc_land_dry_no_verdict : ¬ NoSilentExit incLandDryNoVerdict.replay :=
  refutes_of_search _ _ _ EnumAll.all (qOneVerdict_sound incLandDryNoVerdict.replay "x") (by decide +kernel)

/-- **`TruthfulVerdict` rejects the registered incident.** The replay of `inc-land-dry-no-verdict` fails the
property. -/
theorem TruthfulVerdict_rejects_inc_land_dry_no_verdict : ¬ TruthfulVerdict incLandDryNoVerdict.replay :=
  refutes_of_search _ _ _ EnumAll.all (qTruthful_sound incLandDryNoVerdict.replay "x") (by decide +kernel)

/-- **`NoSilentExit` kills a registered incident.** -/
theorem NoSilentExit_kills : Kills .landDry NoSilentExit :=
  kills_of_rejects _ _ incLandDryNoVerdict incLandDryNoVerdict_mem NoSilentExit_rejects_inc_land_dry_no_verdict

/-- **`TruthfulVerdict` kills a registered incident.** -/
theorem TruthfulVerdict_kills : Kills .landDry TruthfulVerdict :=
  kills_of_rejects _ _ incLandDryNoVerdict incLandDryNoVerdict_mem
    TruthfulVerdict_rejects_inc_land_dry_no_verdict

/-- **`NoSilentExit` rejects the exception mutant** (not a registered incident, so not a kill). -/
theorem NoSilentExit_rejects_exnNoVerdict : ¬ NoSilentExit exnNoVerdict :=
  refutes_of_search _ _ _ EnumAll.all (qOneVerdict_sound exnNoVerdict "x") (by decide +kernel)

/-- **`TruthfulVerdict` rejects the `done` mutant** (not a registered incident, so not a kill). -/
theorem TruthfulVerdict_rejects_emptyDone : ¬ TruthfulVerdict emptyDone :=
  refutes_of_search _ _ _ EnumAll.all (qTruthful_sound emptyDone "x") (by decide +kernel)

/-- No verdict line comes from the log: every log line starts with `dry: `, so for every outcome the log has no
verdict line. -/
theorem log_no_verdict (o : Outcome) : verdictCount o.log = 0 := by
  simp only [verdictCount, List.length_eq_zero_iff, List.filter_eq_nil_iff]
  intro l hl
  simp only [Outcome.log, List.mem_map] at hl
  obtain ⟨s, _, rfl⟩ := hl
  cases s <;> decide +kernel

/-- Every verdict line is a verdict line: for every kind and task, `verdictLine` starts with `VERDICT `. -/
theorem verdictLine_isVerdict (k : Kind) (t : String) : isVerdict (verdictLine k t) = true := by
  simp only [isVerdict, verdictLine, String.startsWith_string_iff, String.toList_append, List.append_assoc]
  exact List.prefix_append _ _

/-- **One property is not enough.** `NoSilentExit` holds of `emptyDone`: it prints one verdict line on every path, just
the wrong one. So `emptyDone` needs the second property's kill witness. -/
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

/-- **The real dry run never exits silently.** For every outcome and task, `dryOut` prints exactly one verdict line. -/
theorem NoSilentExit_impl : NoSilentExit dryOut := fun o t => (dryRun_one_verdict o t).1

/-- **The real dry run tells the truth.** For every outcome and task, `dryOut`'s last line is the verdict of the
outcome's kind and its exit code is that kind's code. -/
theorem TruthfulVerdict_impl : TruthfulVerdict dryOut := fun o t => ⟨(dryRun_one_verdict o t).2, rfl⟩

/-- **`NoSilentExit` meets the convention**: it holds of `dryOut`, kills a registered incident, and the registry is
faithful to `dryOut`. -/
theorem NoSilentExit_convention : Convention .landDry dryOut NoSilentExit :=
  ⟨NoSilentExit_impl, NoSilentExit_kills, landDryRegistry_faithful⟩

/-- **`TruthfulVerdict` meets the convention**: it holds of `dryOut`, kills a registered incident, and the registry
is faithful to `dryOut`. -/
theorem TruthfulVerdict_convention : Convention .landDry dryOut TruthfulVerdict :=
  ⟨TruthfulVerdict_impl, TruthfulVerdict_kills, landDryRegistry_faithful⟩

/-! ## Step 6b: every kill is on the incident, for every task

The kill witnesses of step 5 only say that some input fails. With `landDryRegistry_faithful` (step 3) and the proofs
of step 6, `Fw.Spec.Props.failures_on_incident` / `fails_on_incident` show that the replay fails each check only on
incident inputs and on at least one of them. -/

/-- The `NoSilentExit` check on a (task, outcome) pair. -/
def qOneVerdictAt (run : DryImpl) (y : String × Outcome) : Bool := qOneVerdict run y.1 y.2

/-- The `TruthfulVerdict` check on a (task, outcome) pair. -/
def qTruthfulAt (run : DryImpl) (y : String × Outcome) : Bool := qTruthful run y.1 y.2

/-- `NoSilentExit` is the pointwise property of the pair check: for every implementation. -/
theorem NoSilentExit_iff_pointwise (run : DryImpl) : NoSilentExit run ↔ Pointwise qOneVerdictAt run :=
  (NoSilentExit_iff run).trans ⟨fun h y => h y.1 y.2, fun h t o => h (t, o)⟩

/-- `TruthfulVerdict` is the pointwise property of the pair check: for every implementation. -/
theorem TruthfulVerdict_iff_pointwise (run : DryImpl) : TruthfulVerdict run ↔ Pointwise qTruthfulAt run :=
  (TruthfulVerdict_iff run).trans ⟨fun h y => h y.1 y.2, fun h t o => h (t, o)⟩

/-- The `NoSilentExit` pair check at `(t, O)` reads the implementation only at the outcome `O`. -/
theorem qOneVerdictAt_readsAt : ReadsAt qOneVerdictAt Prod.snd := by
  intro i j y h
  simp only [qOneVerdictAt, qOneVerdict, h]

/-- The `TruthfulVerdict` pair check at `(t, O)` reads the implementation only at the outcome `O`. -/
theorem qTruthfulAt_readsAt : ReadsAt qTruthfulAt Prod.snd := by
  intro i j y h
  simp only [qTruthfulAt, qTruthful, h]

/-- **`NoSilentExit` kills the replay on the empty branch.** Every task and outcome on which the check fails for the
replay of `inc-land-dry-no-verdict` is an incident input (an empty branch), and some task and incident input make it
fail. -/
theorem NoSilentExit_rejects_inc_land_dry_no_verdict_on_incident :
    (∀ t o, qOneVerdict incLandDryNoVerdict.replay t o = false → incLandDryNoVerdict.pred o) ∧
      ∃ t o, incLandDryNoVerdict.pred o ∧ qOneVerdict incLandDryNoVerdict.replay t o = false := by
  have hi := (NoSilentExit_iff_pointwise dryOut).mp NoSilentExit_impl
  have ha := landDryRegistry_faithful incLandDryNoVerdict incLandDryNoVerdict_mem
  refine ⟨fun t o h => failures_on_incident qOneVerdictAt Prod.snd qOneVerdictAt_readsAt dryOut
    incLandDryNoVerdict.replay incLandDryNoVerdict.pred hi ha (t, o) h, ?_⟩
  obtain ⟨⟨t, o⟩, he, hq⟩ := fails_on_incident qOneVerdictAt Prod.snd qOneVerdictAt_readsAt dryOut
    incLandDryNoVerdict.replay incLandDryNoVerdict.pred hi ha
    (fun h => NoSilentExit_rejects_inc_land_dry_no_verdict ((NoSilentExit_iff_pointwise _).mpr h))
  exact ⟨t, o, he, hq⟩

/-- **`TruthfulVerdict` kills the replay on the empty branch.** Every task and outcome on which the check fails for
the replay of `inc-land-dry-no-verdict` is an incident input (an empty branch), and some task and incident input make
it fail. -/
theorem TruthfulVerdict_rejects_inc_land_dry_no_verdict_on_incident :
    (∀ t o, qTruthful incLandDryNoVerdict.replay t o = false → incLandDryNoVerdict.pred o) ∧
      ∃ t o, incLandDryNoVerdict.pred o ∧ qTruthful incLandDryNoVerdict.replay t o = false := by
  have hi := (TruthfulVerdict_iff_pointwise dryOut).mp TruthfulVerdict_impl
  have ha := landDryRegistry_faithful incLandDryNoVerdict incLandDryNoVerdict_mem
  refine ⟨fun t o h => failures_on_incident qTruthfulAt Prod.snd qTruthfulAt_readsAt dryOut
    incLandDryNoVerdict.replay incLandDryNoVerdict.pred hi ha (t, o) h, ?_⟩
  obtain ⟨⟨t, o⟩, he, hq⟩ := fails_on_incident qTruthfulAt Prod.snd qTruthfulAt_readsAt dryOut
    incLandDryNoVerdict.replay incLandDryNoVerdict.pred hi ha
    (fun h => TruthfulVerdict_rejects_inc_land_dry_no_verdict ((TruthfulVerdict_iff_pointwise _).mpr h))
  exact ⟨t, o, he, hq⟩

/-- On every task the `NoSilentExit` check of `emptyNoVerdict` fails exactly on the empty branch: for every task and
outcome. -/
theorem qOneVerdict_emptyNoVerdict (t : String) (o : Outcome) :
    qOneVerdict emptyNoVerdict t o = !isEmptyBranch o := by
  have h1 : verdictCount (dryRun o t) = 1 := (dryRun_one_verdict o t).1
  have h0 : verdictCount [pathLine] = 0 := by decide +kernel
  cases h : isEmptyBranch o <;> simp [qOneVerdict, emptyNoVerdict, h, h1, h0]

/-- On every task the `NoSilentExit` check of `exnNoVerdict` fails exactly when the run threw: for every task and
outcome. -/
theorem qOneVerdict_exnNoVerdict (t : String) (o : Outcome) :
    qOneVerdict exnNoVerdict t o = !o.threw := by
  have h1 : verdictCount (dryRun o t) = 1 := (dryRun_one_verdict o t).1
  have h0 : verdictCount ["Error: land failed"] = 0 := by decide +kernel
  cases h : o.threw <;> simp [qOneVerdict, exnNoVerdict, h, h1, h0]

/-- **The search finds the empty branch, on every task.** For every task `t`, the first outcome on which the
`NoSilentExit` check of `emptyNoVerdict` fails is the empty branch with every later stage false. -/
theorem emptyNoVerdict_search (t : String) :
    search EnumAll.all (qOneVerdict emptyNoVerdict t) = some ⟨false, true, false, false, false, false, false, false⟩ := by
  rw [show qOneVerdict emptyNoVerdict t = fun o => !isEmptyBranch o from funext (qOneVerdict_emptyNoVerdict t)]
  rfl

/-- **The search finds an exception, on every task.** For every task `t`, the first outcome on which the
`NoSilentExit` check of `exnNoVerdict` fails is the one that threw with every other stage false. -/
theorem exnNoVerdict_search (t : String) :
    search EnumAll.all (qOneVerdict exnNoVerdict t) = some ⟨true, false, false, false, false, false, false, false⟩ := by
  rw [show qOneVerdict exnNoVerdict t = fun o => !o.threw from funext (qOneVerdict_exnNoVerdict t)]
  rfl

/-! ## Step 6c: an unrelated property is not a kill

The round-2 loophole: with a bad implementation and an incident predicate chosen per property, an unrelated property
met every rule. `Silly` (exit code at most 100) holds of `dryOut` and rejects a made-up `sillyBad` that differs from
`dryOut` only on the empty branch, yet it passes the registered replay, so it kills no registered incident. -/

/-- **An unrelated property**: for every outcome and task, the exit code is at most 100. -/
def Silly (run : DryImpl) : Prop := ∀ o t, (run o t).exit ≤ 100

/-- **A made-up bad implementation**: on an empty branch the real lines with exit code 200; otherwise the real run. -/
def sillyBad : DryImpl := fun o t => if isEmptyBranch o then ⟨dryRun o t, 200⟩ else dryOut o t

/-- `Silly` holds of the real run: every kind's exit code is at most 100. -/
theorem Silly_impl : Silly dryOut := by
  intro o t
  simp only [dryOut]
  cases o.kind <;> decide

/-- `Silly` rejects the made-up bad implementation, which counted as a kill in round 2 and counts for nothing now. -/
theorem Silly_rejects_sillyBad : ¬ Silly sillyBad := fun h => by
  have := h ⟨false, true, false, false, false, false, false, false⟩ "x"
  simp [sillyBad, isEmptyBranch] at this

/-- **`Silly` passes the registered replay**: it is not a kill witness for `inc-land-dry-no-verdict` (the replay
keeps the real run's exit code on every input). -/
theorem Silly_passes_replay : ¬ ¬ Silly incLandDryNoVerdict.replay := fun hn => hn (by
  intro o t
  show (emptyNoVerdict o t).exit ≤ 100
  simp only [emptyNoVerdict]
  split <;> exact Silly_impl o t)

/-- **`Silly` kills no registered incident.** -/
theorem Silly_not_kill : ¬ Kills .landDry Silly :=
  not_kills_of_passes _ _ fun i hi => by
    rw [mem_landDry] at hi
    subst hi
    exact Classical.not_not.mp Silly_passes_replay

/-- **`Silly` does not meet the convention**, although it holds of `dryOut`. -/
theorem Silly_not_convention : ¬ Convention .landDry dryOut Silly := fun h => Silly_not_kill h.kills

/-! ## Step 7: the premise Lean cannot see, in the statement -/

/-- The premise that `land.ts` writes `dryOut`'s lines to stdout unchanged (a process boundary, kind shell). It is an
example id: the registry entry is task `lfg-premise-registry`. -/
def printsVerbatim : Premise := { kind := .shell, id := "land.dryPrintsOutVerbatim" }

/-- **The real stdout has one verdict line, under a named premise.** For every stdout function `s`: if (premise
`p_out`) `s` is `dryOut`'s lines for every outcome and task, then for every outcome and task `s` has exactly
one verdict line. -/
theorem stdout_one_verdict (stdout : Outcome → String → List String)
    (h : Assume printsVerbatim (∀ o t, stdout o t = (dryOut o t).lines)) (o : Outcome) (t : String) :
    verdictCount (stdout o t) = 1 := by
  rw [h.elim o t]
  exact NoSilentExit_impl o t

end Fw.Spec.Props.LandDryDemo
