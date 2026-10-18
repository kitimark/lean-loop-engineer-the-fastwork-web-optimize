import Lean
import Fw.Spec.Reach
import Fw.Spec.Props
import MathView
/-!
# Math-view facts per theorem (task `lfg-mathview-facts`)

The lean-first gate (research/notes/2026/10-18-lean-first-gate.md, sections 1, 2, 4 and 6) reads, for each theorem, a
few facts that the math view (`lean/MathViewMain.lean`) now emits next to the existing fields:

* `headConst`: the head constant of the statement's result type, under one `¬` (a kill `¬ P m` has the head of `P`);
* `implArg`: which argument of that head is the implementation: the first argument whose type is the implementation
  type `Sig.Dom s → Sig.Cod s` of a registered signature `s` (the `impl` slot of `Incidents.Convention s impl P`, and
  the argument of a property `P impl`); only for a project (`Fw`) head;
* `assumes`: the ids of the `Assume p c` premises among the theorem's hypotheses (literal ids only);
* `killOf`: the ledger id of the registered incident whose replay the theorem rejects (`¬ P i.replay`);
* `class`: `closed`, `rfl`, `defEq` or `general`, by how the proof is built (`classify`);
* `reach`: the declarations with a math-view entry that the statement and the proof reach (`Fw.Spec.Reach.closure`,
  `hasEntry`);
* `reachFromWire`: true or false when the theorem has subjects (whether one of them is reachable from the fwcore
  dispatcher `Fw.Wire.handle` or a golden generator `lean/scripts/*Golden.lean`), null when it has none (`fwIdents`,
  `wireReach`, `reachFromWire`).

The decisions (`classify`, `implIdx`, `killOf`, `fwIdents`, `reachFromWire`) are pure and carry `#guard`s;
`Fw.Spec.MathFactsGuards` checks the classification and the other facts on real `Fw` declarations through `facts%`
and `wire%`. `factsOf` and `wireReach` are the `MetaM` glue that reads the environment.

Threat model of `reachFromWire`: true must never be emitted for a theorem whose subject is dead code
(inc-proof-of-dead-code); false or null only ask a human to look. Hence one root set (the dispatcher and the golden
generators, research/notes/2026/10-18-lean-first-gate.md check (d)), subjects that are operations (`subjectsOf`), and
null when there are none.

Stated limit: the `defEq` class depends on the environment (`sidesDefEq`). The canonical environment is the export's
(`lake exe mathview`); `facts%` in an elaborated file can disagree near the heartbeat budget.
-/
open Lean Meta Elab Term

namespace Fw.Spec.MathFacts

/-! ## Pure decisions -/

/-- How a theorem's proof is built: a closed data lint, a reflexivity proof, a statement that holds by unfolding, or a
general proof. Only `general` proofs count as behaviour proofs for the gate.
$$\mathrm{ProofClass} = \{\mathrm{closed}, \mathrm{rfl}, \mathrm{defEq}, \mathrm{general}\}$$ -/
inductive ProofClass where
  | closed | rfl | defEq | general
deriving DecidableEq, Repr, Inhabited, ToJson, FromJson, ToExpr

/-- The name the export prints for a class.
$$\operatorname{tag}(\mathrm{closed}) = \texttt{closed},\ \operatorname{tag}(\mathrm{rfl}) = \texttt{rfl},\ \operatorname{tag}(\mathrm{defEq}) = \texttt{defEq},\ \operatorname{tag}(\mathrm{general}) = \texttt{general}$$ -/
def ProofClass.tag : ProofClass → String
  | .closed => "closed" | .rfl => "rfl" | .defEq => "defEq" | .general => "general"

#guard [ProofClass.closed, .rfl, .defEq, .general].map ProofClass.tag == ["closed", "rfl", "defEq", "general"]

/-- The reflexivity proof heads: `Eq.refl`, `rfl`, `Iff.rfl`, `Iff.refl`, `HEq.refl`, `HEq.rfl`.
$$H_{\mathrm{rfl}} = \{\texttt{Eq.refl}, \texttt{rfl}, \texttt{Iff.rfl}, \texttt{Iff.refl}, \texttt{HEq.refl}, \texttt{HEq.rfl}\}$$ -/
def rflHeads : List Name := [``Eq.refl, ``rfl, ``Iff.rfl, ``Iff.refl, ``HEq.refl, ``HEq.rfl]

/-- The decision-procedure proof head: `of_decide_eq_true` (what `decide` and `decide +kernel` build).
$$H_{\mathrm{dec}} = \{\texttt{of\_decide\_eq\_true}\}$$ -/
def decideHeads : List Name := [``of_decide_eq_true]

