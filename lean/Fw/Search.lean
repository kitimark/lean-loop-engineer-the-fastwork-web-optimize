/-!
# Bounded search for counterexamples, before any proof

Task `lfg-props-shape` (research/notes/2026/10-18-lean-first-gate.md, rule 5). Core Lean only, no Mathlib.

* `Enum α`: `enum n` is a list of values of `α` at bound `n`; larger bounds list more (`mono`) and every value
  appears at some bound (`complete`). The class has no size function: "bound" means only these two laws.
  `EnumAll α`: a finite type with one list `all` of every value; it is an `Enum` at every bound.
* `search xs q`: the first `x` in `xs` with `q x = false` (a counterexample), `none` when the check passes on all of
  `xs` (`search_none_iff`); `searchUpTo n q` searches `enum n`.
* The link to a property `P` with a sound pointwise check (`P i → ∀ x, q x = true`): a found counterexample is a kill
  witness (`refutes_of_search`), so `¬ P i` is proved by running the search; with a complete check over an `EnumAll`
  type, `search all q = none` proves `P i` (`holds_of_searchAll`, `prop_iff_searchAll`).

Instances: `Bool`, `Unit`, `Option`, products, `EnumAll.ofEquiv` (finite); `Nat`, `List`, `Option`, products
(`Enum`). Guards in a Props module: `#guard (search EnumAll.all (Q impl)).isNone` and, for each bad implementation `m`,
`#guard (search EnumAll.all (Q m)).isSome` (the search can see the bug at all). Worked example:
`Fw.Spec.Props.LandDryDemo`.
-/
namespace Fw.Search

universe u v

/-- Values of `α` enumerated by a bound: `enum n` is a list of values. A larger bound lists every value a smaller one
did, and every value is listed at some bound. There is no size function; the two laws are all the class says.
$$\mathrm{enum} : \mathbb N \to \mathrm{List}(\alpha),\quad \forall m\, n\, x,\ m \le n \wedge x \in \mathrm{enum}(m) \Rightarrow x \in \mathrm{enum}(n),\quad \forall x\ \exists n,\ x \in \mathrm{enum}(n)$$ -/
class Enum (α : Type u) where
  /-- The values listed at bound $n$. $$\mathrm{enum}(n) : \mathrm{List}(\alpha)$$ -/
  enum : Nat → List α
  /-- A larger bound lists more. $$\forall m\, n\, x,\ m \le n \wedge x \in \mathrm{enum}(m) \Rightarrow x \in \mathrm{enum}(n)$$ -/
  mono : ∀ {m n : Nat} {x : α}, m ≤ n → x ∈ enum m → x ∈ enum n
  /-- Every value is listed at some bound. $$\forall x,\ \exists n,\ x \in \mathrm{enum}(n)$$ -/
  complete : ∀ x : α, ∃ n, x ∈ enum n

/-- A finite type: one list `all` holds every value.
$$\mathrm{all} : \mathrm{List}(\alpha),\quad \forall x : \alpha,\ x \in \mathrm{all}$$ -/
class EnumAll (α : Type u) where
  /-- Every value, in a fixed order. $$\mathrm{all} : \mathrm{List}(\alpha)$$ -/
  all : List α
  /-- Every value is in the list. $$\forall x : \alpha,\ x \in \mathrm{all}$$ -/
  complete : ∀ x : α, x ∈ all

/-- A finite type enumerates all of its values at every bound.
$$\forall n,\ \mathrm{enum}(n) = \mathrm{all}$$ -/
instance (priority := low) instEnumOfEnumAll {α : Type u} [EnumAll α] : Enum α where
  enum _ := EnumAll.all
  mono _ h := h
  complete x := ⟨0, EnumAll.complete x⟩

/-- **The search.** The first element of $xs$ on which the check $q$ fails (a counterexample), or none.
$$\operatorname{search}(xs, q) = \begin{cases} \mathrm{some}(x_k) & k = \min\{k : q(x_k) = \mathrm{false}\} \\ \mathrm{none} & \forall k,\ q(x_k) = \mathrm{true} \end{cases}$$ -/
def search {α : Type u} (xs : List α) (q : α → Bool) : Option α := xs.find? (fun x => !q x)

