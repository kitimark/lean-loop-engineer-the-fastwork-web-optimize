/-!
# Did a CI run pass? (task `ci-own-trigger`, round 2)

Since every lane has a guard job (`Fw.Ci.Intent`), a run whose guard skipped every heavy job still ends with the
workflow conclusion `success`. `fw ci wait` used to read that as a pass, so an agent waiting on a lane nobody asked for
read PASS for a lane that never ran. Here the verdict reads the jobs: a run passes only when its guard decided to run,
at least one other job ran, and every job that ran succeeded. A run whose guard skipped (its `if:` was false, or it
decided `run=false`) is *not run*: a verdict of its own, exit code 4, never a pass (`skipped_never_pass`).

The facts come from one `gh run view <id> --json jobs` per finished run (the glue in `packages/gh-budget/src/wait.ts`,
charged to the request budget); fwcore's op `ci.verdict` (`Fw.Wire.Ci`) decides.

The guard shows its decision as a step: `decision: run` runs when it decided `run=true`, `decision: skip` when it
decided `run=false` (`decisionStep`); a run from before these steps shows neither (`decision = none`).
-/
namespace Fw.Ci.Verdict

/-- A job's conclusion, folded: GitHub's `success`, `skipped` and `cancelled`; everything else (`failure`, `timed_out`,
`action_required`, `neutral`, `stale`, `startup_failure`, no conclusion) is `failure`.
$$c \in \{\mathrm{ok},\ \mathrm{skip},\ \mathrm{cancel},\ \mathrm{fail}\}$$ -/
inductive Concl where
  | success
  | skipped
  | cancelled
  | failure
  deriving DecidableEq, Repr

/-- GitHub's conclusion text, folded.
$$\forall s:\ \operatorname{concl}(s) = \begin{cases} \mathrm{ok} & s = \texttt{success} \\ \mathrm{skip} & s = \texttt{skipped} \\ \mathrm{cancel} & s = \texttt{cancelled} \\ \mathrm{fail} & \text{otherwise} \end{cases}$$ -/
def conclOf (s : String) : Concl :=
  match s with
  | "success" => .success
  | "skipped" => .skipped
  | "cancelled" => .cancelled
  | _ => .failure

/-- The facts of one finished run. `guard`: the guard job's conclusion (`skipped` when its `if:` was false).
`decision`: the guard's `run=…` as its decision step shows it (`none`: the run shows no decision step). `jobs`: the
conclusions of every other job.
$$f = (g,\ d,\ J), \quad d \in \{\top, \bot, \mathrm{none}\}$$ -/
structure Facts where
  guard : Concl
  decision : Option Bool
  jobs : List Concl
  deriving Repr

/-- The verdict of a run. $$v \in \{\mathrm{pass},\ \mathrm{fail},\ \mathrm{notRun}\}$$ -/
inductive Verdict where
  | pass
  | fail
  | notRun
  deriving DecidableEq, Repr

/-- A job ran: it was not skipped. $$\forall c:\ \operatorname{ran}(c) \iff c \ne \mathrm{skip}$$ -/
def ran (c : Concl) : Bool := c != .skipped

/-- The guard decided to run: its job succeeded and it did not show `run=false` (no decision step counts as run, the
jobs then decide).
$$\forall f:\ \operatorname{says}(f) \iff f.g = \mathrm{ok} \land f.d \ne \mathrm{some}(\bot)$$ -/
def says (f : Facts) : Bool := f.guard == .success && f.decision != some false

