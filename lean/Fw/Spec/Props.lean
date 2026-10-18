/-!
# Properties first: a never-happen property is a predicate over the implementation

Task `lfg-props-shape` (research/notes/2026/10-18-lean-first-gate.md, rule 1 and rule 4). Ten incidents came from
properties nobody stated (for example `inc-land-dry-no-verdict`: an empty branch printed no `VERDICT` line). The
convention here makes a property a first-class value that exists *before* the code:

* **Property over the signature.** A never-happen property of a task is a `Prop`-valued def over the type of the
  implementation, `P : Impl → Prop` (`Property Impl`), never a statement about one fixed def. So the same `P` can be
  proved of the real implementation and refuted for a bad one.
* **Kill-witness naming.** For a property `P`, the real implementation `impl` and a bad implementation `bad`:
  `theorem P_impl : P impl` and `theorem P_rejects_<bad> : ¬ P bad` (`implName`, `killName`). The gate decides by the
  *type* (`P impl`, `¬ P bad`, same head constant `P`); the names are for readers.
* **Non-vacuity is weak alone.** A kill witness makes the property non-vacuous (`nonvacuous_of_rejects`), but any
  property that some implementation fails is non-vacuous, even when the failure has nothing to do with the incident.
* **The kill is tied to the incident.** So every bad implementation also gets `theorem <bad>_agrees_off :
  AgreesOff impl bad incident`: the bad implementation equals the real one on every input that is not an incident
  input. For a pointwise property whose check reads the implementation at one point (`ReadsAt`), if the property
  holds of `impl` then `bad` fails the check only on incident inputs (`failures_on_incident`), and if the property
  also rejects `bad`, on at least one (`fails_on_incident`). The kill witness then sees the incident, not an
  unrelated difference.
* **Pointwise form.** A property that is a `∀` over inputs of a `Bool` check (`Pointwise`) is what `Fw.Search` can
  search before any proof (`rejects_of_counterexample`).
* **Premises are visible.** `Assume p claim` holds exactly when `claim` does (`assume_iff`), but it is a structure:
  a proof of it is built only with the explicit `Assume.intro`, and it names the premise `p` (its kind and registry
  id) in the statement. So a theorem that takes `(h : Assume p claim)` says in its type that it rests on the engine,
  the shell, the file system or CI, and a checker can list the ids.
* **What Lean does not catch here.** Nothing in this module stops a theorem from taking an outside fact as a bare,
  unmarked hypothesis, and `Premise.id` is a free string, so an unregistered id elaborates. Those two holes are closed
  only by the tasks `lfg-premise-registry` (every id must be a registry row) and `lfg-mathview-facts` (MathView lists
  the hypotheses of each theorem, so an unmarked outside fact is visible in review).

Worked example: `Fw.Spec.Props.LandDryDemo`; how-to: docs/team/tools/lean-first.md.
-/
namespace Fw.Spec.Props

universe u v w

/-- A property of implementations of the signature $I$: a predicate on implementations, so it can be stated before
any implementation exists.
$$\mathrm{Property}(I) = I \to \mathrm{Prop}$$ -/
abbrev Property (Impl : Type u) : Type u := Impl → Prop

/-- A kill witness: the property rejects the bad implementation $b$.
$$\mathrm{Rejects}(P, b) \iff \lnot P(b)$$ -/
def Rejects {Impl : Type u} (P : Property Impl) (bad : Impl) : Prop := ¬ P bad

/-- A property is non-vacuous when some implementation of the signature fails it.
$$\mathrm{Nonvacuous}(P) \iff \exists b : I,\ \lnot P(b)$$ -/
def Nonvacuous {Impl : Type u} (P : Property Impl) : Prop := ∃ bad, ¬ P bad

/-- **A kill witness makes the property non-vacuous.** For every property and every implementation the property
rejects, the property is not true of every implementation.
$$\forall P : I \to \mathrm{Prop},\ \forall b : I,\ \lnot P(b) \Rightarrow \exists b' : I,\ \lnot P(b')$$ -/
theorem nonvacuous_of_rejects {Impl : Type u} (P : Property Impl) (bad : Impl) (h : ¬ P bad) : Nonvacuous P :=
  ⟨bad, h⟩

/-- `Rejects` is the negation, so `P_rejects_<bad>` may be stated either way.
$$\forall P : I \to \mathrm{Prop},\ \forall b : I,\ \mathrm{Rejects}(P, b) \iff \lnot P(b)$$ -/
theorem rejects_iff {Impl : Type u} (P : Property Impl) (bad : Impl) : Rejects P bad ↔ ¬ P bad := Iff.rfl

