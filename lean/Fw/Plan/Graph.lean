/-!
# The work graph: tasks, dependencies, acyclicity, chains, write/device conflicts

The pure graph layer under `Fw.Plan.Core` (the console's `task.*` commands).

* `Dep ts a b`: a row of `ts` with id `a` lists `b` among its deps. `Acyclic ts`: no task reaches
  itself through one or more `Dep` edges.
* `kahn` / `acyclicB`: Kahn's pass over the rows (repeatedly remove a task none of whose deps is
  still present). `acyclicB_sound`: it accepts only acyclic graphs; `acyclicB_complete`: it accepts
  every acyclic graph (a stuck pass has a cycle, by pigeonhole). So `acyclicB ts = true ↔ Acyclic ts`.
* `criticalPath`: the longest chain of undone tasks (unit weights), by a tabulated longest-chain pass
  with fuel $|ts|$. `criticalPath_chain`: it is a chain of undone tasks; `criticalPath_longest`: on an
  acyclic graph no chain of undone tasks is longer. (`Fw.Sched.ParMetrics.cp` gives the same length on
  a numbered DAG but returns no path, so it is not reused here.)
* `globOv`: conservative overlap of two path globs (`**`, `*` inside a segment, and a directory prefix
  covering its subtree). `globOv_sound`: if it says "no overlap", no path matches both.
  On literal paths it is `Fw.Sched.Admit.pconf`'s segment-prefix relation.
-/
namespace Fw.Plan

/-- A task row of the work graph: its definition (id, title, stream, milestone, deps, owner, write
globs, devices) and its two observed facts, the evidence that it is done and the agent that claimed it.

$$t = (\mathit{id}, \mathit{title}, \mathit{stream}, \mathit{milestone}_\bot, \mathit{deps}, \mathit{owner}, \mathit{writes}, \mathit{devices}, \mathit{evidence}_\bot, \mathit{agent}_\bot)$$
-/
structure Task where
  id        : String
  title     : String
  stream    : String
  milestone : Option String
  deps      : List String
  owner     : String
  writes    : List String
  devices   : List String
  evidence  : Option String
  agent     : Option String
deriving Repr, DecidableEq

/-- The ids of a list of rows, in order.

$$\operatorname{ids}(ts) = [\, t.\mathit{id} : t \in ts \,]$$
-/
def ids (ts : List Task) : List String := ts.map (·.id)

/-- The dependency relation: some row with id `a` lists `b` among its deps ("a depends on b").

$$\operatorname{Dep}_{ts}(a, b) \iff \exists t \in ts:\ t.\mathit{id} = a \land b \in t.\mathit{deps}$$
-/
def Dep (ts : List Task) (a b : String) : Prop := ∃ t ∈ ts, t.id = a ∧ b ∈ t.deps

/-- The work graph is acyclic: no task reaches itself by one or more dependency edges.

$$\operatorname{Acyclic}(ts) \iff \forall a:\ \neg\, \operatorname{Dep}_{ts}^{+}(a, a)$$
-/
def Acyclic (ts : List Task) : Prop := ∀ a, ¬ Relation.TransGen (Dep ts) a a

/-! ## Transitive closure helpers -/

/-- A path of one or more edges starts with an edge.

$$\forall R, a, b:\quad R^{+}(a, b) \Rightarrow \exists c:\ R(a, c)$$
-/
theorem tg_first {R : String → String → Prop} {a b : String} (h : Relation.TransGen R a b) :
    ∃ c, R a c := by
  induction h with
  | single h => exact ⟨_, h⟩
  | tail _ _ ih => exact ih

/-- The transitive closure is monotone in the relation.

$$\forall R, S, a, b:\quad (\forall x, y:\ R(x, y) \Rightarrow S(x, y)) \land R^{+}(a, b) \Rightarrow S^{+}(a, b)$$
-/
theorem tg_mono {R S : String → String → Prop} (hs : ∀ x y, R x y → S x y) {a b : String}
    (h : Relation.TransGen R a b) : Relation.TransGen S a b := by
  induction h with
  | single h => exact .single (hs _ _ h)
  | tail _ hbc ih => exact .tail ih (hs _ _ hbc)

/-- A path of the reversed relation is a reversed path.

$$\forall R, a, b:\quad (R^{\top})^{+}(a, b) \Rightarrow R^{+}(b, a), \qquad R^{\top}(x, y) :\iff R(y, x)$$
-/
theorem tg_flip {R : String → String → Prop} {a b : String}
    (h : Relation.TransGen (fun x y => R y x) a b) : Relation.TransGen R b a := by
  induction h with
  | single h => exact .single h
  | tail _ hbc ih => exact Relation.TransGen.trans (.single hbc) ih

/-! ## Chains and pigeonhole -/

/-- A chain: a list whose consecutive elements are related.

