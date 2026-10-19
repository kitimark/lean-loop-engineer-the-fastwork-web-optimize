import Fw.Spec.Props
import Fw.Ops.LeanFirst

/-!
# The properties of the lean-first gate (stated before the proofs)

Task `lfg-spec`, research/notes/2026/10-18-lean-first-gate.md section 7. The convention of `Fw.Spec.Props`: each
property is a predicate over the *signature* (`Gate`, `Render`, the type of `discharges`, the type of `isNew`), so a
mutant of the same type can be refuted. No ledger incident exists for this gate yet (it is new code), so the kills are
tier-K mutants (`FwTest/Mutants/LeanFirst/`), not registry rows.

The spec vocabulary below restates the five rules of section 7 as `Prop`s with list-bounded quantifiers (so each is
decidable and searchable over `Enum Facts`), independent of the Boolean helpers the gate computes with:

* `PropsOk` (rule 1), `KillsOk` (rule 2), `TwinsOk` (rule 3), `PremOk` (rule 4), `SearchOk` (rule 5), `RatchetOk`
  (stage 3), and `PassSpec s F`: the facts are present or no rule is enforced, and every enforced rule holds.
* Decision code is `DecisionWrite`, a closed allowlist over the paths a glob may cover (`GlobCovers`), not the gate's
  own `isDecisionWrite`; `isDecisionWrite_iff` in `Fw.Ops.LeanFirstDecision` ties the two, so `RuleOk` is decidable
  there.
* A theorem discharges a property only with a named implementation (`implArg`), and only a discharging theorem whose
  own implementation is reached from the wire (`reachFromWire = some true`) closes rule 1d.

The proofs (`<P>_impl`) are in `Fw.Ops.LeanFirstProofs`; the search checks `Q` and the `Enum Facts` instance in
`Fw.Ops.LeanFirstSearch`.
-/
namespace Fw.Ops.LeanFirst

open Fw.Spec.Props

/-! ## Spec vocabulary -/

/-- **New**: the first baseline entry with the theorem's name does not carry its hash (or there is none).
$$\operatorname{New}(F, t) \iff \operatorname{lookup}(F.\mathit{baseline}, t.\mathit{name}) \ne \mathrm{some}(t.\mathit{hash})$$ -/
abbrev New (F : Facts) (t : ThmFact) : Prop := F.baseline.lookup t.name ≠ some t.hash

/-- **A kill at a hash**: some kill row has this target and this hash.
$$\operatorname{KillAt}(F, n, h) \iff \exists k \in F.\mathit{kills},\ k.\mathit{target} = n \land k.\mathit{hash} = h$$ -/
abbrev KillAt (F : Facts) (n h : String) : Prop := ∃ k ∈ F.kills, k.target = n ∧ k.hash = h

/-- **Exempt** (rule 2): a data lint or a kill witness, or a new theorem without its own kill used by a theorem of
the facts that has a kill.
$$\operatorname{Exempt}(F, t) \iff t.\mathit{kind} \ne \mathrm{general} \lor \bigl(\operatorname{New}(F, t) \land \lnot\operatorname{KillAt}(F, t.\mathit{name}, t.\mathit{hash}) \land \exists u \in t.\mathit{usedBy},\ \exists v \in F.\mathit{thms},\ v.\mathit{name} = u \land \operatorname{KillAt}(F, v.\mathit{name}, v.\mathit{hash})\bigr)$$ -/
abbrev Exempt (F : Facts) (t : ThmFact) : Prop :=
  t.kind ≠ .general ∨
    (New F t ∧ ¬ KillAt F t.name t.hash ∧ ∃ u ∈ t.usedBy, ∃ v ∈ F.thms, v.name = u ∧ KillAt F v.name v.hash)

/-- **The status of a premise**: the first registry row with the id has this status.
$$\operatorname{StatusIs}(F, p, \mathit{st}) \iff \operatorname{map}(\mathit{status}, \operatorname{find}(\rho \mapsto \rho.\mathit{id} = p, F.\mathit{registry})) = \mathrm{some}(\mathit{st})$$ -/
abbrev StatusIs (F : Facts) (p : String) (st : Status) : Prop :=
  (F.registry.find? (fun r => r.id == p)).map (·.status) = some st

/-- **Discharges** (rule 1c): the theorem's type is `P impl` for a named implementation, it uses the standard axioms
only, it is not exempt, and every untested premise it assumes the property assumes too.
$$\operatorname{Dis}(F, t, P) \iff t.\mathit{proves} = \mathrm{some}(P.\mathit{name}) \land t.\mathit{implArg} \ne \mathrm{none} \land t.\mathit{ax} \land \lnot\operatorname{Exempt}(F, t) \land \forall p \in t.\mathit{assumes},\ \operatorname{StatusIs}(F, p, \mathrm{untested}) \Rightarrow p \in P.\mathit{assumes}$$ -/
def Discharges (F : Facts) (t : ThmFact) (P : PropFact) : Prop :=
  t.proves = some P.name ∧ t.implArg ≠ none ∧ t.axiomsOk = true ∧ ¬ Exempt F t ∧
    ∀ p ∈ t.assumes, StatusIs F p .untested → p ∈ P.assumes