/-- The pointwise property of a Boolean check $Q$: the check passes on every input $x$ of type $A$.
$$\mathrm{Pointwise}(Q)(i) \iff \forall x : A,\ Q(i, x) = \mathrm{true}$$ -/
def Pointwise {Impl : Type u} {α : Type v} (Q : Impl → α → Bool) : Property Impl := fun i => ∀ x, Q i x = true

/-- **One counterexample refutes a pointwise property.** For every check $Q$, implementation $i$ and input $x$: if the
check fails on $x$, the pointwise property fails for $i$.
$$\forall Q,\ \forall i : I,\ \forall x : A,\ Q(i, x) = \mathrm{false} \Rightarrow \lnot\,\mathrm{Pointwise}(Q)(i)$$ -/
theorem rejects_of_counterexample {Impl : Type u} {α : Type v} (Q : Impl → α → Bool) (i : Impl) (x : α)
    (h : Q i x = false) : ¬ Pointwise Q i :=
  fun hp => by simp [hp x] at h

/-- **The bad implementation differs only on the incident.** For implementations that are functions from $A$ to $B$
and an incident predicate $E$ on $A$: `bad` equals `impl` on every input that is not an incident input.
$$\mathrm{AgreesOff}(i, b, E) \iff \forall a : A,\ \lnot E(a) \Rightarrow i(a) = b(a)$$ -/
def AgreesOff {α : Type v} {β : Type w} (impl bad : α → β) (incident : α → Prop) : Prop :=
  ∀ a, ¬ incident a → impl a = bad a

/-- **The check reads one point.** The check $Q$ at input $y : C$ looks at an implementation $i : A \to B$ only
through its value at the point $\pi(y)$: two implementations with the same value there get the same answer.
$$\mathrm{ReadsAt}(Q, \pi) \iff \forall i\, j : A \to B,\ \forall y : C,\ i(\pi(y)) = j(\pi(y)) \Rightarrow Q(i, y) = Q(j, y)$$ -/
def ReadsAt {α : Type v} {β : Type w} {γ : Type u} (Q : (α → β) → γ → Bool) (pt : γ → α) : Prop :=
  ∀ (i j : α → β) (y : γ), i (pt y) = j (pt y) → Q i y = Q j y

/-- **Every failure of the bad implementation is an incident input.** For every check $Q$ and point map $\pi$ with
$\mathrm{ReadsAt}(Q, \pi)$, all implementations $i, b : A \to B$ and every incident predicate $E$: if the pointwise
property of $Q$ holds of $i$ and $b$ agrees with $i$ off $E$, then every input $y$ on which $Q$ fails for $b$ has
$E(\pi(y))$.
$$\forall Q\, \pi\, i\, b\, E,\ \mathrm{ReadsAt}(Q, \pi) \wedge \mathrm{Pointwise}(Q)(i) \wedge \mathrm{AgreesOff}(i, b, E) \Rightarrow \forall y : C,\ Q(b, y) = \mathrm{false} \Rightarrow E(\pi(y))$$ -/
theorem failures_on_incident {α : Type v} {β : Type w} {γ : Type u} (Q : (α → β) → γ → Bool) (pt : γ → α)
    (hQ : ReadsAt Q pt) (impl bad : α → β) (incident : α → Prop) (hi : Pointwise Q impl)
    (ha : AgreesOff impl bad incident) (y : γ) (hy : Q bad y = false) : incident (pt y) :=
  Classical.byContradiction fun hn => by
    have h1 : Q impl y = Q bad y := hQ impl bad y (ha (pt y) hn)
    rw [hi y, hy] at h1
    exact Bool.noConfusion h1

