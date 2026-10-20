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

Round 3: a heavy job whose run is no longer the branch tip stops at its first steps (the tip re-check,
`Fw.Ci.Intent.stale_never_works`): its step `stale: …` fails and the run is *not run* (`stale_never_pass`). A wait on a branch
(`combineRequested`) passes only when every lane the head commit requests, and the default lane (lean), has a passing
run for that commit (`combine_requested_never_pass`).

Round 4: when the head commit's message cannot be read, the requested lanes are unknown and the wait never passes
(`waitVerdict`, `unknown_request_never_pass`).

Round 5: no skip satisfies a lane, the default lane included: lean never skips as `unchanged` on a `ci/**` push
(`Fw.Ci.Intent.lean_never_unchanged`), and the wait needs its pass on the exact commit (`laneOk_iff`,
`Fw.Ci.Intent.wait_needs_default_pass`).
-/
namespace Fw.Ci.Verdict

/-- A job's conclusion, folded: GitHub's `success`, `skipped` and `cancelled`; everything else (`failure`, `timed_out`,
`action_required`, `neutral`, `stale`, `startup_failure`, no conclusion) is `failure`. -/
inductive Concl where
  | success
  | skipped
  | cancelled
  | failure
  deriving DecidableEq, Repr

/-- GitHub's conclusion text, folded. -/
def conclOf (s : String) : Concl :=
  match s with
  | "success" => .success
  | "skipped" => .skipped
  | "cancelled" => .cancelled
  | _ => .failure

/-- The facts of one finished run. `guard`: the guard job's conclusion (`skipped` when its `if:` was false).
`decision`: the guard's `run=…` as its decision step shows it (`none`: the run shows no decision step). `jobs`: the
conclusions of every other job. `stale`: some other job's tip re-check found a newer branch tip (its step `stale: …`
failed, `staleOf`). -/
structure Facts where
  guard : Concl
  decision : Option Bool
  jobs : List Concl
  stale : Bool
  deriving Repr

/-- The verdict of a run. -/
inductive Verdict where
  | pass
  | fail
  | notRun
  deriving DecidableEq, Repr

/-- A job ran: it was not skipped. -/
def ran (c : Concl) : Bool := c != .skipped

/-- The guard decided to run: its job succeeded and it did not show `run=false` (no decision step counts as run, the
jobs then decide). -/
def says (f : Facts) : Bool := f.guard == .success && f.decision != some false

/-- **The verdict.** Not run: the guard was skipped, or a job found the run stale, or the guard succeeded and decided
`run=false` or no other job ran. Pass: the guard decided to run, no job found the run stale, some other job ran, and
every job that ran succeeded. Fail: everything else (a failed or cancelled guard, a job that ran and did not succeed). -/
def verdict (f : Facts) : Verdict :=
  if f.guard == .skipped || f.stale || (f.guard == .success && (f.decision == some false || !f.jobs.any ran)) then
    .notRun
  else if f.guard == .success && f.jobs.all (fun c => !ran c || c == .success) then .pass
  else .fail

/-- **A skipped guard never passes.** A run whose guard job was skipped (its `if:` was false) is not run, whatever its
other jobs show. -/
theorem skipped_never_pass (f : Facts) (h : f.guard = .skipped) : verdict f = .notRun := by
  simp [verdict, h]

/-- **A stale run never passes.** A run in which some job's tip re-check found a newer branch tip is not run, whatever
its other jobs show. -/
theorem stale_never_pass (f : Facts) (h : f.stale = true) : verdict f = .notRun := by
  simp [verdict, h]

/-- **No job ran, no pass.** If every non-guard job was skipped, the run does not pass. -/
theorem all_skipped_never_pass (f : Facts) (h : ∀ c ∈ f.jobs, c = .skipped) : verdict f ≠ .pass := by
  have hn : f.jobs.any ran = false := by
    rw [List.any_eq_false]; intro c hc; simp [ran, h c hc]
  unfold verdict
  cases hg : f.guard <;> cases hs : f.stale <;> simp [hn]

/-- **A guard that decided `run=false` never passes.** -/
theorem decided_skip_never_pass (f : Facts) (h : f.decision = some false) : verdict f ≠ .pass := by
  unfold verdict
  cases hg : f.guard <;> cases hs : f.stale <;> simp [h]