$$\operatorname{Chain}_R([\,]), \quad \operatorname{Chain}_R([a]), \quad R(a, b) \land \operatorname{Chain}_R(b :: l) \Rightarrow \operatorname{Chain}_R(a :: b :: l)$$
-/
inductive Chain (R : String → String → Prop) : List String → Prop where
  | nil : Chain R []
  | single (a : String) : Chain R [a]
  | cons {a b : String} {l : List String} : R a b → Chain R (b :: l) → Chain R (a :: b :: l)

/-- The head of a chain reaches every later element.

$$\forall R, l, a, r, x:\quad \operatorname{Chain}_R(l) \land l = a :: r \land x \in r \Rightarrow R^{+}(a, x)$$
-/
theorem chain_tg {R : String → String → Prop} {l : List String} (h : Chain R l) :
    ∀ a r, l = a :: r → ∀ x ∈ r, Relation.TransGen R a x := by
  induction h with
  | nil => intro a r he; cases he
  | single a => intro a' r he x hx; cases he; simp at hx
  | cons hab _ ih =>
    intro a' r he x hx
    cases he
    rcases List.mem_cons.mp hx with rfl | hx
    · exact .single hab
    · exact Relation.TransGen.trans (.single hab) (ih _ _ rfl x hx)

/-- On an acyclic relation every chain is duplicate-free.

$$\forall R, l:\quad (\forall a:\ \neg R^{+}(a, a)) \land \operatorname{Chain}_R(l) \Rightarrow \operatorname{Nodup}(l)$$
-/
theorem chain_nodup {R : String → String → Prop} (hR : ∀ a, ¬ Relation.TransGen R a a)
    {l : List String} (h : Chain R l) : l.Nodup := by
  induction h with
  | nil => exact List.nodup_nil
  | single a => simp
  | cons hab hc ih =>
    rename_i a b l
    refine List.nodup_cons.mpr ⟨fun ha => hR a ?_, ih⟩
    exact chain_tg (.cons hab hc) a (b :: l) rfl a ha

/-- In a set where every element has a successor inside the set, there are chains of every length.

$$\forall R, S, n, u:\quad (\forall x \in S\ \exists y \in S:\ R(x, y)) \land u \in S \Rightarrow \exists l:\ \operatorname{Chain}_R(u :: l) \land |l| = n \land u :: l \subseteq S$$
-/
theorem stuck_chain {R : String → String → Prop} {S : List String}
    (hs : ∀ x ∈ S, ∃ y ∈ S, R x y) : ∀ (n : Nat) (u : String), u ∈ S →
    ∃ l, Chain R (u :: l) ∧ l.length = n ∧ ∀ x ∈ u :: l, x ∈ S
  | 0, u, hu => ⟨[], .single u, rfl, by simpa using hu⟩
  | n + 1, u, hu => by
    obtain ⟨v, hv, huv⟩ := hs u hu
    obtain ⟨l, hc, hl, hsub⟩ := stuck_chain hs n v hv
    refine ⟨v :: l, .cons huv hc, by simp [hl], ?_⟩
    intro x hx
    rcases List.mem_cons.mp hx with rfl | hx
    · exact hu
    · exact hsub x hx

/-- **Pigeonhole.** A non-empty set where every element has a successor inside the set contains a cycle.

$$\forall R, S:\quad S \ne [\,] \land (\forall x \in S\ \exists y \in S:\ R(x, y)) \Rightarrow \exists a:\ R^{+}(a, a)$$
-/
theorem stuck_cycle {R : String → String → Prop} {S : List String} (hne : S ≠ [])
    (hs : ∀ x ∈ S, ∃ y ∈ S, R x y) : ∃ a, Relation.TransGen R a a := by
  obtain ⟨u, hu⟩ := List.exists_mem_of_ne_nil S hne
  obtain ⟨l, hc, hl, hsub⟩ := stuck_chain hs S.length u hu
  apply Classical.byContradiction
  intro hno
  have hnd := chain_nodup (fun a ha => hno ⟨a, ha⟩) hc
  have := List.Nodup.length_le_of_subset hnd (fun x hx => hsub x hx)
  simp [hl] at this
  omega

/-! ## Kahn's pass -/

/-- All deps listed by the rows with id `x`.

$$\operatorname{succ}_{ts}(x) = \big[\, d : t \in ts,\ t.\mathit{id} = x,\ d \in t.\mathit{deps} \,\big]$$
-/
def succ (ts : List Task) (x : String) : List String := ts.flatMap fun t => if t.id = x then t.deps else []

/-- Membership in `succ` is the dependency relation.

$$\forall ts, a, b:\quad b \in \operatorname{succ}_{ts}(a) \iff \operatorname{Dep}_{ts}(a, b)$$
-/
theorem mem_succ {ts : List Task} {a b : String} : b ∈ succ ts a ↔ Dep ts a b := by
  simp only [succ, List.mem_flatMap, Dep]
  constructor
  · rintro ⟨t, ht, hb⟩
    by_cases h : t.id = a
    · simp only [h, ite_true] at hb; exact ⟨t, ht, h, hb⟩
    · simp [h] at hb
  · rintro ⟨t, ht, rfl, hb⟩
    exact ⟨t, ht, by simpa using hb⟩