/-- **No counterexample means the check holds on the bound.** For every list and every check, the search finds
nothing exactly when the check passes on every element of the list.
$$\forall xs,\ \forall q,\ \operatorname{search}(xs, q) = \mathrm{none} \iff \forall x \in xs,\ q(x) = \mathrm{true}$$ -/
theorem search_none_iff {α : Type u} (xs : List α) (q : α → Bool) :
    search xs q = none ↔ ∀ x ∈ xs, q x = true := by
  simp [search]

/-- **A found value is a real counterexample.** For every list, check and value: if the search returns $x$, then $x$
is in the list and the check fails on it.
$$\forall xs,\ \forall q,\ \forall x,\ \operatorname{search}(xs, q) = \mathrm{some}(x) \Rightarrow x \in xs \wedge q(x) = \mathrm{false}$$ -/
theorem search_some {α : Type u} (xs : List α) (q : α → Bool) (x : α) (h : search xs q = some x) :
    x ∈ xs ∧ q x = false :=
  ⟨List.mem_of_find?_eq_some h, by simpa using List.find?_some h⟩

/-- **The counterexample is the first one.** For every list, check and value: if the search returns $x$, the list is
$pre \mathbin{+\!\!+} x :: suf$ and the check passes on every element of $pre$.
$$\forall xs,\ \forall q,\ \forall x,\ \operatorname{search}(xs, q) = \mathrm{some}(x) \Rightarrow \exists\, pre\ suf,\ xs = pre \mathbin{+\!\!+} x :: suf \wedge \forall y \in pre,\ q(y) = \mathrm{true}$$ -/
theorem search_some_first {α : Type u} (xs : List α) (q : α → Bool) (x : α) (h : search xs q = some x) :
    ∃ pre suf, xs = pre ++ x :: suf ∧ ∀ y ∈ pre, q y = true := by
  obtain ⟨_, pre, suf, hxs, hpre⟩ := List.find?_eq_some_iff_append.mp h
  exact ⟨pre, suf, hxs, fun y hy => by simpa using hpre y hy⟩

/-- The search up to bound $n$: the search over `enum n`.
$$\operatorname{searchUpTo}(n, q) = \operatorname{search}(\mathrm{enum}(n), q)$$ -/
def searchUpTo {α : Type u} [Enum α] (n : Nat) (q : α → Bool) : Option α := search (Enum.enum n) q

/-- **No counterexample up to $n$ means the check holds on every value listed by `enum n`.** For every bound and
every check.
$$\forall n,\ \forall q,\ \operatorname{searchUpTo}(n, q) = \mathrm{none} \iff \forall x \in \mathrm{enum}(n),\ q(x) = \mathrm{true}$$ -/
theorem searchUpTo_none_iff {α : Type u} [Enum α] (n : Nat) (q : α → Bool) :
    searchUpTo n q = none ↔ ∀ x ∈ Enum.enum n, q x = true :=
  search_none_iff _ _

/-- A clean search at a bound is clean at every smaller bound: for all $m \le n$ and every check.
$$\forall m\, n,\ \forall q,\ m \le n \wedge \operatorname{searchUpTo}(n, q) = \mathrm{none} \Rightarrow \operatorname{searchUpTo}(m, q) = \mathrm{none}$$ -/
theorem searchUpTo_none_mono {α : Type u} [Enum α] (m n : Nat) (q : α → Bool) (hmn : m ≤ n)
    (h : searchUpTo n q = none) : searchUpTo m q = none :=
  (searchUpTo_none_iff m q).mpr fun x hx => (searchUpTo_none_iff n q).mp h x (Enum.mono hmn hx)

/-- **Clean at every bound is the universal check.** For every check, the search finds nothing at every bound exactly
when the check passes on every value.
$$\forall q,\ (\forall x,\ q(x) = \mathrm{true}) \iff \forall n,\ \operatorname{searchUpTo}(n, q) = \mathrm{none}$$ -/
theorem forall_iff_searchUpTo {α : Type u} [Enum α] (q : α → Bool) :
    (∀ x, q x = true) ↔ ∀ n, searchUpTo n q = none := by
  constructor
  · intro h n
    exact (searchUpTo_none_iff n q).mpr fun x _ => h x
  · intro h x
    obtain ⟨n, hn⟩ := Enum.complete x
    exact (searchUpTo_none_iff n q).mp (h n) x hn