/-- **When a run passes.** Exactly when the guard job succeeded and did not decide `run=false`, no job found the run
stale, at least one other job ran, and every job that ran succeeded. -/
theorem pass_iff (f : Facts) :
    verdict f = .pass ↔ f.guard = .success ∧ f.decision ≠ some false ∧ f.stale = false ∧
      (∃ c ∈ f.jobs, c ≠ .skipped) ∧ (∀ c ∈ f.jobs, c ≠ .skipped → c = .success) := by
  cases hs : f.stale
  case true => simp [verdict, hs]
  simp only [true_and]
  unfold verdict
  cases hg : f.guard <;> simp [ran, List.all_eq_true, hs]
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

/-- The exit code of a verdict: 0 pass, 1 fail, 4 not run (2, 3 and 64 are the wait's own: no run, timeout, usage). -/
def code : Verdict → Nat
  | .pass => 0
  | .fail => 1
  | .notRun => 4

/-- The verdict of a wait over several runs (one per workflow): fail if any failed, else pass if any passed, else not
run (also for no run at all). -/
def combine (vs : List Verdict) : Verdict :=
  if vs.contains .fail then .fail else if vs.contains .pass then .pass else .notRun

/-- **A combined pass has a real pass behind it.** The wait passes iff no run failed and at least one run passed; so
a wait over runs that were all skipped never passes. -/
theorem combine_pass_iff (vs : List Verdict) : combine vs = .pass ↔ .fail ∉ vs ∧ .pass ∈ vs := by
  unfold combine
  by_cases hf : Verdict.fail ∈ vs <;> by_cases hp : Verdict.pass ∈ vs <;> simp [hf, hp]

/-- **One run: the combined verdict is its own.** -/
theorem combine_single (v : Verdict) : combine [v] = v := by
  cases v <;> rfl

/-- The name of a verdict as the wait prints it. -/
def name : Verdict → String
  | .pass => "pass"
  | .fail => "fail"
  | .notRun => "not-run"

/-- The guard's decision steps: the step that runs when it decided `run=true`, and the prefix of the one that runs
when it decided `run=false` (its name continues with the reason). -/
def decisionStep : Bool → String
  | true => "decision: run"
  | false => "decision: skip"

/-- The decision a guard's steps show: `some true` if the step `decision: run` succeeded, else `some false` if a step
whose name starts with `decision: skip` succeeded, else `none` (a run from before the steps, or a guard that failed
first). Steps are (name, conclusion) pairs; a step whose `if:` was false has conclusion `skipped`. -/
def decisionOf (steps : List (String × Concl)) : Option Bool :=
  if steps.any (fun (n, c) => n == decisionStep true && c == .success) then some true
  else if steps.any (fun (n, c) => n.startsWith (decisionStep false) && c == .success) then some false
  else none

/-- The name prefix of the step that fails in a heavy job when its tip re-check finds a newer branch tip. -/
def staleStep : String := "stale:"

/-- Did some heavy job stop at its tip re-check? True iff some step of a non-guard job whose name starts with
`stale:` concluded `failure` (it ran and stopped the job). Steps are (name, conclusion) pairs. -/
def staleOf (steps : List (String × Concl)) : Bool :=
  steps.any fun (n, c) => n.startsWith staleStep && c == .failure

#guard staleOf [("tip re-check", .success), ("stale: abc is the branch tip", .failure)]
#guard !staleOf [("tip re-check", .success), ("stale: abc is the branch tip", .skipped), ("make", .failure)]

/-- Why a run did not run, as the wait prints it: a skipped guard was stopped by its `if:` (the head commit of a `ci/**`
push does not name the lane); otherwise, when a job found the run stale, the stale text; otherwise the text after
`decision: skip: ` in the name of the first succeeded step that starts with `decision: skip` (the guard's reason);
otherwise no reason. -/
def reasonOf (guard : Concl) (stale : Bool) (steps : List (String × Concl)) : String :=
  if guard == .skipped then "unwanted: guard if: the head commit does not ask for this lane"
  else if stale then "stale: a newer push is the branch tip (the jobs stopped at the tip re-check)"
  else match steps.find? (fun (n, c) => n.startsWith (decisionStep false) && c == .success) with
    | some (n, _) =>
      let p := decisionStep false ++ ": "
      if n.startsWith p then (n.drop p.length).toString else (n.drop (decisionStep false).length).toString
    | none => ""

/-- **A shown skip decision never passes.** If the guard's steps show a skip decision (`decisionOf` gives
`some false`), the run is not a pass, whatever the guard's conclusion and the jobs. -/
theorem shown_skip_never_pass (g : Concl) (steps : List (String × Concl)) (jobs : List Concl) (stale : Bool)
    (h : decisionOf steps = some false) : verdict ⟨g, decisionOf steps, jobs, stale⟩ ≠ .pass :=
  decided_skip_never_pass ⟨g, decisionOf steps, jobs, stale⟩ h

#guard decisionOf [("Set up job", .success), ("decision: run", .success), ("decision: skip: x", .skipped)] == some true
#guard decisionOf [("decision: run", .skipped), ("decision: skip: no input changed", .success)] == some false
#guard decisionOf [("guard", .success)] == none
#guard reasonOf .success false [("decision: run", .skipped), ("decision: skip: unchanged: no input", .success)] ==
  "unchanged: no input"
#guard reasonOf .skipped false [] == "unwanted: guard if: the head commit does not ask for this lane"
#guard reasonOf .success false [("decision: run", .success)] == ""
#guard (reasonOf .success true [("decision: run", .success)]).startsWith "stale:"

-- the lead's case: every heavy job skipped at the guard, workflow conclusion success
#guard verdict ⟨.skipped, none, [.skipped, .skipped], false⟩ == .notRun
#guard verdict ⟨.success, some false, [.skipped], false⟩ == .notRun
#guard verdict ⟨.success, none, [.skipped, .skipped], false⟩ == .notRun
#guard verdict ⟨.success, some true, [.success, .skipped], false⟩ == .pass
#guard verdict ⟨.success, none, [.success], false⟩ == .pass
#guard verdict ⟨.success, some true, [.success, .failure], false⟩ == .fail
#guard verdict ⟨.success, some true, [.cancelled], false⟩ == .fail
#guard verdict ⟨.failure, none, [], false⟩ == .fail
#guard verdict ⟨.cancelled, none, [.skipped], false⟩ == .fail
#guard verdict ⟨.success, some true, [], false⟩ == .notRun
-- round 3: a job stopped at the tip re-check (GitHub: failure) is not run, never a failure or a pass
#guard verdict ⟨.success, some true, [.success, .failure], true⟩ == .notRun
#guard combine [.pass, .notRun] == .pass
#guard combine [.notRun, .notRun] == .notRun
#guard combine [.pass, .fail] == .fail
#guard combine [] == .notRun
#guard conclOf "timed_out" == .failure && conclOf "skipped" == .skipped
#guard (([Verdict.pass, .fail, .notRun].map code) == [0, 1, 4])

/-! ## Why the guard skipped, and the wait over the lanes a commit requests (round 3) -/

/-- Why the guard decided `run=false` on a `ci/**` push (`Fw.Ci.Intent.decision`): the head commit does not want the
lane, the commit is not the branch tip, it is already on `main`, or no input of the lane differs from `main`. -/
inductive Skip where
  | unwanted
  | stale
  | landed
  | unchanged
  deriving DecidableEq, Repr

/-- The tag the guard writes first in its reason (`<tag>: <text>`). -/
def Skip.tag : Skip → String
  | .unwanted => "unwanted"
  | .stale => "stale"
  | .landed => "landed"
  | .unchanged => "unchanged"

/-- Every skip kind, in order. -/
def Skip.all : List Skip := [.unwanted, .stale, .landed, .unchanged]

/-- The skip kind a reason names: the first kind `k` whose tag followed by `:` starts the reason; `none` when no tag
does (a reason from before round 3, or no reason). -/
def skipOf (reason : String) : Option Skip := Skip.all.find? fun k => reason.startsWith (k.tag ++ ":")

#guard skipOf "unchanged: none of the 3 file(s) match" == some .unchanged
#guard skipOf "stale: a newer push" == some .stale
#guard skipOf "no input changed" == none
#guard skipOf "" == none

#guard Skip.all.all fun k => skipOf (k.tag ++ ": some text") == some k

/-- One lane of a branch wait. `v`: the verdict of the lane's newest run for the commit (`none`: no such run). `skip`:
the skip kind its reason names (shown to the agent; it never satisfies the lane). -/
structure LaneRun where
  v : Option Verdict
  skip : Option Skip
  deriving Repr

/-- A lane is satisfied when its run passed (round 5: no skip satisfies it, `unchanged` included). -/
def laneOk (r : LaneRun) : Bool := r.v == some .pass

/-- **Only a pass satisfies a lane**, whatever its skip kind. -/
theorem laneOk_iff (r : LaneRun) : laneOk r = true ↔ r.v = some .pass := by
  simp [laneOk]

/-- **The verdict of a branch wait** over the lanes the head commit requests (plus the default lanes): fail if some
lane failed; pass if every lane is satisfied and at least one passed; otherwise not run. -/
def combineRequested (rs : List LaneRun) : Verdict :=
  if rs.any (·.v == some .fail) then .fail
  else if rs.all laneOk && rs.any (·.v == some .pass) then .pass
  else .notRun

/-- **When a branch wait passes.** Exactly when every lane is satisfied and some lane passed. -/
theorem combine_requested_pass_iff (rs : List LaneRun) :
    combineRequested rs = .pass ↔ (∀ r ∈ rs, laneOk r = true) ∧ ∃ r ∈ rs, r.v = some .pass := by
  unfold combineRequested
  by_cases hf : rs.any (·.v == some .fail) = true
  · simp only [hf, ite_true, reduceCtorEq, false_iff, not_and]
    intro hall _
    obtain ⟨r, hr, hv⟩ := List.any_eq_true.mp hf
    have := hall r hr
    simp only [beq_iff_eq] at hv
    simp [laneOk, hv] at this
  · simp only [Bool.not_eq_true] at hf
    simp only [hf, Bool.false_eq_true, ite_false]
    by_cases hp : (rs.all laneOk && rs.any (·.v == some .pass)) = true
    · simp only [hp, ite_true, true_iff]
      simp only [Bool.and_eq_true, List.all_eq_true, List.any_eq_true, beq_iff_eq] at hp
      exact hp
    · simp only [Bool.not_eq_true] at hp
      simp only [hp, Bool.false_eq_true, ite_false, reduceCtorEq, false_iff, not_and]
      intro hall ⟨r, hr, hv⟩
      simp only [Bool.and_eq_false_iff, List.all_eq_false, List.any_eq_false, beq_iff_eq] at hp
      rcases hp with ⟨x, hx, hn⟩ | h
      · exact absurd (hall x hx) (by simpa using hn)
      · exact h r hr hv

/-- **A lane that did not pass blocks the wait.** If some lane of the wait (requested or default) has no passing run
(not run for any skip kind, `unchanged` included; failed; or no run at all), the branch wait does not pass. -/
theorem combine_requested_never_pass (rs : List LaneRun) (r : LaneRun) (hr : r ∈ rs) (hv : r.v ≠ some .pass) :
    combineRequested rs ≠ .pass := by
  intro h
  have := ((combine_requested_pass_iff rs).mp h).1 r hr
  simp [laneOk, hv] at this

/-- **A missing run never passes.** If some lane of the wait has no run for the commit, the wait does not pass. -/
theorem missing_never_pass (rs : List LaneRun) (r : LaneRun) (hr : r ∈ rs) (hv : r.v = none) :
    combineRequested rs ≠ .pass := by
  intro h
  have := ((combine_requested_pass_iff rs).mp h).1 r hr
  simp [laneOk, hv] at this

/-- **The verdict of a branch wait whose request may be unknown** (round 4). `none`: the head commit's message could not
be read (the commit is not in the local object store, or git failed), so the lanes it requests are unknown and the wait
is not run; `some R`: the lanes it requests, combined by `combineRequested`. -/
def waitVerdict : Option (List LaneRun) → Verdict
  | none => .notRun
  | some rs => combineRequested rs

/-- **An unknown request never passes.** When the lanes the commit requests are unknown, the wait does not pass. -/
theorem unknown_request_never_pass : waitVerdict none ≠ .pass := by
  simp [waitVerdict]

/-- **When a wait passes.** Exactly when the request is known and its lanes pass by `combineRequested`. -/
theorem wait_pass_iff (q : Option (List LaneRun)) :
    waitVerdict q = .pass ↔ ∃ rs, q = some rs ∧ combineRequested rs = .pass := by
  cases q <;> simp [waitVerdict]

#guard waitVerdict none == .notRun
#guard waitVerdict (some [⟨some .pass, none⟩]) == .pass
#guard waitVerdict (some []) == .notRun

-- probe (1) of the round-2 review: difftest requested and skipped at its guard, lean passed: not a pass
#guard combineRequested [⟨some .notRun, some .unchanged⟩, ⟨some .pass, none⟩] == .notRun
-- the round-4 probe: [ci:wktr] passed, lean skipped as unchanged: not a pass (round 5)
#guard combineRequested [⟨some .pass, none⟩, ⟨some .notRun, some .unchanged⟩] == .notRun
#guard combineRequested [⟨some .pass, none⟩, ⟨some .notRun, some .stale⟩] == .notRun
#guard combineRequested [⟨none, none⟩, ⟨some .pass, none⟩] == .notRun
#guard combineRequested [⟨some .pass, none⟩, ⟨some .fail, none⟩] == .fail
#guard combineRequested [⟨some .pass, none⟩, ⟨some .pass, none⟩] == .pass
#guard combineRequested [⟨some .notRun, some .unchanged⟩] == .notRun
#guard combineRequested [] == .notRun

end Fw.Ci.Verdict
