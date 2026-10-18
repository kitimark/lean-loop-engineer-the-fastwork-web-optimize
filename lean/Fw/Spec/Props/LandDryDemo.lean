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
3. **Bad implementations** from the incident classes: `emptyNoVerdict` (the incident: the empty branch returns before
   the verdict), `exnNoVerdict` (a top-level catch prints the error and exits 1), `emptyDone` (the empty branch says
   `done`).
4. **Search before proof.** Pointwise checks `qOneVerdict`, `qTruthful` with `*_sound` lemmas; `#guard`s run the
   search over all 128 outcomes ($\mathbb B^7$, exhaustive) and find the bug in each bad implementation. The
   `emptyDone` guard shows that `NoSilentExit` alone is blind to that bug, which is why `TruthfulVerdict` exists.
5. **Kill witnesses** `*_rejects_*`, proved by running the search (`Fw.Search.refutes_of_search`).
6. **Proof of the real implementation** `dryOut` (`NoSilentExit_impl`, `TruthfulVerdict_impl`), from
   `Fw.Console.LandDry.dryRun_one_verdict`.
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

/-- **Bad: the incident.** On an empty branch the run returns after the log, before the verdict line (exit 0);
otherwise it is the real run.
$$\mathrm{emptyNoVerdict}(O, t) = \begin{cases} (\operatorname{log}(O), 0) & \operatorname{empty}(O) \\ (\operatorname{run}(O, t), \operatorname{code}(\operatorname{kind}(O))) & \text{otherwise} \end{cases}$$ -/
def emptyNoVerdict : DryImpl := fun o t =>
  if isEmptyBranch o then ⟨o.log, 0⟩ else ⟨dryRun o t, o.kind.exitCode⟩

/-- **Bad: an exception with no verdict.** A top-level catch prints the error message and exits 1; otherwise it is the
real run.
$$\mathrm{exnNoVerdict}(O, t) = \begin{cases} ([\texttt{Error: land failed}], 1) & \mathit{threw} \\ (\operatorname{run}(O, t), \operatorname{code}(\operatorname{kind}(O))) & \text{otherwise} \end{cases}$$ -/
def exnNoVerdict : DryImpl := fun o t =>
  if o.threw then ⟨["Error: land failed"], 1⟩ else ⟨dryRun o t, o.kind.exitCode⟩

/-- **Bad: an empty branch says `done`.** One verdict line, but the wrong kind: nothing was landed.
$$\mathrm{emptyDone}(O, t) = \begin{cases} (\operatorname{log}(O) \mathbin{+\!\!+} [\operatorname{line}(\mathrm{done}, t)], 0) & \operatorname{empty}(O) \\ (\operatorname{run}(O, t), \operatorname{code}(\operatorname{kind}(O))) & \text{otherwise} \end{cases}$$ -/
def emptyDone : DryImpl := fun o t =>
  if isEmptyBranch o then ⟨o.log ++ [verdictLine .done t], 0⟩ else ⟨dryRun o t, o.kind.exitCode⟩

/-- **The real implementation**: the Lean dry run (`Fw.Console.LandDry.dryRun`) and the exit code of its kind.
$$\mathrm{dryOut}(O, t) = (\operatorname{run}(O, t), \operatorname{code}(\operatorname{kind}(O)))$$ -/
def dryOut : DryImpl := fun o t => ⟨dryRun o t, o.kind.exitCode⟩

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
#guard ((search EnumAll.all (qOneVerdict emptyNoVerdict "x")).map fun o => (o.threw, o.fresh, o.own)) ==
  some (false, true, false)
#guard ((search EnumAll.all (qOneVerdict exnNoVerdict "x")).map (·.threw)) == some true
-- NoSilentExit is blind to emptyDone (one verdict line, the wrong one); TruthfulVerdict sees it
#guard (search EnumAll.all (qOneVerdict emptyDone "x")).isNone
#guard (search EnumAll.all (qTruthful emptyDone "x")).isSome
#guard (search EnumAll.all (qTruthful emptyNoVerdict "x")).isSome
#guard (search EnumAll.all (qTruthful exnNoVerdict "x")).isSome

/-! ## Step 5: kill witnesses, proved by the search -/

/-- **`NoSilentExit` rejects the incident.** The run that returns before the verdict on an empty branch fails the
property.
$$\lnot\,\mathrm{NoSilentExit}(\mathrm{emptyNoVerdict})$$ -/
theorem NoSilentExit_rejects_emptyNoVerdict : ¬ NoSilentExit emptyNoVerdict :=
  refutes_of_search _ _ _ EnumAll.all (qOneVerdict_sound emptyNoVerdict "x") (by decide +kernel)

/-- **`NoSilentExit` rejects an exception with no verdict.**
$$\lnot\,\mathrm{NoSilentExit}(\mathrm{exnNoVerdict})$$ -/
theorem NoSilentExit_rejects_exnNoVerdict : ¬ NoSilentExit exnNoVerdict :=
  refutes_of_search _ _ _ EnumAll.all (qOneVerdict_sound exnNoVerdict "x") (by decide +kernel)

/-- **`TruthfulVerdict` rejects `done` on an empty branch.**
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

/-! ## Step 7: the premise Lean cannot see, in the statement -/

/-- The premise that `land.ts` writes `dryOut`'s lines to stdout unchanged (a process boundary, kind shell). It is an
example id: the registry entry is task `lfg-premise-registry`.
$$p_{\mathrm{out}} = (\mathrm{shell}, \texttt{land.dryPrintsOutVerbatim})$$ -/
def printsVerbatim : Premise := ⟨.shell, "land.dryPrintsOutVerbatim"⟩

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
