import Std.Data.HashMap
/-!
# Axiom reachability with one memo shared by many queries (task mathview-axreach)

The math view asks, for every exported declaration $c$, which axioms $c$ depends on. Lean's `collectAxioms`
starts every query from an empty cache, so the lint re-walked the same closure through Init and Lean core for each
of ~4,000 entries (research/notes/2026/10-18-land-speed.md, MEASURED 96 % of the lint). This module specifies the
shared-memo search the math view now runs, over an abstract graph: `succ c` lists the constants that `c` mentions
and `isAx c` says whether `c` is an axiom.

Cycles matter: an inductive type mentions its constructors and each constructor mentions the type. A depth-first
search that reaches a node still on its own stack sees only part of that node's set, so a naive shared memo would
store a partial set. The search here stores a node's set only when nothing it reached sits on the stack above it
(the low-link test `k ≤ low` of Tarjan's algorithm). `search_exact` proves such a stored set is exact,
`search_spec` proves the memo stays exact, and `query_exact` / `query_fresh` prove that each query, including the
first on an empty memo, returns exactly the reachable axioms, which is what the old per-call walk returned.
Recursion is bounded by fuel, so the functions are total; running out of fuel returns `none` and the caller falls
back to the old walk.
-/
namespace Fw.AxReach

variable {α : Type} [BEq α] [Hashable α]

/-! ## Semantics: paths, reachable axioms -/

/-- A path of exactly `n` edges from `c` to `e` in the graph `succ`.

$$\forall c:\ \mathrm{Path}_{\mathit{succ}}(0, c, c), \qquad \forall n\ c\ d\ e:\ d \in \mathit{succ}(c) \land
\mathrm{Path}_{\mathit{succ}}(n, d, e) \implies \mathrm{Path}_{\mathit{succ}}(n+1, c, e)$$
and nothing else is a path.
-/
inductive Path (succ : α → List α) : Nat → α → α → Prop
  | refl (c : α) : Path succ 0 c c
  | step {n : Nat} {c d e : α} : d ∈ succ c → Path succ n d e → Path succ (n + 1) c e

/-- The axioms reachable from `c`: nodes `a` with `isAx a` on the end of some path from `c`.

$$a \in R(c) \iff \mathit{isAx}(a) = \mathrm{true} \land \exists n \in \mathbb{N},\ \mathrm{Path}_{\mathit{succ}}(n, c, a)$$
-/
def AxR (succ : α → List α) (isAx : α → Bool) (c a : α) : Prop :=
  (∃ n, Path succ n c a) ∧ isAx a = true

omit [BEq α] [Hashable α] in
/-- T1, the fixpoint equation: the axioms reachable from `c` are `c` itself if it is an axiom, plus the axioms
reachable from its successors.

$$\forall\, \mathit{succ},\ \mathit{isAx},\ c,\ a:\quad a \in R(c) \iff \bigl(a = c \land \mathit{isAx}(c) =
\mathrm{true}\bigr) \lor \exists d \in \mathit{succ}(c),\ a \in R(d)$$
-/
theorem reach_fix (succ : α → List α) (isAx : α → Bool) (c a : α) :
    AxR succ isAx c a ↔ (a = c ∧ isAx c = true) ∨ ∃ d ∈ succ c, AxR succ isAx d a := by
  constructor
  · rintro ⟨⟨n, hp⟩, ha⟩
    cases hp with
    | refl => exact .inl ⟨rfl, ha⟩
    | step hd hp' => exact .inr ⟨_, hd, ⟨_, hp'⟩, ha⟩
  · rintro (⟨rfl, ha⟩ | ⟨d, hd, ⟨n, hp⟩, ha⟩)
    · exact ⟨⟨0, .refl _⟩, ha⟩
    · exact ⟨⟨n + 1, .step hd hp⟩, ha⟩

/-! ## The search -/

/-- Search state: `memo` maps finished nodes to their axiom lists, `prog` maps the nodes on the current search
stack to their depth.

$$\mathrm{St} = (\alpha \rightharpoonup \alpha^{*}) \times (\alpha \rightharpoonup \mathbb{N}), \qquad
s = (s.\mathit{memo},\ s.\mathit{prog})$$
-/
structure St (α : Type) [BEq α] [Hashable α] where
  memo : Std.HashMap α (List α)
  prog : Std.HashMap α Nat

/-- Add the elements of `s` to `acc`, skipping those already present.

$$\mathrm{union}(\mathit{acc}, [\,]) = \mathit{acc}, \qquad \mathrm{union}(\mathit{acc}, x :: s) =
\mathrm{union}(\mathrm{insert}(x, \mathit{acc}), s)$$
-/
def union (acc s : List α) : List α := s.foldl (fun a x => a.insert x) acc

/-- Run `g` on each node of `ds` in order, threading the state, adding each result to `acc` and taking the minimum
of the returned low-links; `none` as soon as one call returns `none`.

$$\mathrm{loop}_g([\,], A, l, s) = (A, l, s), \qquad \mathrm{loop}_g(d :: \mathit{ds}, A, l, s) =
\begin{cases} \bot & g(d, s) = \bot \\ \mathrm{loop}_g(\mathit{ds}, \mathrm{union}(A, S), \min(l, l'), s') &
g(d, s) = (S, l', s') \end{cases}$$
-/
def loop (g : α → St α → Option (List α × Nat × St α)) :
    List α → List α → Nat → St α → Option (List α × Nat × St α)
  | [], acc, low, st => some (acc, low, st)
  | d :: ds, acc, low, st =>
    match g d st with
    | none => none
    | some (s, l, st') => loop g ds (union acc s) (min low l) st'

/-- The memoised depth-first search from `c` at depth `k` with `fuel` levels of recursion left. It returns the
axiom list found, the low-link (the smallest depth of a stack node it reached, or `k`), and the new state. A memo hit
returns the stored list; a node on the stack at depth `j` returns `[]` with low-link `j`; otherwise `c` goes on the
stack, its successors are searched at depth `k + 1`, `c` leaves the stack, and its list is stored only when the
low-link is at least `k`.

$$\mathrm{search}(0, c, k, s) = \bot$$
$$\mathrm{search}(f+1, c, k, s) = \begin{cases}
(M, k, s) & s.\mathit{memo}(c) = M \\
([\,], j, s) & s.\mathit{memo}(c) = \bot \land s.\mathit{prog}(c) = j \\
\bot & s.\mathit{memo}(c) = \bot \land s.\mathit{prog}(c) = \bot \land
\mathrm{loop}_{g}(\mathit{succ}(c), A_0, k, s_1) = \bot \\
(A, l, s_2') & s.\mathit{memo}(c) = \bot \land s.\mathit{prog}(c) = \bot \land
\mathrm{loop}_{g}(\mathit{succ}(c), A_0, k, s_1) = (A, l, s_2)
\end{cases}$$
$$\text{with } g(d, t) = \mathrm{search}(f, d, k+1, t),\quad A_0 = \begin{cases} [c] & \mathit{isAx}(c) =
\mathrm{true} \\ [\,] & \mathit{isAx}(c) = \mathrm{false} \end{cases},\quad s_1 = (s.\mathit{memo},\
s.\mathit{prog}[c \mapsto k]),\quad s_2' = \bigl(\text{if } k \le l \text{ then } s_2.\mathit{memo}[c \mapsto A]
\text{ else } s_2.\mathit{memo},\ s_2.\mathit{prog} \setminus \{c\}\bigr)$$
-/
def search (succ : α → List α) (isAx : α → Bool) :
    Nat → α → Nat → St α → Option (List α × Nat × St α)
  | 0, _, _, _ => none
  | f + 1, c, k, st =>
    match st.memo[c]? with
    | some s => some (s, k, st)
    | none =>
      match st.prog[c]? with
      | some j => some ([], j, st)
      | none =>
        match loop (fun d t => search succ isAx f d (k + 1) t) (succ c) (if isAx c then [c] else []) k
            { st with prog := st.prog.insert c k } with
        | none => none
        | some (acc, low, st2) =>
          some (acc, low,
            { memo := if k ≤ low then st2.memo.insert c acc else st2.memo, prog := st2.prog.erase c })

/-- One query against a shared memo: search from `c` at depth 0 with an empty stack and return the axiom list and
the new memo (`none` when the fuel ran out).

$$\mathrm{query}(f, M, c) = \begin{cases} (A, s.\mathit{memo}) & \mathrm{search}(f, c, 0, (M, \emptyset)) =
(A, l, s) \\ \bot & \mathrm{search}(f, c, 0, (M, \emptyset)) = \bot \end{cases}$$
-/
def query (succ : α → List α) (isAx : α → Bool) (fuel : Nat) (memo : Std.HashMap α (List α)) (c : α) :
    Option (List α × Std.HashMap α (List α)) :=
  (search succ isAx fuel c 0 { memo, prog := ∅ }).map fun (s, _, st) => (s, st.memo)

/-! ## Invariants -/

/-- The memo invariant: every stored list holds exactly the axioms reachable from its key.

$$\mathrm{MemoOK}(M) \iff \forall c\ A,\ M(c) = A \implies \forall a,\ (a \in A \iff a \in R(c))$$
-/
def MemoOK (succ : α → List α) (isAx : α → Bool) (memo : Std.HashMap α (List α)) : Prop :=
  ∀ c s, memo[c]? = some s → ∀ a, a ∈ s ↔ AxR succ isAx c a

/-- Completeness up to the stack: every axiom at the end of an `n`-edge path from `c` is in `s`, or some stack node
`p` at depth `j ≥ low` reaches it in at most `n` edges.

$$\mathrm{Compl}(P, c, S, l) \iff \forall n\ a,\ \mathrm{Path}(n, c, a) \land \mathit{isAx}(a) = \mathrm{true}
\implies a \in S \lor \exists p\ j\ m,\ P(p) = j \land l \le j \land m \le n \land \mathrm{Path}(m, p, a)$$
-/
def Compl (succ : α → List α) (isAx : α → Bool) (prog : Std.HashMap α Nat) (c : α) (s : List α) (low : Nat) :
    Prop :=
  ∀ n a, Path succ n c a → isAx a = true →
    a ∈ s ∨ ∃ p j m, prog[p]? = some j ∧ low ≤ j ∧ m ≤ n ∧ Path succ m p a

section Proofs
variable [LawfulBEq α]

omit [Hashable α] in
/-- Membership in a union.

$$\forall A\ S\ a:\quad a \in \mathrm{union}(A, S) \iff a \in A \lor a \in S$$
-/
theorem mem_union (acc s : List α) (a : α) : a ∈ union acc s ↔ a ∈ acc ∨ a ∈ s := by
  induction s generalizing acc with
  | nil => simp [union]
  | cons x s ih =>
    simp only [union, List.foldl_cons] at ih ⊢
    rw [ih, List.mem_insert_iff, List.mem_cons]
    constructor
    · rintro ((h | h) | h) <;> simp_all
    · rintro (h | h | h) <;> simp_all

omit [LawfulBEq α] in
/-- Completeness is monotone: a larger list and a smaller low-link keep it.

$$\forall \mathit{succ}\ \mathit{isAx}\ P\ c\ S\ S'\ l\ l':\quad S \subseteq S' \land l' \le l \land \mathrm{Compl}(P, c, S, l) \implies
\mathrm{Compl}(P, c, S', l')$$
-/
theorem compl_mono {succ : α → List α} {isAx : α → Bool} {prog : Std.HashMap α Nat} {c : α} {s s' : List α}
    {low low' : Nat} (hs : ∀ a ∈ s, a ∈ s') (hl : low' ≤ low) (h : Compl succ isAx prog c s low) :
    Compl succ isAx prog c s' low' := by
  intro n a hp ha
  rcases h n a hp ha with h | ⟨p, j, m, hpj, hj, hm, hp'⟩
  · exact .inl (hs a h)
  · exact .inr ⟨p, j, m, hpj, Nat.le_trans hl hj, hm, hp'⟩

omit [LawfulBEq α] in
/-- Completeness depends on the stack map only through its lookups.

$$\forall \mathit{succ}\ \mathit{isAx}\ P\ P'\ c\ S\ l:\quad (\forall x,\ P(x) = P'(x)) \land \mathrm{Compl}(P, c, S, l) \implies
\mathrm{Compl}(P', c, S, l)$$
-/
theorem compl_congr {succ : α → List α} {isAx : α → Bool} {prog prog' : Std.HashMap α Nat} {c : α} {s : List α}
    {low : Nat} (he : ∀ x : α, prog[x]? = prog'[x]?) (h : Compl succ isAx prog c s low) :
    Compl succ isAx prog' c s low := by
  intro n a hp ha
  rcases h n a hp ha with h | ⟨p, j, m, hpj, hj, hm, hp'⟩
  · exact .inl h
  · exact .inr ⟨p, j, m, (he p) ▸ hpj, hj, hm, hp'⟩

/-- The loop invariant: if every call of `g` on a node of `ds` keeps the memo exact, restores the stack `P`, is sound
and complete up to `P`, then so is the whole loop, which also keeps `acc` and lowers the low-link.

$$\begin{aligned}&\forall \mathit{succ}\ \mathit{isAx}\ g\ P\ \mathit{ds}:\ \Bigl(\forall d \in \mathit{ds}\ \forall t\ S\ l\ t',\
\mathrm{MemoOK}(t.\mathit{memo}) \land t.\mathit{prog} \equiv P \land g(d, t) = (S, l, t') \implies
\mathrm{MemoOK}(t'.\mathit{memo}) \land t'.\mathit{prog} \equiv P \land S \subseteq R(d) \land
\mathrm{Compl}(P, d, S, l)\Bigr) \implies \\
&\forall A\ l\ s\ A'\ l'\ s',\ \mathrm{MemoOK}(s.\mathit{memo}) \land s.\mathit{prog} \equiv P \land
\mathrm{loop}_g(\mathit{ds}, A, l, s) = (A', l', s') \implies \mathrm{MemoOK}(s'.\mathit{memo}) \land
s'.\mathit{prog} \equiv P \land l' \le l \land A \subseteq A' \\
&\qquad \land \bigl(\forall a \in A',\ a \in A \lor \exists d \in \mathit{ds},\ a \in R(d)\bigr) \land
\forall d \in \mathit{ds},\ \mathrm{Compl}(P, d, A', l') \\
&\text{with } t \equiv P \iff \forall x,\ t(x) = P(x)\end{aligned}$$
-/
theorem loop_spec (succ : α → List α) (isAx : α → Bool) (g : α → St α → Option (List α × Nat × St α))
    (P : Std.HashMap α Nat) (ds : List α)
    (hg : ∀ d ∈ ds, ∀ (t : St α) s l (t' : St α), MemoOK succ isAx t.memo → (∀ x : α, t.prog[x]? = P[x]?) →
      g d t = some (s, l, t') →
      MemoOK succ isAx t'.memo ∧ (∀ x : α, t'.prog[x]? = P[x]?) ∧ (∀ a ∈ s, AxR succ isAx d a) ∧
        Compl succ isAx P d s l) :
    ∀ (acc : List α) (low : Nat) (st : St α) acc' low' (st' : St α), MemoOK succ isAx st.memo →
      (∀ x : α, st.prog[x]? = P[x]?) → loop g ds acc low st = some (acc', low', st') →
      MemoOK succ isAx st'.memo ∧ (∀ x : α, st'.prog[x]? = P[x]?) ∧ low' ≤ low ∧ (∀ a ∈ acc, a ∈ acc') ∧
        (∀ a ∈ acc', a ∈ acc ∨ ∃ d ∈ ds, AxR succ isAx d a) ∧ (∀ d ∈ ds, Compl succ isAx P d acc' low') := by
  induction ds with
  | nil =>
    intro acc low st acc' low' st' hm hp h
    simp only [loop, Option.some.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    exact ⟨hm, hp, Nat.le_refl _, fun _ h => h, fun a h => .inl h, by simp⟩
  | cons d ds ih =>
    intro acc low st acc' low' st' hm hp h
    simp only [loop] at h
    split at h
    · exact absurd h (by simp)
    · rename_i s l t heq
      obtain ⟨hm1, hp1, hs1, hc1⟩ := hg d (by simp) st s l t hm hp heq
      obtain ⟨hm2, hp2, hl2, hacc2, hsnd2, hc2⟩ :=
        ih (fun d' hd' => hg d' (List.mem_cons_of_mem _ hd')) _ _ _ _ _ _ hm1 hp1 h
      refine ⟨hm2, hp2, Nat.le_trans hl2 (Nat.min_le_left _ _), fun a ha => hacc2 a ((mem_union _ _ _).2 (.inl ha)),
        ?_, ?_⟩
      · intro a ha
        rcases hsnd2 a ha with h' | ⟨d', hd', hr⟩
        · rcases (mem_union _ _ _).1 h' with h'' | h''
          · exact .inl h''
          · exact .inr ⟨d, by simp, hs1 a h''⟩
        · exact .inr ⟨d', List.mem_cons_of_mem _ hd', hr⟩
      · intro d' hd'
        rcases List.mem_cons.1 hd' with rfl | hd'
        · exact compl_mono (fun a ha => hacc2 a ((mem_union _ _ _).2 (.inr ha)))
            (Nat.le_trans hl2 (Nat.min_le_right _ _)) hc1
        · exact hc2 d' hd'

/-- The search invariant (T2, general form): started with an exact memo and every stack depth below `k`, a search
that returns $(S, l, s')$ keeps the memo exact, restores the stack, returns $l \le k$, is sound, and is complete up
to the stack.

$$\begin{aligned}&\forall \mathit{succ}\ \mathit{isAx}\ f\ c\ k\ s\ S\ l\ s':\ \mathrm{MemoOK}(s.\mathit{memo}) \land \bigl(\forall p\ j,\
s.\mathit{prog}(p) = j \implies j < k\bigr) \land \mathrm{search}(f, c, k, s) = (S, l, s') \implies \\
&\quad \mathrm{MemoOK}(s'.\mathit{memo}) \land \bigl(\forall x,\ s'.\mathit{prog}(x) = s.\mathit{prog}(x)\bigr)
\land l \le k \land S \subseteq R(c) \land \mathrm{Compl}(s.\mathit{prog}, c, S, l)\end{aligned}$$
-/
theorem search_spec (succ : α → List α) (isAx : α → Bool) (f : Nat) :
    ∀ (c : α) (k : Nat) (st : St α) s low (st' : St α), MemoOK succ isAx st.memo →
      (∀ (p : α) (j : Nat), st.prog[p]? = some j → j < k) → search succ isAx f c k st = some (s, low, st') →
      MemoOK succ isAx st'.memo ∧ (∀ x : α, st'.prog[x]? = st.prog[x]?) ∧ low ≤ k ∧
        (∀ a ∈ s, AxR succ isAx c a) ∧ Compl succ isAx st.prog c s low := by
  induction f with
  | zero => intro c k st s low st' _ _ h; simp [search] at h
  | succ f ih =>
    intro c k st s low st' hm hb h
    simp only [search] at h
    split at h
    · -- memo hit
      rename_i s0 hmc
      simp only [Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      refine ⟨hm, fun _ => rfl, Nat.le_refl _, fun a ha => (hm c _ hmc a).1 ha, ?_⟩
      intro n a hp ha
      exact .inl ((hm c _ hmc a).2 ⟨⟨n, hp⟩, ha⟩)
    · rename_i hmc
      split at h
      · -- on the stack
        rename_i j hpc
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl, rfl⟩ := h
        refine ⟨hm, fun _ => rfl, Nat.le_of_lt (hb c _ hpc), by simp, ?_⟩
        intro n a hp _
        exact .inr ⟨c, _, n, hpc, Nat.le_refl _, Nat.le_refl _, hp⟩
      · rename_i hpc
        split at h
        · exact absurd h (by simp)
        · rename_i acc l st2 hloop
          simp only [Option.some.injEq, Prod.mk.injEq] at h
          obtain ⟨rfl, rfl, rfl⟩ := h
          -- the stack seen by the children
          let P := st.prog.insert c k
          have hP : ∀ x, P[x]? = if c == x then some k else st.prog[x]? := fun x =>
            Std.HashMap.getElem?_insert
          obtain ⟨hm2, hp2, hl2, hacc2, hsnd2, hc2⟩ :=
            loop_spec succ isAx _ P (succ c)
              (fun d _ t s' l' t' hmt hpt hg => by
                obtain ⟨h1, h2, h3, h4, h5⟩ := ih d (k + 1) t s' l' t' hmt (fun p j hpj => by
                  rw [hpt p, hP p] at hpj
                  split at hpj
                  · simp at hpj; omega
                  · exact Nat.lt_succ_of_lt (hb p j hpj)) hg
                exact ⟨h1, fun x => (h2 x).trans (hpt x), h4, compl_congr hpt h5⟩)
              _ _ { st with prog := P } _ _ _ hm (fun _ => rfl) hloop
          -- soundness
          have hsound : ∀ a ∈ acc, AxR succ isAx c a := by
            intro a ha
            rcases hsnd2 a ha with h' | ⟨d, hd, hr⟩
            · split at h'
              · rename_i hax
                simp at h'; subst h'
                exact ⟨⟨0, .refl _⟩, hax⟩
              · simp at h'
            · exact (reach_fix succ isAx c a).2 (.inr ⟨d, hd, hr⟩)
          -- completeness up to the outer stack, by strong induction on the path length
          have hcompl : Compl succ isAx st.prog c acc l := by
            intro n
            induction n using Nat.strongRecOn with
            | _ n ihn =>
              intro a hp ha
              cases hp with
              | refl =>
                exact .inl (hacc2 c (by simp [ha]))
              | @step n' _ d _ hd hp' =>
                rcases hc2 d hd n' a hp' ha with h' | ⟨p, j, m, hpj, hj, hm', hp''⟩
                · exact .inl h'
                · rw [hP p] at hpj
                  by_cases hcp : c = p
                  · subst hcp
                    rcases ihn m (by omega) a hp'' ha with h'' | ⟨p', j', m', h1, h2, h3, h4⟩
                    · exact .inl h''
                    · exact .inr ⟨p', j', m', h1, h2, by omega, h4⟩
                  · have : (c == p) = false := by simpa using hcp
                    rw [this] at hpj
                    exact .inr ⟨p, j, m, hpj, hj, by omega, hp''⟩
          refine ⟨?_, ?_, hl2, hsound, hcompl⟩
          · -- the memo stays exact
            split
            · rename_i hkl
              intro x s' hx a
              rw [Std.HashMap.getElem?_insert] at hx
              split at hx
              · rename_i hcx
                simp at hx hcx; subst hcx; subst hx
                refine ⟨hsound a, fun ⟨⟨n, hp⟩, ha⟩ => ?_⟩
                rcases hcompl n a hp ha with h' | ⟨p, j, m, hpj, hj, _, _⟩
                · exact h'
                · have := hb p j hpj; omega
              · exact hm2 x s' hx a
            · exact hm2
          · -- the stack is restored
            intro x
            simp only
            rw [Std.HashMap.getElem?_erase, hp2 x, hP x]
            split
            · rename_i hcx
              simp at hcx; subst hcx; simpa using hpc
            · rfl

/-- T2: a search started with an exact memo and every stack depth below `k` that returns a low-link `l ≥ k` returns
exactly the axioms reachable from `c`, and leaves an exact memo.

$$\forall \mathit{succ}\ \mathit{isAx}\ f\ c\ k\ s\ S\ l\ s':\ \mathrm{MemoOK}(s.\mathit{memo}) \land \bigl(\forall p\ j,\ s.\mathit{prog}(p) = j
\implies j < k\bigr) \land \mathrm{search}(f, c, k, s) = (S, l, s') \land k \le l \implies \bigl(\forall a,\ a \in S
\iff a \in R(c)\bigr) \land \mathrm{MemoOK}(s'.\mathit{memo})$$
-/
theorem search_exact (succ : α → List α) (isAx : α → Bool) (f : Nat) (c : α) (k : Nat) (st : St α) (s : List α)
    (low : Nat) (st' : St α) (hm : MemoOK succ isAx st.memo) (hb : ∀ (p : α) (j : Nat), st.prog[p]? = some j → j < k)
    (h : search succ isAx f c k st = some (s, low, st')) (hk : k ≤ low) :
    (∀ a, a ∈ s ↔ AxR succ isAx c a) ∧ MemoOK succ isAx st'.memo := by
  obtain ⟨hm', _, _, hsound, hcompl⟩ := search_spec succ isAx f c k st s low st' hm hb h
  refine ⟨fun a => ⟨hsound a, fun ⟨⟨n, hp⟩, ha⟩ => ?_⟩, hm'⟩
  rcases hcompl n a hp ha with h' | ⟨p, j, m, hpj, hj, _, _⟩
  · exact h'
  · have := hb p j hpj; omega

/-- T3: a query against an exact memo returns exactly the axioms reachable from `c` and an exact memo, so the
shared-memo result equals a fresh per-query walk.

$$\forall \mathit{succ}\ \mathit{isAx}\ f\ M\ c\ s\ M':\ \mathrm{MemoOK}(M) \land \mathrm{query}(f, M, c) = (s, M')
\implies \bigl(\forall a,\ a \in s \iff a \in R(c)\bigr) \land \mathrm{MemoOK}(M')$$
-/
theorem query_exact (succ : α → List α) (isAx : α → Bool) (f : Nat) (memo : Std.HashMap α (List α)) (c : α)
    (s : List α) (memo' : Std.HashMap α (List α)) (hm : MemoOK succ isAx memo)
    (h : query succ isAx f memo c = some (s, memo')) :
    (∀ a, a ∈ s ↔ AxR succ isAx c a) ∧ MemoOK succ isAx memo' := by
  simp only [query, Option.map_eq_some_iff] at h
  obtain ⟨⟨s0, low, st'⟩, hs, he⟩ := h
  simp only [Prod.mk.injEq] at he
  obtain ⟨rfl, rfl⟩ := he
  exact search_exact succ isAx f c 0 _ _ low st' hm (fun p j hpj => by simp at hpj) hs (Nat.zero_le _)

/-- The empty memo is exact.

$$\forall\, \mathit{succ},\ \mathit{isAx}:\quad \mathrm{MemoOK}(\emptyset)$$
-/
theorem memoOK_empty (succ : α → List α) (isAx : α → Bool) : MemoOK succ isAx (∅ : Std.HashMap α (List α)) := by
  intro c s h; simp at h

/-- T3 for the first query: on an empty memo the root of the search returns exactly the axioms reachable from `c`,
the result of the old per-call walk.

$$\forall \mathit{succ}\ \mathit{isAx}\ f\ c\ s\ M':\ \mathrm{query}(f, \emptyset, c) = (s, M') \implies \forall a,\
a \in s \iff a \in R(c)$$
-/
theorem query_fresh (succ : α → List α) (isAx : α → Bool) (f : Nat) (c : α) (s : List α)
    (memo' : Std.HashMap α (List α)) (h : query succ isAx f ∅ c = some (s, memo')) :
    ∀ a, a ∈ s ↔ AxR succ isAx c a :=
  (query_exact succ isAx f ∅ c s memo' (memoOK_empty succ isAx) h).1

end Proofs

/-! ## Example: a cyclic graph where a naive shared memo goes wrong

Edges $0 \to 1$, $1 \to 0$, $1 \to 2$, $0 \to 3$; axioms $2$ and $3$. From the root $0$, node $1$ sees $0$ still on
the stack and finds only $\{2\}$, although $R(1) = \{2, 3\}$. A naive memo would store $1 \mapsto \{2\}$; this search
does not store $1$ (its low-link $0$ is below its depth $1$), so the next query from $1$ walks again and is exact. -/

/-- The example graph's successor lists.

$$\mathit{succ}(0) = [1, 3],\ \mathit{succ}(1) = [0, 2],\ \mathit{succ}(n) = [\,]\ (n \ge 2)$$
-/
def exSucc : Nat → List Nat
  | 0 => [1, 3] | 1 => [0, 2] | _ => []

/-- The example graph's axioms.

$$\mathit{isAx}(n) \iff n = 2 \lor n = 3$$
-/
def exIsAx (n : Nat) : Bool := n == 2 || n == 3

/-- Run queries in order on one shared memo, returning each result (sorted) and the memo's keys (sorted).

$$\mathrm{exRun}(\mathit{cs}) = \bigl([\mathrm{sort}(A_i)]_i,\ \mathrm{sort}(\mathrm{keys}(M_{|\mathit{cs}|}))\bigr),\qquad
(A_i, M_{i+1}) = \mathrm{query}(10, M_i, \mathit{cs}_i),\ M_0 = \emptyset$$
(a query that runs out of fuel contributes $[\,]$ and keeps the memo)
-/
def exRun (cs : List Nat) : List (List Nat) × List Nat :=
  let (out, memo) := cs.foldl (fun (out, memo) c =>
    match query exSucc exIsAx 10 memo c with
    | some (s, m') => (out ++ [s.mergeSort], m')
    | none => (out ++ [[]], memo)) (([] : List (List Nat)), (∅ : Std.HashMap Nat (List Nat)))
  (out, memo.keys.mergeSort)

#guard (exRun [0, 1, 2, 3]).1 == [[2, 3], [2, 3], [2], [3]]
-- after the root query only the nodes whose search closed stay memoised: 1 sits in a cycle with 0 and is not stored
#guard (exRun [0]).2 == [0, 2, 3]
#guard (exRun [1, 0]).1 == [[2, 3], [2, 3]]
-- out of fuel: `none`
#guard (query exSucc exIsAx 1 ∅ 0).isNone

end Fw.AxReach
