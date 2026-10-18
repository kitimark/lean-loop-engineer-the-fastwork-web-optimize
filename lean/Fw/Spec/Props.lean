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
* **Non-vacuity.** A kill witness makes the property non-vacuous (`nonvacuous_of_rejects`): some implementation of the
  signature fails it. A proof plus a kill also tell the two implementations apart (`ne_of_holds_of_rejects`).
* **Pointwise form.** A property that is a `∀` over inputs of a `Bool` check (`Pointwise`) is what `Fw.Search` can
  search before any proof (`rejects_of_counterexample`).
* **Premises are visible.** `Assume p claim` is `claim`, but it names the premise `p` (its kind and registry id) in
  the statement, so a theorem that rests on the engine, the shell, the file system or CI says so in its type, and a
  checker (MathView, `lfg-mathview-facts`) can list the ids.

Worked example: `Fw.Spec.Props.LandDryDemo`; how-to: docs/team/tools/lean-first.md.
-/
namespace Fw.Spec.Props

universe u

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

/-- **A proof and a kill tell the implementations apart.** If the property holds of $i$ and fails for $b$, then $i$
and $b$ are different implementations, so the property sees the difference the bad implementation makes.
$$\forall P : I \to \mathrm{Prop},\ \forall i\, b : I,\ P(i) \wedge \lnot P(b) \Rightarrow i \ne b$$ -/
theorem ne_of_holds_of_rejects {Impl : Type u} (P : Property Impl) (impl bad : Impl) (hi : P impl) (hb : ¬ P bad) :
    impl ≠ bad :=
  fun h => hb (h ▸ hi)

/-- The pointwise property of a Boolean check $Q$: the check passes on every input $x$ of type $A$.
$$\mathrm{Pointwise}(Q)(i) \iff \forall x : A,\ Q(i, x) = \mathrm{true}$$ -/
def Pointwise {Impl : Type u} {α : Type} (Q : Impl → α → Bool) : Property Impl := fun i => ∀ x, Q i x = true

/-- **One counterexample refutes a pointwise property.** For every check $Q$, implementation $i$ and input $x$: if the
check fails on $x$, the pointwise property fails for $i$.
$$\forall Q,\ \forall i : I,\ \forall x : A,\ Q(i, x) = \mathrm{false} \Rightarrow \lnot\,\mathrm{Pointwise}(Q)(i)$$ -/
theorem rejects_of_counterexample {Impl : Type u} {α : Type} (Q : Impl → α → Bool) (i : Impl) (x : α)
    (h : Q i x = false) : ¬ Pointwise Q i :=
  fun hp => by simp [hp x] at h

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

/-- **The premise marker.** `Assume p claim` is the claim itself, but the premise $p$ is part of the statement, so a
theorem that takes `(h : Assume p claim)` shows in its type which outside fact (engine, shell, fs, CI) it rests on.
$$\mathrm{Assume}(p, c) := c$$ -/
def Assume (_p : Premise) (claim : Prop) : Prop := claim

/-- The marker adds no logical content: for every premise and every claim, assuming the claim under the premise's
name is the claim.
$$\forall p,\ \forall c : \mathrm{Prop},\ \mathrm{Assume}(p, c) \iff c$$ -/
theorem assume_iff (p : Premise) (c : Prop) : Assume p c ↔ c := Iff.rfl

/-- Introduce a premise: for every premise and every claim, a proof of the claim is a proof of the marked claim.
$$\forall p,\ \forall c : \mathrm{Prop},\ c \Rightarrow \mathrm{Assume}(p, c)$$ -/
theorem Assume.intro {p : Premise} {c : Prop} (h : c) : Assume p c := h

/-- Use a premise: for every premise and every claim, the marked claim gives the claim.
$$\forall p,\ \forall c : \mathrm{Prop},\ \mathrm{Assume}(p, c) \Rightarrow c$$ -/
theorem Assume.elim {p : Premise} {c : Prop} (h : Assume p c) : c := h

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
