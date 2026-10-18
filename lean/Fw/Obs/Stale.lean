/-!
# Stale services: a running service must not lag the files it was built from

A service reads input files once, when it is started (console-api) or built (the `fwcore` binary). If one of them
changed on `main` after that, the running process still holds the old code: the incident of task `console-stale`
(console-api started 04:12 kept running while `workflow-claim` landed at 04:48, so workflow runs stayed unbound in
the ready lane for hours).

Time is not used: `fw land` builds the merge commit before its checks and moves `main` to it 23-89 s later
(MEASURED, 12 lands), so a commit time predates the moment `main` moved. Instead each service records the commit of
`main` it was started or built from (its base), and an input is *changed* iff the first-parent range
`base..main` touches it (`git log --first-parent <base>..main -- <path>` is non-empty). The collector (`fw watch`)
only measures that Bool per input; this module is the rule. Two services are judged separately: console-api (base =
HEAD at start, recorded in `api.json`) and `fwcore` (base = the commit the binary was built from, recorded next to
the binary), so restarting console-api does not refresh the binary.
-/

namespace Fw.Obs

/-- One input group of a service: a path (file or directory prefix) and whether the first-parent range
`base..main` touches it.

$$i = (\mathit{path}, \mathit{changed}) \in \mathrm{String} \times \mathbb B$$
-/
structure SvcInput where
  path    : String
  changed : Bool
deriving DecidableEq, Repr

/-- A service: its name and its input groups, each judged against the service's base commit.

$$s = (\mathit{name}, I) \in \mathrm{String} \times \mathcal I^*$$
-/
structure Svc where
  name   : String
  inputs : List SvcInput := []
deriving DecidableEq, Repr

/-- The changed input paths of a service.

$$\operatorname{changed}(s) = [\,\mathit{path}(i) \mid i \leftarrow I,\ \mathit{changed}(i)\,],\quad s = (n, I)$$
-/
def Svc.changed (s : Svc) : List String :=
  (s.inputs.filter (fun i => i.changed)).map SvcInput.path

/-- A service is stale when some input changed on `main` since its base commit.

$$\operatorname{stale}(s) \iff \operatorname{changed}(s) \ne []$$
-/
def Svc.staleB (s : Svc) : Bool := !s.changed.isEmpty

/-- A path is reported exactly when one of the service's inputs has that path and is changed.

$$\forall s, x:\quad x \in \operatorname{changed}(s) \iff \exists i \in I.\ \mathit{path}(i) = x \wedge \mathit{changed}(i)$$
-/
theorem Svc.mem_changed (s : Svc) (x : String) :
    x ∈ s.changed ↔ ∃ i ∈ s.inputs, i.path = x ∧ i.changed = true := by
  simp only [Svc.changed, List.mem_map, List.mem_filter]
  constructor
  · rintro ⟨i, ⟨hi, hs⟩, rfl⟩; exact ⟨i, hi, rfl, hs⟩
  · rintro ⟨i, hi, rfl, hs⟩; exact ⟨i, ⟨hi, hs⟩, rfl⟩

/-- Stale iff some input is changed.

$$\forall s:\quad \operatorname{stale}(s) \iff \exists i \in I.\ \mathit{changed}(i)$$
-/
theorem Svc.stale_iff (s : Svc) :
    s.staleB = true ↔ ∃ i ∈ s.inputs, i.changed = true := by
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

/-! ### The history model: why a restart clears the Bool

`main` is a first-parent history, oldest first; each commit is the list of paths it touches. A base commit is a
position `b` in it (the number of commits it contains). -/

/-- The path is touched by the range after position `b`.

$$\operatorname{touched}(H, b, x) \iff \exists c \in H[b..].\ x \in c$$
-/
def touched (hist : List (List String)) (b : Nat) (x : String) : Bool :=
  (hist.drop b).any (fun c => decide (x ∈ c))

/-- The service whose inputs are judged against base position `b` of the history `H`.

$$\operatorname{judge}(H, b, n, X) = (n, [(x, \operatorname{touched}(H, b, x)) \mid x \leftarrow X])$$
-/
def Svc.judge (hist : List (List String)) (b : Nat) (name : String) (paths : List String) : Svc :=
  { name, inputs := paths.map (fun x => ⟨x, touched hist b x⟩) }

/-- A restart (console-api) or a rebuild (fwcore) records the current head of `main` as the new base: the range is
empty, so no input is changed and the service is not stale.