/-- What the classification reads of a theorem: the number $b$ of leading binders of its statement (hypotheses
included, nothing unfolded), the head constant $h$ of its proof under the leading `fun`s, after unfolding the
theorem's own auxiliary proofs (`foo._proof_1`), or none when that head is not a constant, and whether its result type
(under the binders) is an `Eq`, `Iff` or `HEq` whose two sides are definitionally equal ($d$).
$$\mathrm{Shape} = \mathbb{N} \times \mathrm{Option}(\mathrm{Name}) \times \mathrm{Bool},\quad (b, h, d)$$ -/
structure Shape where
  /-- Leading binders of the statement. -/
  binders : Nat
  /-- Head constant of the proof under its leading `fun`s. -/
  head : Option Name
  /-- The result type is an equation (`Eq`, `Iff`, `HEq`) with definitionally equal sides. -/
  sidesDefEq : Bool
deriving Repr

/-- **The classification**, first match:
$$\operatorname{classify}(b, h, d) = \begin{cases} \mathrm{closed} & b = 0 \land h \in H_{\mathrm{rfl}} \cup H_{\mathrm{dec}} \\ \mathrm{rfl} & \text{else if } h \in H_{\mathrm{rfl}} \\ \mathrm{defEq} & \text{else if } d \\ \mathrm{general} & \text{otherwise} \end{cases}\qquad (\bot \notin H_{\mathrm{rfl}} \cup H_{\mathrm{dec}})$$
A missing head ($h = \bot$) is in no head set. A closed statement proved by `decide` or reflexivity is a data lint; a
reflexivity proof with binders is a defining equation; a statement whose sides are definitionally equal holds by
unfolding however it was proved. -/
def classify (s : Shape) : ProofClass :=
  if s.binders == 0 && s.head.any (fun h => rflHeads.contains h || decideHeads.contains h) then .closed
  else if s.head.any rflHeads.contains then .rfl
  else if s.sidesDefEq then .defEq
  else .general

#guard classify ⟨0, some ``of_decide_eq_true, false⟩ == .closed
#guard classify ⟨0, some ``rfl, true⟩ == .closed
#guard classify ⟨2, some ``of_decide_eq_true, false⟩ == .general
#guard classify ⟨1, some ``Iff.rfl, true⟩ == .rfl
#guard classify ⟨1, some ``of_eq_true, true⟩ == .defEq
#guard classify ⟨0, some ``of_eq_true, true⟩ == .defEq
#guard classify ⟨0, none, false⟩ == .general
#guard classify ⟨3, some ``And.left, false⟩ == .general

/-- **Only a closed statement is closed.** For every shape: if the class is `closed`, the statement has no binders.
$$\forall s,\ \operatorname{classify}(s) = \mathrm{closed} \Rightarrow s.b = 0$$ -/
theorem closed_binders (s : Shape) (h : classify s = .closed) : s.binders = 0 := by
  unfold classify at h
  split at h
  · rename_i hc
    simp only [Bool.and_eq_true, beq_iff_eq] at hc
    exact hc.1
  · split at h
    · cases h
    · split at h <;> cases h

/-- **A non-reflexivity proof of a non-definitional statement is general.** For every shape whose proof head is not a
reflexivity or decision head and whose sides are not definitionally equal, the class is `general`.
$$\forall s,\ s.h \notin H_{\mathrm{rfl}} \cup H_{\mathrm{dec}} \land \lnot s.d \Rightarrow \operatorname{classify}(s) = \mathrm{general}$$ -/
theorem general_of (s : Shape)
    (hh : s.head.any (fun h => rflHeads.contains h || decideHeads.contains h) = false)
    (hd : s.sidesDefEq = false) : classify s = .general := by
  have hr : s.head.any rflHeads.contains = false := by
    cases hs : s.head with
    | none => rfl
    | some n =>
      rw [hs] at hh
      simp only [Option.any_some, Bool.or_eq_false_iff] at hh ⊢
      exact hh.1
  have h1 : (s.binders == 0 && s.head.any (fun h => rflHeads.contains h || decideHeads.contains h)) = false := by
    rw [hh, Bool.and_false]
  unfold classify
  rw [h1, hr, hd]
  rfl

/-- **Which argument is the implementation.** Given, for each argument of the statement's head in order, whether its
type is the implementation type of a registered signature, the index of the first such argument, or none.
$$\operatorname{implIdx}([t_0, \dots, t_{n-1}]) = \begin{cases} \min\{i : t_i\} & \exists i,\ t_i \\ \bot & \text{otherwise} \end{cases}$$ -/
def implIdx (isImpl : List Bool) : Option Nat := isImpl.findIdx? id

-- `Convention s impl P`: `s : Sig`, `impl : s.Dom → s.Cod`, `P : Property (s.Dom → s.Cod)`
#guard implIdx [false, true, false] == some 1
-- `P impl`
#guard implIdx [true] == some 0
#guard implIdx [] == none
#guard implIdx [false, false] == none
#guard implIdx [true, true] == some 0

