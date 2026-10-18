import Fw.Ci.Intent
/-!
# Who may cancel a lane's run (task `ci-own-trigger`, round 2)

Round 1 kept workflow-level concurrency: a newer push whose paths matched a workflow created a run, and that run
cancelled the in-flight one at once, before its own guard decided anything. A push that did not ask for the lane then
cancelled a requested run and skipped its own (MEASURED: run 39106170371 cancelled by the run of push 74ea297, whose
engine-premises run 39106360862 was skipped; `research/notes/2026/10-18-ci-own-trigger.md`).

Now every heavy job carries a job-level concurrency group per lane, branch, job and matrix leg (`Intent.groupExpr`,
`cancel-in-progress` on `ci/**` refs) and the workflow has none. A job enters its group only when it is queued, and a
job whose `if:` is false (or whose `needs` were skipped) is never queued. GitHub's docs (github/docs@dae83f7,
`data/reusables/actions/actions-group-concurrency.md`: "When a concurrent job or workflow is queued, if another job or
workflow using the same concurrency group in the repository is in progress, the queued job or workflow will be
`pending`", and `cancel-in-progress: true` "also cancel[s] any currently running job ... in the same concurrency
group"; `data/reusables/actions/jobs/section-using-conditions-to-control-job-execution.md`: "use the
`jobs.<job_id>.if` conditional to prevent a job from running", the job is then "marked as _skipped_") give the rule
modelled here (CONFIRMED for queueing and cancelling; that a skipped job is never queued is INFERRED from those
sentences and MEASURED on `ci/ci-own-trigger`: run 39109868988 of a push asking for snapshot-extract kept its 6
running legs and passed after a newer push that touched the lane's inputs without asking for it created run
39110017442, skipped; see the research note). Every heavy job needs the guard (checked by
`scripts/ci-paths.mjs`), so only a run whose guard decided to run enters a group.

The model: a group's history is the list of runs (push indices) whose job entered it, in entry order. An entry may be
cancelled only when a later entry exists (an upper bound: GitHub cancels nothing when the earlier job has finished).
-/
namespace Fw.Ci.Cancel
open Fw.Ci.Intent

/-- A group history is admissible when every run that entered it is one that started (job level).
$$\forall s, E:\ \operatorname{adm}(s, E) \iff \forall r \in E:\ s(r)$$ -/
def Admissible (started : Nat → Bool) (es : List Nat) : Prop := ∀ r ∈ es, started r = true

/-- The entry at position $k$ may be cancelled: some run entered the group after it.
$$\forall E, k:\ \operatorname{canc}(E, k) \iff k + 1 < |E|$$ -/
def MayCancel (es : List Nat) (k : Nat) : Prop := k + 1 < es.length

instance (es : List Nat) (k : Nat) : Decidable (MayCancel es k) := inferInstanceAs (Decidable (k + 1 < es.length))

/-- **A cancellation needs a newer started run.** Under job-level concurrency, if the entry at position $k$ may be
cancelled, a later entry exists and its run started the lane.
$$\forall s, E, k:\ \operatorname{adm}(s, E) \land \operatorname{canc}(E, k) \Rightarrow \exists j:\ k < j < |E| \land s(E_j)$$ -/
theorem cancel_needs_newer_start (started : Nat → Bool) (es : List Nat) (k : Nat) (h : Admissible started es)
    (hc : MayCancel es k) : ∃ j, ∃ hj : j < es.length, k < j ∧ started es[j] = true :=
  ⟨k + 1, hc, Nat.lt_succ_self k, h _ (List.getElem_mem hc)⟩

/-- **Some started run is never cancelled.** If any run entered the group, the last entry may not be cancelled, and
its run started the lane: the lane's result arrives.
$$\forall s, E:\ \operatorname{adm}(s, E) \land E \ne [\,] \Rightarrow \exists k < |E|:\ \lnot\operatorname{canc}(E, k) \land s(E_k)$$ -/
theorem last_never_cancelled (started : Nat → Bool) (es : List Nat) (h : Admissible started es) (hne : es ≠ []) :
    ∃ k, ∃ hk : k < es.length, ¬MayCancel es k ∧ started es[k] = true := by
  have hl : 0 < es.length := List.length_pos_iff.mpr hne
  refine ⟨es.length - 1, by omega, ?_, h _ (List.getElem_mem _)⟩
  unfold MayCancel; omega

