import Fw.Search
import Fw.Ops.LeanFirstDecision

/-!
# Edge-case search for the lean-first gate (before the proofs)

Task `lfg-spec`, rule 5 applied to the gate itself: every property of `Fw.Ops.LeanFirstProps` gets a pointwise check
`q<P>` (the property is exactly "the check passes everywhere", `q<P>_iff`), an `Enum` instance over its inputs, and a
bounded search theorem (`<P>_iff_search`, from `Fw.Search.prop_iff_searchUpTo`). The guards run the search at bound 0
for the real implementation (no counterexample); `FwTest/Mutants/LeanFirst/` runs it for each mutant (a
counterexample exists) and proves each kill in kernel from one found point.

* `Enum Facts` lists, at every bound, the **fault grid** first: a clean `base` (which passes at every stage) with up
  to two of the faults in `Fault` applied (missing proof, a proof of an unreached stub, stale review, missing kill,
  hidden premise, unmarked branch, proof before search, legacy growth, missing source, unknown reach, exemptions read
  off main, a directory glob over decision code, a line break in a name, and more), with and without the
  `leanFirst` flag, and then every facts value whose lists are at most `n` long over strings of at most `n` characters
  (`Enum.ofSurj`, so the enumeration is complete).
* `Enum Evidence` lists evidence that repairs grid faults first, `Enum ThmFact` and `Enum PropFact` the grid's
  theorems and properties first.
-/
namespace Fw.Ops.LeanFirst

open Fw.Search Fw.Spec.Props

universe u v

/-! ## Enumeration helpers -/

/-- **Enumerate through a surjection**: list $f(b)$ for every $b$ listed at the bound.
$$\mathrm{enum}_\alpha(n) = \operatorname{map}(f, \mathrm{enum}_\beta(n)),\quad \text{given } \forall a,\ f(g(a)) = a$$ -/
@[reducible] def Enum.ofSurj {α : Type u} {β : Type v} [Enum β] (f : β → α) (g : α → β) (h : ∀ a, f (g a) = a) :
    Enum α where
  enum n := (Enum.enum n).map f
  mono hmn hx := by
    obtain ⟨b, hb, rfl⟩ := List.mem_map.mp hx
    exact List.mem_map.mpr ⟨b, Enum.mono hmn hb, rfl⟩
  complete a := by
    obtain ⟨n, hn⟩ := Enum.complete (g a)
    exact ⟨n, List.mem_map.mpr ⟨g a, hn, h a⟩⟩

/-- **Seeds first**: list the seeds at every bound, then the base enumeration.
$$\mathrm{enum}'(n) = \mathit{seeds} \mathbin{+\!\!+} \mathrm{enum}(n)$$ -/
@[reducible] def Enum.withSeeds {α : Type u} (seeds : List α) (E : Enum α) : Enum α where
  enum n := seeds ++ E.enum n
  mono hmn hx := by
    rcases List.mem_append.mp hx with h | h
    · exact List.mem_append.mpr (Or.inl h)
    · exact List.mem_append.mpr (Or.inr (E.mono hmn h))
  complete a := by
    obtain ⟨n, hn⟩ := E.complete a
    exact ⟨n, List.mem_append.mpr (Or.inr hn)⟩

/-- Characters by code point: the characters with code at most $n$ (invalid codes map to `\0`).
$$\mathrm{enum}_{\mathrm{Char}}(n) = [\operatorname{chr}(i) : i \le n]$$ -/
instance instEnumChar : Enum Char := Enum.ofSurj (β := Nat) Char.ofNat Char.toNat Char.ofNat_toNat

/-- Strings: the strings of at most $n$ characters with codes at most $n$.
$$\mathrm{enum}_{\mathrm{String}}(n) = \operatorname{map}(\operatorname{ofList}, \mathrm{enum}_{\mathrm{List}(\mathrm{Char})}(n))$$ -/
instance instEnumString : Enum String :=
  Enum.ofSurj (β := List Char) String.ofList String.toList (fun _ => String.ofList_toList)

/-- The roles. $$\mathrm{all} = [\mathrm{math}, \mathrm{adversary}]$$ -/
instance : EnumAll Role where
  all := [.math, .adversary]
  complete x := by cases x <;> simp

/-- The theorem classes. $$\mathrm{all} = [\mathrm{general}, \mathrm{data}, \mathrm{kill}]$$ -/
instance : EnumAll ThmKind where
  all := [.general, .data, .kill]
  complete x := by cases x <;> simp

/-- The marks. $$\mathrm{all} = [\bot, \mathrm{op}, \mathrm{twin}, \mathrm{glue}_{ok}, \mathrm{glue}_{bad}]$$ -/
instance : EnumAll Mark where
  all := [.none, .op, .twin, .glueOk, .glueBad]
  complete x := by cases x <;> simp

/-- The premise statuses. $$\mathrm{all} = [\mathrm{measured}, \mathrm{untested}, \mathrm{refuted}, \mathrm{unmeasurable}]$$ -/
instance : EnumAll Status where
  all := [.measured, .untested, .refuted, .unmeasurable]
  complete x := by cases x <;> simp

/-- The stages. $$\mathrm{all} = [0, 1, 2, 3]$$ -/
instance : EnumAll Stage where
  all := [.shadow, .newTasks, .allNew, .ratchet]
  complete x := by cases x <;> simp

/-- Signoff rows from their fields. $$\mathrm{enum}(n) = \operatorname{map}(\mathrm{mk}, \mathrm{enum}_{\mathrm{String}^3 \times \mathrm{Role} \times \mathbb B}(n))$$ -/
instance : Enum Signoff :=
  Enum.ofSurj (β := String × String × String × Role × Bool) (fun ⟨a, b, c, r, x⟩ => ⟨a, b, c, r, x⟩)
    (fun s => (s.decl, s.stmtHash, s.docHash, s.role, s.agree)) (fun _ => rfl)

/-- Kill rows from their fields. $$\mathrm{enum}(n) = \operatorname{map}(\mathrm{mk}, \mathrm{enum}_{\mathrm{String}^2}(n))$$ -/
instance : Enum KillRow :=
  Enum.ofSurj (β := String × String) (fun ⟨a, b⟩ => ⟨a, b⟩) (fun k => (k.target, k.hash)) (fun _ => rfl)

/-- Branches from their fields. $$\mathrm{enum}(n) = \operatorname{map}(\mathrm{mk}, \mathrm{enum}_{\mathrm{String} \times \mathbb N \times \mathrm{Mark}}(n))$$ -/
instance : Enum Branch :=
  Enum.ofSurj (β := String × Nat × Mark) (fun ⟨a, b, c⟩ => ⟨a, b, c⟩) (fun b => (b.file, b.line, b.mark))
    (fun _ => rfl)

/-- Registry rows from their fields. $$\mathrm{enum}(n) = \operatorname{map}(\mathrm{mk}, \mathrm{enum}_{\mathrm{String} \times \mathrm{Status} \times \mathrm{List}(\mathrm{String})}(n))$$ -/
instance : Enum PremRow :=
  Enum.ofSurj (β := String × Status × List String) (fun ⟨a, b, c⟩ => ⟨a, b, c⟩)
    (fun r => (r.id, r.status, r.carriers)) (fun _ => rfl)

/-- Source flags from their fields. $$\mathrm{enum}(n) = \operatorname{map}(\mathrm{mk}, \mathrm{enum}_{\mathbb B^3}(n))$$ -/
instance : Enum Present :=
  Enum.ofSurj (β := Bool × Bool × Bool) (fun ⟨a, b, c⟩ => ⟨a, b, c⟩) (fun p => (p.mathview, p.kills, p.tsLint))
    (fun _ => rfl)

/-! ## The fault grid -/

/-- The clean property of the grid.
$$P_0 = \{\mathit{name}{=}\texttt{P},\ \mathit{stmt}{=}\texttt{hP},\ \mathit{doc}{=}\texttt{dP},\ \mathit{assumes}{=}[\,],\ \mathit{searchAt}{=}\texttt{c1},\ \mathit{proofAt}{=}\texttt{c2}\}$$ -/
def baseProp : PropFact :=
  { name := "P", stmtHash := "hP", docHash := "dP", assumes := [], searchAt := some "c1", proofAt := some "c2" }

/-- The clean proof of `P` in the grid, of the implementation `impl`, which the wire reaches.
$$T_0 = \{\mathit{name}{=}\texttt{P\_impl},\ \mathit{hash}{=}\texttt{hT},\ \mathit{kind}{=}\mathrm{general},\ \mathit{proves}{=}\texttt{P},\ \mathit{implArg}{=}\texttt{impl},\ \mathit{rw}{=}\mathrm{true},\ \mathit{axiomsOk},\ \mathit{usedBy}{=}[\,],\ \mathit{reach}{=}[\texttt{impl}],\ \mathit{assumes}{=}[\,]\}$$ -/
def baseThm : ThmFact :=
  { name := "P_impl", hash := "hT", kind := .general, proves := some "P", implArg := some "impl",
    reachFromWire := some true, axiomsOk := true, usedBy := [], reach := ["impl"], assumes := [] }