$$\forall H, n, X:\quad \neg\operatorname{stale}(\operatorname{judge}(H, |H|, n, X))$$
-/
theorem Svc.judge_head_not_stale (hist : List (List String)) (name : String) (paths : List String) :
    (Svc.judge hist hist.length name paths).staleB = false := by
  cases hb : (Svc.judge hist hist.length name paths).staleB with
  | false => rfl
  | true =>
    obtain ⟨i, hi, hc⟩ := (Svc.stale_iff _).1 hb
    simp only [Svc.judge, List.mem_map] at hi
    obtain ⟨x, _, rfl⟩ := hi
    simp [touched] at hc

/-- A commit on `main` at or after the base that touches a path marks it: a landing after the start is stale.

$$\forall H, b, j, c, x:\quad b \le j \wedge H[j] = c \wedge x \in c \Rightarrow \operatorname{touched}(H, b, x)$$
-/
theorem touched_of_mem (hist : List (List String)) (b j : Nat) (hj : b ≤ j) (c : List String)
    (hc : hist[j]? = some c) (x : String) (hx : x ∈ c) : touched hist b x = true := by
  simp only [touched, List.any_eq_true, decide_eq_true_eq]
  refine ⟨c, ?_, hx⟩
  rw [List.mem_iff_getElem?]
  exact ⟨j - b, by rw [List.getElem?_drop]; simpa [Nat.add_sub_cancel' hj] using hc⟩

/-- Restarting: the new process reads the files at the current head of `main`, so every input is unchanged
(`judge_head_not_stale`).

$$\operatorname{restart}(s) = (n, [(\mathit{path}(i), \mathrm{false}) \mid i \leftarrow I]),\quad s = (n, I)$$
-/
def Svc.restart (s : Svc) : Svc := { s with inputs := s.inputs.map (fun i => { i with changed := false }) }

/-- A restart clears staleness.

$$\forall s:\quad \neg\operatorname{stale}(\operatorname{restart}(s))$$
-/
theorem Svc.restart_clears (s : Svc) : s.restart.staleB = false := by
  cases hb : s.restart.staleB with
  | false => rfl
  | true =>
    obtain ⟨i, hi, hc⟩ := (Svc.stale_iff _).1 hb
    simp only [Svc.restart, List.mem_map] at hi
    obtain ⟨j, _, rfl⟩ := hi
    simp at hc

/-- The running stack: console-api (base = its start commit) and the `fwcore` binary (base = its build commit).

$$\Theta = (\mathit{api}, \mathit{core}) \in \mathrm{Svc} \times \mathrm{Svc}$$
-/
structure Stack where
  api  : Svc
  core : Svc

/-- Restarting console-api leaves the `fwcore` binary as it was (a land does not rebuild it in the main checkout).

$$\operatorname{restartApi}(\mathit{api}, \mathit{core}) = (\operatorname{restart}(\mathit{api}), \mathit{core})$$
-/
def Stack.restartApi (t : Stack) : Stack := { t with api := t.api.restart }

/-- `lake build` at the head of `main` refreshes the binary only.

$$\operatorname{rebuild}(\mathit{api}, \mathit{core}) = (\mathit{api}, \operatorname{restart}(\mathit{core}))$$
-/
def Stack.rebuild (t : Stack) : Stack := { t with core := t.core.restart }

/-- Restarting console-api without a rebuild leaves a stale `fwcore` stale.

$$\forall \Theta:\quad \operatorname{stale}(\mathit{core}(\Theta)) \Rightarrow \operatorname{stale}(\mathit{core}(\operatorname{restartApi}(\Theta)))\ \wedge\ \neg\operatorname{stale}(\mathit{api}(\operatorname{restartApi}(\Theta)))$$
-/
theorem Stack.restart_without_build_stale (t : Stack) (h : t.core.staleB = true) :
    t.restartApi.core.staleB = true ∧ t.restartApi.api.staleB = false :=
  ⟨h, t.api.restart_clears⟩

/-- A rebuild clears `fwcore` and leaves console-api's verdict alone.

$$\forall \Theta:\quad \neg\operatorname{stale}(\mathit{core}(\operatorname{rebuild}(\Theta)))\ \wedge\ \mathit{api}(\operatorname{rebuild}(\Theta)) = \mathit{api}(\Theta)$$
-/
theorem Stack.rebuild_clears (t : Stack) : t.rebuild.core.staleB = false ∧ t.rebuild.api = t.api :=
  ⟨t.core.restart_clears, rfl⟩

end Fw.Obs