/-- A task is free in the remaining rows when none of its deps is the id of a remaining row.

$$\operatorname{free}(R, x) \iff \forall d \in \operatorname{succ}_R(x):\ d \notin \operatorname{ids}(R)$$
-/
def free (rem : List Task) (x : String) : Bool := (succ rem x).all fun b => !(ids rem).contains b

/-- Kahn's pass with fuel: while rows remain, remove every row with the id of the first free row;
fail when no row is free or the fuel is spent.

$$\operatorname{kahn}(f, R) = \begin{cases} \mathrm{true} & R = [\,] \\ \mathrm{false} & R \ne [\,] \land f = 0 \\ \mathrm{false} & R \ne [\,] \land \text{no } t \in R \text{ has } \operatorname{free}(R, t.\mathit{id}) \\ \operatorname{kahn}\big(f - 1, [\, r \in R : r.\mathit{id} \ne t.\mathit{id} \,]\big) & \text{else, } t \text{ the first row with } \operatorname{free}(R, t.\mathit{id}) \end{cases}$$
-/
def kahn : Nat → List Task → Bool
  | _, [] => true
  | 0, _ :: _ => false
  | f + 1, r :: rs =>
    match (r :: rs).find? (fun t => free (r :: rs) t.id) with
    | none => false
    | some t => kahn f ((r :: rs).filter fun x => x.id != t.id)

/-- The acyclicity decision: Kahn's pass with fuel $|ts|$.

$$\operatorname{acyclicB}(ts) = \operatorname{kahn}(|ts|, ts)$$
-/
def acyclicB (ts : List Task) : Bool := kahn ts.length ts

/-- The source of a dependency edge is the id of a row.

$$\forall ts, a, b:\quad \operatorname{Dep}_{ts}(a, b) \Rightarrow a \in \operatorname{ids}(ts)$$
-/
theorem dep_src {ts : List Task} {a b : String} (h : Dep ts a b) : a ∈ ids ts := by
  obtain ⟨t, ht, rfl, _⟩ := h
  exact List.mem_map_of_mem ht

/-- Removing rows removes edges: the edges of a filtered list are edges of the list.

$$\forall ts, p, a, b:\quad \operatorname{Dep}_{[t \in ts : p(t)]}(a, b) \Rightarrow \operatorname{Dep}_{ts}(a, b)$$
-/
theorem dep_filter {ts : List Task} {p : Task → Bool} {a b : String}
    (h : Dep (ts.filter p) a b) : Dep ts a b := by
  obtain ⟨t, ht, h1, h2⟩ := h
  exact ⟨t, (List.mem_filter.mp ht).1, h1, h2⟩

/-- An edge whose source is not `x` survives removing the rows with id `x`.

$$\forall ts, x, a, b:\quad \operatorname{Dep}_{ts}(a, b) \land a \ne x \Rightarrow \operatorname{Dep}_{[t \in ts : t.\mathit{id} \ne x]}(a, b)$$
-/
theorem dep_keep {ts : List Task} {x a b : String} (h : Dep ts a b) (hx : a ≠ x) :
    Dep (ts.filter fun r => r.id != x) a b := by
  obtain ⟨t, ht, rfl, hb⟩ := h
  exact ⟨t, List.mem_filter.mpr ⟨ht, by simpa using hx⟩, rfl, hb⟩

/-- A free task has no edge into a remaining row.

$$\forall R, x, v:\quad \operatorname{free}(R, x) \land \operatorname{Dep}_R(x, v) \Rightarrow v \notin \operatorname{ids}(R)$$
-/
theorem free_no_edge {rem : List Task} {x v : String} (hf : free rem x = true) (h : Dep rem x v) :
    v ∉ ids rem := by
  have := List.all_eq_true.mp hf v (mem_succ.mpr h)
  simpa using this

/-- One Kahn step keeps cycles: a cycle of the rows survives removing a free task.

$$\forall R, x, a:\quad \operatorname{free}(R, x) \land \operatorname{Dep}_R^{+}(a, a) \Rightarrow \operatorname{Dep}_{[r \in R : r.\mathit{id} \ne x]}^{+}(a, a)$$
-/
theorem cycle_survives {rem : List Task} {x a : String} (hf : free rem x = true)
    (h : Relation.TransGen (Dep rem) a a) :
    Relation.TransGen (Dep (rem.filter fun r => r.id != x)) a a := by
  -- every edge into a row id has a source other than `x`
  have key : ∀ u v, Dep rem u v → v ∈ ids rem → u ≠ x := by
    intro u v huv hv hux
    subst hux
    exact free_no_edge hf huv hv
  have gen : ∀ b, Relation.TransGen (Dep rem) a b → b ∈ ids rem →
      Relation.TransGen (Dep (rem.filter fun r => r.id != x)) a b := by
    intro b hab
    induction hab with
    | single h1 => intro hb; exact .single (dep_keep h1 (key _ _ h1 hb))
    | tail hac hcb ih =>
      intro hb
      exact .tail (ih (dep_src hcb)) (dep_keep hcb (key _ _ hcb hb))
  obtain ⟨c, hc⟩ := tg_first h
  exact gen a h (dep_src hc)