/-- The kill witness of `P` in the grid (exempt by class).
$$K_0 = \{\mathit{name}{=}\texttt{P\_rejects\_m},\ \mathit{hash}{=}\texttt{hK},\ \mathit{kind}{=}\mathrm{kill},\ \mathit{proves}{=}\mathit{implArg}{=}\mathit{rw}{=}\mathrm{none},\ \mathit{axiomsOk},\ \mathit{usedBy}{=}\mathit{reach}{=}\mathit{assumes}{=}[\,]\}$$ -/
def killThm : ThmFact :=
  { name := "P_rejects_m", hash := "hK", kind := .kill, proves := none, implArg := none, reachFromWire := none,
    axiomsOk := true, usedBy := [], reach := [], assumes := [] }

/-- A lemma that `P_impl` uses (no kill of its own, so exempt as a lemma).
$$L_0 = \{\mathit{name}{=}\texttt{L},\ \mathit{hash}{=}\texttt{hL},\ \mathit{kind}{=}\mathrm{general},\ \mathit{proves}{=}\mathit{implArg}{=}\mathit{rw}{=}\mathrm{none},\ \mathit{axiomsOk},\ \mathit{usedBy}{=}[\texttt{P\_impl}],\ \mathit{reach}{=}\mathit{assumes}{=}[\,]\}$$ -/
def lemmaThm : ThmFact :=
  { name := "L", hash := "hL", kind := .general, proves := none, implArg := none, reachFromWire := none,
    axiomsOk := true, usedBy := ["P_impl"], reach := [], assumes := [] }

/-- A baseline theorem at its baseline hash (not new).
$$O = L_0[\mathit{name}{=}\texttt{Old},\ \mathit{hash}{=}\texttt{hO},\ \mathit{usedBy}{=}[\,]]$$ -/
def oldThmFact : ThmFact := { lemmaThm with name := "Old", hash := "hO", usedBy := [] }

/-- A baseline theorem whose statement changed (new).
$$O' = L_0[\mathit{name}{=}\texttt{Old},\ \mathit{hash}{=}\texttt{hO2},\ \mathit{usedBy}{=}[\,]]$$ -/
def changedThmFact : ThmFact := { lemmaThm with name := "Old", hash := "hO2", usedBy := [] }

/-- **The clean facts**: one decision write, one property proved of a reached implementation, signed by both roles
and killed, its proof killed, one marked branch, a three-row registry (measured, untested, refuted), one baseline
theorem, search before proof, equal legacy counts, every source present, exemptions read at main `m`. It passes at
every stage.
$$\begin{aligned} F_0 = \{&\mathit{leanFirst}{=}\top,\ \mathit{writes}{=}[\texttt{lean/Fw/Ops/X.lean}, \texttt{docs/x.md}],\ \mathit{props}{=}[P_0],\ \mathit{thms}{=}[T_0, K_0],\ \mathit{kills}{=}[(\texttt{P\_impl},\texttt{hT}),(\texttt{P},\texttt{hP})], \\ &\mathit{signoffs}{=}[(\texttt{P},\texttt{hP},\texttt{dP},\mathrm{math},\top),(\texttt{P},\texttt{hP},\texttt{dP},\mathrm{adversary},\top)],\ \mathit{branches}{=}[(\texttt{apps/x/src/a.ts},3,\mathrm{op})], \\ &\mathit{registry}{=}[(\texttt{pm},\mathrm{measured},[\texttt{cM}]),(\texttt{pu},\mathrm{untested},[\texttt{cU}]),(\texttt{pr},\mathrm{refuted},[\texttt{cR}])],\ \mathit{baseline}{=}[(\texttt{Old},\texttt{hO})],\ \mathit{ancestry}{=}[(\texttt{c1},\texttt{c2})], \\ &\mathit{legacyMain}{=}\mathit{legacyHead}{=}2,\ \mathit{present}{=}(\top,\top,\top),\ \mathit{mainAt}{=}\texttt{m},\ \mathit{exemptAt}{=}\mathrm{some}(\texttt{m})\} \end{aligned}$$ -/
def base : Facts :=
  { leanFirst := true, writes := ["lean/Fw/Ops/X.lean", "docs/x.md"], props := [baseProp],
    thms := [baseThm, killThm],
    kills := [⟨"P_impl", "hT"⟩, ⟨"P", "hP"⟩],
    signoffs := [⟨"P", "hP", "dP", .math, true⟩, ⟨"P", "hP", "dP", .adversary, true⟩],
    branches := [⟨"apps/x/src/a.ts", 3, .op⟩],
    registry := [⟨"pm", .measured, ["cM"]⟩, ⟨"pu", .untested, ["cU"]⟩, ⟨"pr", .refuted, ["cR"]⟩],
    baseline := [("Old", "hO")], ancestry := [("c1", "c2")], legacyMain := 2, legacyHead := 2,
    present := ⟨true, true, true⟩, mainAt := "m", exemptAt := some "m" }

/-- One edit of the clean facts.
$$\begin{aligned} \mathrm{Fault} = \{&\mathrm{noProps}, \mathrm{noDecision}, \mathrm{unproved}, \mathrm{badAxioms}, \mathrm{stub}, \mathrm{noImpl}, \mathrm{unsignedMath}, \mathrm{unsignedAdv}, \mathrm{disagreeAdv}, \mathrm{staleDoc}, \\ &\mathrm{unkilledProp}, \mathrm{noKill}, \mathrm{lemma}, \mathrm{lemmaProves}, \mathrm{dataProof}, \mathrm{oldThm}, \mathrm{changedOld}, \mathrm{unmarked}, \mathrm{glueBad}, \mathrm{glueOk}, \\ &\mathrm{hidden}, \mathrm{assumedOk}, \mathrm{unregistered}, \mathrm{refuted}, \mathrm{untestedHidden}, \mathrm{untestedShared}, \mathrm{searchOrder}, \mathrm{searchMissing}, \\ &\mathrm{ratchet}, \mathrm{ratchetDown}, \mathrm{missingMathview}, \mathrm{missingKills}, \mathrm{missingLint}, \mathrm{notLeanFirst}, \mathrm{newlineName}, \mathrm{dupSignoff}, \\ &\mathrm{reachUnknown}, \mathrm{exemptBranch}, \mathrm{dirGlob}, \mathrm{docsGlob}\},\quad |\mathrm{Fault}| = 40 \end{aligned}$$ -/
inductive Fault where
  | noProps | noDecision | unproved | badAxioms | stub | noImpl | unsignedMath | unsignedAdv | disagreeAdv | staleDoc
  | unkilledProp | noKill | lemma | lemmaProves | dataProof | oldThm | changedOld | unmarked | glueBad | glueOk
  | hidden | assumedOk | unregistered | refuted | untestedHidden | untestedShared | searchOrder | searchMissing
  | ratchet | ratchetDown | missingMathview | missingKills | missingLint | notLeanFirst | newlineName | dupSignoff
  | reachUnknown | exemptBranch | dirGlob | docsGlob
deriving DecidableEq, Repr

/-- Every fault, in declaration order.
$$\mathrm{Fault.all} = [\mathrm{noProps}, \mathrm{noDecision}, \ldots, \mathrm{docsGlob}],\quad |\mathrm{Fault.all}| = 40$$ -/
def Fault.all : List Fault :=
  [.noProps, .noDecision, .unproved, .badAxioms, .stub, .noImpl, .unsignedMath, .unsignedAdv, .disagreeAdv, .staleDoc,
   .unkilledProp, .noKill, .lemma, .lemmaProves, .dataProof, .oldThm, .changedOld, .unmarked, .glueBad, .glueOk,
   .hidden, .assumedOk, .unregistered, .refuted, .untestedHidden, .untestedShared, .searchOrder, .searchMissing,
   .ratchet, .ratchetDown, .missingMathview, .missingKills, .missingLint, .notLeanFirst, .newlineName, .dupSignoff,
   .reachUnknown, .exemptBranch, .dirGlob, .docsGlob]

/-- Edit the proof `P_impl` wherever it is in the theorem list.
$$\forall F\, f,\ \operatorname{mapImpl}(F, f) = F[\mathit{thms} := \operatorname{map}(\lambda t.\ \text{if } t.\mathit{name} = \texttt{P\_impl} \text{ then } f(t) \text{ else } t,\ F.\mathit{thms})]$$ -/
def mapImpl (F : Facts) (f : ThmFact → ThmFact) : Facts :=
  { F with thms := F.thms.map fun t => if t.name = "P_impl" then f t else t }

/-- Edit the property `P` wherever it is in the property list.
$$\forall F\, f,\ \operatorname{mapProp}(F, f) = F[\mathit{props} := \operatorname{map}(\lambda P.\ \text{if } P.\mathit{name} = \texttt{P} \text{ then } f(P) \text{ else } P,\ F.\mathit{props})]$$ -/
def mapProp (F : Facts) (f : PropFact → PropFact) : Facts :=
  { F with props := F.props.map fun P => if P.name = "P" then f P else P }

