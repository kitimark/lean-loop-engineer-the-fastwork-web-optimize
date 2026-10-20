import Fw.Ci.Intent
/-!
# Who may cancel a lane's run (task `ci-own-trigger`, round 3: nobody on `ci/**`)

Round 1 kept workflow-level concurrency: a newer push whose paths matched a workflow created a run, and that run
cancelled the in-flight one at once, before its own guard decided anything. A push that did not ask for the lane then
cancelled a requested run and skipped its own (MEASURED: run 39106170371 cancelled by the run of push 74ea297, whose
engine-premises run 39106360862 was skipped; `research/notes/2026/10-18-ci-own-trigger.md`; `wf_level_loses` below).

Round 2 moved the groups to the heavy jobs with `cancel-in-progress` on `ci/**`. That still let a newer push cancel a
running job, and GitHub keeps only one pending job per group (github/docs@dae83f7,
`data/reusables/actions/actions-group-concurrency.md`: "any existing `pending` job or workflow in the same concurrency
group ... will be canceled"), so the round-2 design relied on the newer run doing the work.

Round 3 (lead decision): on `ci/**` no two runs share a group, so nothing is cancelled or replaced while pending; an
older run instead stops itself at its tip re-check (`Fw.Ci.Intent.stale_never_works`). The group of a heavy job is the
lane, a value and the job (`Intent.groupExpr`); the value is the ref on a `main` push (main runs queue, as before) and
the run id otherwise. Here the value is modelled as a sum type (`GVal`): a ref and a run id never collide, since every
push ref starts with `refs/` and a run id is a decimal number (INFERRED from GitHub's contexts reference; the text is
checked against `groupExpr` by `scripts/ci-paths.test.mjs`).

The model: a group's history is the list of runs whose job entered it, in entry order. An entry may be cancelled (or
replaced while pending) only when a later entry exists.
-/
namespace Fw.Ci.Cancel
open Fw.Ci.Intent

/-- The entry at position `k` may be cancelled: some run entered the group after it. -/
def MayCancel {α} (es : List α) (k : Nat) : Prop := k + 1 < es.length

instance {α} (es : List α) (k : Nat) : Decidable (MayCancel es k) :=
  inferInstanceAs (Decidable (k + 1 < es.length))

/-- The evaluated value in the middle of a group: a ref or a run id. -/
inductive GVal where
  | ref (r : String)
  | run (id : Nat)
  deriving DecidableEq, Repr

/-- A run as the group sees it: its id, event name and ref. -/
structure Run where
  id : Nat
  event : String
  ref : String
  deriving DecidableEq, Repr

/-- The value of `github.event_name == 'push' && !startsWith(github.ref, 'refs/heads/ci/') && github.ref ||
github.run_id`: the ref on a push off `ci/**`, else the run id. -/
def groupVal (r : Run) : GVal :=
  if r.event == "push" && !r.ref.startsWith "refs/heads/ci/" then .ref r.ref else .run r.id

/-- The group of the job `j`, leg `x`, of lane `n` for run `ρ`. -/
def groupOf (lane job : String) (leg : Nat) (r : Run) : String × GVal × String × Nat := (lane, groupVal r, job, leg)

/-- **A `ci/**` run shares its group with no other run.** If run `ρ` is a `ci/**` push and `σ` has another id,
their groups differ (any lane, job and leg). -/
theorem ci_group_alone (lane job : String) (leg : Nat) (r s : Run) (hci : isCi r.event r.ref = true)
    (hid : r.id ≠ s.id) : groupOf lane job leg r ≠ groupOf lane job leg s := by
  have hr : groupVal r = .run r.id := by
    simp only [isCi, Bool.and_eq_true] at hci
    simp [groupVal, hci.1, hci.2]
  intro h
  simp only [groupOf, Prod.mk.injEq, true_and, and_true] at h
  rw [hr] at h
  unfold groupVal at h
  split at h
  · exact GVal.noConfusion h
  · exact hid (GVal.run.inj h)

/-- **Nothing cancels a `ci/**` run.** In a group history of distinct runs that holds a `ci/**` run, that run is the
only entry, so no entry may be cancelled or replaced. -/
theorem ci_never_cancelled (lane job : String) (leg : Nat) (g : String × GVal × String × Nat) (es : List Run)
    (hnd : (es.map (·.id)).Nodup) (hg : ∀ s ∈ es, groupOf lane job leg s = g) (r : Run) (hr : r ∈ es)
    (hci : isCi r.event r.ref = true) : es.length = 1 ∧ ∀ k, ¬MayCancel es k := by
  have hsame : ∀ s ∈ es, s.id = r.id := by
    intro s hs
    exact Decidable.byContradiction fun hne =>
      ci_group_alone lane job leg r s hci (Ne.symm hne) ((hg r hr).trans (hg s hs).symm)
  have hc : (es.map (·.id)).count r.id = (es.map (·.id)).length :=
    List.count_eq_length.mpr (by
      intro b hb
      obtain ⟨s, hs, rfl⟩ := List.mem_map.mp hb
      simpa using (hsame s hs).symm)
  have h1 : (es.map (·.id)).count r.id ≤ 1 := by rw [List.Nodup.count hnd]; split <;> omega
  have hpos : 0 < es.length := List.length_pos_of_mem hr
  have hlen : es.length = 1 := by
    rw [List.length_map] at hc
    omega
  exact ⟨hlen, fun k hk => by unfold MayCancel at hk; omega⟩

#guard groupVal ⟨7, "push", "refs/heads/ci/x"⟩ == .run 7
#guard groupVal ⟨7, "push", "refs/heads/main"⟩ == .ref "refs/heads/main"
#guard groupVal ⟨7, "workflow_dispatch", "refs/heads/main"⟩ == .run 7
#guard groupOf "lean" "lean" 0 ⟨1, "push", "refs/heads/ci/x"⟩ != groupOf "lean" "lean" 0 ⟨2, "push", "refs/heads/ci/x"⟩
#guard groupOf "lean" "lean" 0 ⟨1, "push", "refs/heads/main"⟩ == groupOf "lean" "lean" 0 ⟨2, "push", "refs/heads/main"⟩

/-! ## The round-1 rule, for contrast -/

/-- Workflow level: every run whose paths matched (created) enters the group, started or not. -/
def WfAdmissible (created : Nat → Bool) (es : List Nat) : Prop := ∀ r ∈ es, created r = true

/-- **The workflow-level rule can lose a requested lane.** Two created runs, the first started, the second not: the
history is admissible, the first may be cancelled, and no entry that started survives. -/
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