/-- **Kahn accepts only acyclic graphs.**

$$\forall f, R:\quad \operatorname{kahn}(f, R) = \mathrm{true} \Rightarrow \operatorname{Acyclic}(R)$$
-/
theorem kahn_sound : ∀ (f : Nat) (rem : List Task), kahn f rem = true → Acyclic rem
  | _, [], _ => by
    intro a h
    obtain ⟨c, t, ht, _⟩ := tg_first h
    cases ht
  | 0, _ :: _, h => by simp [kahn] at h
  | f + 1, r :: rs, h => by
    simp only [kahn] at h
    split at h
    · cases h
    · rename_i t ht
      have hf : free (r :: rs) t.id = true := by
        have := List.find?_some ht
        simpa using this
      have ih := kahn_sound f _ h
      intro a ha
      exact ih a (cycle_survives hf ha)

/-- **Kahn with enough fuel accepts every acyclic graph**: a stuck pass leaves a non-empty set of rows
each with a dep among them, hence a cycle.

$$\forall f, R:\quad |R| \le f \land \operatorname{kahn}(f, R) = \mathrm{false} \Rightarrow \neg \operatorname{Acyclic}(R)$$
-/
theorem kahn_complete : ∀ (f : Nat) (rem : List Task), rem.length ≤ f → kahn f rem = false →
    ¬ Acyclic rem
  | _, [], _, h => by simp [kahn] at h
  | 0, _ :: _, hl, _ => by simp at hl
  | f + 1, r :: rs, hl, h => by
    simp only [kahn] at h
    split at h
    · rename_i hn
      intro hac
      have hs : ∀ x ∈ ids (r :: rs), ∃ y ∈ ids (r :: rs), Dep (r :: rs) x y := by
        intro x hx
        obtain ⟨t, ht, rfl⟩ := List.mem_map.mp hx
        have hnf : free (r :: rs) t.id = false := by
          have := List.find?_eq_none.mp hn t ht
          simpa using this
        simp only [free, List.all_eq_false] at hnf
        obtain ⟨y, hy, hyc⟩ := hnf
        exact ⟨y, by simpa using hyc, mem_succ.mp hy⟩
      obtain ⟨a, ha⟩ := stuck_cycle (by simp [ids]) hs
      exact hac a ha
    · rename_i t ht
      have hmem : t ∈ r :: rs := List.mem_of_find?_eq_some ht
      have hlt : ((r :: rs).filter fun x => x.id != t.id).length < (r :: rs).length := by
        apply List.length_filter_lt_length_iff_exists.mpr
        exact ⟨t, hmem, by simp⟩
      have ih := kahn_complete f _ (by omega) h
      intro hac
      exact ih fun a ha => hac a (tg_mono (fun _ _ => dep_filter) ha)

/-- **The acyclicity decision is exact.**

$$\forall ts:\quad \operatorname{acyclicB}(ts) = \mathrm{true} \iff \operatorname{Acyclic}(ts)$$
-/
theorem acyclicB_iff (ts : List Task) : acyclicB ts = true ↔ Acyclic ts := by
  constructor
  · exact kahn_sound _ _
  · intro h
    cases hk : acyclicB ts
    · exact absurd h (kahn_complete ts.length ts (Nat.le_refl _) hk)
    · rfl

/-! ## The critical path over undone tasks -/

/-- The undone rows (no evidence yet).

$$\operatorname{undone}(ts) = [\, t \in ts : t.\mathit{evidence} = \bot \,]$$
-/
def undone (ts : List Task) : List Task := ts.filter fun t => t.evidence.isNone

/-- The ids of the undone rows.

$$\operatorname{uids}(ts) = \operatorname{ids}(\operatorname{undone}(ts))$$
-/
def uids (ts : List Task) : List String := ids (undone ts)

/-- The "next" relation of chains: `b` is an undone row that depends on `a` (work flows from `a` to `b`).

$$\operatorname{Next}_{ts}(a, b) \iff \exists t \in ts:\ t.\mathit{evidence} = \bot \land t.\mathit{id} = b \land a \in t.\mathit{deps}$$
-/
def Next (ts : List Task) (a b : String) : Prop := ∃ t ∈ ts, t.evidence = none ∧ t.id = b ∧ a ∈ t.deps

/-- A chain of undone tasks: consecutive tasks are `Next`-related and every task is an undone row.

$$\operatorname{UChain}_{ts}(l) \iff \operatorname{Chain}_{\operatorname{Next}_{ts}}(l) \land \forall x \in l:\ x \in \operatorname{uids}(ts)$$
-/
def UChain (ts : List Task) (l : List String) : Prop := Chain (Next ts) l ∧ ∀ x ∈ l, x ∈ uids ts

/-- The undone rows that depend on `x` (their ids).

