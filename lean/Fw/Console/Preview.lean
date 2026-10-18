import Fw.Console
import Fw.Ops.Identity
/-!
# Task preview: which commit, who may start it, how many, which ports, when it ends

The console can start a local web server per `port-*` / `fix-*` task: the task's version of the site next
to the original snapshot, for manual testing (task `task-preview`, `research/notes/2026/10-18-task-preview.md`).
Everything that is a *decision* is here; the TypeScript glue only does git, process and http I/O.

* **Target commit** (`target`). The preview shows the commit that has the task's work in the state the user
  wants to judge: `main` when the task head is already an ancestor of main (landed); else the first
  integration ref that contains the head (the glue passes the refs newest first, `git for-each-ref
  --sort=-committerdate`); else the task's own head (nothing integrated it yet); no head, no preview.
* **Admission** (`admit`). Only the actor `user` may start a preview (`mayStart`; the lead, owner and
  reviewer are the agent actors of `Fw.Ops.Identity.isAgentActor`). Then, in this order: one live preview per
  task, at most `K` live previews, a disk floor, a target, and two free ports of the fixed localhost range
  (one for the rewrite, one for the original).
* **Expiry** (`tick`). A preview lives `ttl` milliseconds from its start; the console ticks, and every
  preview past its deadline is removed from the table and its process group is stopped.
* **Stop** (`stop`, `reap`). The kill list is always a part of the console's own table (the previews it
  started and recorded), never a name or a pattern.

`Reach` is every table the three transitions can produce from the empty one; `reach_inv` proves the
invariants for all of them: at most `K` live previews (`live_le_K`) and pairwise distinct ports
(`ports_distinct`).
-/
namespace Fw.Console.Preview
open Fw.Console

/-! ## Limits -/

/-- Most live previews (a build is about 60 MB of disk and a few seconds of CPU).

$$K = 2$$ -/
def K : Nat := 2

/-- A preview's lifetime in milliseconds (60 minutes).

$$\mathit{ttl} = 60 \cdot 60 \cdot 1000$$ -/
def ttl : Nat := 3600000

/-- Disk floor in MB: a start is refused when less is free.

$$\mathit{floor} = 2048$$ -/
def diskFloor : Nat := 2048

/-- The first port of the localhost range.

$$P = \{47100, \dots, 47139\}, \quad \mathit{portLo} = 47100$$ -/
def portLo : Nat := 47100

/-- The number of ports in the range.

$$|P| = 40$$ -/
def portN : Nat := 40

/-! ## Target commit -/

/-- An integration ref the glue found: its name, its tip, and whether it contains the task head
(`git merge-base --is-ancestor head tip`).

$$c = (\mathit{ref}, \mathit{sha}, \mathit{contains}) \in \mathrm{String} \times \mathrm{String} \times \mathbb{B}$$ -/
structure Cand where
  ref : String
  sha : String
  contains : Bool
deriving Repr, DecidableEq

/-- What a preview shows.

$$\mathrm{Target} = \mathrm{main}(s) \mid \mathrm{integration}(\mathit{ref}, s) \mid \mathrm{own}(s) \mid \mathrm{none}$$ -/
inductive Target where
  | main (sha : String)
  | integration (ref sha : String)
  | own (sha : String)
  | none
deriving Repr, DecidableEq

/-- The first candidate that contains the head (candidates come newest first).

$$\operatorname{firstContaining}(cs) = \text{the first } c \in cs \text{ with } c.\mathit{contains}$$ -/
def firstContaining (cs : List Cand) : Option Cand := cs.find? (·.contains)

/-- The preview target of a task.

$$\operatorname{target}(m, h, \mathit{onMain}, cs) = \begin{cases}
\mathrm{none} & h = \bot\\
\mathrm{main}(m) & h \ne \bot \wedge \mathit{onMain}\\
\mathrm{integration}(c) & h \ne \bot \wedge \neg\mathit{onMain} \wedge c = \operatorname{firstContaining}(cs)\\
\mathrm{own}(h) & \text{otherwise}
\end{cases}$$ -/
def target (mainSha : String) (head : Option String) (onMain : Bool) (cs : List Cand) : Target :=
  match head with
  | none => .none
  | some h =>
    if onMain then .main mainSha
    else match firstContaining cs with
      | some c => .integration c.ref c.sha
      | none => .own h