instance instDecidableDischarges (F : Facts) (t : ThmFact) (P : PropFact) : Decidable (Discharges F t P) :=
  inferInstanceAs (Decidable (t.proves = some P.name ∧ t.implArg ≠ none ∧ t.axiomsOk = true ∧ ¬ Exempt F t ∧
    ∀ p ∈ t.assumes, StatusIs F p .untested → p ∈ P.assumes))

/-- A signoff row is about the property at its current hashes, for the role.
$$\operatorname{At}(\sigma, P, r) \iff \sigma.\mathit{decl} = P.\mathit{name} \land \sigma.\mathit{stmt} = P.\mathit{stmt} \land \sigma.\mathit{doc} = P.\mathit{doc} \land \sigma.\mathit{role} = r$$ -/
abbrev At (s : Signoff) (P : PropFact) (r : Role) : Prop :=
  s.decl = P.name ∧ s.stmtHash = P.stmtHash ∧ s.role = r

/-- **Signed** (rule 1b): some row at the current hashes for the role agrees, and every such row agrees.
$$\operatorname{Signed}(F, P, r) \iff (\exists \sigma \in F.\mathit{signoffs},\ \operatorname{At}(\sigma, P, r) \land \sigma.a) \land \forall \sigma \in F.\mathit{signoffs},\ \operatorname{At}(\sigma, P, r) \Rightarrow \sigma.a$$ -/
abbrev Signed (F : Facts) (P : PropFact) (r : Role) : Prop :=
  (∃ s ∈ F.signoffs, At s P r ∧ s.agree = true) ∧ ∀ s ∈ F.signoffs, At s P r → s.agree = true

/-! ## Decision code (rule 1a), stated without the gate's `isDecisionWrite` -/

/-- **What a write glob may cover**, over characters: an over-approximation of the land-scope matcher
`Fw.Ops.PathCheck.matchesPath` on paths without empty or `.` segments. `*` matches any run of characters, `/`
included (so it covers `**` too); `/**` before `/` or the end, and `**/`, may match nothing (zero segments); a glob
that ends, or ends in `/`, covers the paths below it; every other character matches itself.
$$\begin{gathered} \operatorname{Cov}([\,], [\,]) \qquad \operatorname{Cov}([\,], \texttt{/} :: p) \qquad \operatorname{Cov}([\texttt{/}], [\,]) \qquad \operatorname{Cov}([\texttt{/}], \texttt{/} :: p) \qquad \frac{\operatorname{Cov}(g, p)}{\operatorname{Cov}(\texttt{*} :: g, p)} \qquad \frac{\operatorname{Cov}(\texttt{*} :: g, p)}{\operatorname{Cov}(\texttt{*} :: g, c :: p)} \\ \frac{c \ne \texttt{*} \quad \operatorname{Cov}(g, p)}{\operatorname{Cov}(c :: g, c :: p)} \qquad \frac{(g = [\,] \lor \exists g',\ g = \texttt{/} :: g') \quad \operatorname{Cov}(g, p)}{\operatorname{Cov}(\texttt{/**} \mathbin{+\!\!+} g, p)} \qquad \frac{\operatorname{Cov}(g, p)}{\operatorname{Cov}(\texttt{**/} \mathbin{+\!\!+} g, p)} \end{gathered}\quad (\forall c, g, p)$$ -/
inductive GlobCovers : List Char → List Char → Prop
  | done : GlobCovers [] []
  | under (p : List Char) : GlobCovers [] ('/' :: p)
  | slashEnd : GlobCovers ['/'] []
  | slashBelow (p : List Char) : GlobCovers ['/'] ('/' :: p)
  | starStop {g p : List Char} : GlobCovers g p → GlobCovers ('*' :: g) p
  | starEat {g p : List Char} (c : Char) : GlobCovers ('*' :: g) p → GlobCovers ('*' :: g) (c :: p)
  | lit {g p : List Char} (c : Char) : c ≠ '*' → GlobCovers g p → GlobCovers (c :: g) (c :: p)
  | dstarSkip {g p : List Char} : (g = [] ∨ ∃ g', g = '/' :: g') → GlobCovers g p →
      GlobCovers ('/' :: '*' :: '*' :: g) p
  | dstarLead {g p : List Char} : GlobCovers g p → GlobCovers ('*' :: '*' :: '/' :: g) p

/-- The first segment of a path is $d$: the path is $d$, or $d$, `/` and a rest.
$$\operatorname{Seg}_1(p, d) \iff p = d \lor \exists r,\ p = d \mathbin{+\!\!+} \texttt{/} :: r$$ -/
def FirstSeg (p d : List Char) : Prop := p = d ∨ ∃ r, p = d ++ '/' :: r

/-- **The non-decision allowlist** (rule 1a), over paths: under `docs/` (handoffs `docs/team/handoffs/**` and the work
graph `docs/team/work-graph.json` included) or `research/`, or a `.md` file outside `lean/`.
$$\operatorname{Allowed}(p) \iff \operatorname{Seg}_1(p, \texttt{docs}) \lor \operatorname{Seg}_1(p, \texttt{research}) \lor \bigl((\exists r,\ p = r \mathbin{+\!\!+} \texttt{.md}) \land \lnot\operatorname{Seg}_1(p, \texttt{lean})\bigr)$$ -/
def Allowed (p : List Char) : Prop :=
  FirstSeg p "docs".toList ∨ FirstSeg p "research".toList ∨
    ((∃ r, p = r ++ ".md".toList) ∧ ¬ FirstSeg p "lean".toList)