/-- **On a finite type one search decides the check.** For every check, the search over `all` finds nothing exactly
when the check passes on every value.
$$\forall q,\ \operatorname{search}(\mathrm{all}, q) = \mathrm{none} \iff \forall x,\ q(x) = \mathrm{true}$$ -/
theorem searchAll_none_iff {α : Type u} [EnumAll α] (q : α → Bool) :
    search EnumAll.all q = none ↔ ∀ x, q x = true := by
  rw [search_none_iff]
  exact ⟨fun h x => h x (EnumAll.complete x), fun h x _ => h x⟩

/-! ## The link to a property (`Fw.Spec.Props`) -/

/-- **A found counterexample is a kill witness.** For every property $P$, implementation $i$, check $q$ and list
$xs$: if $P(i)$ implies that $q$ passes everywhere (the check is sound for $P$) and the search over $xs$ finds a value,
then $P(i)$ fails.
$$\forall P\, i\, q\, xs,\ (P(i) \Rightarrow \forall x,\ q(x) = \mathrm{true}) \wedge \operatorname{isSome}(\operatorname{search}(xs, q)) = \mathrm{true} \Rightarrow \lnot P(i)$$ -/
theorem refutes_of_search {Impl : Type v} {α : Type u} (P : Impl → Prop) (i : Impl) (q : α → Bool) (xs : List α)
    (hsound : P i → ∀ x, q x = true) (h : (search xs q).isSome = true) : ¬ P i := by
  intro hp
  cases hs : search xs q with
  | none => simp [hs] at h
  | some x => have := (search_some xs q x hs).2; simp [hsound hp x] at this

/-- **A clean exhaustive search is a proof.** For every property $P$, implementation $i$ and check $q$ over a finite
type: if $q$ passing everywhere implies $P(i)$ (the check is complete for $P$) and the search over `all` finds
nothing, then $P(i)$ holds.
$$\forall P\, i\, q,\ ((\forall x,\ q(x) = \mathrm{true}) \Rightarrow P(i)) \wedge \operatorname{search}(\mathrm{all}, q) = \mathrm{none} \Rightarrow P(i)$$ -/
theorem holds_of_searchAll {Impl : Type v} {α : Type u} [EnumAll α] (P : Impl → Prop) (i : Impl) (q : α → Bool)
    (hcomplete : (∀ x, q x = true) → P i) (h : search EnumAll.all q = none) : P i :=
  hcomplete ((searchAll_none_iff q).mp h)

/-- **`P_iff` links the search to the stated property.** For every property $P$, pointwise check $Q$ over a finite
type and implementation $i$: if $P$ is exactly "$Q$ passes everywhere" for every implementation, then $P(i)$ holds
exactly when the search over `all` finds nothing.
$$\forall P\, Q,\ (\forall i,\ P(i) \iff \forall x,\ Q(i, x) = \mathrm{true}) \Rightarrow \forall i,\ P(i) \iff \operatorname{search}(\mathrm{all}, Q(i)) = \mathrm{none}$$ -/
theorem prop_iff_searchAll {Impl : Type v} {α : Type u} [EnumAll α] (P : Impl → Prop) (Q : Impl → α → Bool)
    (hiff : ∀ i, P i ↔ ∀ x, Q i x = true) (i : Impl) : P i ↔ search EnumAll.all (Q i) = none := by
  rw [hiff i, searchAll_none_iff]

/-- **The property is a clean search at every bound.** For every property $P$, pointwise check $Q$ and implementation
$i$: if $P$ is exactly "$Q$ passes everywhere", then $P(i)$ holds exactly when the search finds nothing at every
bound; a clean search at one bound is the property on that bound only (`searchUpTo_none_iff`).
$$\forall P\, Q,\ (\forall i,\ P(i) \iff \forall x,\ Q(i, x) = \mathrm{true}) \Rightarrow \forall i,\ P(i) \iff \forall n,\ \operatorname{searchUpTo}(n, Q(i)) = \mathrm{none}$$ -/
theorem prop_iff_searchUpTo {Impl : Type v} {α : Type u} [Enum α] (P : Impl → Prop) (Q : Impl → α → Bool)
    (hiff : ∀ i, P i ↔ ∀ x, Q i x = true) (i : Impl) : P i ↔ ∀ n, searchUpTo n (Q i) = none := by
  rw [hiff i, forall_iff_searchUpTo]

