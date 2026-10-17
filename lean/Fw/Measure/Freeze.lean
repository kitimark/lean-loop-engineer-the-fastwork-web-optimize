import Fw.Measure.Classes
/-!
# The freeze rule: one signed class table from several CI workflow runs (task freeze-lean)

A CI workflow run of the counts lane classifies its jobs (separate VMs) with `classifyAllU` and
uploads a *class table*: one entry per count type with its class, the observed maxima `k`, `t` and,
for pixel-area types, the gap bound `tBound`. The frozen (signed) table of a profile combines the
tables of at least three workflow runs that used one pinned container image:

* the frozen class of a type is its **worst** class over the runs
  (`deterministic` < `stable` < `quarantined`);
* a type missing from any run's table counts as `quarantined` in that run;
* `k` and `t` are the maxima over the runs, `tBound` the smallest recorded bound;
* fewer than 3 runs, a repeated run id, a run without an image digest, or two different image
  digests are refused.

Proved: the worst class depends only on the set of tables (`worstOf_congr`), so it is
order-independent (`worstOf_perm`) and idempotent (`worstOf_append_self`, `worstOf_replicate`,
`worstOf_refreeze`); adding a run never improves a class (`worstOf_mono`, `worstOf_cons`); it is
the least upper bound of the runs' classes (`le_worstOf`, `worstOf_attained`); a missing type is
quarantined (`worstOf_missing`); on a single run it is the class `classifyU` gives
(`worstOf_single_classify`); and `freeze` answers exactly when the run conditions hold
(`freeze_ok_iff`).
-/
namespace Fw.Measure.Freeze
open Fw.Measure

/-! ## Class levels and the worst of two -/

/-- The three class levels of a frozen table (a `stable` class without its parameters).

$$\mathrm{Level} = \{\mathrm{det}, \mathrm{stable}, \mathrm{quar}\}$$
-/
inductive Level where
  | det
  | stable
  | quar
deriving Repr, DecidableEq

/-- The strictness rank of a level.

$$\operatorname{rank}(\mathrm{det}) = 0,\quad \operatorname{rank}(\mathrm{stable}) = 1,\quad \operatorname{rank}(\mathrm{quar}) = 2$$
-/
def Level.rank : Level → Nat
  | .det => 0
  | .stable => 1
  | .quar => 2

/-- The worse of two levels (the one of larger rank).

$$a \curlyvee b = \begin{cases} b & \operatorname{rank}(a) \le \operatorname{rank}(b) \\ a & \text{otherwise} \end{cases}$$
-/
def Level.worse (a b : Level) : Level := if a.rank ≤ b.rank then b else a

#guard Level.worse .det .stable == .stable && Level.worse .quar .stable == .quar && Level.worse .det .det == .det

/-- The level of a class.

$$\operatorname{lvl}(\mathrm{det}) = \mathrm{det},\quad \operatorname{lvl}(\mathrm{stable}(k, t)) = \mathrm{stable},\quad \operatorname{lvl}(\mathrm{quar}) = \mathrm{quar}$$
-/
def levelOf : Class → Level
  | .deterministic => .det
  | .stable _ _ => .stable
  | .quarantined => .quar

/-- The rank determines the level.

$$\forall a, b \in \mathrm{Level}:\ \operatorname{rank}(a) = \operatorname{rank}(b) \;\Rightarrow\; a = b$$
-/
theorem Level.rank_inj : ∀ {a b : Level}, a.rank = b.rank → a = b := by
  intro a b h; cases a <;> cases b <;> simp_all [Level.rank]

/-- Every rank is at most 2.

$$\forall a \in \mathrm{Level}:\ \operatorname{rank}(a) \le 2$$
-/
theorem Level.rank_le_two (a : Level) : a.rank ≤ 2 := by cases a <;> simp [Level.rank]

/-- The worse of two levels has the larger rank.

$$\forall a, b \in \mathrm{Level}:\ \operatorname{rank}(a \curlyvee b) = \max(\operatorname{rank}(a), \operatorname{rank}(b))$$
-/
theorem Level.rank_worse (a b : Level) : (a.worse b).rank = max a.rank b.rank := by
  cases a <;> cases b <;> rfl

/-- The class order is preserved by the levels: a class at most as strict as another has a level of
at most the same rank.