/-- **A decision write** (rule 1a, fail closed): the glob may cover some path that is not allowlisted.
$$\forall w,\ \operatorname{DecW}(w) \iff \exists p,\ \operatorname{Cov}(w, p) \land \lnot\operatorname{Allowed}(p)$$
A glob also covers the paths below it, so a `.md` glob outside `docs/` and `research/` is a decision write too. -/
def DecisionWrite (w : String) : Prop := ∃ p, GlobCovers w.toList p ∧ ¬ Allowed p

/-- **Decision code** (rule 1a): some write is a decision write.
$$\operatorname{Dec}(F) \iff \exists w \in F.\mathit{writes},\ \operatorname{DecW}(w)$$ -/
abbrev Decides (F : Facts) : Prop := ∃ w ∈ F.writes, DecisionWrite w

/-- **One property is done** (rules 1b-1e): one theorem discharges it and the implementation named by that theorem's
own `implArg` is reached from the wire, both roles signed it, and it is killed at its statement hash.
$$\operatorname{PropOk}(F, P) \iff (\exists t \in F.\mathit{thms},\ \operatorname{Dis}(F, t, P) \land t.\mathit{rw} = \mathrm{some}(\mathrm{true})) \land \operatorname{Signed}(F, P, \mathrm{math}) \land \operatorname{Signed}(F, P, \mathrm{adversary}) \land \operatorname{KillAt}(F, P.\mathit{name}, P.\mathit{stmt})$$ -/
def PropOk (F : Facts) (P : PropFact) : Prop :=
  (∃ t ∈ F.thms, Discharges F t P ∧ t.reachFromWire = some true) ∧ Signed F P .math ∧ Signed F P .adversary ∧
    KillAt F P.name P.stmtHash

instance instDecidablePropOk (F : Facts) (P : PropFact) : Decidable (PropOk F P) :=
  inferInstanceAs (Decidable ((∃ t ∈ F.thms, Discharges F t P ∧ t.reachFromWire = some true) ∧ Signed F P .math ∧
    Signed F P .adversary ∧ KillAt F P.name P.stmtHash))

/-- **Rule 1**: decision code has at least one property, and every property is done.
$$\operatorname{Props}(F) \iff (\operatorname{Dec}(F) \Rightarrow F.\mathit{props} \ne [\,]) \land \forall P \in F.\mathit{props},\ \operatorname{PropOk}(F, P)$$ -/
abbrev PropsOk (F : Facts) : Prop := (Decides F → F.props ≠ []) ∧ ∀ P ∈ F.props, PropOk F P

/-- **Rule 2**: every new theorem has a kill at its hash or is exempt.
$$\operatorname{Kills}(F) \iff \forall t \in F.\mathit{thms},\ \operatorname{New}(F, t) \Rightarrow \operatorname{KillAt}(F, t.\mathit{name}, t.\mathit{hash}) \lor \operatorname{Exempt}(F, t)$$ -/
abbrev KillsOk (F : Facts) : Prop := ∀ t ∈ F.thms, New F t → KillAt F t.name t.hash ∨ Exempt F t

/-- **Rule 3**: every new data branch is marked `op`, `twin` or an accepted `glue`.
$$\operatorname{Twins}(F) \iff \forall b \in F.\mathit{branches},\ b.\mathit{mark} \in \{\mathrm{op}, \mathrm{twin}, \mathrm{glue}_{ok}\}$$ -/
abbrev TwinsOk (F : Facts) : Prop := ∀ b ∈ F.branches, b.mark = .op ∨ b.mark = .twin ∨ b.mark = .glueOk

/-- **Rule 4**: for every new theorem, every registry row whose carrier it reaches is assumed, every assumed id is a
registry row, and no assumed id is refuted.
$$\operatorname{Prem}(F) \iff \forall t \in F.\mathit{thms},\ \operatorname{New}(F, t) \Rightarrow (\forall \rho \in F.\mathit{registry},\ (\exists c \in \rho.\mathit{carriers},\ c \in t.\mathit{reach}) \Rightarrow \rho.\mathit{id} \in t.\mathit{assumes}) \land (\forall p \in t.\mathit{assumes},\ \exists \rho \in F.\mathit{registry},\ \rho.\mathit{id} = p) \land (\forall p \in t.\mathit{assumes},\ \lnot\operatorname{StatusIs}(F, p, \mathrm{refuted}))$$ -/
abbrev PremOk (F : Facts) : Prop :=
  ∀ t ∈ F.thms, New F t →
    (∀ r ∈ F.registry, (∃ c ∈ r.carriers, c ∈ t.reach) → r.id ∈ t.assumes) ∧
    (∀ p ∈ t.assumes, ∃ r ∈ F.registry, r.id = p) ∧
    (∀ p ∈ t.assumes, ¬ StatusIs F p .refuted)