$$\operatorname{dependents}_{ts}(x) = [\, t.\mathit{id} : t \in \operatorname{undone}(ts),\ x \in t.\mathit{deps} \,]$$
-/
def dependents (ts : List Task) (x : String) : List String :=
  ((undone ts).filter fun t => t.deps.contains x).map (·.id)

/-- Membership in `dependents` is `Next`.

$$\forall ts, x, y:\quad y \in \operatorname{dependents}_{ts}(x) \iff \operatorname{Next}_{ts}(x, y)$$
-/
theorem mem_dependents {ts : List Task} {x y : String} : y ∈ dependents ts x ↔ Next ts x y := by
  simp only [dependents, undone, List.mem_map, List.mem_filter, Next, List.contains_iff_mem,
    Option.isNone_iff_eq_none]
  constructor
  · rintro ⟨t, ⟨⟨ht, he⟩, hx⟩, rfl⟩; exact ⟨t, ht, he, rfl, hx⟩
  · rintro ⟨t, ht, he, rfl, hx⟩; exact ⟨t, ⟨⟨ht, he⟩, hx⟩, rfl⟩

/-- The target of a `Next` edge is an undone row id.

$$\forall ts, x, y:\quad \operatorname{Next}_{ts}(x, y) \Rightarrow y \in \operatorname{uids}(ts)$$
-/
theorem next_uid {ts : List Task} {x y : String} (h : Next ts x y) : y ∈ uids ts := by
  obtain ⟨t, ht, he, rfl, _⟩ := h
  exact List.mem_map_of_mem (List.mem_filter.mpr ⟨ht, by simp [he]⟩)

/-- The longest list (the first one among the longest; `[]` for no lists).

$$\operatorname{best}([\,]) = [\,], \qquad \operatorname{best}(l :: L) = \begin{cases} \operatorname{best}(L) & |\operatorname{best}(L)| > |l| \\ l & \text{otherwise} \end{cases}$$
-/
def best : List (List String) → List String
  | [] => []
  | l :: ls => let b := best ls; if l.length < b.length then b else l

/-- `best` is empty or one of the lists.

$$\forall L:\quad \operatorname{best}(L) = [\,] \lor \operatorname{best}(L) \in L$$
-/
theorem best_cases : ∀ L : List (List String), best L = [] ∨ best L ∈ L
  | [] => .inl rfl
  | l :: ls => by
    simp only [best]
    split
    · rcases best_cases ls with h | h
      · exact .inl h
      · exact .inr (List.mem_cons_of_mem _ h)
    · exact .inr List.mem_cons_self

/-- `best` is at least as long as every list.

$$\forall L, l:\quad l \in L \Rightarrow |l| \le |\operatorname{best}(L)|$$
-/
theorem le_best : ∀ {L : List (List String)} {l : List String}, l ∈ L → l.length ≤ (best L).length
  | [], _, h => by cases h
  | l' :: ls, l, h => by
    simp only [best]
    rcases List.mem_cons.mp h with rfl | h
    · split <;> omega
    · have := le_best h
      split <;> omega

/-- Look up the list recorded for `x` in a table (`[x]` when absent).

$$\operatorname{look}(T, x) = l \text{ for the first } (x, l) \in T, \text{ else } [x]$$
-/
def look (tab : List (String × List String)) (x : String) : List String :=
  ((tab.find? (·.1 == x)).map (·.2)).getD [x]

/-- Looking up a listed key in a tabulated function gives the function's value.

$$\forall K, F, x:\quad x \in K \Rightarrow \operatorname{look}([\, (k, F(k)) : k \in K \,], x) = F(x)$$
-/
theorem look_map {K : List String} {F : String → List String} {x : String} (hx : x ∈ K) :
    look (K.map fun k => (k, F k)) x = F x := by
  induction K with
  | nil => cases hx
  | cons k ks ih =>
    simp only [look, List.map_cons, List.find?_cons] at ih ⊢
    by_cases hk : k = x
    · subst hk; simp
    · have hb : (k == x) = false := by simpa using hk
      simp only [hb]
      exact ih (by rcases List.mem_cons.mp hx with h | h; exact absurd h.symm hk; exact h)

/-- The longest-chain table with fuel `k`: for every undone task `x`, a longest chain of undone tasks
starting at `x` among those with at most `k + 1` tasks.

$$T_0 = [\, (x, [x]) : x \in \operatorname{uids} \,], \qquad T_{k+1} = \big[\, \big(x,\ x :: \operatorname{best}([\, \operatorname{look}(T_k, y) : y \in \operatorname{dependents}(x) \,])\big) : x \in \operatorname{uids} \,\big]$$
-/
def tab (ts : List Task) : Nat → List (String × List String)
  | 0 => (uids ts).map fun x => (x, [x])
  | k + 1 =>
    let p := tab ts k
    (uids ts).map fun x => (x, x :: best ((dependents ts x).map (look p)))

/-- The chain recorded for `x` at fuel `k`.