/-- A registry row as the facts see it: its ledger id, the name of the row's definition (when the registry lists it by
name) and the name of its replay.
$$\mathrm{Row} = \mathrm{String} \times \mathrm{Option}(\mathrm{Name}) \times \mathrm{Name},\quad (\iota, \rho, r)$$ -/
structure Row where
  /-- The ledger id. -/
  id : String
  /-- The row's own definition, for example `Fw.Spec.Incidents.LandDry.incLandDryNoVerdict`. -/
  row : Option Name
  /-- The replay definition, for example `Fw.Spec.Incidents.LandDry.emptyNoVerdict`. -/
  replay : Name
deriving Repr

/-- **The incident a theorem kills.** A theorem kills the row whose definition or replay is the target $t$ of its
implementation argument (the replay `i.replay` of a row $i$ targets $i$; a named replay targets itself), provided its
result type is a negation. The first such row in registry order; none when the statement is not a negation, has no
target, or no row matches.
$$\operatorname{killOf}(\nu, t, R) = \begin{cases} \iota_k & \nu \land t \ne \bot \land k = \min\{k : \rho_k = t \lor r_k = t\} \\ \bot & \text{otherwise} \end{cases}$$ -/
def killOf (negated : Bool) (target : Option Name) (rows : List Row) : Option String :=
  if negated then
    target.bind fun t => (rows.find? fun r => r.row == some t || r.replay == t).map (·.id)
  else none

#guard killOf true (some `R.inc) [⟨"inc-a", some `R.inc, `R.rep⟩] == some "inc-a"
#guard killOf true (some `R.rep) [⟨"inc-a", some `R.inc, `R.rep⟩] == some "inc-a"
#guard killOf false (some `R.inc) [⟨"inc-a", some `R.inc, `R.rep⟩] == none
#guard killOf true (some `R.other) [⟨"inc-a", some `R.inc, `R.rep⟩] == none
#guard killOf true none [⟨"inc-a", some `R.inc, `R.rep⟩] == none
#guard killOf true (some `R.inc) [] == none
#guard killOf true (some `X) [⟨"a", none, `Y⟩, ⟨"b", none, `X⟩, ⟨"c", some `X, `Z⟩] == some "b"