/-- **Search before proof** for one property: both commits are known and the search commit is a strict ancestor of
the proof commit.
$$\operatorname{First}(F, P) \iff \exists a\, b,\ P.\mathit{searchAt} = \mathrm{some}(a) \land P.\mathit{proofAt} = \mathrm{some}(b) \land (a, b) \in F.\mathit{ancestry}$$ -/
abbrev SearchFirst (F : Facts) (P : PropFact) : Prop :=
  ∃ a ∈ P.searchAt.toList, ∃ b ∈ P.proofAt.toList, (a, b) ∈ F.ancestry

/-- **Rule 5**: every property's search came first.
$$\operatorname{Search}(F) \iff \forall P \in F.\mathit{props},\ \operatorname{First}(F, P)$$ -/
abbrev SearchOk (F : Facts) : Prop := ∀ P ∈ F.props, SearchFirst F P

/-- **The ratchet** (stage 3): the legacy gap count at the head is at most the count on main.
$$\operatorname{Ratchet}(F) \iff F.\mathit{legacyHead} \le F.\mathit{legacyMain}$$ -/
abbrev RatchetOk (F : Facts) : Prop := F.legacyHead ≤ F.legacyMain

/-- **The reach of every candidate is known**: every theorem that is `Q impl` for a property `Q` of the task, with a
named implementation, has a `reachFromWire` fact.
$$\operatorname{ReachKnown}(F) \iff \forall t \in F.\mathit{thms},\ t.\mathit{implArg} \ne \mathrm{none} \Rightarrow (\exists Q \in F.\mathit{props},\ t.\mathit{proves} = \mathrm{some}(Q.\mathit{name})) \Rightarrow t.\mathit{rw} \ne \mathrm{none}$$ -/
abbrev ReachKnown (F : Facts) : Prop :=
  ∀ t ∈ F.thms, t.implArg ≠ none → (∃ Q ∈ F.props, t.proves = some Q.name) → t.reachFromWire ≠ none

/-- **Every fact is present**: the three sources were read, the reach of every candidate is known, and the exemption
classes (`exempt.tsv`, `killOf`) were read at the main commit the land merges onto, not at the branch under test.
$$\operatorname{Present}(F) \iff F.\mathit{present}.\mathit{mathview} \land F.\mathit{present}.\mathit{kills} \land F.\mathit{present}.\mathit{tsLint} \land \operatorname{ReachKnown}(F) \land F.\mathit{exemptAt} = \mathrm{some}(F.\mathit{mainAt})$$ -/
abbrev AllPresent (F : Facts) : Prop :=
  F.present.mathview = true ∧ F.present.kills = true ∧ F.present.tsLint = true ∧ ReachKnown F ∧
    F.exemptAt = some F.mainAt

/-- The spec of each rule.
$$\operatorname{Ok}(\mathrm{props}) = \operatorname{Props},\ \operatorname{Ok}(\mathrm{kills}) = \operatorname{Kills},\ \operatorname{Ok}(\mathrm{twins}) = \operatorname{Twins},\ \operatorname{Ok}(\mathrm{premises}) = \operatorname{Prem},\ \operatorname{Ok}(\mathrm{search}) = \operatorname{Search},\ \operatorname{Ok}(\mathrm{ratchet}) = \operatorname{Ratchet}$$ -/
abbrev RuleOk : Rule → Facts → Prop
  | .props, F => PropsOk F
  | .kills, F => KillsOk F
  | .twins, F => TwinsOk F
  | .premises, F => PremOk F
  | .search, F => SearchOk F
  | .ratchet, F => RatchetOk F

/-- **When the land passes** (section 7, the right side of `pass_iff`): every source is present or no rule is
enforced, and every enforced rule holds.
$$\operatorname{Pass}(s, F) \iff (\operatorname{Present}(F) \lor \forall r \in \mathrm{rules},\ \lnot\operatorname{en}(s, F.\mathit{lf}, r)) \land \forall r \in \mathrm{rules},\ \operatorname{en}(s, F.\mathit{lf}, r) \Rightarrow \operatorname{Ok}(r)(F)$$ -/
abbrev PassSpec (s : Stage) (F : Facts) : Prop :=
  (AllPresent F ∨ ∀ r ∈ Rule.all, enforced s F.leanFirst r = false) ∧
    ∀ r ∈ Rule.all, enforced s F.leanFirst r = true → RuleOk r F

/-- The reasons of a refusal; none for pass and pending.
$$\operatorname{refusals}(\mathrm{refuse}(\rho s)) = \rho s,\quad \operatorname{refusals}(\mathrm{pass}) = \operatorname{refusals}(\mathrm{pending}(M)) = [\,]$$ -/
def Verdict.refusals : Verdict → List Reason
  | .refuse rs => rs
  | _ => []

/-- The missing sources of a pending verdict; none otherwise.
$$\operatorname{pendingOn}(\mathrm{pending}(M)) = M,\quad \operatorname{pendingOn}(\mathrm{pass}) = \operatorname{pendingOn}(\mathrm{refuse}(\rho s)) = [\,]$$ -/
def Verdict.pendingOn : Verdict → List Missing
  | .pending ms => ms
  | _ => []