/-! ## Finite instances -/

/-- The Booleans.
$$\mathrm{all}_{\mathbb B} = [\mathrm{false}, \mathrm{true}]$$ -/
instance instEnumAllBool : EnumAll Bool where
  all := [false, true]
  complete x := by cases x <;> simp

/-- The unit type.
$$\mathrm{all}_{1} = [()]$$ -/
instance instEnumAllUnit : EnumAll Unit where
  all := [()]
  complete x := by cases x; simp

/-- An optional value of a finite type: none, then every value.
$$\mathrm{all}_{\mathrm{Option}(\alpha)} = \mathrm{none} :: \operatorname{map}(\mathrm{some}, \mathrm{all}_\alpha)$$ -/
instance instEnumAllOption {α : Type u} [EnumAll α] : EnumAll (Option α) where
  all := none :: EnumAll.all.map some
  complete x := by cases x <;> simp [EnumAll.complete]

/-- A pair of finite types: every pair, the first component outermost.
$$\mathrm{all}_{\alpha \times \beta} = [(a, b) : a \in \mathrm{all}_\alpha,\ b \in \mathrm{all}_\beta]$$ -/
instance instEnumAllProd {α : Type u} {β : Type v} [EnumAll α] [EnumAll β] : EnumAll (α × β) where
  all := EnumAll.all.flatMap fun a => EnumAll.all.map fun b => (a, b)
  complete x := by
    obtain ⟨a, b⟩ := x
    simp only [List.mem_flatMap, List.mem_map, Prod.mk.injEq]
    exact ⟨a, EnumAll.complete a, b, EnumAll.complete b, rfl, rfl⟩

/-- A finite type through a surjection $f : \beta \to \alpha$ with right inverse $g$ ($f(g(a)) = a$ for all $a$): the
image of $\beta$'s list.
$$\mathrm{all}_\alpha = \operatorname{map}(f, \mathrm{all}_\beta)\quad\text{given } \forall a : \alpha,\ f(g(a)) = a$$ -/
@[reducible] def EnumAll.ofEquiv {α : Type u} {β : Type v} [EnumAll β] (f : β → α) (g : α → β) (h : ∀ a, f (g a) = a) :
    EnumAll α where
  all := EnumAll.all.map f
  complete a := List.mem_map.mpr ⟨g a, EnumAll.complete (g a), h a⟩

/-! ## Infinite instances -/

/-- The naturals up to $n$.
$$\mathrm{enum}_{\mathbb N}(n) = [0, 1, \dots, n]$$ -/
instance instEnumNat : Enum Nat where
  enum n := List.range (n + 1)
  mono hmn hx := by simp only [List.mem_range] at *; omega
  complete x := ⟨x, by simp⟩

/-- An optional value: none, then every value up to the bound.
$$\mathrm{enum}_{\mathrm{Option}(\alpha)}(n) = \mathrm{none} :: \operatorname{map}(\mathrm{some}, \mathrm{enum}_\alpha(n))$$ -/
instance instEnumOption {α : Type u} [Enum α] : Enum (Option α) where
  enum n := none :: (Enum.enum n).map some
  mono hmn hx := by
    simp only [List.mem_cons, List.mem_map] at *
    rcases hx with rfl | ⟨a, ha, rfl⟩
    · exact Or.inl rfl
    · exact Or.inr ⟨a, Enum.mono hmn ha, rfl⟩
  complete x := by
    cases x with
    | none => exact ⟨0, by simp⟩
    | some a =>
      obtain ⟨n, hn⟩ := Enum.complete a
      exact ⟨n, by simp [hn]⟩

/-- Pairs whose two components are both listed at bound $n$.
$$\mathrm{enum}_{\alpha \times \beta}(n) = [(a, b) : a \in \mathrm{enum}_\alpha(n),\ b \in \mathrm{enum}_\beta(n)]$$ -/
instance instEnumProd {α : Type u} {β : Type v} [Enum α] [Enum β] : Enum (α × β) where
  enum n := (Enum.enum n).flatMap fun a => (Enum.enum n).map fun b => (a, b)
  mono hmn hx := by
    simp only [List.mem_flatMap, List.mem_map] at *
    obtain ⟨a, ha, b, hb, rfl⟩ := hx
    exact ⟨a, Enum.mono hmn ha, b, Enum.mono hmn hb, rfl⟩
  complete x := by
    obtain ⟨a, b⟩ := x
    obtain ⟨na, ha⟩ := Enum.complete a
    obtain ⟨nb, hb⟩ := Enum.complete b
    refine ⟨na + nb, ?_⟩
    simp only [List.mem_flatMap, List.mem_map, Prod.mk.injEq]
    exact ⟨a, Enum.mono (by omega) ha, b, Enum.mono (by omega) hb, rfl, rfl⟩

