/-!
# Stale services: a running service must not lag the files it was built from

A service (console-api and the `fwcore` binary it spawns) reads input files when it starts. If one of
them changed on `main` after the start, the running process still holds the old code: the incident of task
`console-stale` (console-api started 04:12 kept running while `workflow-claim` landed at 04:48, so workflow runs
stayed unbound in the ready lane for hours). This module is the pure rule; the collector (`fw watch`) only measures
the start time and the last change time of each input group, and the console-api reports its own commit and start time.

Units: times are ms since the epoch. A change at the very instant of the start is not stale (the service read the
files at or after it).
-/

namespace Fw.Obs

/-- One input group of a service: a path (file or directory prefix) and the time the last change reached `main`
(ms): the committer time of the newest first-parent commit of `main` that touched it, so a branch merged with
`--no-ff` counts at the merge, not at the branch commit.

$$i = (\mathit{path}, \mathit{changed}) \in \mathrm{String} \times \mathbb N$$
-/
structure SvcInput where
  path      : String
  changedAt : Nat
deriving DecidableEq, Repr

/-- A service: its name, its start time (ms) and its input groups.

$$s = (\mathit{name}, \mathit{start}, I) \in \mathrm{String} \times \mathbb N \times \mathcal I^*$$
-/
structure Svc where
  name      : String
  startedAt : Nat
  inputs    : List SvcInput := []
deriving DecidableEq, Repr

/-- The changed input paths of a service: those whose last change on `main` is strictly after the start.

$$\operatorname{changed}(s) = [\,\mathit{path}(i) \mid i \leftarrow I,\ \mathit{start}(s) < \mathit{changed}(i)\,],\quad s = (n, \mathit{start}, I)$$
-/
def Svc.changed (s : Svc) : List String :=
  (s.inputs.filter (fun i => decide (s.startedAt < i.changedAt))).map SvcInput.path

/-- A service is stale when some input changed after it started.

$$\operatorname{stale}(s) \iff \operatorname{changed}(s) \ne []$$
-/
def Svc.staleB (s : Svc) : Bool := !s.changed.isEmpty

/-- A path is reported exactly when one of the service's inputs has that path and changed after the start.

$$\forall s, x:\quad x \in \operatorname{changed}(s) \iff \exists i \in I.\ \mathit{path}(i) = x \wedge \mathit{start}(s) < \mathit{changed}(i)$$
-/
theorem Svc.mem_changed (s : Svc) (x : String) :
    x ∈ s.changed ↔ ∃ i ∈ s.inputs, i.path = x ∧ s.startedAt < i.changedAt := by
  simp only [Svc.changed, List.mem_map, List.mem_filter, decide_eq_true_eq]
  constructor
  · rintro ⟨i, ⟨hi, hs⟩, rfl⟩; exact ⟨i, hi, rfl, hs⟩
  · rintro ⟨i, hi, rfl, hs⟩; exact ⟨i, ⟨hi, hs⟩, rfl⟩

/-- Stale iff some input changed after the start.

$$\forall s:\quad \operatorname{stale}(s) \iff \exists i \in I.\ \mathit{start}(s) < \mathit{changed}(i)$$
-/
theorem Svc.stale_iff (s : Svc) :
    s.staleB = true ↔ ∃ i ∈ s.inputs, s.startedAt < i.changedAt := by
  unfold Svc.staleB
  constructor
  · intro h
    cases hc : s.changed with
    | nil => simp [hc] at h
    | cons x _ =>
      obtain ⟨i, hi, _, hs⟩ := (Svc.mem_changed s x).1 (by rw [hc]; exact List.mem_cons_self)
      exact ⟨i, hi, hs⟩
  · rintro ⟨i, hi, hs⟩
    have hm := (Svc.mem_changed s i.path).2 ⟨i, hi, rfl, hs⟩
    cases hc : s.changed with
    | nil => rw [hc] at hm; simp at hm
    | cons _ _ => rfl

/-- Restarting at time $t$: the new process starts at $t$ and reads the same input files.

$$\operatorname{restart}(s, t) = (n, t, I),\quad s = (n, \mathit{start}, I)$$
-/
def Svc.restart (s : Svc) (t : Nat) : Svc := { s with startedAt := t }

/-- A restart at or after the last change on `main` (every input changed at or before $t$) clears staleness.

$$\forall s, t:\quad (\forall i \in I.\ \mathit{changed}(i) \le t) \Rightarrow \neg\operatorname{stale}(\operatorname{restart}(s, t))$$
-/
theorem Svc.restart_clears (s : Svc) (t : Nat) (h : ∀ i ∈ s.inputs, i.changedAt ≤ t) :
    (s.restart t).staleB = false := by
  cases hb : (s.restart t).staleB with
  | false => rfl
  | true =>
    obtain ⟨i, hi, hs⟩ := ((s.restart t).stale_iff).1 hb
    exact absurd (h i hi) (by simp only [Svc.restart] at hs; omega)

/-- A restart before the last change of an input leaves the service stale.

$$\forall s, t, i:\quad i \in I \wedge t < \mathit{changed}(i) \Rightarrow \operatorname{stale}(\operatorname{restart}(s, t))$$
-/
theorem Svc.stale_of_restart_older (s : Svc) (t : Nat) (i : SvcInput) (hi : i ∈ s.inputs)
    (h : t < i.changedAt) : (s.restart t).staleB = true :=
  ((s.restart t).stale_iff).2 ⟨i, hi, h⟩

end Fw.Obs