/-- Is the verdict pending?
$$\operatorname{isPending}(v) \iff \exists M,\ v = \mathrm{pending}(M)$$ -/
def Verdict.isPending : Verdict → Bool
  | .pending _ => true
  | _ => false

/-! ## The properties (section 7) -/

/-- **`pass_iff`**: the gate passes exactly when `PassSpec` holds.
$$\operatorname{PassIff}(g) :\iff \forall s\, F,\ g(s, F) = \mathrm{pass} \iff \operatorname{Pass}(s, F)$$
The gate passes exactly when the sources are present (or nothing is enforced) and every enforced rule holds. -/
def PassIff : Property Gate := fun g => ∀ s F, g s F = .pass ↔ PassSpec s F

/-- **`land_refuses_unproved`** (theorem 1): with rule 1 enforced and every source present, a property that no
theorem discharges is a refusal reason.
$$\operatorname{RefusesUnproved}(g) :\iff \forall s\, F,\ \operatorname{en}(s, F.\mathit{lf}, \mathrm{props}) \land \operatorname{Present}(F) \Rightarrow \forall P \in F.\mathit{props},\ \lnot(\exists t \in F.\mathit{thms},\ \operatorname{Dis}(F, t, P)) \Rightarrow \mathrm{unproved}(P.\mathit{name}) \in \operatorname{refusals}(g(s, F))$$
An unproved property refuses the land, naming the property. -/
def RefusesUnproved : Property Gate := fun g =>
  ∀ s F, enforced s F.leanFirst .props = true → AllPresent F →
    ∀ P ∈ F.props, ¬ (∃ t ∈ F.thms, Discharges F t P) → Reason.unproved P.name ∈ (g s F).refusals

/-- **`stale_review_refuses`** (theorem 2): with rule 1 enforced and every source present, a property that a role has
not signed at its current hashes (or has disagreed with) is a refusal reason.
$$\operatorname{StaleReviewRefuses}(g) :\iff \forall s\, F,\ \operatorname{en}(s, F.\mathit{lf}, \mathrm{props}) \land \operatorname{Present}(F) \Rightarrow \forall P \in F.\mathit{props},\ \forall r \in [\mathrm{math}, \mathrm{adversary}],\ \lnot\operatorname{Signed}(F, P, r) \Rightarrow \mathrm{unsigned}(P.\mathit{name}, r) \in \operatorname{refusals}(g(s, F))$$
A missing, stale or disagreeing review refuses the land, naming the property and the role. -/
def StaleReviewRefuses : Property Gate := fun g =>
  ∀ s F, enforced s F.leanFirst .props = true → AllPresent F →
    ∀ P ∈ F.props, ∀ r ∈ [Role.math, Role.adversary], ¬ Signed F P r →
      Reason.unsigned P.name r ∈ (g s F).refusals

/-- **`land_refuses_unreached`** (rule 1d, the stub case): with rule 1 enforced and every fact present, a property
that some theorem discharges, but only of implementations not reached from the wire, is a refusal reason, whatever
other reached definitions exist.
$$\operatorname{RefusesUnreached}(g) :\iff \forall s\, F,\ \operatorname{en}(s, F.\mathit{lf}, \mathrm{props}) \land \operatorname{Present}(F) \Rightarrow \forall P \in F.\mathit{props},\ (\exists t \in F.\mathit{thms},\ \operatorname{Dis}(F, t, P)) \land (\forall t \in F.\mathit{thms},\ \operatorname{Dis}(F, t, P) \Rightarrow t.\mathit{rw} \ne \mathrm{some}(\mathrm{true})) \Rightarrow \mathrm{unreached}(P.\mathit{name}) \in \operatorname{refusals}(g(s, F))$$
A property proved only of a stub refuses the land. -/
def RefusesUnreached : Property Gate := fun g =>
  ∀ s F, enforced s F.leanFirst .props = true → AllPresent F →
    ∀ P ∈ F.props, (∃ t ∈ F.thms, Discharges F t P) → (∀ t ∈ F.thms, Discharges F t P → t.reachFromWire ≠ some true) →
      Reason.unreached P.name ∈ (g s F).refusals