/-- **The kill is on the incident.** For every check $Q$ and point map $\pi$ with $\mathrm{ReadsAt}(Q, \pi)$, all
implementations $i, b : A \to B$ and every incident predicate $E$: if the pointwise property of $Q$ holds of $i$, $b$
agrees with $i$ off $E$, and the property rejects $b$, then some input $y$ with $E(\pi(y))$ makes $Q$ fail for $b$.
$$\forall Q\, \pi\, i\, b\, E,\ \mathrm{ReadsAt}(Q, \pi) \wedge \mathrm{Pointwise}(Q)(i) \wedge \mathrm{AgreesOff}(i, b, E) \wedge \lnot\,\mathrm{Pointwise}(Q)(b) \Rightarrow \exists y : C,\ E(\pi(y)) \wedge Q(b, y) = \mathrm{false}$$ -/
theorem fails_on_incident {α : Type v} {β : Type w} {γ : Type u} (Q : (α → β) → γ → Bool) (pt : γ → α)
    (hQ : ReadsAt Q pt) (impl bad : α → β) (incident : α → Prop) (hi : Pointwise Q impl)
    (ha : AgreesOff impl bad incident) (hb : ¬ Pointwise Q bad) : ∃ y, incident (pt y) ∧ Q bad y = false := by
  have : ∃ y, Q bad y = false := Classical.byContradiction fun hn =>
    hb fun y => by cases hy : Q bad y; exact absurd ⟨y, hy⟩ hn; rfl
  obtain ⟨y, hy⟩ := this
  exact ⟨y, failures_on_incident Q pt hQ impl bad incident hi ha y hy, hy⟩

/-- The kinds of premise a property may rest on: a browser engine, the shell, the file system, CI, the platform
(OS, toolchain) or the DOM. The registry `Fw.Ops.Premise` gives each premise one kind.
$$\mathrm{PremiseKind} = \{\mathrm{engine}, \mathrm{shell}, \mathrm{fs}, \mathrm{ci}, \mathrm{platform}, \mathrm{dom}\}$$ -/
inductive PremiseKind where
  | engine | shell | fs | ci | platform | dom
deriving DecidableEq, Repr

/-- A named premise: its kind and its registry id (an `id` of `Fw.Ops.Premise.registry` or of a module's premise
rows, for example `land.dryStagesAreLandStages`).
$$p = (\mathit{kind}, \mathit{id}) \in \mathrm{PremiseKind} \times \mathrm{String}$$ -/
structure Premise where
  kind : PremiseKind
  id : String
deriving DecidableEq, Repr

/-- **The premise marker.** An opaque wrapper around the claim: a proof of `Assume p claim` is built only with the
explicit `Assume.intro` and read only with `Assume.elim`, so a bare proof of the claim does not elaborate where the
marker is expected, and a theorem that takes `(h : Assume p claim)` shows in its type which outside fact (engine,
shell, fs, CI) it rests on. A bare, unmarked hypothesis is still possible elsewhere; `lfg-mathview-facts` and
`lfg-premise-registry` catch that, not this type.
$$\mathrm{Assume}(p, c) : \mathrm{Prop},\quad \mathrm{intro} : c \to \mathrm{Assume}(p, c),\quad \mathrm{elim} : \mathrm{Assume}(p, c) \to c$$ -/
structure Assume (p : Premise) (claim : Prop) : Prop where
  /-- Introduce a premise: a proof of the claim, marked with the premise $p$.
  $$\forall p,\ \forall c : \mathrm{Prop},\ c \Rightarrow \mathrm{Assume}(p, c)$$ -/
  intro ::
  /-- Use a premise: the marked claim gives the claim.
  $$\forall p,\ \forall c : \mathrm{Prop},\ \mathrm{Assume}(p, c) \Rightarrow c$$ -/
  elim : claim

/-- The marker adds no logical content: for every premise and every claim, the marked claim is equivalent to the
claim.
$$\forall p,\ \forall c : \mathrm{Prop},\ \mathrm{Assume}(p, c) \iff c$$ -/
theorem assume_iff (p : Premise) (c : Prop) : Assume p c ↔ c := ⟨Assume.elim, Assume.intro⟩

-- the marker is opaque: a bare proof of the claim is not a marked claim, only `Assume.intro` builds one
example (c : Prop) (h : c) : Assume ⟨.shell, "example.id"⟩ c := by
  fail_if_success exact h
  exact Assume.intro h

/-- The name of the theorem that proves property $P$ of the real implementation.
$$\operatorname{implName}(P) = P \mathbin{+\!\!+} \texttt{\_impl}$$ -/
def implName (prop : String) : String := prop ++ "_impl"

/-- The name of the kill witness of property $P$ against the bad implementation $b$.
$$\operatorname{killName}(P, b) = P \mathbin{+\!\!+} \texttt{\_rejects\_} \mathbin{+\!\!+} b$$ -/
def killName (prop bad : String) : String := prop ++ "_rejects_" ++ bad

#guard implName "NoSilentExit" == "NoSilentExit_impl"
#guard killName "NoSilentExit" "emptyNoVerdict" == "NoSilentExit_rejects_emptyNoVerdict"
#guard killName "TruthfulVerdict" "emptyDone" == "TruthfulVerdict_rejects_emptyDone"

end Fw.Spec.Props