$$\operatorname{cpf}_{ts}(k, x) = \operatorname{look}(T_k, x)$$
-/
def cpf (ts : List Task) (k : Nat) (x : String) : List String := look (tab ts k) x

/-- The critical path: the longest recorded chain at fuel $|ts|$, in work order (each task depends on
the one before it); `[]` when every task is done.

$$\operatorname{criticalPath}(ts) = \operatorname{best}\big([\, \operatorname{cpf}_{ts}(|ts|, x) : x \in \operatorname{uids}(ts) \,]\big)$$
-/
def criticalPath (ts : List Task) : List String :=
  let p := tab ts ts.length
  best ((uids ts).map (look p))

/-- At fuel 0 the chain of an undone task is the task alone.

$$\forall ts, x:\quad x \in \operatorname{uids}(ts) \Rightarrow \operatorname{cpf}_{ts}(0, x) = [x]$$
-/
theorem cpf_zero {ts : List Task} {x : String} (hx : x ∈ uids ts) : cpf ts 0 x = [x] := by
  simp only [cpf, tab]
  exact look_map (F := fun k => [k]) hx

/-- One more unit of fuel extends by the best chain of a dependent.

$$\forall ts, k, x:\quad x \in \operatorname{uids}(ts) \Rightarrow \operatorname{cpf}_{ts}(k + 1, x) = x :: \operatorname{best}\big([\, \operatorname{cpf}_{ts}(k, y) : y \in \operatorname{dependents}_{ts}(x) \,]\big)$$
-/
theorem cpf_succ {ts : List Task} {k : Nat} {x : String} (hx : x ∈ uids ts) :
    cpf ts (k + 1) x = x :: best ((dependents ts x).map (cpf ts k)) := by
  simp only [cpf, tab]
  exact look_map (F := fun x => x :: best ((dependents ts x).map (look (tab ts k)))) hx

/-- Every recorded chain is a chain of undone tasks starting at its task.

$$\forall ts, k, x:\quad x \in \operatorname{uids}(ts) \Rightarrow \operatorname{UChain}_{ts}(\operatorname{cpf}_{ts}(k, x)) \land \exists r:\ \operatorname{cpf}_{ts}(k, x) = x :: r$$
-/
theorem cpf_chain {ts : List Task} : ∀ (k : Nat) (x : String), x ∈ uids ts →
    UChain ts (cpf ts k x) ∧ ∃ r, cpf ts k x = x :: r
  | 0, x, hx => by
    rw [cpf_zero hx]
    exact ⟨⟨.single x, by simpa using hx⟩, [], rfl⟩
  | k + 1, x, hx => by
    rw [cpf_succ hx]
    refine ⟨?_, _, rfl⟩
    rcases best_cases ((dependents ts x).map (cpf ts k)) with h | h
    · rw [h]; exact ⟨.single x, by simpa using hx⟩
    · obtain ⟨y, hy, hyl⟩ := List.mem_map.mp h
      have hn := mem_dependents.mp hy
      obtain ⟨⟨hc, hu⟩, r, hr⟩ := cpf_chain k y (next_uid hn)
      rw [← hyl, hr]
      rw [hr] at hc hu
      refine ⟨.cons hn hc, ?_⟩
      intro z hz
      rcases List.mem_cons.mp hz with rfl | hz
      · exact hx
      · exact hu z hz

/-- A recorded chain is at least as long as every chain of undone tasks from the same task that has at
most `k + 1` tasks.

$$\forall ts, k, x, l:\quad \operatorname{UChain}_{ts}(x :: l) \land |l| \le k \Rightarrow |x :: l| \le |\operatorname{cpf}_{ts}(k, x)|$$
-/
theorem cpf_long {ts : List Task} : ∀ (k : Nat) (x : String) (l : List String),
    UChain ts (x :: l) → l.length ≤ k → (x :: l).length ≤ (cpf ts k x).length
  | 0, x, l, hc, hl => by
    have hx : x ∈ uids ts := hc.2 x List.mem_cons_self
    rw [cpf_zero hx]
    cases l with
    | nil => simp
    | cons _ _ => simp at hl
  | k + 1, x, l, hc, hl => by
    have hx : x ∈ uids ts := hc.2 x List.mem_cons_self
    rw [cpf_succ hx]
    cases l with
    | nil => simp
    | cons y l' =>
      obtain ⟨hch, hu⟩ := hc
      cases hch with
      | cons hxy hyl =>
        have ih := cpf_long k y l' ⟨hyl, fun z hz => hu z (List.mem_cons_of_mem _ hz)⟩
          (by simp at hl; omega)
        have hb := le_best (List.mem_map_of_mem (f := cpf ts k) (mem_dependents.mpr hxy))
        simp only [List.length_cons] at ih hb ⊢
        omega

/-- **The critical path is a chain of undone tasks.**