/-- **`no_props_refuses`** (theorem 3, the non-vacuity of the gate): with rule 1 enforced and every fact present, a
task with a decision write (`DecisionWrite`, the allowlist rule, not the gate's own test) and no property is refused,
naming a decision write.
$$\operatorname{NoPropsRefuses}(g) :\iff \forall s\, F,\ \operatorname{en}(s, F.\mathit{lf}, \mathrm{props}) \land \operatorname{Present}(F) \land \operatorname{Dec}(F) \land F.\mathit{props} = [\,] \Rightarrow \exists w \in F.\mathit{writes},\ \operatorname{DecW}(w) \land \mathrm{noProps}(w) \in \operatorname{refusals}(g(s, F))$$
Writing decision code without stating a property refuses the land. -/
def NoPropsRefuses : Property Gate := fun g =>
  ∀ s F, enforced s F.leanFirst .props = true → AllPresent F → Decides F → F.props = [] →
    ∃ w ∈ F.writes, DecisionWrite w ∧ Reason.noProps w ∈ (g s F).refusals

/-- **`mutant_kills_or_refuse`** (theorem 4): with rule 2 enforced and every source present, a new theorem without a
kill at its hash that is not exempt is a refusal reason.
$$\operatorname{MutantKillsOrRefuse}(g) :\iff \forall s\, F,\ \operatorname{en}(s, F.\mathit{lf}, \mathrm{kills}) \land \operatorname{Present}(F) \Rightarrow \forall t \in F.\mathit{thms},\ \operatorname{New}(F, t) \land \lnot\operatorname{KillAt}(F, t.\mathit{name}, t.\mathit{hash}) \land \lnot\operatorname{Exempt}(F, t) \Rightarrow \mathrm{noKill}(t.\mathit{name}) \in \operatorname{refusals}(g(s, F))$$
A new theorem that no mutant kills refuses the land. -/
def MutantKillsOrRefuse : Property Gate := fun g =>
  ∀ s F, enforced s F.leanFirst .kills = true → AllPresent F →
    ∀ t ∈ F.thms, New F t → ¬ KillAt F t.name t.hash → ¬ Exempt F t → Reason.noKill t.name ∈ (g s F).refusals

/-- **`exempt_not_discharge`** (theorem 5), over the type of `discharges`: an exempt theorem discharges no property.
$$\operatorname{ExemptNotDischarge}(d) :\iff \forall F\, t\, P,\ \operatorname{Exempt}(F, t) \Rightarrow d(F, t, P) = \mathrm{false}$$
A lemma, data lint or kill witness can never be the proof of a property. -/
def ExemptNotDischarge : Property (Facts → ThmFact → PropFact → Bool) := fun d =>
  ∀ F t P, Exempt F t → d F t P = false

/-- **`hidden_premise_refuses`** (theorem 6): with rule 4 enforced and every source present, a new theorem that
reaches a registry row's carrier without assuming that premise is a refusal reason.
$$\operatorname{HiddenPremiseRefuses}(g) :\iff \forall s\, F,\ \operatorname{en}(s, F.\mathit{lf}, \mathrm{premises}) \land \operatorname{Present}(F) \Rightarrow \forall t \in F.\mathit{thms},\ \operatorname{New}(F, t) \Rightarrow \forall \rho \in F.\mathit{registry},\ (\exists c \in \rho.\mathit{carriers},\ c \in t.\mathit{reach}) \land \rho.\mathit{id} \notin t.\mathit{assumes} \Rightarrow \mathrm{hidden}(t.\mathit{name}, \rho.\mathit{id}) \in \operatorname{refusals}(g(s, F))$$
A premise hidden inside a definition the proof reaches refuses the land. -/
def HiddenPremiseRefuses : Property Gate := fun g =>
  ∀ s F, enforced s F.leanFirst .premises = true → AllPresent F →
    ∀ t ∈ F.thms, New F t → ∀ r ∈ F.registry, (∃ c ∈ r.carriers, c ∈ t.reach) → r.id ∉ t.assumes →
      Reason.hidden t.name r.id ∈ (g s F).refusals

/-- **`unregistered_premise_refuses`** (rule 4c): with rule 4 enforced and every source present, a new theorem that
assumes an id with no registry row is a refusal reason.
$$\operatorname{UnregisteredPremiseRefuses}(g) :\iff \forall s\, F,\ \operatorname{en}(s, F.\mathit{lf}, \mathrm{premises}) \land \operatorname{Present}(F) \Rightarrow \forall t \in F.\mathit{thms},\ \operatorname{New}(F, t) \Rightarrow \forall p \in t.\mathit{assumes},\ \lnot(\exists \rho \in F.\mathit{registry},\ \rho.\mathit{id} = p) \Rightarrow \mathrm{unregistered}(t.\mathit{name}, p) \in \operatorname{refusals}(g(s, F))$$
A premise id that is not in the registry refuses the land. -/
def UnregisteredPremiseRefuses : Property Gate := fun g =>
  ∀ s F, enforced s F.leanFirst .premises = true → AllPresent F →
    ∀ t ∈ F.thms, New F t → ∀ p ∈ t.assumes, ¬ (∃ r ∈ F.registry, r.id = p) →
      Reason.unregistered t.name p ∈ (g s F).refusals

/-- **`refuted_premise_refuses`** (theorem 7): with rule 4 enforced and every source present, a new theorem that
assumes a refuted premise is a refusal reason.
$$\operatorname{RefutedPremiseRefuses}(g) :\iff \forall s\, F,\ \operatorname{en}(s, F.\mathit{lf}, \mathrm{premises}) \land \operatorname{Present}(F) \Rightarrow \forall t \in F.\mathit{thms},\ \operatorname{New}(F, t) \Rightarrow \forall p \in t.\mathit{assumes},\ \operatorname{StatusIs}(F, p, \mathrm{refuted}) \Rightarrow \mathrm{refuted}(t.\mathit{name}, p) \in \operatorname{refusals}(g(s, F))$$
A proof that rests on a refuted premise refuses the land. -/
def RefutedPremiseRefuses : Property Gate := fun g =>
  ∀ s F, enforced s F.leanFirst .premises = true → AllPresent F →
    ∀ t ∈ F.thms, New F t → ∀ p ∈ t.assumes, StatusIs F p .refuted →
      Reason.refuted t.name p ∈ (g s F).refusals

/-- **`untwinned_branch_refuses`** (theorem 8): with rule 3 enforced and every source present, a new data branch with
no mark or a refused glue mark is a refusal reason.
$$\operatorname{UntwinnedBranchRefuses}(g) :\iff \forall s\, F,\ \operatorname{en}(s, F.\mathit{lf}, \mathrm{twins}) \land \operatorname{Present}(F) \Rightarrow \forall b \in F.\mathit{branches},\ b.\mathit{mark} \in \{\bot, \mathrm{glue}_{bad}\} \Rightarrow \mathrm{branch}(b.\mathit{file}, b.\mathit{line}, b.\mathit{mark}) \in \operatorname{refusals}(g(s, F))$$
A TS decision branch with neither a Lean op, a twin nor accepted glue refuses the land. -/
def UntwinnedBranchRefuses : Property Gate := fun g =>
  ∀ s F, enforced s F.leanFirst .twins = true → AllPresent F →
    ∀ b ∈ F.branches, (b.mark = .none ∨ b.mark = .glueBad) → Reason.branch b.file b.line b.mark ∈ (g s F).refusals

/-- **`proof_before_search_refuses`** (theorem 9): with rule 5 enforced and every source present, a property whose
search guards are not a strict git ancestor of its proof is a refusal reason.
$$\operatorname{ProofBeforeSearchRefuses}(g) :\iff \forall s\, F,\ \operatorname{en}(s, F.\mathit{lf}, \mathrm{search}) \land \operatorname{Present}(F) \Rightarrow \forall P \in F.\mathit{props},\ \lnot\operatorname{First}(F, P) \Rightarrow \mathrm{searchOrder}(P.\mathit{name}) \in \operatorname{refusals}(g(s, F))$$
A proof committed before (or without) its edge-case search refuses the land. -/
def ProofBeforeSearchRefuses : Property Gate := fun g =>
  ∀ s F, enforced s F.leanFirst .search = true → AllPresent F →
    ∀ P ∈ F.props, ¬ SearchFirst F P → Reason.searchOrder P.name ∈ (g s F).refusals

/-- **`missing_fact_not_pass`** (theorem 10, the verdict half): when some rule is enforced and a fact is missing, the
verdict is pending on exactly the missing facts: each absent source, an unknown reach, exemptions not read at main.
$$\operatorname{MissingFactPending}(g) :\iff \forall s\, F,\ (\exists r \in \mathrm{rules},\ \operatorname{en}(s, F.\mathit{lf}, r)) \land \lnot\operatorname{Present}(F) \Rightarrow \operatorname{isPending}(g(s, F)) \land \bigwedge_{x \in \{\mathit{mathview}, \mathit{kills}, \mathit{tsLint}\}} (F.\mathit{present}.x = \mathrm{false} \iff x \in \operatorname{pendingOn}(g(s, F))) \land (\lnot\operatorname{ReachKnown}(F) \iff \mathrm{reach} \in \operatorname{pendingOn}(g(s, F))) \land (F.\mathit{exemptAt} \ne \mathrm{some}(F.\mathit{mainAt}) \iff \mathrm{exempt} \in \operatorname{pendingOn}(g(s, F)))$$
A missing fact fails closed as pending, never as a vacuous pass. -/
def MissingFactPending : Property Gate := fun g =>
  ∀ s F, (∃ r ∈ Rule.all, enforced s F.leanFirst r = true) → ¬ AllPresent F →
    (g s F).isPending = true ∧
    (F.present.mathview = false ↔ Missing.mathview ∈ (g s F).pendingOn) ∧
    (F.present.kills = false ↔ Missing.kills ∈ (g s F).pendingOn) ∧
    (F.present.tsLint = false ↔ Missing.tsLint ∈ (g s F).pendingOn) ∧
    (¬ ReachKnown F ↔ Missing.reach ∈ (g s F).pendingOn) ∧
    (F.exemptAt ≠ some F.mainAt ↔ Missing.exempt ∈ (g s F).pendingOn)

/-- **`missing_fact_not_pass`** (theorem 10, the exit half), over the renderer: when some rule is enforced and a
fact is missing (`Present` fails), the output is pending with exit code 75.
$$\operatorname{PendingExit}(o) :\iff \forall s\, F,\ (\exists r \in \mathrm{rules},\ \operatorname{en}(s, F.\mathit{lf}, r)) \land \lnot\operatorname{Present}(F) \Rightarrow o(s, F).\mathit{kind} = \mathrm{pending} \land o(s, F).\mathit{exit} = 75$$
A missing fact source exits 75, the retry code. -/
def PendingExit : Property Render := fun o =>
  ∀ s F, (∃ r ∈ Rule.all, enforced s F.leanFirst r = true) → ¬ AllPresent F →
    (o s F).kind = .pending ∧ (o s F).exit = 75

/-- **`one_verdict`** (theorem 11): the output has exactly one verdict line, and it is the last line.
$$\operatorname{OneVerdict}(o) :\iff \forall s\, F,\ |[\ell \in o(s, F).\mathit{lines} : \operatorname{isV}(\ell)]| = 1 \land \operatorname{map}(\operatorname{isV}, \operatorname{last}(o(s, F).\mathit{lines})) = \mathrm{some}(\mathrm{true})$$
Every run prints one VERDICT line, as its last line. -/
def OneVerdict : Property Render := fun o =>
  ∀ s F, verdictCount (o s F).lines = 1 ∧ (o s F).lines.getLast?.map isVerdict = some true

/-- **`exit_zero_iff`** (theorem 11): the exit code is 0 exactly when `PassSpec` holds.
$$\operatorname{ExitZeroIff}(o) :\iff \forall s\, F,\ o(s, F).\mathit{exit} = 0 \iff \operatorname{Pass}(s, F)$$
The check exits 0 exactly when the land passes the spec. -/
def ExitZeroIff : Property Render := fun o => ∀ s F, (o s F).exit = 0 ↔ PassSpec s F

/-- **`gate_mono`** (theorem 12): adding evidence (kill rows, agreeing signoffs, marks on unmarked branches, present
sources) never turns a pass into anything else.
$$\operatorname{GateMono}(g) :\iff \forall s\, F\, e,\ g(s, F) = \mathrm{pass} \Rightarrow g(s, F \oplus e) = \mathrm{pass}$$
More evidence never refuses a land that passed. -/
def GateMono : Property Gate := fun g => ∀ s F e, g s F = .pass → g s (F.add e) = .pass

/-- **`stage_mono`** (theorem 13): a land that passes at a later stage passes at every earlier stage.
$$\operatorname{StageMono}(g) :\iff \forall s\, s'\, F,\ \operatorname{rank}(s) \le \operatorname{rank}(s') \land g(s', F) = \mathrm{pass} \Rightarrow g(s, F) = \mathrm{pass}$$
A stricter stage refuses a superset. -/
def StageMono : Property Gate := fun g =>
  ∀ s s' F, s.rank ≤ s'.rank → g s' F = .pass → g s F = .pass

/-- **`baseline_not_new`** (theorem 14), over the type of `isNew`: a theorem whose name has baseline entries, all with
its hash, is not new.
$$\operatorname{BaselineNotNew}(\nu) :\iff \forall F\, t,\ (t.\mathit{name}, t.\mathit{hash}) \in F.\mathit{baseline} \land (\forall (n, h) \in F.\mathit{baseline},\ n = t.\mathit{name} \Rightarrow h = t.\mathit{hash}) \Rightarrow \nu(F, t) = \mathrm{false}$$
An unchanged old theorem is not gated. -/
def BaselineNotNew : Property (Facts → ThmFact → Bool) := fun ν =>
  ∀ F t, (t.name, t.hash) ∈ F.baseline → (∀ p ∈ F.baseline, p.1 = t.name → p.2 = t.hash) → ν F t = false

/-- **`changed_is_new`** (theorem 14): a theorem whose (name, hash) pair is not in the baseline is new.
$$\operatorname{ChangedIsNew}(\nu) :\iff \forall F\, t,\ (t.\mathit{name}, t.\mathit{hash}) \notin F.\mathit{baseline} \Rightarrow \nu(F, t) = \mathrm{true}$$
An edit to an old theorem's statement is gated like a new theorem. -/
def ChangedIsNew : Property (Facts → ThmFact → Bool) := fun ν =>
  ∀ F t, (t.name, t.hash) ∉ F.baseline → ν F t = true

/-- **`ratchet_refuses_growth`** (theorem 15): with the ratchet enforced and every source present, a legacy count
that grew is a refusal reason.
$$\operatorname{RatchetRefusesGrowth}(g) :\iff \forall s\, F,\ \operatorname{en}(s, F.\mathit{lf}, \mathrm{ratchet}) \land \operatorname{Present}(F) \land F.\mathit{legacyMain} < F.\mathit{legacyHead} \Rightarrow \mathrm{growth}(F.\mathit{legacyMain}, F.\mathit{legacyHead}) \in \operatorname{refusals}(g(s, F))$$
The grandfathered gap count may only shrink. -/
def RatchetRefusesGrowth : Property Gate := fun g =>
  ∀ s F, enforced s F.leanFirst .ratchet = true → AllPresent F → F.legacyMain < F.legacyHead →
    Reason.growth F.legacyMain F.legacyHead ∈ (g s F).refusals

/-- **`shadow_passes`** (section 8, stage 0): in the shadow stage every land passes.
$$\operatorname{ShadowPasses}(g) :\iff \forall F,\ g(\mathrm{shadow}, F) = \mathrm{pass}$$
The shadow stage never blocks a land. -/
def ShadowPasses : Property Gate := fun g => ∀ F, g .shadow F = .pass

/-- **`no_newline`**: no output line contains a line break, whatever the facts' strings contain.
$$\operatorname{NoNewline}(o) :\iff \forall s\, F,\ \forall \ell \in o(s, F).\mathit{lines},\ \texttt{\textbackslash n} \notin \ell \land \texttt{\textbackslash r} \notin \ell$$
A fact cannot forge an extra stdout line, such as a second VERDICT. -/
def NoNewline : Property Render := fun o =>
  ∀ s F, ∀ l ∈ (o s F).lines, '\n' ∉ l.toList ∧ '\r' ∉ l.toList

end Fw.Ops.LeanFirst