/-- **No work, no preview.**

$$\forall m, \mathit{om}, cs:\ \operatorname{target}(m, \bot, \mathit{om}, cs) = \mathrm{none}$$ -/
theorem target_noWork (m : String) (om : Bool) (cs : List Cand) : target m none om cs = .none := rfl

/-- **Landed means main.**

$$\operatorname{target}(m, \mathrm{some}\ h, \mathrm{true}, cs) = \mathrm{main}(m)$$ -/
theorem target_landed (m h : String) (cs : List Cand) : target m (some h) true cs = .main m := by
  simp [target]

/-- **Own head only when nothing contains it.**

$$\operatorname{target}(m, \mathrm{some}\ h, \mathrm{false}, cs) = \mathrm{own}(h) \iff \forall c \in cs,\ \neg c.\mathit{contains}$$ -/
theorem target_own_iff (m h : String) (cs : List Cand) :
    target m (some h) false cs = .own h ↔ ∀ c ∈ cs, c.contains = false := by
  unfold target firstContaining
  cases hf : cs.find? (·.contains) with
  | none =>
    have h0 : ∀ c ∈ cs, c.contains = false := by
      intro c hc
      have := List.find?_eq_none.mp hf c hc
      simpa using this
    simp
    exact h0
  | some c =>
    have hm := List.mem_of_find?_eq_some hf
    have hc := List.find?_some hf
    simp only [ite_false, reduceCtorEq, false_iff]
    intro hall
    have := hall c hm
    simp_all

/-- **The integration pick is the first containing ref.**

$$\operatorname{target}(m, \mathrm{some}\ h, \mathrm{false}, cs) = \mathrm{integration}(r, s) \Rightarrow
cs = \mathit{pre} \mathbin{+\!\!+} (r, s, \mathrm{true}) :: \mathit{post} \wedge \forall p \in \mathit{pre},\ \neg p.\mathit{contains}$$ -/
theorem target_integration_first (m h r s : String) (cs : List Cand)
    (ht : target m (some h) false cs = .integration r s) :
    ∃ pre c post, cs = pre ++ c :: post ∧ c.contains = true ∧ c.ref = r ∧ c.sha = s ∧
      ∀ p ∈ pre, p.contains = false := by
  unfold target firstContaining at ht
  cases hf : cs.find? (·.contains) with
  | none => simp [hf] at ht
  | some c =>
    simp only [hf, Bool.false_eq_true, ite_false, Target.integration.injEq] at ht
    obtain ⟨hcon, pre, post, hcs, hpre⟩ := (List.find?_eq_some_iff_append.mp hf)
    refine ⟨pre, c, post, hcs, by simpa using hcon, ht.1, ht.2, fun p hp => ?_⟩
    simpa using hpre p hp

/-- **Determinism.** The target is a function of its four inputs, and candidates that do not contain the
head do not matter: dropping them gives the same target.

$$\operatorname{target}(m, h, \mathit{om}, cs) = \operatorname{target}(m, h, \mathit{om}, \operatorname{filter}(\mathit{contains}, cs))$$ -/
theorem target_deterministic (m : String) (h : Option String) (om : Bool) (cs : List Cand) :
    target m h om cs = target m h om (cs.filter (·.contains)) := by
  unfold target firstContaining
  have : (cs.filter (·.contains)).find? (·.contains) = cs.find? (·.contains) := by
    induction cs with
    | nil => rfl
    | cons c t ih =>
      by_cases hc : c.contains = true
      · simp [hc]
      · simp [hc, ih]
  rw [this]

/-! ## The table, admission, ports -/