/-- The started flag of a lane over a branch's pushes. $$\forall S, \ell, P:\ s_{S,\ell,P}(r) = \operatorname{start}(S, \ell, P_r)$$ -/
def startedOf (S : String → List String) (l : Lane) (ps : Nat → Push) (r : Nat) : Bool := start S l (ps r)

/-- **A push that does not want the lane never enters its group,** so it never cancels a run of that lane.
$$\forall S, \ell, P, E, r:\ \operatorname{adm}(s_{S,\ell,P}, E) \land P_r.\mathit{ci} \land \lnot\operatorname{want}(\ell, P_r.m) \Rightarrow r \notin E$$ -/
theorem unwanted_never_enters (S : String → List String) (l : Lane) (ps : Nat → Push) (es : List Nat) (r : Nat)
    (h : Admissible (startedOf S l ps) es) (hci : (ps r).ci = true) (hw : wanted l (ps r).msg = false) : r ∉ es := by
  intro hr
  have := h r hr
  simp [startedOf, start, hci, hw] at this

/-- **No requested lane is lost to a cancel.** On a branch, if a requested run of the lane entered its group, then
(1) it may be cancelled only by a later entry whose push itself started the lane (so wanted it), and (2) some entry
that started the lane is never cancelled.
$$\forall S, \ell, P, E, k < |E|:\ \operatorname{adm}(s_{S,\ell,P}, E) \Rightarrow \bigl(\operatorname{canc}(E, k) \Rightarrow \exists j:\ k < j < |E| \land \operatorname{start}(S, \ell, P_{E_j}) \land (P_{E_j}.\mathit{ci} \Rightarrow \operatorname{want}(\ell, P_{E_j}.m))\bigr) \land \exists k' < |E|:\ \lnot\operatorname{canc}(E, k') \land \operatorname{start}(S, \ell, P_{E_{k'}})$$ -/
theorem no_requested_lost (S : String → List String) (l : Lane) (ps : Nat → Push) (es : List Nat) (k : Nat)
    (hk : k < es.length) (h : Admissible (startedOf S l ps) es) :
    (MayCancel es k → ∃ j, ∃ hj : j < es.length, k < j ∧ start S l (ps es[j]) = true ∧
        ((ps es[j]).ci = true → wanted l (ps es[j]).msg = true)) ∧
      ∃ k', ∃ hk' : k' < es.length, ¬MayCancel es k' ∧ start S l (ps es[k']) = true := by
  refine ⟨fun hc => ?_, ?_⟩
  · obtain ⟨j, hj, hkj, hs⟩ := cancel_needs_newer_start _ es k h hc
    refine ⟨j, hj, hkj, hs, fun hci => ((start_ci_iff S l _ hci).mp hs).1⟩
  · exact last_never_cancelled _ es h (List.ne_nil_of_length_pos (by omega))

/-! ## The round-1 rule, for contrast -/

/-- Workflow level: every run whose paths matched (created) enters the group, started or not.
$$\forall c, E:\ \operatorname{adm}_{\mathrm{wf}}(c, E) \iff \forall r \in E:\ c(r)$$ -/
def WfAdmissible (created : Nat → Bool) (es : List Nat) : Prop := ∀ r ∈ es, created r = true

/-- **The workflow-level rule can lose a requested lane.** Two created runs, the first started, the second not: the
history is admissible, the first may be cancelled, and no entry that started survives.
$$\exists c, s, E:\ \operatorname{adm}_{\mathrm{wf}}(c, E) \land (\exists r \in E:\ s(r)) \land \forall k < |E|:\ s(E_k) \Rightarrow \operatorname{canc}(E, k)$$ -/
theorem wf_level_loses : ∃ (created started : Nat → Bool) (es : List Nat), WfAdmissible created es ∧
    (∃ r ∈ es, started r = true) ∧ ∀ k, ∀ hk : k < es.length, started es[k] = true → MayCancel es k := by
  refine ⟨fun _ => true, fun r => r == 0, [0, 1], fun _ _ => rfl, ⟨0, by simp, rfl⟩, ?_⟩
  intro k hk hs
  unfold MayCancel
  match k, hk with
  | 0, _ => simp
  | 1, _ => simp at hs

-- the measured round-1 case: push 1 asked for engine-premises (started), push 2 did not (created, skipped)
#guard decide (MayCancel [0, 1] 0) && !decide (MayCancel [0, 1] 1)
#guard decide (MayCancel [0] 0) == false

end Fw.Ci.Cancel