$$\forall c, c' \in \mathrm{Class}:\ \operatorname{le}(c, c') \;\Rightarrow\; \operatorname{rank}(\operatorname{lvl}(c)) \le \operatorname{rank}(\operatorname{lvl}(c'))$$
-/
theorem levelOf_mono : ∀ {c c' : Class}, c.le c' = true → (levelOf c).rank ≤ (levelOf c').rank := by
  intro c c' h
  cases c <;> cases c' <;> simp_all [Class.le, levelOf, Level.rank]

/-! ## Per-run class tables -/

/-- One type's entry in one run's class table: level, observed maxima `k`, `t`, and the gap bound of
a pixel-area type (`none` for count types).

$$\mathrm{Entry} = \mathrm{Level} \times \mathbb{N} \times \mathbb{N} \times (\mathbb{N} \cup \{\bot\})$$
-/
structure Entry where
  cls : Level
  k : Nat
  t : Nat
  tBound : Option Nat
deriving Repr, DecidableEq

/-- A run's class table: (type, entry) pairs; a lookup takes the first pair of a type.

$$\mathrm{Table} = (\Sigma^{*} \times \mathrm{Entry})^{*}$$
-/
abbrev Table := List (String × Entry)

/-- The entry of a type in a table: the first pair with that type, `none` if the type is missing.

$$\operatorname{entry}(T, \tau) = \begin{cases} e & (\tau, e) \text{ is the first pair of } T \text{ with type } \tau \\ \bot & \text{no pair of } T \text{ has type } \tau \end{cases}$$
-/
def entry? (tb : Table) (ty : String) : Option Entry := (tb.find? (·.1 == ty)).map (·.2)

/-- The level of a type in one run: its entry's level, `quar` if the type is missing.

$$\operatorname{lvl}_T(\tau) = \begin{cases} e.\mathrm{cls} & \operatorname{entry}(T, \tau) = e \\ \mathrm{quar} & \operatorname{entry}(T, \tau) = \bot \end{cases}$$
-/
def levelIn (tb : Table) (ty : String) : Level :=
  match entry? tb ty with
  | some e => e.cls
  | none => .quar

/-- **The worst level** of a type over a list of run tables (`det` for no tables).

$$\operatorname{worst}([T_1, \dots, T_n], \tau) = \operatorname{lvl}_{T_1}(\tau) \curlyvee \cdots \curlyvee \operatorname{lvl}_{T_n}(\tau) \curlyvee \mathrm{det}$$
-/
def worstOf (tbs : List Table) (ty : String) : Level :=
  tbs.foldr (fun tb acc => (levelIn tb ty).worse acc) .det

/-- The types of a list of run tables: every type with an entry in some table, sorted, no
duplicates.

$$\operatorname{types}([T_1, \dots, T_n]) = \operatorname{sort}\{\, \tau \mid \exists i, e:\ (\tau, e) \in T_i \,\}$$
-/
def typesOf (tbs : List Table) : List String :=
  keysOf (tbs.map fun tb => tb.map fun p => (p.1, (0 : Int)))

/-- The largest `k` of a type over the runs (a missing type contributes 0).

$$k(\mathcal{T}, \tau) = \max{}^{*}[\, \operatorname{entry}(T, \tau).k \text{ (0 if } \bot) \,]_{T \in \mathcal{T}},\quad \max{}^{*}[\,] = 0,\ \max{}^{*}(x :: L) = \max(x, \max{}^{*} L)$$
-/
def kOf (tbs : List Table) (ty : String) : Nat := maxOf (tbs.map fun tb => ((entry? tb ty).map (·.k)).getD 0)

/-- The largest `t` of a type over the runs (a missing type contributes 0).

$$t(\mathcal{T}, \tau) = \max{}^{*}[\, \operatorname{entry}(T, \tau).t \text{ (0 if } \bot) \,]_{T \in \mathcal{T}}$$
-/
def tOf (tbs : List Table) (ty : String) : Nat := maxOf (tbs.map fun tb => ((entry? tb ty).map (·.t)).getD 0)

/-- The smallest recorded gap bound of a type over the runs (`none` if no run records one).

$$b(\mathcal{T}, \tau) = \min\{\, \operatorname{entry}(T, \tau).\mathrm{tBound} \mid T \in \mathcal{T},\ \operatorname{entry}(T, \tau) \ne \bot,\ \operatorname{entry}(T, \tau).\mathrm{tBound} \ne \bot \,\}\ (\bot \text{ if the set is empty})$$
-/
def tBoundOf (tbs : List Table) (ty : String) : Option Nat :=
  (tbs.filterMap fun tb => (entry? tb ty).bind (·.tBound)).min?

/-- One row of the frozen table: type, worst level, maxima `k`, `t`, the per-run levels in run
order (`none` where the type is missing) and the smallest gap bound.

$$\mathrm{FRow} = \Sigma^{*} \times \mathrm{Level} \times \mathbb{N} \times \mathbb{N} \times (\mathrm{Level} \cup \{\bot\})^{*} \times (\mathbb{N} \cup \{\bot\})$$
-/
structure FRow where
  type : String
  cls : Level
  k : Nat
  t : Nat
  perRun : List (Option Level)
  tBound : Option Nat
deriving Repr, DecidableEq

/-- **The frozen table** of a list of run tables: one row per type, in the order of `typesOf`.

$$\operatorname{frozen}(\mathcal{T}) = \big[\,(\tau,\ \operatorname{worst}(\mathcal{T}, \tau),\ k(\mathcal{T}, \tau),\ t(\mathcal{T}, \tau),\ [\operatorname{entry}(T, \tau).\mathrm{cls}\ (\bot \text{ if } \operatorname{entry}(T, \tau) = \bot)]_{T \in \mathcal{T}},\ b(\mathcal{T}, \tau))\,\big]_{\tau \in \operatorname{types}(\mathcal{T})}$$
-/
def freezeCore (tbs : List Table) : List FRow :=
  (typesOf tbs).map fun ty =>
    { type := ty, cls := worstOf tbs ty, k := kOf tbs ty, t := tOf tbs ty,
      perRun := tbs.map fun tb => (entry? tb ty).map (·.cls), tBound := tBoundOf tbs ty }

/-- A frozen table read back as a class table.

$$\operatorname{table}(F) = [\,(r.\tau, (r.\mathrm{cls}, r.k, r.t, r.\mathrm{tBound}))\,]_{r \in F}$$
-/
def toTable (rows : List FRow) : Table := rows.map fun r => (r.type, ⟨r.cls, r.k, r.t, r.tBound⟩)

/-- The number of rows of each level: (det, stable, quar).

$$\operatorname{tally}(L) = \big(|[\,x \in L \mid x = \mathrm{det}\,]|,\ |[\,x \in L \mid x = \mathrm{stable}\,]|,\ |[\,x \in L \mid x = \mathrm{quar}\,]|\big)$$
-/
def tally (ls : List Level) : Nat × Nat × Nat :=
  ((ls.filter (· == .det)).length, (ls.filter (· == .stable)).length, (ls.filter (· == .quar)).length)

-- worked examples: a, b in both runs; c only in run 2 (so quarantined)
private def e (c : Level) (k t : Nat) (b : Option Nat := none) : Entry := ⟨c, k, t, b⟩
#guard worstOf [[("a", e .det 0 0)], [("a", e .stable 2 3)]] "a" == .stable
#guard worstOf [[("a", e .stable 2 3)], [("a", e .det 0 0)], [("a", e .det 0 0)]] "a" == .stable
#guard worstOf [[("a", e .det 0 0)], [("b", e .det 0 0)]] "a" == .quar
#guard worstOf [] "a" == .det
#guard typesOf [[("b", e .det 0 0), ("a", e .det 0 0)], [("c", e .det 0 0)]] == ["a", "b", "c"]
#guard freezeCore [[("a", e .stable 2 3 (some 9))], [("a", e .det 0 0 (some 7)), ("c", e .det 0 0)]] ==
  [⟨"a", .stable, 2, 3, [some .stable, some .det], some 7⟩, ⟨"c", .quar, 0, 0, [none, some .det], none⟩]
#guard tally [.det, .quar, .det, .stable] == (2, 1, 1)

/-! ## The worst level is a maximum over the set of tables -/

/-- The ranks of a type's levels over the runs.

$$\operatorname{ranks}(\mathcal{T}, \tau) = [\operatorname{rank}(\operatorname{lvl}_T(\tau))]_{T \in \mathcal{T}}$$
-/
def ranks (tbs : List Table) (ty : String) : List Nat := tbs.map fun tb => (levelIn tb ty).rank

/-- The rank of the worst level is the largest rank over the runs.

$$\forall \mathcal{T}, \tau:\ \operatorname{rank}(\operatorname{worst}(\mathcal{T}, \tau)) = \max{}^{*}(\operatorname{ranks}(\mathcal{T}, \tau))\quad (\text{so } \mathcal{T} = [\,] \text{ gives rank } 0 = \operatorname{rank}(\mathrm{det}))$$
-/
theorem rank_worstOf (tbs : List Table) (ty : String) : (worstOf tbs ty).rank = maxOf (ranks tbs ty) := by
  induction tbs with
  | nil => rfl
  | cons tb rest ih =>
    simp only [worstOf, List.foldr_cons, ranks, List.map_cons, maxOf] at *
    rw [Level.rank_worse, ih]

/-- The maximum depends only on the members.

$$\forall L, L' \in \mathbb{N}^{*}:\ (\forall x:\ x \in L \iff x \in L') \;\Rightarrow\; \max{}^{*}(L) = \max{}^{*}(L')$$
-/
theorem maxOf_congr {l l' : List Nat} (h : ∀ x, x ∈ l ↔ x ∈ l') : maxOf l = maxOf l' :=
  Nat.le_antisymm (maxOf_le fun x hx => le_maxOf ((h x).1 hx)) (maxOf_le fun x hx => le_maxOf ((h x).2 hx))

/-- **Set dependence.** Two lists with the same tables give every type the same worst level.

$$\forall \mathcal{T}, \mathcal{T}', \tau:\ (\forall T:\ T \in \mathcal{T} \iff T \in \mathcal{T}') \;\Rightarrow\; \operatorname{worst}(\mathcal{T}, \tau) = \operatorname{worst}(\mathcal{T}', \tau)$$
-/
theorem worstOf_congr {tbs tbs' : List Table} (h : ∀ tb, tb ∈ tbs ↔ tb ∈ tbs') (ty : String) :
    worstOf tbs ty = worstOf tbs' ty := by
  apply Level.rank_inj
  rw [rank_worstOf, rank_worstOf]
  apply maxOf_congr
  intro x
  simp only [ranks, List.mem_map]
  exact ⟨fun ⟨tb, hm, hx⟩ => ⟨tb, (h tb).1 hm, hx⟩, fun ⟨tb, hm, hx⟩ => ⟨tb, (h tb).2 hm, hx⟩⟩

/-- **Order independence.** Reordering the runs leaves every worst level unchanged.

$$\forall \mathcal{T}, \mathcal{T}', \tau:\ \mathcal{T} \sim \mathcal{T}' \text{ (a permutation)} \;\Rightarrow\; \operatorname{worst}(\mathcal{T}, \tau) = \operatorname{worst}(\mathcal{T}', \tau)$$
-/
theorem worstOf_perm {tbs tbs' : List Table} (h : tbs.Perm tbs') (ty : String) :
    worstOf tbs ty = worstOf tbs' ty :=
  worstOf_congr (fun _ => h.mem_iff) ty

/-- **Idempotence.** Listing every run twice changes nothing.

$$\forall \mathcal{T}, \tau:\ \operatorname{worst}(\mathcal{T} \mathbin{+\!\!+} \mathcal{T}, \tau) = \operatorname{worst}(\mathcal{T}, \tau)$$
-/
theorem worstOf_append_self (tbs : List Table) (ty : String) : worstOf (tbs ++ tbs) ty = worstOf tbs ty :=
  worstOf_congr (fun _ => by simp) ty

/-- **One run.** The worst level over a single table is that table's level.

$$\forall T, \tau:\ \operatorname{worst}([T], \tau) = \operatorname{lvl}_T(\tau)$$
-/
theorem worstOf_single (tb : Table) (ty : String) : worstOf [tb] ty = levelIn tb ty := by
  simp only [worstOf, List.foldr_cons, List.foldr_nil, Level.worse]
  cases levelIn tb ty <;> rfl

/-- **Idempotence on copies.** Freezing $n + 1$ copies of one table gives that table's levels.

$$\forall T, n, \tau:\ \operatorname{worst}(\underbrace{[T, \dots, T]}_{n+1}, \tau) = \operatorname{lvl}_T(\tau)$$
-/
theorem worstOf_replicate (tb : Table) (n : Nat) (ty : String) :
    worstOf (List.replicate (n + 1) tb) ty = levelIn tb ty := by
  rw [worstOf_congr (tbs' := [tb]) (fun x => by simp [List.mem_replicate]), worstOf_single]

/-- **Upper bound.** No run's level is worse than the worst level.

$$\forall \mathcal{T}, T, \tau:\ T \in \mathcal{T} \;\Rightarrow\; \operatorname{rank}(\operatorname{lvl}_T(\tau)) \le \operatorname{rank}(\operatorname{worst}(\mathcal{T}, \tau))$$
-/
theorem le_worstOf {tbs : List Table} {tb : Table} (h : tb ∈ tbs) (ty : String) :
    (levelIn tb ty).rank ≤ (worstOf tbs ty).rank := by
  rw [rank_worstOf]; exact le_maxOf (List.mem_map_of_mem h)

/-- **Attained.** Over a non-empty list of runs, the worst level is the level of some run.

$$\forall \mathcal{T}, \tau:\ \mathcal{T} \ne [\,] \;\Rightarrow\; \exists T \in \mathcal{T}:\ \operatorname{worst}(\mathcal{T}, \tau) = \operatorname{lvl}_T(\tau)$$
-/
theorem worstOf_attained : ∀ {tbs : List Table}, tbs ≠ [] → ∀ ty, ∃ tb ∈ tbs, worstOf tbs ty = levelIn tb ty
  | [], h, _ => absurd rfl h
  | [tb], _, ty => ⟨tb, by simp, worstOf_single tb ty⟩
  | tb :: tb' :: rest, _, ty => by
    obtain ⟨u, hu, he⟩ := worstOf_attained (tbs := tb' :: rest) (by simp) ty
    have hw : worstOf (tb :: tb' :: rest) ty = (levelIn tb ty).worse (worstOf (tb' :: rest) ty) := rfl
    rw [hw, he]
    unfold Level.worse
    split
    · exact ⟨u, List.mem_cons_of_mem _ hu, rfl⟩
    · exact ⟨tb, by simp, rfl⟩

/-- **Monotone.** A superset of runs never has a better worst level.

$$\forall \mathcal{T}, \mathcal{T}', \tau:\ (\forall T \in \mathcal{T}:\ T \in \mathcal{T}') \;\Rightarrow\; \operatorname{rank}(\operatorname{worst}(\mathcal{T}, \tau)) \le \operatorname{rank}(\operatorname{worst}(\mathcal{T}', \tau))$$
-/
theorem worstOf_mono {tbs tbs' : List Table} (h : ∀ tb ∈ tbs, tb ∈ tbs') (ty : String) :
    (worstOf tbs ty).rank ≤ (worstOf tbs' ty).rank := by
  rw [rank_worstOf, rank_worstOf]
  apply maxOf_le
  intro x hx
  simp only [ranks, List.mem_map] at hx
  obtain ⟨tb, hm, rfl⟩ := hx
  exact le_maxOf (List.mem_map_of_mem (h tb hm))

/-- **Adding a run never improves a class**, wherever the run is added.

$$\forall \mathcal{T}, \mathcal{U}, T, \tau:\ \operatorname{rank}(\operatorname{worst}(\mathcal{T} \mathbin{+\!\!+} \mathcal{U}, \tau)) \le \operatorname{rank}(\operatorname{worst}(\mathcal{T} \mathbin{+\!\!+} T :: \mathcal{U}, \tau))$$
-/
theorem worstOf_cons (tbs us : List Table) (tb : Table) (ty : String) :
    (worstOf (tbs ++ us) ty).rank ≤ (worstOf (tbs ++ tb :: us) ty).rank :=
  worstOf_mono (fun x hx => by
    simp only [List.mem_append, List.mem_cons] at hx ⊢
    rcases hx with h | h <;> simp [h]) ty

/-- **A type missing from a run is quarantined.**

$$\forall \mathcal{T}, T, \tau:\ T \in \mathcal{T} \land \operatorname{entry}(T, \tau) = \bot \;\Rightarrow\; \operatorname{worst}(\mathcal{T}, \tau) = \mathrm{quar}$$
-/
theorem worstOf_missing {tbs : List Table} {tb : Table} {ty : String} (hm : tb ∈ tbs) (he : entry? tb ty = none) :
    worstOf tbs ty = .quar := by
  have hq : levelIn tb ty = .quar := by simp [levelIn, he]
  have h1 := le_worstOf hm ty
  rw [hq] at h1
  change 2 ≤ _ at h1
  have h2 := Level.rank_le_two (worstOf tbs ty)
  apply Level.rank_inj
  change _ = 2
  omega

/-! ## Types and lookups -/

/-- Membership in the keys of count lists.

$$\forall x, \mathcal{C}:\ x \in \operatorname{keys}(\mathcal{C}) \iff \exists C \in \mathcal{C}, v:\ (x, v) \in C$$
-/
theorem mem_keysOf (x : String) : ∀ css : List Counts, x ∈ keysOf css ↔ ∃ cs ∈ css, ∃ v, (x, v) ∈ cs
  | [] => by simp [keysOf]
  | cs :: css => by
    have hf : ∀ l : Counts, x ∈ l.foldr (fun p acc => insKey p.1 acc) (keysOf css) ↔
        (∃ v, (x, v) ∈ l) ∨ x ∈ keysOf css := by
      intro l
      induction l with
      | nil => simp
      | cons p ps ih =>
        rw [List.foldr_cons, mem_insKey, ih]
        constructor
        · rintro (h | (⟨v, hv⟩ | h))
          · exact Or.inl ⟨p.2, by rw [h]; simp⟩
          · exact Or.inl ⟨v, List.mem_cons_of_mem _ hv⟩
          · exact Or.inr h
        · rintro (⟨v, hv⟩ | h)
          · rcases List.mem_cons.mp hv with hv | hv
            · exact Or.inl (by rw [← hv])
            · exact Or.inr (Or.inl ⟨v, hv⟩)
          · exact Or.inr (Or.inr h)
    simp only [keysOf, hf, mem_keysOf x css, List.mem_cons]
    constructor
    · rintro (h | ⟨c, hc, h⟩)
      · exact ⟨cs, Or.inl rfl, h⟩
      · exact ⟨c, Or.inr hc, h⟩
    · rintro ⟨c, hc | hc, h⟩
      · subst hc; exact Or.inl h
      · exact Or.inr ⟨c, hc, h⟩

/-- An entry exists exactly when the table has a pair of that type.

$$\forall T, \tau:\ \operatorname{entry}(T, \tau) \ne \bot \iff \exists e:\ (\tau, e) \in T$$
-/
theorem entry_isSome_iff (tb : Table) (ty : String) : (entry? tb ty).isSome ↔ ∃ e, (ty, e) ∈ tb := by
  simp only [entry?, Option.isSome_map, List.find?_isSome, beq_iff_eq]
  constructor
  · rintro ⟨⟨a, e⟩, hm, rfl⟩; exact ⟨e, hm⟩
  · rintro ⟨e, hm⟩; exact ⟨(ty, e), hm, rfl⟩

/-- A type is a type of the runs exactly when some run's table has an entry for it.

$$\forall \mathcal{T}, \tau:\ \tau \in \operatorname{types}(\mathcal{T}) \iff \exists T \in \mathcal{T}:\ \operatorname{entry}(T, \tau) \ne \bot$$
-/
theorem mem_typesOf (tbs : List Table) (ty : String) :
    ty ∈ typesOf tbs ↔ ∃ tb ∈ tbs, (entry? tb ty).isSome := by
  simp only [typesOf, mem_keysOf, entry_isSome_iff]
  constructor
  · rintro ⟨cs, hcs, v, hv⟩
    obtain ⟨tb, htb, rfl⟩ := List.mem_map.mp hcs
    obtain ⟨p, hp, hpe⟩ := List.mem_map.mp hv
    simp only [Prod.mk.injEq] at hpe
    exact ⟨tb, htb, p.2, by rw [← hpe.1]; simpa using hp⟩
  · rintro ⟨tb, htb, e, he⟩
    exact ⟨_, List.mem_map.mpr ⟨tb, htb, rfl⟩, 0, List.mem_map.mpr ⟨(ty, e), he, rfl⟩⟩

/-- The frozen table has one row per type, in the order of the types.

$$\forall \mathcal{T}:\ [\, r.\tau \mid r \in \operatorname{frozen}(\mathcal{T}) \,] = \operatorname{types}(\mathcal{T})$$
-/
theorem freezeCore_types (tbs : List Table) : (freezeCore tbs).map (·.type) = typesOf tbs := by
  simp [freezeCore, Function.comp_def]

/-- Each frozen row carries the worst level, the maxima, the per-run levels and the smallest bound
of its type.

$$\forall \mathcal{T}, r \in \operatorname{frozen}(\mathcal{T}):\ r.\mathrm{cls} = \operatorname{worst}(\mathcal{T}, r.\tau) \land r.k = k(\mathcal{T}, r.\tau) \land r.t = t(\mathcal{T}, r.\tau) \land r.\mathrm{perRun} = [\operatorname{entry}(T, r.\tau).\mathrm{cls}\ (\bot \text{ if } \operatorname{entry}(T, r.\tau) = \bot)]_{T \in \mathcal{T}} \land r.\mathrm{tBound} = b(\mathcal{T}, r.\tau)$$
-/
theorem freezeCore_row (tbs : List Table) : ∀ r ∈ freezeCore tbs,
    r.cls = worstOf tbs r.type ∧ r.k = kOf tbs r.type ∧ r.t = tOf tbs r.type ∧
    r.perRun = tbs.map (fun tb => (entry? tb r.type).map (·.cls)) ∧ r.tBound = tBoundOf tbs r.type := by
  intro r h
  simp only [freezeCore, List.mem_map] at h
  obtain ⟨ty, _, rfl⟩ := h
  exact ⟨rfl, rfl, rfl, rfl, rfl⟩

/-- The level of a type in a table whose pairs of that type all carry one level.

$$\forall T, \tau, \ell:\ (\exists e:\ (\tau, e) \in T) \land (\forall e:\ (\tau, e) \in T \Rightarrow e.\mathrm{cls} = \ell) \;\Rightarrow\; \operatorname{lvl}_T(\tau) = \ell$$
-/
theorem levelIn_of {tb : Table} {ty : String} {l : Level} (hx : ∃ e, (ty, e) ∈ tb)
    (hall : ∀ e, (ty, e) ∈ tb → e.cls = l) : levelIn tb ty = l := by
  have hs := (entry_isSome_iff tb ty).2 hx
  unfold levelIn
  cases hq : entry? tb ty with
  | none => simp [hq] at hs
  | some e =>
    simp only [entry?, Option.map_eq_some_iff] at hq
    obtain ⟨⟨a, e'⟩, hf, rfl⟩ := hq
    have ha : a = ty := by simpa using List.find?_some hf
    subst ha
    exact hall e' (List.mem_of_find?_eq_some hf)

/-- **Re-freezing changes nothing.** Over a non-empty list of runs, the frozen table read as a single
run's table gives every type the same level.

$$\forall \mathcal{T}, \tau:\ \mathcal{T} \ne [\,] \;\Rightarrow\; \operatorname{worst}([\operatorname{table}(\operatorname{frozen}(\mathcal{T}))], \tau) = \operatorname{worst}(\mathcal{T}, \tau)$$
-/
theorem worstOf_refreeze {tbs : List Table} (hne : tbs ≠ []) (ty : String) :
    worstOf [toTable (freezeCore tbs)] ty = worstOf tbs ty := by
  rw [worstOf_single]
  by_cases hm : ty ∈ typesOf tbs
  · apply levelIn_of
    · rw [← freezeCore_types] at hm
      obtain ⟨r, hr, hrt⟩ := List.mem_map.mp hm
      exact ⟨_, List.mem_map.mpr ⟨r, hr, by rw [hrt]⟩⟩
    · intro e he
      obtain ⟨r, hr, hre⟩ := List.mem_map.mp he
      simp only [Prod.mk.injEq] at hre
      rw [← hre.2, ← hre.1]
      exact (freezeCore_row tbs r hr).1
  · have hnone : entry? (toTable (freezeCore tbs)) ty = none := by
      cases hq : entry? (toTable (freezeCore tbs)) ty with
      | none => rfl
      | some e =>
        exfalso; apply hm
        obtain ⟨e', he'⟩ := (entry_isSome_iff (toTable (freezeCore tbs)) ty).1 (by simp [hq])
        obtain ⟨r, hr, hre⟩ := List.mem_map.mp he'
        simp only [Prod.mk.injEq] at hre
        rw [← freezeCore_types, ← hre.1]
        exact List.mem_map_of_mem hr
    obtain ⟨tb, htb⟩ := List.exists_mem_of_ne_nil tbs hne
    have hmiss : entry? tb ty = none := by
      cases hq : entry? tb ty with
      | none => rfl
      | some _ => exact absurd ((mem_typesOf tbs ty).2 ⟨tb, htb, by simp [hq]⟩) hm
    simp only [levelIn, hnone]
    exact (worstOf_missing htb hmiss).symm

/-! ## Agreement with `classify` on a single run -/

/-- The class table of one workflow run, as `classifyAllU` decides it (the `measure.classify` reply):
each type's level, maxima and, for pixel-area types, the gap bound.

$$\operatorname{table}_{p,q}(\mathcal{R}) = \big[\,(\tau,\ (\operatorname{lvl}(c),\ k,\ t,\ \beta_\tau))\,\big]_{(\tau, c, k, t) \in \operatorname{classifyAll}_{p,q}(\mathcal{R})},\quad \beta_\tau = \begin{cases} \operatorname{tBound}_{p,q}(\mathrm{px}, R_\tau) & \operatorname{unit}(\tau) = \mathrm{px} \\ \bot & \operatorname{unit}(\tau) = \mathrm{count} \end{cases},\quad R_\tau = [\operatorname{series}_\tau(r)]_{r \in \mathcal{R}}$$
-/
def tableOf (p : Policy) (q : PxTol) (runs : List (List Counts)) : Table :=
  (classifyAllU p q runs).map fun r =>
    (r.type, ⟨levelOf r.cls, r.k, r.t, match unitOf r.type with
      | .px => some (tBound p q .px (runs.map (seriesOf r.type)))
      | .count => none⟩)

/-- **Agrees with classify on a single run.** Freezing the table of one workflow run gives every
count type of that run the level of its `classifyU` class.

$$\forall p, q, \mathcal{R}, \tau:\ \tau \in \operatorname{keys}(\mathcal{R}) \;\Rightarrow\; \operatorname{worst}([\operatorname{table}_{p,q}(\mathcal{R})], \tau) = \operatorname{lvl}\big(\operatorname{classify}_{p,q}(\operatorname{unit}(\tau), R_\tau)\big),\quad R_\tau = [\operatorname{series}_\tau(r)]_{r \in \mathcal{R}}$$
-/
theorem worstOf_single_classify (p : Policy) (q : PxTol) (runs : List (List Counts)) {τ : String}
    (hk : τ ∈ keysOf runs.flatten) :
    worstOf [tableOf p q runs] τ = levelOf (classifyU p q (unitOf τ) (runs.map (seriesOf τ))) := by
  rw [worstOf_single]
  apply levelIn_of
  · rw [← classifyAllU_types p q] at hk
    obtain ⟨r, hr, hrt⟩ := List.mem_map.mp hk
    exact ⟨_, List.mem_map.mpr ⟨r, hr, by rw [hrt]⟩⟩
  · intro e he
    obtain ⟨r, hr, hre⟩ := List.mem_map.mp he
    simp only [Prod.mk.injEq] at hre
    rw [← hre.2, ← hre.1]
    exact congrArg levelOf (classifyAllU_row p q runs r hr).1

/-! ## The refusing wrapper -/

/-- The least number of workflow runs a freeze accepts.

$$m = 3$$
-/
def minRuns : Nat := 3

/-- One workflow run: its id, the image digest reported by each of its jobs, and its class table.

$$\mathrm{Run} = \Sigma^{*} \times (\Sigma^{*})^{*} \times \mathrm{Table}$$
-/
structure RunTable where
  id : String
  images : List String
  table : Table
deriving Repr, DecidableEq

/-- **The freeze.** Refuses fewer than $m$ runs, a repeated run id, a run without an image digest,
and two different digests; otherwise the common digest and the frozen table.

$$\operatorname{freeze}(\mathcal{W}) = \begin{cases} \text{refused} & |\mathcal{W}| < m \\ \text{refused} & |\mathcal{W}| \ge m,\ \text{the ids } [w.\mathrm{id}]_{w \in \mathcal{W}} \text{ repeat} \\ \text{refused} & \text{the above pass},\ \exists w \in \mathcal{W}:\ w.\mathrm{images} = [\,] \\ \text{refused} & \text{the above pass},\ \exists w, w' \in \mathcal{W}, x \in w.\mathrm{images}, x' \in w'.\mathrm{images}:\ x \ne x' \\ (d,\ \operatorname{frozen}([w.\mathrm{table}]_{w \in \mathcal{W}})) & \text{otherwise, } d \text{ the common digest} \end{cases}$$
-/
def freeze (runs : List RunTable) : Except String (String × List FRow) :=
  if runs.length < minRuns then
    .error s!"need at least {minRuns} workflow runs, got {runs.length}"
  else if !decide (runs.map (·.id)).Nodup then
    .error "a workflow run id occurs twice"
  else if runs.any (·.images.isEmpty) then
    .error "a workflow run reports no image digest"
  else match runs.flatMap (·.images) with
    | [] => .error "no image digest"
    | d :: ds =>
      if ds.all (· == d) then .ok (d, freezeCore (runs.map (·.table)))
      else .error "mixed image digests"

#guard (freeze [⟨"1", ["x"], []⟩, ⟨"2", ["x"], []⟩]).toOption.isNone
#guard (freeze [⟨"1", ["x"], []⟩, ⟨"1", ["x"], []⟩, ⟨"2", ["x"], []⟩]).toOption.isNone
#guard (freeze [⟨"1", ["x"], []⟩, ⟨"2", [], []⟩, ⟨"3", ["x"], []⟩]).toOption.isNone
#guard (freeze [⟨"1", ["x", "x"], []⟩, ⟨"2", ["x"], []⟩, ⟨"3", ["y"], []⟩]).toOption.isNone
#guard (freeze [⟨"1", ["x", "x"], [("a", e .det 0 0)]⟩, ⟨"2", ["x"], [("a", e .stable 1 1)]⟩,
    ⟨"3", ["x"], [("b", e .det 0 0)]⟩]).toOption ==
  some ("x", [⟨"a", .quar, 1, 1, [some .det, some .stable, none], none⟩,
              ⟨"b", .quar, 0, 0, [none, none, some .det], none⟩])

/-- **When the freeze answers.** It answers $(d, F)$ exactly when there are at least $m$ runs with
distinct ids, every run reports at least one digest, every digest is $d$, and $F$ is the frozen table.

$$\forall \mathcal{W}, d, F:\ \operatorname{freeze}(\mathcal{W}) = (d, F) \iff |\mathcal{W}| \ge m \land [w.\mathrm{id}]_{w \in \mathcal{W}} \text{ has no repeats} \land (\forall w \in \mathcal{W}:\ w.\mathrm{images} \ne [\,]) \land (\forall w \in \mathcal{W}, x \in w.\mathrm{images}:\ x = d) \land F = \operatorname{frozen}([w.\mathrm{table}]_{w \in \mathcal{W}})$$
-/
theorem freeze_ok_iff (ws : List RunTable) (d : String) (fr : List FRow) :
    freeze ws = .ok (d, fr) ↔
      minRuns ≤ ws.length ∧ (ws.map (·.id)).Nodup ∧ (∀ w ∈ ws, w.images ≠ []) ∧
      (∀ w ∈ ws, ∀ x ∈ w.images, x = d) ∧ fr = freezeCore (ws.map (·.table)) := by
  unfold freeze
  by_cases hl : ws.length < minRuns
  · simp only [hl, ite_true]
    constructor
    · intro h; cases h
    · intro h; omega
  simp only [hl, ite_false]
  by_cases hn : (ws.map (·.id)).Nodup
  · simp only [hn, decide_true, Bool.not_true, Bool.false_eq_true, ite_false]
    by_cases he : ws.any (·.images.isEmpty) = true
    · simp only [he, ite_true]
      constructor
      · intro h; cases h
      · rintro ⟨_, _, hne, _⟩
        obtain ⟨w, hw, hwe⟩ := List.any_eq_true.mp he
        exact absurd (List.isEmpty_iff.mp hwe) (hne w hw)
    · simp only [he, Bool.false_eq_true, ite_false]
      have hne : ∀ w ∈ ws, w.images ≠ [] := by
        intro w hw h0
        exact he (List.any_eq_true.mpr ⟨w, hw, by simp [h0]⟩)
      have hpos : 0 < ws.length := by simp [minRuns] at hl; omega
      split
      · rename_i h0
        exfalso
        obtain ⟨w, hw⟩ := List.exists_mem_of_length_pos hpos
        obtain ⟨x, hx⟩ := List.exists_mem_of_ne_nil _ (hne w hw)
        have : x ∈ ws.flatMap (·.images) := List.mem_flatMap.mpr ⟨w, hw, hx⟩
        rw [h0] at this; simp at this
      · rename_i d' ds hfl
        have hall : ∀ w ∈ ws, ∀ x ∈ w.images, x = d' ∨ x ∈ ds := by
          intro w hw x hx
          have : x ∈ ws.flatMap (·.images) := List.mem_flatMap.mpr ⟨w, hw, hx⟩
          rw [hfl] at this; simpa using this
        by_cases hd : ds.all (· == d') = true
        · simp only [hd, ite_true]
          have hds : ∀ y ∈ ds, y = d' := fun y hy => by simpa using List.all_eq_true.mp hd y hy
          constructor
          · intro h
            simp only [Except.ok.injEq, Prod.mk.injEq] at h
            obtain ⟨rfl, rfl⟩ := h
            refine ⟨by omega, trivial, hne, ?_, rfl⟩
            intro w hw x hx
            rcases hall w hw x hx with h | h
            · exact h
            · exact hds x h
          · rintro ⟨_, _, _, hd', rfl⟩
            obtain ⟨w, hw⟩ := List.exists_mem_of_length_pos hpos
            obtain ⟨x, hx⟩ := List.exists_mem_of_ne_nil _ (hne w hw)
            have h1 : d' = d := by
              have hmem : d' ∈ ws.flatMap (·.images) := by rw [hfl]; simp
              obtain ⟨w', hw', hx'⟩ := List.mem_flatMap.mp hmem
              exact hd' w' hw' d' hx'
            rw [h1]
        · simp only [hd, Bool.false_eq_true, ite_false]
          constructor
          · intro h; cases h
          · rintro ⟨_, _, _, hd', _⟩
            exfalso
            apply hd
            apply List.all_eq_true.mpr
            intro y hy
            have hy' : y ∈ ws.flatMap (·.images) := by rw [hfl]; simp [hy]
            have hd0 : d' ∈ ws.flatMap (·.images) := by rw [hfl]; simp
            obtain ⟨w1, hw1, hx1⟩ := List.mem_flatMap.mp hy'
            obtain ⟨w2, hw2, hx2⟩ := List.mem_flatMap.mp hd0
            simp [hd' w1 hw1 y hx1, hd' w2 hw2 d' hx2]
  · simp only [hn, decide_false, Bool.not_false, ite_true]
    constructor
    · intro h; cases h
    · rintro ⟨_, h, _⟩; exact h.elim

/-- **Fewer than three runs are refused.**

$$\forall \mathcal{W}:\ |\mathcal{W}| < m \;\Rightarrow\; \forall d, F:\ \operatorname{freeze}(\mathcal{W}) \ne (d, F)$$
-/
theorem freeze_few {ws : List RunTable} (h : ws.length < minRuns) (d : String) (fr : List FRow) :
    freeze ws ≠ .ok (d, fr) := by
  intro hf; have := ((freeze_ok_iff ws d fr).1 hf).1; omega

/-- **Mixed image digests are refused.**

$$\forall \mathcal{W}:\ (\exists w, w' \in \mathcal{W}, x \in w.\mathrm{images}, x' \in w'.\mathrm{images}:\ x \ne x') \;\Rightarrow\; \forall d, F:\ \operatorname{freeze}(\mathcal{W}) \ne (d, F)$$
-/
theorem freeze_mixed {ws : List RunTable}
    (h : ∃ w ∈ ws, ∃ w' ∈ ws, ∃ x ∈ w.images, ∃ x' ∈ w'.images, x ≠ x') (d : String) (fr : List FRow) :
    freeze ws ≠ .ok (d, fr) := by
  intro hf
  obtain ⟨_, _, _, hd, _⟩ := (freeze_ok_iff ws d fr).1 hf
  obtain ⟨w, hw, w', hw', x, hx, x', hx', hne⟩ := h
  exact hne ((hd w hw x hx).trans (hd w' hw' x' hx').symm)

end Fw.Measure.Freeze