/-- Every list of length at most $n$ with elements from $E$.
$$\operatorname{lists}(E, 0) = [[\,]],\qquad \operatorname{lists}(E, n+1) = [\,] :: [a :: l : a \in E,\ l \in \operatorname{lists}(E, n)]$$ -/
def listsUpTo {α : Type u} (E : List α) : Nat → List (List α)
  | 0 => [[]]
  | n + 1 => [] :: E.flatMap fun a => (listsUpTo E n).map (a :: ·)

/-- **`listsUpTo` lists exactly the short lists over $E$.** For every list $E$, bound $n$ and list $l$.
$$\forall E\, n\, l,\ l \in \operatorname{lists}(E, n) \iff |l| \le n \wedge \forall x \in l,\ x \in E$$ -/
theorem mem_listsUpTo {α : Type u} (E : List α) (n : Nat) (l : List α) :
    l ∈ listsUpTo E n ↔ l.length ≤ n ∧ ∀ x ∈ l, x ∈ E := by
  induction n generalizing l with
  | zero => cases l <;> simp [listsUpTo]
  | succ n ih =>
    cases l with
    | nil => simp [listsUpTo]
    | cons a t =>
      simp only [listsUpTo, List.mem_cons, List.mem_flatMap, List.mem_map, List.cons.injEq, ih,
        List.length_cons, forall_eq_or_imp]
      constructor
      · rintro (h | ⟨b, hb, l', ⟨hl, hx⟩, rfl, rfl⟩)
        · exact absurd h (by simp)
        · exact ⟨by omega, hb, hx⟩
      · rintro ⟨hl, ha, ht⟩
        exact Or.inr ⟨a, ha, t, ⟨by omega, ht⟩, rfl, rfl⟩

/-- Lists of length at most $n$ whose elements are listed at bound $n$.
$$\mathrm{enum}_{\mathrm{List}(\alpha)}(n) = \operatorname{lists}(\mathrm{enum}_\alpha(n), n)$$ -/
instance instEnumList {α : Type u} [Enum α] : Enum (List α) where
  enum n := listsUpTo (Enum.enum n) n
  mono hmn hx := by
    rw [mem_listsUpTo] at *
    exact ⟨by omega, fun y hy => Enum.mono hmn (hx.2 y hy)⟩
  complete l := by
    induction l with
    | nil => exact ⟨0, by simp [listsUpTo]⟩
    | cons a t ih =>
      obtain ⟨na, ha⟩ := Enum.complete a
      obtain ⟨nt, ht⟩ := ih
      rw [mem_listsUpTo] at ht
      refine ⟨na + nt + 1, (mem_listsUpTo _ _ _).mpr ⟨by simp; omega, ?_⟩⟩
      intro y hy
      rcases List.mem_cons.mp hy with rfl | hy
      · exact Enum.mono (by omega) ha
      · exact Enum.mono (by omega) (ht.2 y hy)

/-! ## Examples -/

#guard searchUpTo (α := Nat) 100 (fun n => n * n < 50) == some 8
#guard searchUpTo (α := Nat) 7 (fun n => n * n < 50) == none
#guard search (EnumAll.all : List (Bool × Bool)) (fun p => p.1 || p.2) == some (false, false)
#guard (EnumAll.all : List (Bool × Bool × Bool)).length == 8
#guard (EnumAll.all : List (Option Bool)).length == 3
#guard (Enum.enum 2 : List (List Bool)).length == 7
#guard (Enum.enum 9 : List (List Bool)).length == 1023
#guard searchUpTo (α := List Nat) 3 (fun l => l.length < 3) == some [0, 0, 0]
#guard searchUpTo (α := Option Nat × Nat) 3 (fun p => p.1.isSome || p.2 > 0) == some (none, 0)

end Fw.Search