$$\forall ts:\quad \operatorname{UChain}_{ts}(\operatorname{criticalPath}(ts))$$
-/
theorem criticalPath_chain (ts : List Task) : UChain ts (criticalPath ts) := by
  show UChain ts (best ((uids ts).map (cpf ts ts.length)))
  rcases best_cases ((uids ts).map (cpf ts ts.length)) with h | h
  · rw [h]; exact ⟨.nil, by simp⟩
  · obtain ⟨x, hx, hxl⟩ := List.mem_map.mp h
    rw [← hxl]
    exact (cpf_chain _ x hx).1

/-- The `Next` relation of an acyclic graph is acyclic.

$$\forall ts:\quad \operatorname{Acyclic}(ts) \Rightarrow \forall a:\ \neg \operatorname{Next}_{ts}^{+}(a, a)$$
-/
theorem next_acyclic {ts : List Task} (h : Acyclic ts) (a : String) :
    ¬ Relation.TransGen (Next ts) a a := by
  intro ha
  have hf : Relation.TransGen (fun x y => Dep ts y x) a a :=
    tg_mono (fun _ _ ⟨t, ht, _, hid, hd⟩ => ⟨t, ht, hid, hd⟩) ha
  exact h a (tg_flip hf)

/-- **The critical path is a longest chain**: on an acyclic graph no chain of undone tasks is longer.

$$\forall ts, l:\quad \operatorname{Acyclic}(ts) \land \operatorname{UChain}_{ts}(l) \Rightarrow |l| \le |\operatorname{criticalPath}(ts)|$$
-/
theorem criticalPath_longest {ts : List Task} (hac : Acyclic ts) {l : List String}
    (hl : UChain ts l) : l.length ≤ (criticalPath ts).length := by
  show l.length ≤ (best ((uids ts).map (cpf ts ts.length))).length
  cases l with
  | nil => simp
  | cons x r =>
    have hnd := chain_nodup (next_acyclic hac) hl.1
    have hlen : (x :: r).length ≤ (uids ts).length := List.Nodup.length_le_of_subset hnd hl.2
    have hu : (uids ts).length ≤ ts.length := by
      simp only [uids, ids, undone, List.length_map]; exact List.length_filter_le _ _
    have h1 := cpf_long ts.length x r hl (by simp at hlen; omega)
    have h2 := le_best (List.mem_map_of_mem (f := cpf ts ts.length) (hl.2 x List.mem_cons_self))
    omega

/-! ## Write and device conflicts -/

/-- The segments of a path or glob (split at `/`, empty segments dropped).

$$\operatorname{segs}(p) = [\, s : s \in \operatorname{split}_{/}(p),\ s \ne \varepsilon \,]$$
-/
def segs (p : String) : List String := (p.splitOn "/").filter (· != "")

/-- A glob segment is a wildcard segment when it contains `*`.

$$\operatorname{wild}(g) \iff \texttt{*} \in g$$
-/
def wild (g : String) : Bool := g.contains '*'

/-- Two glob segments may match a common path segment: equal, or one of them has a `*`.

$$\operatorname{segOv}(a, b) \iff a = b \lor \operatorname{wild}(a) \lor \operatorname{wild}(b)$$
-/
def segOv (a b : String) : Bool := a == b || wild a || wild b

/-- Two globs (as segment lists) may overlap: one ends first (a directory covers its subtree), one has
`**` at this position, or the segments may match and the rests may overlap.

$$\operatorname{globOv}(p, q) = \begin{cases} \mathrm{true} & p = [\,] \lor q = [\,] \\ a = \texttt{**} \lor b = \texttt{**} \lor (\operatorname{segOv}(a, b) \land \operatorname{globOv}(p', q')) & p = a :: p',\ q = b :: q' \end{cases}$$
-/
def globOv : List String → List String → Bool
  | [], _ => true
  | _ :: _, [] => true
  | a :: as, b :: bs => a == "**" || b == "**" || (segOv a b && globOv as bs)

/-- What a glob may match (an over-approximation of shell globs): a glob that ends covers the whole
subtree, `**` matches any rest, a `*`-segment matches any one segment, a literal segment only itself.

$$\operatorname{gm}([\,], s) = \top, \quad \operatorname{gm}(\texttt{**} :: g, s) = \top, \quad \operatorname{gm}(a :: g, [\,]) = \bot\ (a \ne \texttt{**}), \quad \operatorname{gm}(a :: g, c :: s) \iff (\operatorname{wild}(a) \lor a = c) \land \operatorname{gm}(g, s)\ (a \ne \texttt{**})$$
-/
def gm : List String → List String → Prop
  | [], _ => True
  | a :: g, s =>
    if a = "**" then True else
    match s with
    | [] => False
    | c :: s => (wild a = true ∨ a = c) ∧ gm g s

/-- **No reported overlap means no common path.** If `globOv` says two globs do not overlap, no path
is matched by both (under the over-approximating `gm`, hence under real glob matching).