/-- Apply one fault: each constructor is one field edit (drop, append, or flip), listed case by case below. `stub`
re-targets the proof at an unreached `stub` and adds a reached lemma; `dirGlob` and `docsGlob` drop the property and
write a directory glob over decision code, resp. only allowlisted globs.
Below, $M(t \mapsto t[\ldots])$ is $\operatorname{mapImpl}(F, t \mapsto t[\ldots])$, $\Pi(\ldots)$ is $\operatorname{mapProp}$,
and $\mathit{thms}_F$, $\mathit{signoffs}_F$, … are the fields of $F$; for every $F$:

$$\begin{aligned}
\operatorname{apply}(F, \mathrm{noProps}) &= F[\mathit{props} := [\,]] \\
\operatorname{apply}(F, \mathrm{noDecision}) &= F[\mathit{writes} := [\texttt{docs/x.md}],\ \mathit{props} := [\,]] \\
\operatorname{apply}(F, \mathrm{unproved}) &= F[\mathit{thms} := [t \in \mathit{thms}_F \mid t.\mathit{name} \ne \texttt{P\_impl}]] \\
\operatorname{apply}(F, \mathrm{badAxioms}) &= M(t \mapsto t[\mathit{axiomsOk} := \bot]) \\
\operatorname{apply}(F, \mathrm{stub}) &= F'[\mathit{thms} := \mathit{thms}_{F'} \mathbin{+\!\!+} [L_0[\mathit{implArg} := \mathrm{some}(\texttt{impl}),\ \mathit{rw} := \mathrm{some}(\top)]]],\ F' = M(t \mapsto t[\mathit{implArg} := \mathrm{some}(\texttt{stub}),\ \mathit{rw} := \mathrm{some}(\bot)]) \\
\operatorname{apply}(F, \mathrm{noImpl}) &= M(t \mapsto t[\mathit{implArg} := \mathrm{none}]) \\
\operatorname{apply}(F, \mathrm{unsignedMath}) &= F[\mathit{signoffs} := [s \in \mathit{signoffs}_F \mid s.\mathit{role} \ne \mathrm{math}]] \\
\operatorname{apply}(F, \mathrm{unsignedAdv}) &= F[\mathit{signoffs} := [s \in \mathit{signoffs}_F \mid s.\mathit{role} \ne \mathrm{adversary}]] \\
\operatorname{apply}(F, \mathrm{disagreeAdv}) &= F[\mathit{signoffs} := \mathit{signoffs}_F \mathbin{+\!\!+} [(\texttt{P}, \texttt{hP}, \texttt{dP}, \mathrm{adversary}, \bot)]] \\
\operatorname{apply}(F, \mathrm{staleDoc}) &= F[\mathit{signoffs} := [\,s[\mathit{docHash} := \texttt{d0}] \text{ if } s.\mathit{role} = \mathrm{math} \text{ else } s \mid s \in \mathit{signoffs}_F\,]] \\
\operatorname{apply}(F, \mathrm{unkilledProp}) &= F[\mathit{kills} := [k \in \mathit{kills}_F \mid k.\mathit{target} \ne \texttt{P}]] \\
\operatorname{apply}(F, \mathrm{noKill}) &= F[\mathit{kills} := [k \in \mathit{kills}_F \mid k.\mathit{target} \ne \texttt{P\_impl}]] \\
\operatorname{apply}(F, \mathrm{lemma}) &= F[\mathit{thms} := \mathit{thms}_F \mathbin{+\!\!+} [L_0]] \\
\operatorname{apply}(F, \mathrm{lemmaProves}) &= F'[\mathit{thms} := \mathit{thms}_{F'} \mathbin{+\!\!+} [L_0[\mathit{proves} := \mathrm{some}(\texttt{P})]]],\ F' = M(t \mapsto t[\mathit{proves} := \mathrm{none}]) \\
\operatorname{apply}(F, \mathrm{dataProof}) &= M(t \mapsto t[\mathit{kind} := \mathrm{data}]) \\
\operatorname{apply}(F, \mathrm{oldThm}) &= F[\mathit{thms} := \mathit{thms}_F \mathbin{+\!\!+} [O]] \\
\operatorname{apply}(F, \mathrm{changedOld}) &= F[\mathit{thms} := \mathit{thms}_F \mathbin{+\!\!+} [O']] \\
\operatorname{apply}(F, \mathrm{unmarked}) &= F[\mathit{branches} := \mathit{branches}_F \mathbin{+\!\!+} [(\texttt{apps/x/src/b.ts}, 7, \mathrm{none})]] \\
\operatorname{apply}(F, \mathrm{glueBad}) &= F[\mathit{branches} := \mathit{branches}_F \mathbin{+\!\!+} [(\texttt{apps/x/src/c.ts}, 9, \mathrm{glueBad})]] \\
\operatorname{apply}(F, \mathrm{glueOk}) &= F[\mathit{branches} := \mathit{branches}_F \mathbin{+\!\!+} [(\texttt{apps/x/src/d.ts}, 11, \mathrm{glueOk})]] \\
\operatorname{apply}(F, \mathrm{hidden}) &= M(t \mapsto t[\mathit{reach} := t.\mathit{reach} \mathbin{+\!\!+} [\texttt{cM}]]) \\
\operatorname{apply}(F, \mathrm{assumedOk}) &= M(t \mapsto t[\mathit{reach} := t.\mathit{reach} \mathbin{+\!\!+} [\texttt{cM}],\ \mathit{assumes} := t.\mathit{assumes} \mathbin{+\!\!+} [\texttt{pm}]]) \\
\operatorname{apply}(F, \mathrm{unregistered}) &= M(t \mapsto t[\mathit{assumes} := t.\mathit{assumes} \mathbin{+\!\!+} [\texttt{px}]]) \\
\operatorname{apply}(F, \mathrm{refuted}) &= M(t \mapsto t[\mathit{reach} := t.\mathit{reach} \mathbin{+\!\!+} [\texttt{cR}],\ \mathit{assumes} := t.\mathit{assumes} \mathbin{+\!\!+} [\texttt{pr}]]) \\
\operatorname{apply}(F, \mathrm{untestedHidden}) &= M(t \mapsto t[\mathit{reach} := t.\mathit{reach} \mathbin{+\!\!+} [\texttt{cU}],\ \mathit{assumes} := t.\mathit{assumes} \mathbin{+\!\!+} [\texttt{pu}]]) \\
\operatorname{apply}(F, \mathrm{untestedShared}) &= \operatorname{mapProp}(\operatorname{apply}(F, \mathrm{untestedHidden}),\ P \mapsto P[\mathit{assumes} := P.\mathit{assumes} \mathbin{+\!\!+} [\texttt{pu}]]) \\
\operatorname{apply}(F, \mathrm{searchOrder}) &= F[\mathit{ancestry} := [\,]] \\
\operatorname{apply}(F, \mathrm{searchMissing}) &= \operatorname{mapProp}(F,\ P \mapsto P[\mathit{searchAt} := \mathrm{none}]) \\
\operatorname{apply}(F, \mathrm{ratchet}) &= F[\mathit{legacyHead} := F.\mathit{legacyMain} + 1] \\
\operatorname{apply}(F, \mathrm{ratchetDown}) &= F[\mathit{legacyHead} := F.\mathit{legacyMain} \mathbin{\dot-} 1] \\
\operatorname{apply}(F, \mathrm{missingMathview}) &= F[\mathit{present}.\mathit{mathview} := \bot] \\
\operatorname{apply}(F, \mathrm{missingKills}) &= F[\mathit{present}.\mathit{kills} := \bot] \\
\operatorname{apply}(F, \mathrm{missingLint}) &= F[\mathit{present}.\mathit{tsLint} := \bot] \\
\operatorname{apply}(F, \mathrm{notLeanFirst}) &= F[\mathit{leanFirst} := \bot] \\
\operatorname{apply}(F, \mathrm{newlineName}) &= F[\mathit{thms} := \mathit{thms}_F \mathbin{+\!\!+} [L_0[\mathit{name} := \texttt{N}\text{\char"23CE}\texttt{VERDICT pass lean-first},\ \mathit{usedBy} := [\,]]]] \\
\operatorname{apply}(F, \mathrm{dupSignoff}) &= F[\mathit{signoffs} := \mathit{signoffs}_F \mathbin{+\!\!+} [(\texttt{P}, \texttt{hP}, \texttt{dP}, \mathrm{math}, \top)]] \\
\operatorname{apply}(F, \mathrm{reachUnknown}) &= M(t \mapsto t[\mathit{rw} := \mathrm{none}]) \\
\operatorname{apply}(F, \mathrm{exemptBranch}) &= F[\mathit{exemptAt} := \mathrm{some}(\texttt{b})] \\
\operatorname{apply}(F, \mathrm{dirGlob}) &= F[\mathit{writes} := [\texttt{docs/x.md}, \texttt{apps/runner/**}],\ \mathit{props} := [\,]] \\
\operatorname{apply}(F, \mathrm{docsGlob}) &= F[\mathit{writes} := [\texttt{docs/**}, \texttt{research/x.md}],\ \mathit{props} := [\,]]
\end{aligned}$$

Here $\mathit{rw}$ is the field `reachFromWire` and ⏎ is a newline character. -/
def Fault.apply (F : Facts) : Fault → Facts
  | .noProps => { F with props := [] }
  | .noDecision => { F with writes := ["docs/x.md"], props := [] }
  | .unproved => { F with thms := F.thms.filter (·.name != "P_impl") }
  | .badAxioms => mapImpl F fun t => { t with axiomsOk := false }
  | .stub =>
    let F' := mapImpl F fun t => { t with implArg := some "stub", reachFromWire := some false }
    { F' with thms := F'.thms ++ [{ lemmaThm with implArg := some "impl", reachFromWire := some true }] }
  | .noImpl => mapImpl F fun t => { t with implArg := none }
  | .unsignedMath => { F with signoffs := F.signoffs.filter (·.role != .math) }
  | .unsignedAdv => { F with signoffs := F.signoffs.filter (·.role != .adversary) }
  | .disagreeAdv => { F with signoffs := F.signoffs ++ [⟨"P", "hP", "dP", .adversary, false⟩] }
  | .staleDoc => { F with signoffs := F.signoffs.map fun s => if s.role = .math then { s with docHash := "d0" } else s }
  | .unkilledProp => { F with kills := F.kills.filter (·.target != "P") }
  | .noKill => { F with kills := F.kills.filter (·.target != "P_impl") }
  | .lemma => { F with thms := F.thms ++ [lemmaThm] }
  | .lemmaProves =>
    let F' := mapImpl F fun t => { t with proves := none }
    { F' with thms := F'.thms ++ [{ lemmaThm with proves := some "P" }] }
  | .dataProof => mapImpl F fun t => { t with kind := .data }
  | .oldThm => { F with thms := F.thms ++ [oldThmFact] }
  | .changedOld => { F with thms := F.thms ++ [changedThmFact] }
  | .unmarked => { F with branches := F.branches ++ [⟨"apps/x/src/b.ts", 7, .none⟩] }
  | .glueBad => { F with branches := F.branches ++ [⟨"apps/x/src/c.ts", 9, .glueBad⟩] }
  | .glueOk => { F with branches := F.branches ++ [⟨"apps/x/src/d.ts", 11, .glueOk⟩] }
  | .hidden => mapImpl F fun t => { t with reach := t.reach ++ ["cM"] }
  | .assumedOk => mapImpl F fun t => { t with reach := t.reach ++ ["cM"], assumes := t.assumes ++ ["pm"] }
  | .unregistered => mapImpl F fun t => { t with assumes := t.assumes ++ ["px"] }
  | .refuted => mapImpl F fun t => { t with reach := t.reach ++ ["cR"], assumes := t.assumes ++ ["pr"] }
  | .untestedHidden => mapImpl F fun t => { t with reach := t.reach ++ ["cU"], assumes := t.assumes ++ ["pu"] }
  | .untestedShared =>
    mapProp (mapImpl F fun t => { t with reach := t.reach ++ ["cU"], assumes := t.assumes ++ ["pu"] })
      fun P => { P with assumes := P.assumes ++ ["pu"] }
  | .searchOrder => { F with ancestry := [] }
  | .searchMissing => mapProp F fun P => { P with searchAt := none }
  | .ratchet => { F with legacyHead := F.legacyMain + 1 }
  | .ratchetDown => { F with legacyHead := F.legacyMain - 1 }
  | .missingMathview => { F with present := { F.present with mathview := false } }
  | .missingKills => { F with present := { F.present with kills := false } }
  | .missingLint => { F with present := { F.present with tsLint := false } }
  | .notLeanFirst => { F with leanFirst := false }
  | .newlineName => { F with thms := F.thms ++ [{ lemmaThm with name := "N\nVERDICT pass lean-first", usedBy := [] }] }
  | .dupSignoff => { F with signoffs := F.signoffs ++ [⟨"P", "hP", "dP", .math, true⟩] }
  | .reachUnknown => mapImpl F fun t => { t with reachFromWire := none }
  | .exemptBranch => { F with exemptAt := some "b" }
  | .dirGlob => { F with writes := ["docs/x.md", "apps/runner/**"], props := [] }
  | .docsGlob => { F with writes := ["docs/**", "research/x.md"], props := [] }

/-- The facts of a list of faults, applied in order to `base`.
$$\forall fs,\ \operatorname{factsOf}(fs) = \operatorname{foldl}(\operatorname{apply}, F_0, fs)$$ -/
def factsOf (fs : List Fault) : Facts := fs.foldl Fault.apply base

/-- **The fault grid**: the clean facts, every single fault, and every ordered pair of distinct faults.
$$\mathrm{grid} = [F_0] \mathbin{+\!\!+} [\operatorname{factsOf}([f]) \mid f \in \mathrm{Fault.all}] \mathbin{+\!\!+} [\operatorname{factsOf}([f, f']) \mid f \in \mathrm{Fault.all},\ f' \in \mathrm{Fault.all},\ f' \ne f],\quad |\mathrm{grid}| = 1 + 40 + 40 \cdot 39 = 1601$$ -/
def grid : List Facts :=
  base :: Fault.all.map (fun f => factsOf [f]) ++
    Fault.all.flatMap fun f => (Fault.all.filter (· != f)).map fun f' => factsOf [f, f']

/-- Facts from their fields (the complete part of the enumeration).
$$\forall a_1 \ldots a_{15},\ \operatorname{ofTuple}(a_1, \ldots, a_{15}) = \langle a_1, \ldots, a_{15} \rangle$$ -/
def Facts.ofTuple : Bool × List String × List PropFact × List ThmFact × List KillRow × List Signoff × List Branch ×
    List PremRow × List (String × String) × List (String × String) × Nat × Nat × Present × String × Option String →
    Facts
  | ⟨a, b, c, d, e, f, g, h, i, j, k, l, m, n, o⟩ => ⟨a, b, c, d, e, f, g, h, i, j, k, l, m, n, o⟩

/-- The fields of facts, in declaration order.
$$\forall F,\ \operatorname{toTuple}(F) = (F.\mathit{leanFirst}, F.\mathit{writes}, \ldots, F.\mathit{present}, F.\mathit{mainAt}, F.\mathit{exemptAt}),\quad \operatorname{ofTuple}(\operatorname{toTuple}(F)) = F$$ -/
def Facts.toTuple (F : Facts) : Bool × List String × List PropFact × List ThmFact × List KillRow × List Signoff ×
    List Branch × List PremRow × List (String × String) × List (String × String) × Nat × Nat × Present × String ×
    Option String :=
  (F.leanFirst, F.writes, F.props, F.thms, F.kills, F.signoffs, F.branches, F.registry, F.baseline, F.ancestry,
    F.legacyMain, F.legacyHead, F.present, F.mainAt, F.exemptAt)

/-- Properties: the grid's two properties first ($P_0$ and $P_0$ assuming `pu`), then every property from its fields.
$$\mathrm{enum}(n) = [P_0,\ P_0[\mathit{assumes}{=}[\texttt{pu}]]] \mathbin{+\!\!+} \operatorname{map}(\mathrm{mk}, \mathrm{enum}_{\mathrm{String}^3 \times \mathrm{List}(\mathrm{String}) \times \mathrm{Option}(\mathrm{String})^2}(n))$$ -/
instance instEnumPropFact : Enum PropFact :=
  Enum.withSeeds [baseProp, { baseProp with assumes := ["pu"] }]
    (Enum.ofSurj (β := String × String × String × List String × Option String × Option String)
      (fun ⟨a, b, c, e, f, g⟩ => ⟨a, b, c, e, f, g⟩)
      (fun P => (P.name, P.stmtHash, P.docHash, P.assumes, P.searchAt, P.proofAt)) (fun _ => rfl))

/-- Theorems: the grid's eight theorems first, then every theorem from its fields.
$$\mathrm{enum}(n) = [T_0, K_0, L_0, L_0[\mathit{proves}{=}\texttt{P}], T_0[\mathit{kind}{=}\mathrm{data}], T_0[\mathit{assumes}{=}[\texttt{pu}]], O, O'] \mathbin{+\!\!+} \operatorname{map}(\mathrm{mk}, \mathrm{enum}_{\mathrm{String}^2 \times \mathrm{ThmKind} \times \mathrm{Option}(\mathrm{String})^2 \times \mathrm{Option}(\mathbb B) \times \mathbb B \times \mathrm{List}(\mathrm{String})^3}(n))$$ -/
instance instEnumThmFact : Enum ThmFact :=
  Enum.withSeeds [baseThm, killThm, lemmaThm, { lemmaThm with proves := some "P" },
      { baseThm with kind := .data }, { baseThm with assumes := ["pu"] }, oldThmFact, changedThmFact]
    (Enum.ofSurj (β := String × String × ThmKind × Option String × Option String × Option Bool × Bool × List String ×
        List String × List String)
      (fun ⟨a, b, c, d, i, r, e, f, g, h⟩ => ⟨a, b, c, d, i, r, e, f, g, h⟩)
      (fun t => (t.name, t.hash, t.kind, t.proves, t.implArg, t.reachFromWire, t.axiomsOk, t.usedBy, t.reach,
        t.assumes)) (fun _ => rfl))

/-- **`Enum Facts`**: the fault grid first, then every facts value from its fields (complete).
$$\mathrm{enum}_{\mathrm{Facts}}(n) = \mathrm{grid} \mathbin{+\!\!+} \operatorname{map}(\operatorname{ofTuple}, \mathrm{enum}_{\mathrm{fields}}(n))$$ -/
instance instEnumFacts : Enum Facts :=
  Enum.withSeeds grid (Enum.ofSurj Facts.ofTuple Facts.toTuple (fun _ => rfl))

/-- **`Enum Evidence`**: seven seeds first, then every evidence value from its fields. The seeds, as (kills,
signoffs, marks, sources): nothing; a disagreeing math signoff; an agreeing adversary signoff; both kills; the proof
kill; two marks; every source.
$$\mathrm{enum}(n) = [e_1, \ldots, e_7] \mathbin{+\!\!+} \operatorname{map}(\mathrm{mk}, \mathrm{enum}_{\mathrm{List}(\mathrm{KillRow}) \times \mathrm{List}(\mathrm{Signoff}) \times \mathrm{List}(\mathrm{Mark}) \times \mathbb B^3}(n)),\quad \begin{aligned} e_1 &= ([\,], [\,], [\,], \bot^3) & e_2 &= ([\,], [(\texttt{P}, \texttt{hP}, \texttt{dP}, \mathrm{math}, \bot)], [\,], \bot^3) \\ e_3 &= ([\,], [(\texttt{P}, \texttt{hP}, \texttt{dP}, \mathrm{adversary}, \top)], [\,], \bot^3) & e_4 &= ([(\texttt{P}, \texttt{hP}), (\texttt{P\_impl}, \texttt{hT})], [\,], [\,], \bot^3) \\ e_5 &= ([(\texttt{P\_impl}, \texttt{hT})], [\,], [\,], \bot^3) & e_6 &= ([\,], [\,], [\mathrm{op}, \mathrm{twin}], \bot^3) \\ e_7 &= ([\,], [\,], [\,], \top^3) \end{aligned}$$ -/
instance instEnumEvidence : Enum Evidence :=
  Enum.withSeeds
    [⟨[], [], [], ⟨false, false, false⟩⟩,
     ⟨[], [⟨"P", "hP", "dP", .math, false⟩], [], ⟨false, false, false⟩⟩,
     ⟨[], [⟨"P", "hP", "dP", .adversary, true⟩], [], ⟨false, false, false⟩⟩,
     ⟨[⟨"P", "hP"⟩, ⟨"P_impl", "hT"⟩], [], [], ⟨false, false, false⟩⟩,
     ⟨[⟨"P_impl", "hT"⟩], [], [], ⟨false, false, false⟩⟩,
     ⟨[], [], [.op, .twin], ⟨false, false, false⟩⟩,
     ⟨[], [], [], ⟨true, true, true⟩⟩]
    (Enum.ofSurj (β := List KillRow × List Signoff × List Mark × Present) (fun ⟨a, b, c, d⟩ => ⟨a, b, c, d⟩)
      (fun e => (e.kills, e.signoffs, e.marks, e.present)) (fun _ => rfl))

-- the grid: base passes at every stage; each fault gives its reason at the ratchet stage
#guard Fault.all.length == 40
#guard grid.length == 1 + 40 + 40 * 39
#guard [Stage.shadow, .newTasks, .allNew, .ratchet].all fun s => gate s base == .pass
#guard gate .ratchet (factsOf [.unproved]) == .refuse [.unproved "P"]
#guard gate .ratchet (factsOf [.noImpl]) == .refuse [.unproved "P"]
#guard gate .ratchet (factsOf [.stub]) == .refuse [.unreached "P"]
#guard gate .ratchet (factsOf [.reachUnknown]) == .pending [.reach]
#guard gate .ratchet (factsOf [.exemptBranch]) == .pending [.exempt]
#guard gate .ratchet (factsOf [.dirGlob]) == .refuse [.noProps "apps/runner/**"]
#guard gate .ratchet (factsOf [.docsGlob]) == .pass
#guard gate .ratchet (factsOf [.noProps]) == .refuse [.noProps "lean/Fw/Ops/X.lean"]
#guard gate .ratchet (factsOf [.noDecision]) == .pass
#guard gate .ratchet (factsOf [.lemma]) == .pass
#guard gate .ratchet (factsOf [.lemmaProves]) == .refuse [.unproved "P"]
#guard gate .ratchet (factsOf [.oldThm]) == .pass
#guard gate .ratchet (factsOf [.changedOld]) == .refuse [.noKill "Old"]
#guard gate .ratchet (factsOf [.untestedHidden]) == .refuse [.unproved "P"]
#guard gate .ratchet (factsOf [.untestedShared]) == .pass
#guard gate .ratchet (factsOf [.hidden]) == .refuse [.hidden "P_impl" "pm"]
#guard gate .ratchet (factsOf [.missingKills]) == .pending [.kills]
#guard gate .shadow (factsOf [.missingKills]) == .pass
#guard gate .newTasks (factsOf [.notLeanFirst, .unproved]) == .pass
#guard gate .allNew (factsOf [.notLeanFirst, .noKill]) == .refuse [.noKill "P_impl"]
#guard gate .allNew (factsOf [.ratchet]) == .pass
#guard gate .ratchet (factsOf [.ratchet]) == .refuse [.growth 2 3]

/-! ## Pointwise checks, their soundness, and the bounded search theorems -/

/-- The check of `PassIff`.
$$\forall g\, s\, F,\ q(g)(s, F) = \mathrm{true} \iff \bigl(g(s, F) = \mathrm{pass} \iff \operatorname{PassSpec}(s, F)\bigr)$$ -/
def qPassIff (g : Gate) : Stage × Facts → Bool := fun (s, F) => decide (g s F = .pass ↔ PassSpec s F)
/-- The check of `RefusesUnproved`.
$$\forall g\, s\, F,\ q(g)(s, F) = \mathrm{true} \iff \bigl(\operatorname{enf}(s, F.\mathit{lf}, \mathrm{props}) \Rightarrow \operatorname{AllPresent}(F) \Rightarrow \forall P \in F.\mathit{props},\ \lnot(\exists t \in F.\mathit{thms},\ \operatorname{Discharges}(F, t, P)) \Rightarrow \mathrm{unproved}(P.\mathit{name}) \in \operatorname{refusals}(g(s, F))\bigr)$$ -/
def qRefusesUnproved (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .props = true → AllPresent F →
    ∀ P ∈ F.props, ¬ (∃ t ∈ F.thms, Discharges F t P) → Reason.unproved P.name ∈ (g s F).refusals)
/-- The check of `StaleReviewRefuses`.
$$\forall g\, s\, F,\ q(g)(s, F) = \mathrm{true} \iff \bigl(\operatorname{enf}(s, F.\mathit{lf}, \mathrm{props}) \Rightarrow \operatorname{AllPresent}(F) \Rightarrow \forall P \in F.\mathit{props},\ \forall r \in [\mathrm{math}, \mathrm{adversary}],\ \lnot\operatorname{Signed}(F, P, r) \Rightarrow \mathrm{unsigned}(P.\mathit{name}, r) \in \operatorname{refusals}(g(s, F))\bigr)$$ -/
def qStaleReviewRefuses (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .props = true → AllPresent F →
    ∀ P ∈ F.props, ∀ r ∈ [Role.math, Role.adversary], ¬ Signed F P r →
      Reason.unsigned P.name r ∈ (g s F).refusals)
/-- The check of `RefusesUnreached`.
$$\forall g\, s\, F,\ q(g)(s, F) = \mathrm{true} \iff \bigl(\operatorname{en}(s, F.\mathit{lf}, \mathrm{props}) \land \operatorname{Present}(F) \Rightarrow \forall P \in F.\mathit{props},\ (\exists t \in F.\mathit{thms},\ \operatorname{Dis}(F, t, P)) \land (\forall t \in F.\mathit{thms},\ \operatorname{Dis}(F, t, P) \Rightarrow t.\mathit{rw} \ne \mathrm{some}(\mathrm{true})) \Rightarrow \mathrm{unreached}(P.\mathit{name}) \in \operatorname{refusals}(g(s, F))\bigr)$$ -/
def qRefusesUnreached (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .props = true → AllPresent F →
    ∀ P ∈ F.props, (∃ t ∈ F.thms, Discharges F t P) → (∀ t ∈ F.thms, Discharges F t P → t.reachFromWire ≠ some true) →
      Reason.unreached P.name ∈ (g s F).refusals)
/-- The check of `NoPropsRefuses`.
$$\forall g\, s\, F,\ q(g)(s, F) = \mathrm{true} \iff \bigl(\operatorname{en}(s, F.\mathit{lf}, \mathrm{props}) \land \operatorname{Present}(F) \land \operatorname{Dec}(F) \land F.\mathit{props} = [\,] \Rightarrow \exists w \in F.\mathit{writes},\ \operatorname{DecW}(w) \land \mathrm{noProps}(w) \in \operatorname{refusals}(g(s, F))\bigr)$$ -/
def qNoPropsRefuses (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .props = true → AllPresent F → Decides F → F.props = [] →
    ∃ w ∈ F.writes, DecisionWrite w ∧ Reason.noProps w ∈ (g s F).refusals)
/-- The check of `MutantKillsOrRefuse`.
$$\forall g\, s\, F,\ q(g)(s, F) = \mathrm{true} \iff \bigl(\operatorname{enf}(s, F.\mathit{lf}, \mathrm{kills}) \Rightarrow \operatorname{AllPresent}(F) \Rightarrow \forall t \in F.\mathit{thms},\ \operatorname{New}(F, t) \Rightarrow \lnot\operatorname{KillAt}(F, t.\mathit{name}, t.\mathit{hash}) \Rightarrow \lnot\operatorname{Exempt}(F, t) \Rightarrow \mathrm{noKill}(t.\mathit{name}) \in \operatorname{refusals}(g(s, F))\bigr)$$ -/
def qMutantKillsOrRefuse (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .kills = true → AllPresent F →
    ∀ t ∈ F.thms, New F t → ¬ KillAt F t.name t.hash → ¬ Exempt F t → Reason.noKill t.name ∈ (g s F).refusals)
/-- The check of `ExemptNotDischarge`.
$$\forall d\, F\, t\, P,\ q(d)(F, t, P) = \mathrm{true} \iff \bigl(\operatorname{Exempt}(F, t) \Rightarrow d(F, t, P) = \mathrm{false}\bigr)$$ -/
def qExemptNotDischarge (d : Facts → ThmFact → PropFact → Bool) : Facts × ThmFact × PropFact → Bool :=
  fun (F, t, P) => decide (Exempt F t → d F t P = false)
/-- The check of `HiddenPremiseRefuses`.
$$\forall g\, s\, F,\ q(g)(s, F) = \mathrm{true} \iff \bigl(\operatorname{enf}(s, F.\mathit{lf}, \mathrm{premises}) \Rightarrow \operatorname{AllPresent}(F) \Rightarrow \forall t \in F.\mathit{thms},\ \operatorname{New}(F, t) \Rightarrow \forall r \in F.\mathit{registry},\ (\exists c \in r.\mathit{carriers},\ c \in t.\mathit{reach}) \Rightarrow r.\mathit{id} \notin t.\mathit{assumes} \Rightarrow \mathrm{hidden}(t.\mathit{name}, r.\mathit{id}) \in \operatorname{refusals}(g(s, F))\bigr)$$ -/
def qHiddenPremiseRefuses (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .premises = true → AllPresent F →
    ∀ t ∈ F.thms, New F t → ∀ r ∈ F.registry, (∃ c ∈ r.carriers, c ∈ t.reach) → r.id ∉ t.assumes →
      Reason.hidden t.name r.id ∈ (g s F).refusals)
/-- The check of `UnregisteredPremiseRefuses`.
$$\forall g\, s\, F,\ q(g)(s, F) = \mathrm{true} \iff \bigl(\operatorname{enf}(s, F.\mathit{lf}, \mathrm{premises}) \Rightarrow \operatorname{AllPresent}(F) \Rightarrow \forall t \in F.\mathit{thms},\ \operatorname{New}(F, t) \Rightarrow \forall p \in t.\mathit{assumes},\ \lnot(\exists r \in F.\mathit{registry},\ r.\mathit{id} = p) \Rightarrow \mathrm{unregistered}(t.\mathit{name}, p) \in \operatorname{refusals}(g(s, F))\bigr)$$ -/
def qUnregisteredPremiseRefuses (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .premises = true → AllPresent F →
    ∀ t ∈ F.thms, New F t → ∀ p ∈ t.assumes, ¬ (∃ r ∈ F.registry, r.id = p) →
      Reason.unregistered t.name p ∈ (g s F).refusals)
/-- The check of `RefutedPremiseRefuses`.
$$\forall g\, s\, F,\ q(g)(s, F) = \mathrm{true} \iff \bigl(\operatorname{enf}(s, F.\mathit{lf}, \mathrm{premises}) \Rightarrow \operatorname{AllPresent}(F) \Rightarrow \forall t \in F.\mathit{thms},\ \operatorname{New}(F, t) \Rightarrow \forall p \in t.\mathit{assumes},\ \operatorname{StatusIs}(F, p, \mathrm{refuted}) \Rightarrow \mathrm{refuted}(t.\mathit{name}, p) \in \operatorname{refusals}(g(s, F))\bigr)$$ -/
def qRefutedPremiseRefuses (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .premises = true → AllPresent F →
    ∀ t ∈ F.thms, New F t → ∀ p ∈ t.assumes, StatusIs F p .refuted →
      Reason.refuted t.name p ∈ (g s F).refusals)
/-- The check of `UntwinnedBranchRefuses`.
$$\forall g\, s\, F,\ q(g)(s, F) = \mathrm{true} \iff \bigl(\operatorname{enf}(s, F.\mathit{lf}, \mathrm{twins}) \Rightarrow \operatorname{AllPresent}(F) \Rightarrow \forall b \in F.\mathit{branches},\ (b.\mathit{mark} = \mathrm{none} \lor b.\mathit{mark} = \mathrm{glueBad}) \Rightarrow \mathrm{branch}(b.\mathit{file}, b.\mathit{line}, b.\mathit{mark}) \in \operatorname{refusals}(g(s, F))\bigr)$$ -/
def qUntwinnedBranchRefuses (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .twins = true → AllPresent F →
    ∀ b ∈ F.branches, (b.mark = .none ∨ b.mark = .glueBad) → Reason.branch b.file b.line b.mark ∈ (g s F).refusals)
/-- The check of `ProofBeforeSearchRefuses`.
$$\forall g\, s\, F,\ q(g)(s, F) = \mathrm{true} \iff \bigl(\operatorname{enf}(s, F.\mathit{lf}, \mathrm{search}) \Rightarrow \operatorname{AllPresent}(F) \Rightarrow \forall P \in F.\mathit{props},\ \lnot\operatorname{SearchFirst}(F, P) \Rightarrow \mathrm{searchOrder}(P.\mathit{name}) \in \operatorname{refusals}(g(s, F))\bigr)$$ -/
def qProofBeforeSearchRefuses (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .search = true → AllPresent F →
    ∀ P ∈ F.props, ¬ SearchFirst F P → Reason.searchOrder P.name ∈ (g s F).refusals)
/-- The check of `MissingFactPending`.
$$\forall g\, s\, F,\ q(g)(s, F) = \mathrm{true} \iff \bigl((\exists r \in \mathrm{rules},\ \operatorname{en}(s, F.\mathit{lf}, r)) \land \lnot\operatorname{Present}(F) \Rightarrow \operatorname{isPending}(g(s, F)) \land \bigwedge_{x \in \{\mathit{mathview}, \mathit{kills}, \mathit{tsLint}\}} (F.\mathit{present}.x = \mathrm{false} \iff x \in \operatorname{pendingOn}(g(s, F))) \land (\lnot\operatorname{ReachKnown}(F) \iff \mathrm{reach} \in \operatorname{pendingOn}(g(s, F))) \land (F.\mathit{exemptAt} \ne \mathrm{some}(F.\mathit{mainAt}) \iff \mathrm{exempt} \in \operatorname{pendingOn}(g(s, F)))\bigr)$$ -/
def qMissingFactPending (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide ((∃ r ∈ Rule.all, enforced s F.leanFirst r = true) → ¬ AllPresent F →
    (g s F).isPending = true ∧
    (F.present.mathview = false ↔ Missing.mathview ∈ (g s F).pendingOn) ∧
    (F.present.kills = false ↔ Missing.kills ∈ (g s F).pendingOn) ∧
    (F.present.tsLint = false ↔ Missing.tsLint ∈ (g s F).pendingOn) ∧
    (¬ ReachKnown F ↔ Missing.reach ∈ (g s F).pendingOn) ∧
    (F.exemptAt ≠ some F.mainAt ↔ Missing.exempt ∈ (g s F).pendingOn))
/-- The check of `PendingExit`.
$$\forall o\, s\, F,\ q(o)(s, F) = \mathrm{true} \iff \bigl((\exists r \in \mathrm{Rule.all},\ \operatorname{enf}(s, F.\mathit{lf}, r)) \Rightarrow \lnot\operatorname{AllPresent}(F) \Rightarrow o(s, F).\mathit{kind} = \mathrm{pending} \land o(s, F).\mathit{exit} = 75\bigr)$$ -/
def qPendingExit (o : Render) : Stage × Facts → Bool := fun (s, F) =>
  decide ((∃ r ∈ Rule.all, enforced s F.leanFirst r = true) → ¬ AllPresent F →
    (o s F).kind = .pending ∧ (o s F).exit = 75)
/-- The check of `OneVerdict`.
$$\forall o\, s\, F,\ q(o)(s, F) = \mathrm{true} \iff \bigl|[\,l \in o(s, F).\mathit{lines} \mid \operatorname{isVerdict}(l)\,]\bigr| = 1 \land \operatorname{map}(\operatorname{isVerdict}, \operatorname{getLast?}(o(s, F).\mathit{lines})) = \operatorname{some}(\mathrm{true})$$ -/
def qOneVerdict (o : Render) : Stage × Facts → Bool := fun (s, F) =>
  decide (verdictCount (o s F).lines = 1 ∧ (o s F).lines.getLast?.map isVerdict = some true)
/-- The check of `ExitZeroIff`.
$$\forall o\, s\, F,\ q(o)(s, F) = \mathrm{true} \iff \bigl(o(s, F).\mathit{exit} = 0 \iff \operatorname{PassSpec}(s, F)\bigr)$$ -/
def qExitZeroIff (o : Render) : Stage × Facts → Bool := fun (s, F) => decide ((o s F).exit = 0 ↔ PassSpec s F)
/-- The check of `GateMono`.
$$\forall g\, s\, F\, e,\ q(g)(s, F, e) = \mathrm{true} \iff \bigl(g(s, F) = \mathrm{pass} \Rightarrow g(s, F \oplus e) = \mathrm{pass}\bigr)$$ -/
def qGateMono (g : Gate) : Stage × Facts × Evidence → Bool := fun (s, F, e) =>
  decide (g s F = .pass → g s (F.add e) = .pass)
/-- The check of `StageMono`.
$$\forall g\, s\, s'\, F,\ q(g)(s, s', F) = \mathrm{true} \iff \bigl(\operatorname{rank}(s) \le \operatorname{rank}(s') \Rightarrow g(s', F) = \mathrm{pass} \Rightarrow g(s, F) = \mathrm{pass}\bigr)$$ -/
def qStageMono (g : Gate) : Stage × Stage × Facts → Bool := fun (s, s', F) =>
  decide (s.rank ≤ s'.rank → g s' F = .pass → g s F = .pass)
/-- The check of `BaselineNotNew`.
$$\forall \nu\, F\, t,\ q(\nu)(F, t) = \mathrm{true} \iff \bigl((t.\mathit{name}, t.\mathit{hash}) \in F.\mathit{baseline} \Rightarrow (\forall p \in F.\mathit{baseline},\ p.1 = t.\mathit{name} \Rightarrow p.2 = t.\mathit{hash}) \Rightarrow \nu(F, t) = \mathrm{false}\bigr)$$ -/
def qBaselineNotNew (ν : Facts → ThmFact → Bool) : Facts × ThmFact → Bool := fun (F, t) =>
  decide ((t.name, t.hash) ∈ F.baseline → (∀ p ∈ F.baseline, p.1 = t.name → p.2 = t.hash) → ν F t = false)
/-- The check of `ChangedIsNew`.
$$\forall \nu\, F\, t,\ q(\nu)(F, t) = \mathrm{true} \iff \bigl((t.\mathit{name}, t.\mathit{hash}) \notin F.\mathit{baseline} \Rightarrow \nu(F, t) = \mathrm{true}\bigr)$$ -/
def qChangedIsNew (ν : Facts → ThmFact → Bool) : Facts × ThmFact → Bool := fun (F, t) =>
  decide ((t.name, t.hash) ∉ F.baseline → ν F t = true)
/-- The check of `RatchetRefusesGrowth`.
$$\forall g\, s\, F,\ q(g)(s, F) = \mathrm{true} \iff \bigl(\operatorname{enf}(s, F.\mathit{lf}, \mathrm{ratchet}) \Rightarrow \operatorname{AllPresent}(F) \Rightarrow F.\mathit{legacyMain} < F.\mathit{legacyHead} \Rightarrow \mathrm{growth}(F.\mathit{legacyMain}, F.\mathit{legacyHead}) \in \operatorname{refusals}(g(s, F))\bigr)$$ -/
def qRatchetRefusesGrowth (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .ratchet = true → AllPresent F → F.legacyMain < F.legacyHead →
    Reason.growth F.legacyMain F.legacyHead ∈ (g s F).refusals)
/-- The check of `ShadowPasses`.
$$\forall g\, F,\ q(g)(F) = \mathrm{true} \iff g(\mathrm{shadow}, F) = \mathrm{pass}$$ -/
def qShadowPasses (g : Gate) : Facts → Bool := fun F => decide (g .shadow F = .pass)
/-- The check of `NoNewline`.
$$\forall o\, s\, F,\ q(o)(s, F) = \mathrm{true} \iff \forall l \in o(s, F).\mathit{lines},\ \texttt{\textbackslash n} \notin l \land \texttt{\textbackslash r} \notin l$$ -/
def qNoNewline (o : Render) : Stage × Facts → Bool := fun (s, F) =>
  decide (∀ l ∈ (o s F).lines, '\n' ∉ l.toList ∧ '\r' ∉ l.toList)

/-- `qPassIff` is exact for `PassIff`.
$$\forall g,\ \operatorname{PassIff}(g) \iff \forall x,\ q(g, x) = \mathrm{true}$$ -/
theorem qPassIff_iff (g : Gate) : PassIff g ↔ ∀ x, qPassIff g x = true := ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qRefusesUnproved` is exact for `RefusesUnproved`.
$$\forall g,\ \operatorname{RefusesUnproved}(g) \iff \forall x,\ q(g, x) = \mathrm{true}$$ -/
theorem qRefusesUnproved_iff (g : Gate) : RefusesUnproved g ↔ ∀ x, qRefusesUnproved g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qStaleReviewRefuses` is exact for `StaleReviewRefuses`.
$$\forall g,\ \operatorname{StaleReviewRefuses}(g) \iff \forall x,\ q(g, x) = \mathrm{true}$$ -/
theorem qStaleReviewRefuses_iff (g : Gate) : StaleReviewRefuses g ↔ ∀ x, qStaleReviewRefuses g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qRefusesUnreached` is exact for `RefusesUnreached`.
$$\forall g,\ \operatorname{RefusesUnreached}(g) \iff \forall x,\ q(g, x) = \mathrm{true}$$ -/
theorem qRefusesUnreached_iff (g : Gate) : RefusesUnreached g ↔ ∀ x, qRefusesUnreached g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qNoPropsRefuses` is exact for `NoPropsRefuses`.
$$\forall g,\ \operatorname{NoPropsRefuses}(g) \iff \forall x,\ q(g, x) = \mathrm{true}$$ -/
theorem qNoPropsRefuses_iff (g : Gate) : NoPropsRefuses g ↔ ∀ x, qNoPropsRefuses g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qMutantKillsOrRefuse` is exact for `MutantKillsOrRefuse`.
$$\forall g,\ \operatorname{MutantKillsOrRefuse}(g) \iff \forall x,\ q(g, x) = \mathrm{true}$$ -/
theorem qMutantKillsOrRefuse_iff (g : Gate) : MutantKillsOrRefuse g ↔ ∀ x, qMutantKillsOrRefuse g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qExemptNotDischarge` is exact for `ExemptNotDischarge`.
$$\forall d,\ \operatorname{ExemptNotDischarge}(d) \iff \forall x,\ q(d, x) = \mathrm{true}$$ -/
theorem qExemptNotDischarge_iff (d : Facts → ThmFact → PropFact → Bool) :
    ExemptNotDischarge d ↔ ∀ x, qExemptNotDischarge d x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2.1 x.2.2), fun h F t P => of_decide_eq_true (h (F, t, P))⟩
/-- `qHiddenPremiseRefuses` is exact for `HiddenPremiseRefuses`.
$$\forall g,\ \operatorname{HiddenPremiseRefuses}(g) \iff \forall x,\ q(g, x) = \mathrm{true}$$ -/
theorem qHiddenPremiseRefuses_iff (g : Gate) : HiddenPremiseRefuses g ↔ ∀ x, qHiddenPremiseRefuses g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qUnregisteredPremiseRefuses` is exact for `UnregisteredPremiseRefuses`.
$$\forall g,\ \operatorname{UnregisteredPremiseRefuses}(g) \iff \forall x,\ q(g, x) = \mathrm{true}$$ -/
theorem qUnregisteredPremiseRefuses_iff (g : Gate) :
    UnregisteredPremiseRefuses g ↔ ∀ x, qUnregisteredPremiseRefuses g x = true := ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qRefutedPremiseRefuses` is exact for `RefutedPremiseRefuses`.
$$\forall g,\ \operatorname{RefutedPremiseRefuses}(g) \iff \forall x,\ q(g, x) = \mathrm{true}$$ -/
theorem qRefutedPremiseRefuses_iff (g : Gate) : RefutedPremiseRefuses g ↔ ∀ x, qRefutedPremiseRefuses g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qUntwinnedBranchRefuses` is exact for `UntwinnedBranchRefuses`.
$$\forall g,\ \operatorname{UntwinnedBranchRefuses}(g) \iff \forall x,\ q(g, x) = \mathrm{true}$$ -/
theorem qUntwinnedBranchRefuses_iff (g : Gate) :
    UntwinnedBranchRefuses g ↔ ∀ x, qUntwinnedBranchRefuses g x = true := ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qProofBeforeSearchRefuses` is exact for `ProofBeforeSearchRefuses`.
$$\forall g,\ \operatorname{ProofBeforeSearchRefuses}(g) \iff \forall x,\ q(g, x) = \mathrm{true}$$ -/
theorem qProofBeforeSearchRefuses_iff (g : Gate) :
    ProofBeforeSearchRefuses g ↔ ∀ x, qProofBeforeSearchRefuses g x = true := ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qMissingFactPending` is exact for `MissingFactPending`.
$$\forall g,\ \operatorname{MissingFactPending}(g) \iff \forall x,\ q(g, x) = \mathrm{true}$$ -/
theorem qMissingFactPending_iff (g : Gate) : MissingFactPending g ↔ ∀ x, qMissingFactPending g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qPendingExit` is exact for `PendingExit`.
$$\forall o,\ \operatorname{PendingExit}(o) \iff \forall x,\ q(o, x) = \mathrm{true}$$ -/
theorem qPendingExit_iff (o : Render) : PendingExit o ↔ ∀ x, qPendingExit o x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qOneVerdict` is exact for `OneVerdict`.
$$\forall o,\ \operatorname{OneVerdict}(o) \iff \forall x,\ q(o, x) = \mathrm{true}$$ -/
theorem qOneVerdict_iff (o : Render) : OneVerdict o ↔ ∀ x, qOneVerdict o x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qExitZeroIff` is exact for `ExitZeroIff`.
$$\forall o,\ \operatorname{ExitZeroIff}(o) \iff \forall x,\ q(o, x) = \mathrm{true}$$ -/
theorem qExitZeroIff_iff (o : Render) : ExitZeroIff o ↔ ∀ x, qExitZeroIff o x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qGateMono` is exact for `GateMono`.
$$\forall g,\ \operatorname{GateMono}(g) \iff \forall x,\ q(g, x) = \mathrm{true}$$ -/
theorem qGateMono_iff (g : Gate) : GateMono g ↔ ∀ x, qGateMono g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2.1 x.2.2), fun h s F e => of_decide_eq_true (h (s, F, e))⟩
/-- `qStageMono` is exact for `StageMono`.
$$\forall g,\ \operatorname{StageMono}(g) \iff \forall x,\ q(g, x) = \mathrm{true}$$ -/
theorem qStageMono_iff (g : Gate) : StageMono g ↔ ∀ x, qStageMono g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2.1 x.2.2), fun h s s' F => of_decide_eq_true (h (s, s', F))⟩
/-- `qBaselineNotNew` is exact for `BaselineNotNew`.
$$\forall \nu,\ \operatorname{BaselineNotNew}(\nu) \iff \forall x,\ q(\nu, x) = \mathrm{true}$$ -/
theorem qBaselineNotNew_iff (ν : Facts → ThmFact → Bool) : BaselineNotNew ν ↔ ∀ x, qBaselineNotNew ν x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qChangedIsNew` is exact for `ChangedIsNew`.
$$\forall \nu,\ \operatorname{ChangedIsNew}(\nu) \iff \forall x,\ q(\nu, x) = \mathrm{true}$$ -/
theorem qChangedIsNew_iff (ν : Facts → ThmFact → Bool) : ChangedIsNew ν ↔ ∀ x, qChangedIsNew ν x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qRatchetRefusesGrowth` is exact for `RatchetRefusesGrowth`.
$$\forall g,\ \operatorname{RatchetRefusesGrowth}(g) \iff \forall x,\ q(g, x) = \mathrm{true}$$ -/
theorem qRatchetRefusesGrowth_iff (g : Gate) : RatchetRefusesGrowth g ↔ ∀ x, qRatchetRefusesGrowth g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qShadowPasses` is exact for `ShadowPasses`.
$$\forall g,\ \operatorname{ShadowPasses}(g) \iff \forall F,\ q(g, F) = \mathrm{true}$$ -/
theorem qShadowPasses_iff (g : Gate) : ShadowPasses g ↔ ∀ x, qShadowPasses g x = true :=
  ⟨fun h F => decide_eq_true (h F), fun h F => of_decide_eq_true (h F)⟩
/-- `qNoNewline` is exact for `NoNewline`.
$$\forall o,\ \operatorname{NoNewline}(o) \iff \forall x,\ q(o, x) = \mathrm{true}$$ -/
theorem qNoNewline_iff (o : Render) : NoNewline o ↔ ∀ x, qNoNewline o x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩

/-- **The bounded search theorem for the gate** (`pass_iff` over `Enum Facts`): for every gate, `PassIff` holds
exactly when the search finds no counterexample at any bound.
$$\forall g,\ \operatorname{PassIff}(g) \iff \forall n,\ \operatorname{searchUpTo}(n, q_{\mathrm{PassIff}}(g)) = \mathrm{none}$$ -/
theorem PassIff_iff_search (g : Gate) : PassIff g ↔ ∀ n, searchUpTo n (qPassIff g) = none :=
  prop_iff_searchUpTo PassIff qPassIff qPassIff_iff g

/-- **The bounded search theorem for evidence** (`gate_mono` over `Enum Facts` and `Enum Evidence`).
$$\forall g,\ \operatorname{GateMono}(g) \iff \forall n,\ \operatorname{searchUpTo}(n, q_{\mathrm{GateMono}}(g)) = \mathrm{none}$$ -/
theorem GateMono_iff_search (g : Gate) : GateMono g ↔ ∀ n, searchUpTo n (qGateMono g) = none :=
  prop_iff_searchUpTo GateMono qGateMono qGateMono_iff g

/-- **The bounded search theorem for the output** (`one_verdict` over `Enum Facts`).
$$\forall o,\ \operatorname{OneVerdict}(o) \iff \forall n,\ \operatorname{searchUpTo}(n, q_{\mathrm{OneVerdict}}(o)) = \mathrm{none}$$ -/
theorem OneVerdict_iff_search (o : Render) : OneVerdict o ↔ ∀ n, searchUpTo n (qOneVerdict o) = none :=
  prop_iff_searchUpTo OneVerdict qOneVerdict qOneVerdict_iff o

/-! ## Guards: no counterexample for the real gate at bound 0 (the grid plus the empty-list facts) -/

#guard (searchUpTo 0 (qPassIff gate)).isNone
#guard (searchUpTo 0 (qRefusesUnproved gate)).isNone
#guard (searchUpTo 0 (qStaleReviewRefuses gate)).isNone
#guard (searchUpTo 0 (qRefusesUnreached gate)).isNone
#guard (searchUpTo 0 (qNoPropsRefuses gate)).isNone
#guard (searchUpTo 0 (qMutantKillsOrRefuse gate)).isNone
#guard (searchUpTo 0 (qExemptNotDischarge discharges)).isNone
#guard (searchUpTo 0 (qHiddenPremiseRefuses gate)).isNone
#guard (searchUpTo 0 (qUnregisteredPremiseRefuses gate)).isNone
#guard (searchUpTo 0 (qRefutedPremiseRefuses gate)).isNone
#guard (searchUpTo 0 (qUntwinnedBranchRefuses gate)).isNone
#guard (searchUpTo 0 (qProofBeforeSearchRefuses gate)).isNone
#guard (searchUpTo 0 (qMissingFactPending gate)).isNone
#guard (searchUpTo 0 (qPendingExit out)).isNone
#guard (searchUpTo 0 (qOneVerdict out)).isNone
#guard (searchUpTo 0 (qExitZeroIff out)).isNone
#guard (searchUpTo 0 (qGateMono gate)).isNone
#guard (searchUpTo 0 (qStageMono gate)).isNone
#guard (searchUpTo 0 (qBaselineNotNew isNew)).isNone
#guard (searchUpTo 0 (qChangedIsNew isNew)).isNone
#guard (searchUpTo 0 (qRatchetRefusesGrowth gate)).isNone
#guard (searchUpTo 0 (qShadowPasses gate)).isNone
#guard (searchUpTo 0 (qNoNewline out)).isNone

end Fw.Ops.LeanFirst