/-- **The `Fw.` identifiers of a source text** (a generator script under `lean/scripts/`): every maximal run of
identifier characters (ASCII letters and digits, `_`, `'`, `.`; any other character, Unicode letters included, ends a
run) that, with its trailing dots dropped, starts with the string `Fw.`, in order of first occurrence, without
repeats. Below, $\operatorname{runs}_C(s)$ lists the maximal runs of characters of $C$ in $s$, and
$\sqsubseteq_{\mathrm{str}}$ reads "is a string prefix of".
$$\forall s,\ \operatorname{fwIdents}(s) = \operatorname{dedup}[\operatorname{rtrim}_{\texttt{.}}(w) : w \in \operatorname{runs}_{[\texttt{A-Za-z0-9\_'.}]}(s),\ \texttt{"Fw."} \sqsubseteq_{\mathrm{str}} \operatorname{rtrim}_{\texttt{.}}(w)]$$ -/
def fwIdents (src : String) : List String := Id.run do
  let isId (c : Char) := c.isAlphanum || c == '_' || c == '\'' || c == '.'
  let mut out : Array String := #[]
  -- the current run, reversed
  let mut cur : List Char := []
  for c in src.toList ++ [' '] do
    if isId c then cur := c :: cur
    else
      let w := String.ofList (cur.dropWhile (· == '.')).reverse
      if w.startsWith "Fw." && !out.contains w then out := out.push w
      cur := []
  return out.toList

#guard fwIdents "if ← Fw.Console.LandDry.checkGolden then\n  Fw.Console.LandDry.writeGolden" ==
  ["Fw.Console.LandDry.checkGolden", "Fw.Console.LandDry.writeGolden"]
#guard fwIdents "import Fw.Ops.Golden\n(Fw.Ops.Golden.rows). x.Fw.y Fw." == ["Fw.Ops.Golden", "Fw.Ops.Golden.rows"]
#guard fwIdents "" == []
#guard fwIdents "MyFw.x Fw.a Fw.a" == ["Fw.a"]
#guard fwIdents "Fw.x₁ Fw.y" == ["Fw.x", "Fw.y"]

/-- **Is a theorem reachable from the wire?** With no subjects the answer is unknown (null: a human looks); otherwise
whether some subject is in the wire reach $W$ (passed as its membership test).
$$\forall S, W,\ \operatorname{reachFromWire}(S, W) = \begin{cases} \bot & S = [\,] \\ \mathrm{true} & S \ne [\,] \land \exists x \in S,\ x \in W \\ \mathrm{false} & \text{otherwise} \end{cases}$$ -/
def reachFromWire (subjects : List String) (inWire : String → Bool) : Option Bool :=
  if subjects.isEmpty then none else some (subjects.any inWire)

#guard reachFromWire ["Fw.a", "Fw.b"] ["Fw.b", "Fw.c"].contains == some true
#guard reachFromWire ["Fw.a"] ["Fw.b"].contains == some false
#guard reachFromWire [] ["Fw.b"].contains == none
#guard reachFromWire ["Fw.a"] ([] : List String).contains == some false

/-! ## The facts of one theorem (glue) -/

/-- The facts of one theorem, as the export stores them: head constant, implementation argument (index and printed
argument), premise ids, killed incident id, class, reach, and the subjects that `reachFromWire` reads (stored, not
printed).
$$\mathrm{Facts} = (h, a, A, k, c, \mathit{reach}, S)$$ -/
structure Facts where
  /-- Head constant of the result type, under one `¬`. -/
  headConst : Option String := none
  /-- Index of the implementation argument of the head. -/
  implIdx : Option Nat := none
  /-- That argument, printed with full names. -/
  implExpr : Option String := none
  /-- Ids of the `Assume` premises among the hypotheses. -/
  assumes : List String := []
  /-- Ledger id of the incident whose replay the theorem rejects. -/
  killOf : Option String := none
  /-- How the proof is built. -/
  cls : ProofClass := .general
  /-- Declarations with a math-view entry that the statement and the proof reach, sorted. -/
  reach : List String := []
  /-- The theorem's subjects (`subjectsOf`): the operations the statement is about. -/
  subjects : List String := []
deriving Repr, Inhabited, ToJson, FromJson, ToExpr

/-- The scope of the facts: modules under `Fw`, and the anonymous module, which `Reach.modOf` returns for a name the
environment does not know or declares in no module (`importModules` sets no main module; `Reach.closure` still drops
names that are not in the environment).
$$\mathrm{scope} = ([\texttt{Fw}],\ \texttt{.anonymous}),\quad \forall m,\ \operatorname{project}_{\mathrm{scope}}(m) \iff \operatorname{root}(m) = \texttt{Fw} \lor m = \texttt{.anonymous}$$ -/
def scope : Reach.Scope := ⟨[`Fw], .anonymous⟩

/-- An expression under its leading `fun`s and metadata.
$$\operatorname{body}(\lambda x.\ e) = \operatorname{body}(e),\quad \operatorname{body}(\mathrm{mdata}(e)) = \operatorname{body}(e),\quad \operatorname{body}(e) = e \text{ otherwise}$$ -/
partial def lamBody : Expr → Expr
  | .lam _ _ b _ => lamBody b
  | .mdata _ e => lamBody e
  | e => e

/-- The number of leading binders of a type (metadata skipped, nothing unfolded).
$$\operatorname{binders}(\forall x : A,\ B) = 1 + \operatorname{binders}(B),\quad \operatorname{binders}(\mathrm{mdata}(e)) = \operatorname{binders}(e),\quad \operatorname{binders}(e) = 0 \text{ otherwise}$$ -/
partial def binderCount : Expr → Nat
  | .forallE _ _ b _ => binderCount b + 1
  | .mdata _ e => binderCount e
  | _ => 0

/-- The head constant of a proof under its leading `fun`s, unfolding an auxiliary proof of the theorem itself
(`n._proof_1`, `n.proof_1`, what `decide +kernel` and `by` blocks abstract) at most `fuel` times; `head` is the
function of an application's spine, and none when it is not a constant.
$$\operatorname{proofHead}_0(e) = \operatorname{head}(\operatorname{body}(e)),\qquad \operatorname{proofHead}_{k+1}(e) = \begin{cases} \operatorname{proofHead}_k(\mathrm{value}(c)) & \operatorname{body}(e) = c \text{ (no arguments)},\ \operatorname{prefix}(c) = n,\ c \text{ internal},\ c \text{ a theorem} \\ \operatorname{head}(\operatorname{body}(e)) & \text{otherwise} \end{cases}$$ -/
def proofHead (env : Environment) (n : Name) : Nat → Expr → Option Name
  | 0, e => (lamBody e).getAppFn.constName?
  | fuel + 1, e =>
    let b := lamBody e
    match b.getAppFn with
    | .const c _ =>
      if b.getAppNumArgs == 0 && c.getPrefix == n && c.isInternalDetail then
        match env.find? c with
        | some (.thmInfo t) => proofHead env n fuel t.value
        | _ => some c
      else some c
    | _ => none

/-- Run `x` without smart unfolding (`smartUnfolding := false`): smart unfolding reads the matcher extension, which the
math view does not load (`importModules (loadExts := false)`), so with it a recursive definition does not unfold there
while it does in an elaborated file; without it both unfold the same way (`facts%` agrees with the export).
$$\operatorname{plainUnfold}(x) = x \text{ run with } \mathit{smartUnfolding} = \mathrm{false}$$ -/
def plainUnfold {α} (x : MetaM α) : MetaM α := withOptions (·.set `smartUnfolding false) x

/-- Whether the result type of a statement (under its binders) is an `Eq`, `Iff` or `HEq` whose sides are
definitionally equal at default transparency, within a budget of `budget` thousand heartbeats; false when the budget
or the recursion limit runs out (`budget = 0` means no limit, as `maxHeartbeats` reads it). The heartbeats `isDefEq` spends depend on the environment it runs in, so near the
budget edge the answer does too. The canonical environment is the math-view export's (`importModules` with
`loadExts := false`, in `lake exe mathview`); `facts%` in an elaborated file can differ there (stated limit, one known
case guarded in `Fw.Spec.MathFactsGuards`).
$$\operatorname{sidesDefEq}(\forall \vec x,\ l \sim r) \iff l \equiv_{\delta\beta\iota\zeta} r \text{ within the budget},\quad {\sim} \in \{=, \leftrightarrow, \simeq\}$$ -/
def sidesDefEq (ty : Expr) (budget : Nat) : MetaM Bool :=
  withCurrHeartbeats <| withTheReader Core.Context (fun c => { c with maxHeartbeats := budget * 1000 }) <|
    tryCatchRuntimeEx (forallTelescope ty fun _ r => do
      let r := r.consumeMData
      let sides := match r.getAppFnArgs with
        | (``Eq, #[_, l, r]) => some (l, r)
        | (``Iff, #[l, r]) => some (l, r)
        | (``HEq, #[_, l, _, r]) => some (l, r)
        | _ => none
      match sides with
      | some (l, r) => withTransparency .default (isDefEq l r)
      | none => pure false) fun _ => pure false

/-- The heartbeat budget of `sidesDefEq`, in thousands.
$$\mathrm{defEqBudget} = 2000$$ -/
def defEqBudget : Nat := 2000

/-- Whether a type is the implementation type `Sig.Dom s → Sig.Cod s` of one of the signature constructors `sigs`.
$$\operatorname{isImplType}(\tau) \iff \exists s \in \mathit{sigs},\ \tau \equiv (\operatorname{Dom}(s) \to \operatorname{Cod}(s))$$ -/
def isImplType (sigs : List Name) (ty : Expr) : MetaM Bool := do
  for s in sigs do
    let dom ← whnf (mkApp (mkConst `Fw.Spec.Incidents.Sig.Dom) (mkConst s))
    let cod ← whnf (mkApp (mkConst `Fw.Spec.Incidents.Sig.Cod) (mkConst s))
    if ← withTransparency .default (isDefEq ty (mkForall `x .default dom cod)) then return true
  return false

/-- The registry rows as `Row`s: id, row definition name (when the registry lists a named definition) and replay name;
a row that does not reduce to an `Incident.mk` literal with a string id and a named replay is skipped. Below,
$\operatorname{const}(e)$ is the name of $e$ when $e$ is a constant and $\bot$ otherwise.
$$\operatorname{rows} = [(\iota, \operatorname{const}(i), r) : (s, i) \in \operatorname{registryRows},\ \operatorname{whnf}(i) = \mathrm{Incident.mk}(\_, \_, e_\iota, \_, r),\ \operatorname{strLit}(e_\iota) = \iota,\ r \text{ a constant}]$$ -/
def rows : MetaM (List Row) := plainUnfold do
  let mut out : List Row := []
  for (_, e) in ← Reach.registryRows do
    let r ← whnf e
    match r.getAppFnArgs with
    | (``Fw.Spec.Props.Incident.mk, #[_, _, idE, _, replayE]) =>
      let some rep := replayE.consumeMData.constName? | continue
      let id ← try Reach.strLit idE catch _ => continue
      out := out ++ [⟨id, e.consumeMData.constName?, rep⟩]
    | _ => continue
  return out

/-- The target of an implementation argument: a constant $c$ itself, or the row $c$ of a projection `Incident.replay c`;
none otherwise.
$$\operatorname{target}(c) = c,\quad \operatorname{target}(\mathrm{replay}(c)) = c,\quad \operatorname{target}(e) = \bot \text{ otherwise}$$ -/
def target (e : Expr) : Option Name :=
  let e := e.consumeMData
  match e with
  | .const c _ => some c
  | _ =>
    if e.isAppOf ``Fw.Spec.Props.Incident.replay then e.appArg!.consumeMData.constName? else none

/-- The premise id of an `Assume p c` application, when `p` reduces to a structure literal with a literal id.
$$\operatorname{premiseId}(\mathrm{Assume}(p, c)) = p.\mathit{id} \text{ when it reduces to a literal}$$ -/
def premiseId (p : Expr) : MetaM (Option String) := do
  try
    let idE ← mkAppM ``Fw.Spec.Props.Premise.id #[p]
    return some (← Reach.strLit idE)
  catch _ => return none

/-- The `Assume p c` applications anywhere in an expression, outermost first.
$$\operatorname{assumeApps}(e) = [p : \mathrm{Assume}(p, c) \text{ a subterm of } e]$$ -/
partial def assumeApps (e : Expr) : List Expr :=
  let here := match e.getAppFnArgs with
    | (``Fw.Spec.Props.Assume, #[p, _]) => [p]
    | _ => []
  let sub := match e with
    | .app f a => assumeApps f ++ assumeApps a
    | .lam _ t b _ | .forallE _ t b _ => assumeApps t ++ assumeApps b
    | .letE _ t v b _ => assumeApps t ++ assumeApps v ++ assumeApps b
    | .mdata _ b | .proj _ _ b => assumeApps b
    | _ => []
  here ++ sub

/-- Whether a constant is a declaration the facts list: a project definition or opaque (and, when `thms` is set, a
theorem) that the math view would export, so not an auxiliary recursor, a `noConfusion`, a projection, a reserved or
internal name, nor a name with an `inst…` component.
$$\operatorname{entryLike}_{T}(c) \iff \operatorname{project}(c) \land \operatorname{kind}(c) \in \{\mathrm{def}, \mathrm{opaque}\} \cup T \land \lnot\operatorname{generated}(c),\quad T = \begin{cases} \{\mathrm{theorem}\} & \mathit{thms} \\ \emptyset & \text{otherwise} \end{cases}$$ -/
def entryLike (c : Name) (thms : Bool) : MetaM Bool := do
  let env ← getEnv
  unless Reach.isProject scope (Reach.modOf env c) do return false
  let kindOk := match env.find? c with
    | some (.defnInfo _) | some (.opaqueInfo _) => true
    | some (.thmInfo _) => thms
    | _ => false
  if !kindOk || c.isInternalDetail || isAuxRecursor env c || isNoConfusion env c || isReservedName env c then
    return false
  if c.components.any (fun x => x.toString.startsWith "inst") then return false
  return !(← isProjectionFn c)

/-- **Does a constant get a math-view entry?** The tests `MathView.entries` and `MathView.entryOf` apply, in one
place: `MathView.skip` keeps it, it is imported (has a module index), its name is not internal and has no `.match_`
part, no component starts with `inst`, it has a source line (not generated, so no `ctorIdx` or `noConfusionType`),
and it is neither an instance nor a structure projection. The export also keeps a reach name only when it is an
exported entry name (`entryJson`), so a drift between this copy and `MathView` cannot list a name without an entry.
Below, $\sqsubseteq_{\mathrm{str}}$ reads "is a substring of" and $\preceq_{\mathrm{str}}$ "is a string prefix of".
$$\forall n, c,\ \operatorname{hasEntry}(n, c) \iff \lnot\operatorname{skip}(n, c) \land \operatorname{mod}(n) \ne \bot \land \lnot\operatorname{internal}(n) \land \texttt{.match\_} \not\sqsubseteq_{\mathrm{str}} n \land \lnot\exists x \in \operatorname{components}(n),\ \texttt{inst} \preceq_{\mathrm{str}} x \land \operatorname{line}(n) \ne 0 \land \lnot\operatorname{instance}(n) \land \lnot\operatorname{projection}(n)$$ -/
def hasEntry (n : Name) (ci : ConstantInfo) : MetaM Bool := do
  let env ← getEnv
  if MathView.skip env n ci || (env.getModuleIdxFor? n).isNone || n.isInternal then return false
  if (n.toString.splitOn ".match_").length > 1 then return false
  if n.components.any (fun c => c.toString.startsWith "inst") then return false
  let line := ((← findDeclarationRanges? n).map (·.range.pos.line)).getD 0
  return line != 0 && !(← isInstance n) && !(← isProjectionFn n)

/-- Whether a constant's type ends in a sort: under its binders, opened with `forallTelescopeReducing` (which unfolds
to expose them), the result type in weak head normal form is `Sort u`. A type (`Counts : Type`), a type family or a
predicate (`lt : Work → Work → Prop`) is sort-valued; an operation on data is not.
$$\forall c,\ \operatorname{sortValued}(c) \iff \exists u,\ \tau_c \equiv_{\mathrm{whnf}} \forall \vec x,\ \mathrm{Sort}\ u$$ -/
def sortValued (c : Name) : MetaM Bool := do
  let ci ← getConstInfo c
  forallTelescopeReducing ci.type fun _ r => return (← whnf r).isSort

/-- The operations among constants: the `entryLike` definitions and opaques (theorems excluded) that are not
sort-valued, in order.
$$\forall X,\ \operatorname{ops}(X) = [c \in X : \operatorname{entryLike}_{\emptyset}(c),\ \lnot\operatorname{sortValued}(c)]$$ -/
def opsOf (cs : List Name) : MetaM (List Name) :=
  cs.filterM fun c => do
    unless ← entryLike c false do return false
    return !(← sortValued c)

/-- The operations an inductive predicate is built from: starting from the project inductive predicates (inductives
whose type ends in `Prop`) among `cs`, the `opsOf` the constants of their constructors' types, following each project
inductive predicate those types name, each inductive once; definitions are not unfolded. The result is a list in
breadth-first order (repeats are removed by `factsOf`). Below, $P(Z)$ is the set of project inductive predicates in
$Z$ and $Y^{*}$ the least set with $P(X) \subseteq Y^{*}$ and $P(\operatorname{consts}(\tau_k)) \subseteq Y^{*}$ for
every $I \in Y^{*}$ and $k \in \operatorname{ctors}(I)$.
$$\forall X,\ \operatorname{set}(\operatorname{ctorOps}(X)) =\bigcup \{\operatorname{set}(\operatorname{ops}(\operatorname{consts}(\tau_k))) : I \in Y^{*},\ k \in \operatorname{ctors}(I)\}$$ -/
def ctorOps (cs : List Name) : MetaM (List Name) := do
  let env ← getEnv
  let mut seen : NameSet := {}
  let mut todo := cs
  let mut out : List Name := []
  while true do
    match todo with
    | [] => break
    | c :: rest =>
      todo := rest
      if seen.contains c then continue
      seen := seen.insert c
      let some (.inductInfo i) := env.find? c | continue
      unless Reach.isProject scope (Reach.modOf env c) do continue
      unless ← forallTelescopeReducing i.type fun _ r => return r.isProp do continue
      let ks := i.ctors.flatMap fun k => ((env.find? k).map (·.type.getUsedConstants.toList)).getD []
      out := out ++ (← opsOf ks)
      todo := rest ++ ks
  return out

/-- **The subjects of a theorem** with statement $\tau$ and implementation argument $a$: the operations among the
constants of $a$ (or of $\tau$ when there is no implementation argument); when there are none, the operations its
inductive predicates are built from (`ctorOps` over the constants of $\tau$); possibly empty.
$$\forall \tau, a,\ \operatorname{subjects}(\tau, a) =\begin{cases} \operatorname{ops}(X) & \operatorname{ops}(X) \ne [\,] \\ \operatorname{ctorOps}(\operatorname{consts}(\tau)) & \text{otherwise} \end{cases},\quad X = \begin{cases} \operatorname{consts}(a) & a \ne \bot \\ \operatorname{consts}(\tau) & a = \bot \end{cases}$$ -/
def subjectsOf (ty : Expr) (implE : Option Expr) : MetaM (List Name) := do
  let base ← opsOf (match implE with | some a => a.getUsedConstants.toList | none => ty.getUsedConstants.toList)
  if base.isEmpty then ctorOps ty.getUsedConstants.toList else return base

/-- **The facts of one theorem** $n$ with constant info `ci`, given the registry rows. Its head constant and
implementation argument come from the result type under one `¬`; its premises from the `Assume` applications in the
hypotheses with a literal id (deduplicated, in order); its kill from `killOf`; its class from `classify`; its reach
from `closure` over the constants of its statement and proof, keeping the names other than $n$ that have a math-view
entry (`hasEntry`), sorted by printed name; its subjects from `subjectsOf`, without repeats. Runs under
`plainUnfold`.
$$\operatorname{factsOf}(n) = \bigl(h, a, A, \operatorname{killOf}(\nu, \operatorname{target}(a), R), \operatorname{classify}(\operatorname{binders}(\tau_n), \operatorname{proofHead}_4(v_n), \operatorname{sidesDefEq}(\tau_n)), \operatorname{sort}\{c \in \operatorname{closure}(\operatorname{consts}(\tau_n) \mathbin{+\!\!+} \operatorname{consts}(v_n)) \mid c \ne n,\ \operatorname{hasEntry}(c)\}, \operatorname{dedup}(\operatorname{subjects}(\tau_n, a))\bigr)$$ -/
def factsOf (n : Name) (ci : ConstantInfo) (rs : List Row) : MetaM Facts := plainUnfold do
  let env ← getEnv
  let value := match ci with | .thmInfo t => t.value | _ => default
  forallTelescope ci.type fun xs body => do
    let body := body.consumeMData
    let (negated, core) := if body.isAppOfArity ``Not 1 then (true, body.appArg!.consumeMData) else (false, body)
    let head := core.getAppFn.constName?
    -- the implementation argument: only for a project head (a property or `Convention`), by its type
    let (implI, implE) ← do
      match head with
      | some h =>
        if Reach.isProject scope (Reach.modOf env h) then
          let args := core.getAppArgs.toList
          let flags ← args.mapM fun a => do isImplType (Reach.sigCtors env) (← inferType a)
          match implIdx flags with
          | some i => pure (some i, args[i]?)
          | none => pure (none, none)
        else pure (none, none)
      | none => pure (none, none)
    let implS ← implE.mapM fun a => do
      withOptions (fun o => (o.set `pp.fullNames true).set `format.width (1000 : Nat)) do
        return toString (← ppExpr a)
    let mut assumes : List String := []
    for x in xs do
      for p in assumeApps (← inferType x) do
        if let some id ← premiseId p then
          unless assumes.contains id do assumes := assumes ++ [id]
    let kill := killOf negated (implE.bind target) rs
    let d ← sidesDefEq ci.type defEqBudget
    let cls := classify ⟨binderCount ci.type, proofHead env n 4 value, d⟩
    let roots := ci.type.getUsedConstants.toList ++ value.getUsedConstants.toList
    let reach ← (Reach.closure env scope roots).filterM fun c => do
      let some cc := env.find? c | return false
      return c != n && (← hasEntry c cc)
    let reachS := (reach.map toString).toArray.qsort (· < ·) |>.toList
    let subjects ← subjectsOf ci.type implE
    return { headConst := head.map toString, implIdx := implI, implExpr := implS, assumes, killOf := kill, cls,
             reach := reachS, subjects := (subjects.map toString).eraseDups }

/-- The fwcore dispatcher, the one wire root besides the generators.
$$\mathrm{dispatcher} = \texttt{Fw.Wire.handle}$$ -/
def dispatcher : Name := `Fw.Wire.handle

/-- **The wire reach** $W$: every project declaration reachable (`closure`) from the fwcore dispatcher
`Fw.Wire.handle` and from the `Fw.` identifiers (`fwIdents`) of the given generator sources that name a constant of
the environment (research/notes/2026/10-18-lean-first-gate.md, land check (d)). No module is a root by its name.
$$\forall \mathit{srcs},\ W(\mathit{srcs}) = \operatorname{closure}\bigl([\texttt{Fw.Wire.handle}] \mathbin{+\!\!+} [c : s \in \mathit{srcs},\ c \in \operatorname{fwIdents}(s),\ c \in \mathrm{env}]\bigr)$$ -/
def wireReach (env : Environment) (srcs : List String) : List Name :=
  let named := (srcs.flatMap fwIdents).filterMap fun s => let c := s.toName; if env.contains c then some c else none
  Reach.closure env scope (dispatcher :: named)

/-- The generator sources: the text of every file under `root/scripts` whose name ends in `Golden.lean`, in path
order; none when the directory is missing.
$$\operatorname{goldenSources}(\mathit{root}) = [\operatorname{read}(f) : f \in \operatorname{sort}\{f \in \mathit{root}/\texttt{scripts} \mid f \text{ ends with } \texttt{Golden.lean}\}]$$ -/
def goldenSources (root : System.FilePath) : IO (List String) := do
  let dir := root / "scripts"
  unless ← dir.pathExists do return []
  let fs := (← dir.readDir).filter (·.fileName.endsWith "Golden.lean") |>.map (·.path)
  fs.qsort (·.toString < ·.toString) |>.toList.mapM IO.FS.readFile

/-- `wire% n`: whether the constant `n` is in the wire reach $W$ of the current environment, with the generator
sources read from `scripts/` under the working directory (the package root under `lake build`); for `#guard`s.
$$\texttt{wire\%}\ n \iff n \in W$$ -/
elab "wire% " n:ident : term => do
  let c ← realizeGlobalConstNoOverloadWithInfo n
  let w := wireReach (← getEnv) (← goldenSources ".")
  return toExpr (w.contains c)

/-- `wireOf% n`: `reachFromWire` of the theorem `n`'s subjects against the wire reach $W$ of the current environment
(generator sources as in `wire%`); for `#guard`s.
$$\texttt{wireOf\%}\ n = \operatorname{reachFromWire}(\operatorname{factsOf}(n).S,\ W)$$ -/
elab "wireOf% " n:ident : term => do
  let c ← realizeGlobalConstNoOverloadWithInfo n
  let f ← factsOf c (← getConstInfo c) (← rows)
  let w := wireReach (← getEnv) (← goldenSources ".")
  let ws := w.foldl (fun s x => s.insert x.toString) (∅ : Std.HashSet String)
  return toExpr (reachFromWire f.subjects ws.contains)

/-- `defEqAt% n k`: `sidesDefEq` of the theorem `n`'s statement within `k` thousand heartbeats, under `plainUnfold`
(`k = 0` means no limit); for `#guard`s on the budget edge of the `defEq` class.
$$\texttt{defEqAt\%}\ n\ k = \operatorname{sidesDefEq}(\tau_n, k)$$ -/
elab "defEqAt% " n:ident k:num : term => do
  let c ← realizeGlobalConstNoOverloadWithInfo n
  return toExpr (← plainUnfold (sidesDefEq (← getConstInfo c).type k.getNat))

/-- `facts% n`: the `Facts` of the theorem `n`, computed at elaboration time in the current environment (for
`#guard`s over real declarations).
$$\texttt{facts\%}\ n = \operatorname{factsOf}(n)$$ -/
elab "facts% " n:ident : term => do
  let c ← realizeGlobalConstNoOverloadWithInfo n
  let ci ← getConstInfo c
  let f ← factsOf c ci (← rows)
  return toExpr f

end Fw.Spec.MathFacts