$$\forall p, q:\quad \operatorname{globOv}(p, q) = \mathrm{false} \Rightarrow \neg \exists s:\ \operatorname{gm}(p, s) \land \operatorname{gm}(q, s)$$
-/
theorem globOv_sound : ∀ (p q : List String), globOv p q = false → ¬ ∃ s, gm p s ∧ gm q s
  | [], _, h => by simp [globOv] at h
  | _ :: _, [], h => by simp [globOv] at h
  | a :: as, b :: bs, h => by
    rintro ⟨s, hp, hq⟩
    simp only [globOv, Bool.or_eq_false_iff, Bool.and_eq_false_iff, beq_eq_false_iff_ne] at h
    obtain ⟨⟨ha, hb⟩, hr⟩ := h
    simp only [gm, ha, hb, ite_false] at hp hq
    cases s with
    | nil => exact hp
    | cons c s =>
      obtain ⟨hpa, hps⟩ := hp
      obtain ⟨hqb, hqs⟩ := hq
      rcases hr with hr | hr
      · simp only [segOv, Bool.or_eq_false_iff, beq_eq_false_iff_ne] at hr
        obtain ⟨⟨hne, hwa⟩, hwb⟩ := hr
        rcases hpa with h1 | h1
        · rw [h1] at hwa; cases hwa
        rcases hqb with h2 | h2
        · rw [h2] at hwb; cases hwb
        exact hne (h1.trans h2.symm)
      · exact globOv_sound as bs hr ⟨s, hps, hqs⟩

/-- On literal segment lists (no `*` anywhere) `globOv` is the segment-prefix relation of
`Fw.Sched.Admit.pconf`.

$$\forall p, q:\quad (\forall s \in p \mathbin{+\!\!+} q:\ \neg\operatorname{wild}(s) \land s \ne \texttt{**}) \Rightarrow \big(\operatorname{globOv}(p, q) \iff p \sqsubseteq q \lor q \sqsubseteq p\big)$$
-/
theorem globOv_literal : ∀ (p q : List String), (∀ s ∈ p ++ q, wild s = false ∧ s ≠ "**") →
    (globOv p q = true ↔ (p.isPrefixOf q || q.isPrefixOf p) = true)
  | [], _, _ => by simp [globOv, List.isPrefixOf]
  | _ :: _, [], _ => by simp [globOv, List.isPrefixOf]
  | a :: as, b :: bs, h => by
    have ha := h a (by simp)
    have hb := h b (by simp)
    have ih := globOv_literal as bs (fun s hs => h s (by
      simp only [List.mem_append, List.mem_cons] at hs ⊢; rcases hs with hs | hs <;> simp [hs]))
    simp only [globOv, segOv, List.isPrefixOf, ha.1, hb.1, beq_iff_eq, ha.2, hb.2, false_or,
      Bool.or_false, Bool.or_eq_true, Bool.and_eq_true]
    rw [ih]
    by_cases hab : a = b
    · subst hab; simp
    · have hba : ¬ b = a := fun h => hab h.symm
      simp [hab, hba]

/-- Two tasks conflict on writes: some write glob of one may overlap some write glob of the other.

$$\operatorname{wconf}(x, y) \iff \exists p \in W(x),\ q \in W(y):\ \operatorname{globOv}(\operatorname{segs}(p), \operatorname{segs}(q))$$
-/
def wconf (x y : Task) : Bool := x.writes.any fun p => y.writes.any fun q => globOv (segs p) (segs q)

/-- Two tasks share a device.

$$\operatorname{dconf}(x, y) \iff V(x) \cap V(y) \ne \emptyset$$
-/
def dconf (x y : Task) : Bool := x.devices.any fun v => y.devices.contains v

/-- Two tasks conflict when they conflict on writes or share a device.

$$\operatorname{conflict}(x, y) \iff \operatorname{wconf}(x, y) \lor \operatorname{dconf}(x, y)$$
-/
def conflict (x y : Task) : Bool := wconf x y || dconf x y

/-- `wconf` and `dconf` say exactly what they claim, as propositions.

$$\forall x, y:\quad \operatorname{conflict}(x, y) = \mathrm{false} \iff (\forall p \in W(x),\ q \in W(y):\ \neg\operatorname{globOv}(\operatorname{segs}(p), \operatorname{segs}(q))) \land (\forall v \in V(x):\ v \notin V(y))$$
-/
theorem conflict_false_iff (x y : Task) : conflict x y = false ↔
    (∀ p ∈ x.writes, ∀ q ∈ y.writes, globOv (segs p) (segs q) = false) ∧
    (∀ v ∈ x.devices, v ∉ y.devices) := by
  simp [conflict, wconf, dconf, List.any_eq_false]

#guard globOv (segs "lean/Fw/Plan/**") (segs "lean/Fw/Plan/Core.lean")
#guard globOv (segs "lean/Fw/Console*.lean") (segs "lean/Fw/Console.lean")
#guard !globOv (segs "lean/Fw/Plan/**") (segs "lean/Fw/Wire.lean")
#guard globOv (segs "lean/") (segs "lean/Fw/Wire.lean")
#guard !globOv (segs "apps/console-web/**") (segs "apps/console-api/**")

end Fw.Plan