/-- A live preview (the console's own record of a process group it started).

$$p = (\mathit{id}, \mathit{task}, \mathit{rp}, \mathit{op}, t_0)$$ with the rewrite port `rp`, the original's port `op`, the start time `t₀` (ms). -/
structure Pv where
  id : String
  task : String
  rp : Nat
  op : Nat
  started : Nat
deriving Repr, DecidableEq

/-- The deadline of a preview.

$$\operatorname{deadline}(p) = p.t_0 + \mathit{ttl}$$ -/
def Pv.deadline (p : Pv) : Nat := p.started + ttl

/-- The ports the table holds.

$$\operatorname{ports}(T) = [\,p.\mathit{rp}, p.\mathit{op}\ \text{for}\ p \in T\,]$$ -/
def ports (s : List Pv) : List Nat := s.flatMap fun p => [p.rp, p.op]

/-- The free ports of the range, ascending.

$$F(T) = \{\mathit{portLo} + i \mid i < \mathit{portN}\} \setminus \operatorname{ports}(T)$$ -/
def freePorts (s : List Pv) : List Nat := (List.range' portLo portN).filter fun q => q ∉ ports s

/-- Why a start is refused.

$$\mathrm{Refusal} = \{\mathrm{notOwner}, \mathrm{taskBusy}, \mathrm{tooMany}, \mathrm{lowDisk}, \mathrm{noPorts}, \mathrm{noTarget}\}$$ -/
inductive Refusal where
  | notOwner | taskBusy | tooMany | lowDisk | noPorts | noTarget
deriving Repr, DecidableEq

/-- The wire name of a refusal.

$$\operatorname{name}(r) = \text{the constructor name of } r$$ -/
def Refusal.name : Refusal → String
  | .notOwner => "notOwner" | .taskBusy => "taskBusy" | .tooMany => "tooMany"
  | .lowDisk => "lowDisk" | .noPorts => "noPorts" | .noTarget => "noTarget"

/-- Who may start or stop a preview: the user only.

$$\operatorname{mayStart}(a) = \mathrm{true} \iff a = \mathrm{user}$$ -/
def mayStart (a : Actor) : Bool := a == .user

/-- Every agent actor is refused.

$$\operatorname{isAgentActor}(a) \Rightarrow \operatorname{mayStart}(a) = \mathrm{false}$$ -/
theorem mayStart_not_agent (a : Actor) (h : Fw.Ops.Identity.isAgentActor a = true) : mayStart a = false := by
  cases a <;> simp_all [mayStart, Fw.Ops.Identity.isAgentActor]

/-- A start request (the facts; `hasTarget` is `target ≠ none`).

$$r = (a, \mathit{id}, \mathit{task}, \mathit{now}, \mathit{disk}, \mathit{hasTarget})$$ -/
structure Req where
  actor : Actor
  id : String
  task : String
  now : Nat
  diskMb : Nat
  hasTarget : Bool

/-- The decision on a start: the new table or the refusal. The first failing rule wins.

$$\operatorname{admit}(T, r) = \begin{cases}
\mathrm{notOwner} & r.a \ne \mathrm{user}\\
\mathrm{taskBusy} & \exists p \in T,\ p.\mathit{task} = r.\mathit{task} \vee p.\mathit{id} = r.\mathit{id}\\
\mathrm{tooMany} & |T| \ge K\\
\mathrm{lowDisk} & r.\mathit{disk} < \mathit{floor}\\
\mathrm{noTarget} & \neg r.\mathit{hasTarget}\\
\mathrm{noPorts} & |F(T)| < 2\\
(q_1, q_2, r.\mathit{now})\!::\!T & q_1, q_2 \text{ the two smallest of } F(T)
\end{cases}$$ -/
def admit (s : List Pv) (r : Req) : Except Refusal (List Pv) :=
  if !mayStart r.actor then .error .notOwner
  else if s.any (fun p => p.task == r.task || p.id == r.id) then .error .taskBusy
  else if K ≤ s.length then .error .tooMany
  else if r.diskMb < diskFloor then .error .lowDisk
  else if !r.hasTarget then .error .noTarget
  else match freePorts s with
    | a :: b :: _ => .ok ({ id := r.id, task := r.task, rp := a, op := b, started := r.now } :: s)
    | _ => .error .noPorts

/-- **Agents are never admitted.**

$$\operatorname{isAgentActor}(a) \Rightarrow \operatorname{admit}(T, r) = \mathrm{error}(\mathrm{notOwner})$$ -/
theorem agent_never_admitted (s : List Pv) (r : Req) (h : Fw.Ops.Identity.isAgentActor r.actor = true) :
    admit s r = .error .notOwner := by
  simp [admit, mayStart_not_agent r.actor h]

/-- **Only the user is admitted.**

$$\operatorname{admit}(T, r) = \mathrm{ok}(T') \Rightarrow r.a = \mathrm{user}$$ -/
theorem admit_user (s s' : List Pv) (r : Req) (h : admit s r = .ok s') : r.actor = .user := by
  unfold admit at h
  by_cases hm : (!mayStart r.actor) = true
  · simp [hm] at h
  · simpa [mayStart] using hm

/-- Time passing: every preview past its deadline leaves the table (and its process group is stopped).

$$\operatorname{tick}(T, t) = [\,p \in T \mid t < p.\mathit{deadline}\,]$$ -/
def tick (s : List Pv) (now : Nat) : List Pv := s.filter fun p => now < p.deadline

/-- The previews a tick stops.

$$\operatorname{expired}(T, t) = [\,p \in T \mid p.\mathit{deadline} \le t\,]$$ -/
def expired (s : List Pv) (now : Nat) : List Pv := s.filter fun p => !(now < p.deadline)

/-- A user stop: the previews with that id leave the table.

$$\operatorname{stop}(T, i) = [\,p \in T \mid p.\mathit{id} \ne i\,]$$ -/
def stop (s : List Pv) (i : String) : List Pv := s.filter fun p => p.id != i

/-- The previews a stop of `i` kills: only entries of the table.

$$\operatorname{own}(T, i) = [\,p \in T \mid p.\mathit{id} = i\,]$$ -/
def own (s : List Pv) (i : String) : List Pv := s.filter fun p => p.id == i

/-- Console start or stop: everything recorded is killed and the table is empty.

$$\operatorname{reap}(T) = (\,[\,],\ T\,)$$ -/
def reap (s : List Pv) : List Pv × List Pv := ([], s)

/-! ## Reachable tables and their invariants -/

/-- The tables the transitions produce from the empty one (admit, tick, stop).

$$\mathrm{Reach}([\,]),\quad \mathrm{Reach}(T) \wedge \operatorname{admit}(T, r) = \mathrm{ok}(T') \Rightarrow \mathrm{Reach}(T'),\quad \mathrm{Reach}(T) \Rightarrow \mathrm{Reach}(\operatorname{tick}(T, t)) \wedge \mathrm{Reach}(\operatorname{stop}(T, i))$$ -/
inductive Reach : List Pv → Prop where
  | init : Reach []
  | admit {s s' : List Pv} (r : Req) : Reach s → admit s r = .ok s' → Reach s'
  | tick {s : List Pv} (t : Nat) : Reach s → Reach (tick s t)
  | stop {s : List Pv} (i : String) : Reach s → Reach (stop s i)

/-- The invariants.

$$\operatorname{Inv}(T) \iff |T| \le K \wedge \operatorname{ports}(T)\ \text{has no duplicates} \wedge \operatorname{ports}(T) \subseteq P$$ -/
def Inv (s : List Pv) : Prop :=
  s.length ≤ K ∧ (ports s).Nodup ∧ ∀ q ∈ ports s, portLo ≤ q ∧ q < portLo + portN

/-- Filtering the table filters its ports (a sublist).

$$\operatorname{ports}(\operatorname{filter}(f, T)) \preceq \operatorname{ports}(T)$$ -/
theorem ports_filter_sublist (s : List Pv) (f : Pv → Bool) : (ports (s.filter f)).Sublist (ports s) := by
  induction s with
  | nil => simp [ports]
  | cons a t ih =>
    cases hfa : f a
    · simp only [ports, List.filter_cons, hfa, List.flatMap_cons] at ih ⊢
      exact ih.trans ((List.sublist_cons_self _ _).trans (List.sublist_cons_self _ _))
    · simp only [ports, List.filter_cons, hfa, List.flatMap_cons] at ih ⊢
      simpa using ih.append_left [a.rp, a.op]

/-- The invariants survive any filter (tick and stop are filters).

$$\operatorname{Inv}(T) \Rightarrow \operatorname{Inv}(\operatorname{filter}(f, T))$$ -/
theorem inv_filter {s : List Pv} (f : Pv → Bool) (h : Inv s) : Inv (s.filter f) := by
  obtain ⟨hl, hn, hr⟩ := h
  exact ⟨Nat.le_trans (List.length_filter_le _ _) hl, hn.sublist (ports_filter_sublist s f),
    fun q hq => hr q ((ports_filter_sublist s f).subset hq)⟩

/-- The invariants survive an admitted start.

$$\operatorname{Inv}(T) \wedge \operatorname{admit}(T, r) = \mathrm{ok}(T') \Rightarrow \operatorname{Inv}(T')$$ -/
theorem inv_admit {s s' : List Pv} (r : Req) (hi : Inv s) (h : admit s r = .ok s') : Inv s' := by
  obtain ⟨hl, hn, hr⟩ := hi
  unfold admit at h
  split at h
  · simp at h
  split at h
  · simp at h
  rename_i h1 h2
  split at h
  · simp at h
  rename_i h3
  split at h
  · simp at h
  split at h
  · simp at h
  split at h
  · rename_i a b rest hf
    simp only [Except.ok.injEq] at h
    subst h
    have hmem : ∀ q ∈ freePorts s, portLo ≤ q ∧ q < portLo + portN ∧ q ∉ ports s := by
      intro q hq
      unfold freePorts at hq
      simp only [List.mem_filter, List.mem_range'_1, decide_eq_true_eq] at hq
      exact ⟨hq.1.1, hq.1.2, hq.2⟩
    have hnd : (freePorts s).Nodup := List.Nodup.sublist List.filter_sublist List.nodup_range'
    rw [hf] at hmem hnd
    have ha := hmem a (by simp)
    have hb := hmem b (by simp)
    have hab : a ≠ b := by
      intro e; subst e; simp at hnd
    refine ⟨?_, ?_, ?_⟩
    · simp only [List.length_cons]
      simp only [Nat.not_le] at h3
      omega
    · simp only [ports, List.flatMap_cons, List.cons_append, List.nil_append] at hn ⊢
      simp only [List.nodup_cons, List.mem_cons, not_or]
      exact ⟨⟨hab, fun hh => ha.2.2 (by simpa [ports] using hh)⟩, fun hh => hb.2.2 (by simpa [ports] using hh), hn⟩
    · intro q hq
      simp only [ports, List.flatMap_cons, List.cons_append, List.nil_append, List.mem_cons] at hq
      rcases hq with rfl | rfl | hq
      · exact ⟨ha.1, ha.2.1⟩
      · exact ⟨hb.1, hb.2.1⟩
      · exact hr q (by simpa [ports] using hq)
  · simp at h

/-- **Every reachable table satisfies the invariants.**

$$\mathrm{Reach}(T) \Rightarrow \operatorname{Inv}(T)$$ -/
theorem reach_inv {s : List Pv} (h : Reach s) : Inv s := by
  induction h with
  | init => exact ⟨by simp [K], by simp [ports], by simp [ports]⟩
  | admit r _ ha ih => exact inv_admit r ih ha
  | tick t _ ih => exact inv_filter _ ih
  | stop i _ ih => exact inv_filter _ ih

/-- **At most `K` live previews, always.**

$$\mathrm{Reach}(T) \Rightarrow |T| \le K = 2$$ -/
theorem live_le_K {s : List Pv} (h : Reach s) : s.length ≤ K := (reach_inv h).1

/-- **Ports are pairwise distinct** (the rewrite and original ports of all live previews).

$$\mathrm{Reach}(T) \Rightarrow \operatorname{ports}(T)\ \text{has no duplicates}$$ -/
theorem ports_distinct {s : List Pv} (h : Reach s) : (ports s).Nodup := (reach_inv h).2.1

/-- **Ports stay in the fixed localhost range.**

$$\mathrm{Reach}(T) \Rightarrow \forall q \in \operatorname{ports}(T):\ 47100 \le q < 47140$$ -/
theorem ports_in_range {s : List Pv} (h : Reach s) : ∀ q ∈ ports s, portLo ≤ q ∧ q < portLo + portN :=
  (reach_inv h).2.2

/-- **Expired previews are stopped at the next tick.** After a tick no preview of the table is past its deadline,
and every one that was is in the kill list.

$$\forall p \in \operatorname{tick}(T, t):\ t < p.t_0 + \mathit{ttl}, \qquad \forall p \in T:\ p.t_0 + \mathit{ttl} \le t \Rightarrow p \in \operatorname{expired}(T, t) \wedge p \notin \operatorname{tick}(T, t)$$ -/
theorem expired_stopped (s : List Pv) (t : Nat) :
    (∀ p ∈ tick s t, t < p.started + ttl) ∧
    (∀ p ∈ s, p.started + ttl ≤ t → p ∈ expired s t ∧ p ∉ tick s t) := by
  refine ⟨fun p hp => ?_, fun p hp he => ?_⟩
  · exact of_decide_eq_true (List.mem_filter.mp hp).2
  · refine ⟨List.mem_filter.mpr ⟨hp, ?_⟩, fun hm => ?_⟩
    · have : ¬ t < p.deadline := by simp only [Pv.deadline]; omega
      simp [this]
    · have h2 : t < p.deadline := of_decide_eq_true (List.mem_filter.mp hm).2
      simp only [Pv.deadline] at h2
      omega

/-- **Bounded lifetime.** A preview that survives a tick is younger than the TTL.

$$p \in \operatorname{tick}(T, t) \wedge t_0 \le t \Rightarrow t - p.t_0 < \mathit{ttl}$$ -/
theorem tick_lifetime (s : List Pv) (t : Nat) (p : Pv) (hp : p ∈ tick s t) (h0 : p.started ≤ t) :
    t - p.started < ttl := by
  have := (expired_stopped s t).1 p hp
  omega

/-- A tick is idempotent.

$$\operatorname{tick}(\operatorname{tick}(T, t), t) = \operatorname{tick}(T, t)$$ -/
theorem tick_idem (s : List Pv) (t : Nat) : tick (tick s t) t = tick s t := by
  simp [tick, List.filter_filter]

/-- **A stop kills only what the console recorded.** Every process group in the kill list is a table entry, and
an id that is not in the table kills nothing.

$$\operatorname{own}(T, i) \subseteq T, \qquad (\forall p \in T,\ p.\mathit{id} \ne i) \Rightarrow \operatorname{own}(T, i) = [\,]$$ -/
theorem stop_only_own (s : List Pv) (i : String) :
    (∀ p ∈ own s i, p ∈ s) ∧ ((∀ p ∈ s, p.id ≠ i) → own s i = []) := by
  refine ⟨fun p hp => (List.mem_filter.mp hp).1, fun h => ?_⟩
  unfold own
  rw [List.filter_eq_nil_iff]
  intro p hp
  have := h p hp
  simp [this]

/-- A stop splits the table into what stays and what is killed.

$$\operatorname{own}(T, i) \mathbin{+\!\!+} \operatorname{stop}(T, i) \sim T \ \text{(a permutation)}$$ -/
theorem stop_partition (s : List Pv) (i : String) : (own s i ++ stop s i).Perm s := by
  unfold stop own
  have := List.filter_append_perm (fun p : Pv => p.id == i) s
  simpa [Function.comp_def, bne] using this

/-- **Expiry kills only table entries too.**

$$\operatorname{expired}(T, t) \subseteq T$$ -/
theorem expired_sub (s : List Pv) (t : Nat) : ∀ p ∈ expired s t, p ∈ s :=
  fun _ hp => (List.mem_filter.mp hp).1

/-- **Reap kills exactly the table and empties it.**

$$\operatorname{reap}(T) = ([\,], T)$$ -/
theorem reap_all (s : List Pv) : (reap s).1 = [] ∧ (reap s).2 = s := ⟨rfl, rfl⟩

end Fw.Console.Preview