/-- **The verdict.** Not run: the guard was skipped, or it succeeded and decided `run=false` or no other job ran. Pass:
the guard decided to run, some other job ran, and every job that ran succeeded. Fail: everything else (a failed or
cancelled guard, a job that ran and did not succeed).
$$\forall f:\ \operatorname{verdict}(f) = \begin{cases} \mathrm{notRun} & f.g = \mathrm{skip} \lor \bigl(f.g = \mathrm{ok} \land (f.d = \mathrm{some}(\bot) \lor \forall c \in f.J:\ \lnot\operatorname{ran}(c))\bigr) \\ \mathrm{pass} & \text{else if } f.g = \mathrm{ok} \land \forall c \in f.J:\ \operatorname{ran}(c) \Rightarrow c = \mathrm{ok} \\ \mathrm{fail} & \text{otherwise} \end{cases}$$ -/
def verdict (f : Facts) : Verdict :=
  if f.guard == .skipped || (f.guard == .success && (f.decision == some false || !f.jobs.any ran)) then .notRun
  else if f.guard == .success && f.jobs.all (fun c => !ran c || c == .success) then .pass
  else .fail

/-- **A skipped guard never passes.** A run whose guard job was skipped (its `if:` was false) is not run, whatever its
other jobs show.
$$\forall f:\ f.g = \mathrm{skip} \Rightarrow \operatorname{verdict}(f) = \mathrm{notRun}$$ -/
theorem skipped_never_pass (f : Facts) (h : f.guard = .skipped) : verdict f = .notRun := by
  simp [verdict, h]

/-- **No job ran, no pass.** If every non-guard job was skipped, the run does not pass.
$$\forall f:\ (\forall c \in f.J:\ c = \mathrm{skip}) \Rightarrow \operatorname{verdict}(f) \ne \mathrm{pass}$$ -/
theorem all_skipped_never_pass (f : Facts) (h : ∀ c ∈ f.jobs, c = .skipped) : verdict f ≠ .pass := by
  have hn : f.jobs.any ran = false := by
    rw [List.any_eq_false]; intro c hc; simp [ran, h c hc]
  unfold verdict
  cases hg : f.guard <;> simp [hn]

/-- **A guard that decided `run=false` never passes.**
$$\forall f:\ f.d = \mathrm{some}(\bot) \Rightarrow \operatorname{verdict}(f) \ne \mathrm{pass}$$ -/
theorem decided_skip_never_pass (f : Facts) (h : f.decision = some false) : verdict f ≠ .pass := by
  unfold verdict
  cases hg : f.guard <;> simp [h]

/-- **When a run passes.** Exactly when the guard job succeeded and did not decide `run=false`, at least one other
job ran, and every job that ran succeeded.
$$\forall f:\ \operatorname{verdict}(f) = \mathrm{pass} \iff f.g = \mathrm{ok} \land f.d \ne \mathrm{some}(\bot) \land (\exists c \in f.J:\ c \ne \mathrm{skip}) \land (\forall c \in f.J:\ c \ne \mathrm{skip} \Rightarrow c = \mathrm{ok})$$ -/
theorem pass_iff (f : Facts) :
    verdict f = .pass ↔ f.guard = .success ∧ f.decision ≠ some false ∧ (∃ c ∈ f.jobs, c ≠ .skipped) ∧
      (∀ c ∈ f.jobs, c ≠ .skipped → c = .success) := by
  unfold verdict
  cases hg : f.guard <;> simp [ran, List.all_eq_true]
  by_cases hd : f.decision = some false
  · simp [hd]
  · simp only [hd, false_or, not_false_eq_true, true_and]
    by_cases hA : ∀ x ∈ f.jobs, x = .skipped
    · rw [ite_eq_left_of_eq_true _ _ (eq_true hA)]
      refine ⟨(fun h => nomatch h), fun ⟨⟨c, hc, hs⟩, _⟩ => absurd (hA c hc) hs⟩
    · have hE : ∃ c, c ∈ f.jobs ∧ ¬c = .skipped :=
        Classical.byContradiction fun hn => hA fun x hx =>
          Classical.byContradiction fun h => hn ⟨x, hx, h⟩
      rw [ite_eq_right_of_eq_false _ _ (eq_false hA)]
      by_cases hB : ∀ x ∈ f.jobs, x = .skipped ∨ x = .success
      · rw [ite_eq_left_of_eq_true _ _ (eq_true hB)]
        exact ⟨fun _ => ⟨hE, fun c hc hs => (hB c hc).resolve_left hs⟩, fun _ => rfl⟩
      · rw [ite_eq_right_of_eq_false _ _ (eq_false hB)]
        refine ⟨(fun h => nomatch h), fun ⟨_, h⟩ => ?_⟩
        exact absurd (fun x hx => by
          by_cases hs : x = .skipped
          · exact Or.inl hs
          · exact Or.inr (h x hx hs)) hB

/-- The exit code of a verdict: 0 pass, 1 fail, 4 not run (2, 3 and 64 are the wait's own: no run, timeout, usage).
$$\operatorname{code}(\mathrm{pass}) = 0,\ \operatorname{code}(\mathrm{fail}) = 1,\ \operatorname{code}(\mathrm{notRun}) = 4$$ -/
def code : Verdict → Nat
  | .pass => 0
  | .fail => 1
  | .notRun => 4

/-- The verdict of a wait over several runs (one per workflow): fail if any failed, else pass if any passed, else not
run (also for no run at all).
$$\forall V:\ \operatorname{all}(V) = \begin{cases} \mathrm{fail} & \mathrm{fail} \in V \\ \mathrm{pass} & \mathrm{fail} \notin V \land \mathrm{pass} \in V \\ \mathrm{notRun} & \text{otherwise} \end{cases}$$ -/
def combine (vs : List Verdict) : Verdict :=
  if vs.contains .fail then .fail else if vs.contains .pass then .pass else .notRun

/-- **A combined pass has a real pass behind it.** The wait passes iff no run failed and at least one run passed; so
a wait over runs that were all skipped never passes.
$$\forall V:\ \operatorname{all}(V) = \mathrm{pass} \iff \mathrm{fail} \notin V \land \mathrm{pass} \in V$$ -/
theorem combine_pass_iff (vs : List Verdict) : combine vs = .pass ↔ .fail ∉ vs ∧ .pass ∈ vs := by
  unfold combine
  by_cases hf : Verdict.fail ∈ vs <;> by_cases hp : Verdict.pass ∈ vs <;> simp [hf, hp]

/-- **One run: the combined verdict is its own.** $$\forall v:\ \operatorname{all}([v]) = v$$ -/
theorem combine_single (v : Verdict) : combine [v] = v := by
  cases v <;> rfl

/-- The name of a verdict as the wait prints it. $$\mathrm{pass} \mapsto \texttt{pass},\ \mathrm{fail} \mapsto \texttt{fail},\ \mathrm{notRun} \mapsto \texttt{not-run}$$ -/
def name : Verdict → String
  | .pass => "pass"
  | .fail => "fail"
  | .notRun => "not-run"

/-- The guard's decision steps: the step that runs when it decided `run=true`, and the prefix of the one that runs
when it decided `run=false` (its name continues with the reason).
$$\mathrm{step}(\top) = \texttt{decision: run},\ \mathrm{step}(\bot) = \texttt{decision: skip}$$ -/
def decisionStep : Bool → String
  | true => "decision: run"
  | false => "decision: skip"

/-- The decision a guard's steps show: `some true` if the step `decision: run` succeeded, else `some false` if a step
whose name starts with `decision: skip` succeeded, else `none` (a run from before the steps, or a guard that failed
first). Steps are (name, conclusion) pairs; a step whose `if:` was false has conclusion `skipped`.
$$\forall T:\ \operatorname{dec}(T) = \begin{cases} \mathrm{some}(\top) & \exists (n, c) \in T:\ n = \mathrm{step}(\top) \land c = \mathrm{ok} \\ \mathrm{some}(\bot) & \text{else if } \exists (n, c) \in T:\ \mathrm{step}(\bot) \sqsubseteq_{\mathrm{pre}} n \land c = \mathrm{ok} \\ \mathrm{none} & \text{otherwise} \end{cases}$$ -/
def decisionOf (steps : List (String × Concl)) : Option Bool :=
  if steps.any (fun (n, c) => n == decisionStep true && c == .success) then some true
  else if steps.any (fun (n, c) => n.startsWith (decisionStep false) && c == .success) then some false
  else none

/-- Why a run did not run, as the wait prints it: a skipped guard was stopped by its `if:` (the head commit of a `ci/**`
push does not name the lane); otherwise the text after `decision: skip: ` in the name of the first succeeded step that
starts with `decision: skip` (the guard's reason); otherwise no reason.
$$\forall g, T:\ \operatorname{why}(g, T) = \begin{cases} \texttt{guard if: the head commit does not ask for this lane} & g = \mathrm{skip} \\ n \setminus \texttt{decision: skip} & \text{else if } (n, \mathrm{ok}) \text{ is the first } (n, c) \in T \text{ with } \mathrm{step}(\bot) \sqsubseteq_{\mathrm{pre}} n \land c = \mathrm{ok} \\ \texttt{""} & \text{otherwise} \end{cases}$$
where $n \setminus p$ drops $p$ followed by `: ` when $n$ starts with that, else drops $p$. -/
def reasonOf (guard : Concl) (steps : List (String × Concl)) : String :=
  if guard == .skipped then "guard if: the head commit does not ask for this lane"
  else match steps.find? (fun (n, c) => n.startsWith (decisionStep false) && c == .success) with
    | some (n, _) =>
      let p := decisionStep false ++ ": "
      if n.startsWith p then (n.drop p.length).toString else (n.drop (decisionStep false).length).toString
    | none => ""

/-- **A shown skip decision never passes.** If the guard's steps show a skip decision (`decisionOf` gives
`some false`), the run is not a pass, whatever the guard's conclusion and the jobs.
$$\forall g, T, J:\ \operatorname{dec}(T) = \mathrm{some}(\bot) \Rightarrow \operatorname{verdict}(g, \operatorname{dec}(T), J) \ne \mathrm{pass}$$ -/
theorem shown_skip_never_pass (g : Concl) (steps : List (String × Concl)) (jobs : List Concl)
    (h : decisionOf steps = some false) : verdict ⟨g, decisionOf steps, jobs⟩ ≠ .pass :=
  decided_skip_never_pass ⟨g, decisionOf steps, jobs⟩ h

#guard decisionOf [("Set up job", .success), ("decision: run", .success), ("decision: skip: x", .skipped)] == some true
#guard decisionOf [("decision: run", .skipped), ("decision: skip: no input changed", .success)] == some false
#guard decisionOf [("guard", .success)] == none
#guard reasonOf .success [("decision: run", .skipped), ("decision: skip: no input changed", .success)] ==
  "no input changed"
#guard reasonOf .skipped [] == "guard if: the head commit does not ask for this lane"
#guard reasonOf .success [("decision: run", .success)] == ""

-- the lead's case: every heavy job skipped at the guard, workflow conclusion success
#guard verdict ⟨.skipped, none, [.skipped, .skipped]⟩ == .notRun
#guard verdict ⟨.success, some false, [.skipped]⟩ == .notRun
#guard verdict ⟨.success, none, [.skipped, .skipped]⟩ == .notRun
#guard verdict ⟨.success, some true, [.success, .skipped]⟩ == .pass
#guard verdict ⟨.success, none, [.success]⟩ == .pass
#guard verdict ⟨.success, some true, [.success, .failure]⟩ == .fail
#guard verdict ⟨.success, some true, [.cancelled]⟩ == .fail
#guard verdict ⟨.failure, none, []⟩ == .fail
#guard verdict ⟨.cancelled, none, [.skipped]⟩ == .fail
#guard verdict ⟨.success, some true, []⟩ == .notRun
#guard combine [.pass, .notRun] == .pass
#guard combine [.notRun, .notRun] == .notRun
#guard combine [.pass, .fail] == .fail
#guard combine [] == .notRun
#guard conclOf "timed_out" == .failure && conclOf "skipped" == .skipped
#guard (([Verdict.pass, .fail, .notRun].map code) == [0, 1, 4])

end Fw.Ci.Verdict
