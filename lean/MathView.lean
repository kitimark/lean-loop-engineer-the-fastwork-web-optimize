import Lean
import Fw.Spec.AxReach
/-!
# Math view (ported from the kickoff scratch `04-mathview`, note 10/04)

Export every `Fw.*` declaration as a math-view entry.

Per declaration: kind, module, docstring, the `$$…$$` blocks found in it, the pretty-printed
signature, a *deep* statement hash (signature + bodies of every `Fw.*` definition it reaches),
a docstring hash (the whole docstring, whitespace-normalised, so a review goes stale when its math or English changes),
the axioms it depends on (an unfinished proof shows as `sorryAx`), and a mechanical LaTeX rendering of the type.
-/
namespace MathView
open Lean Meta

/-! ## Mechanical Expr → LaTeX (small fixed vocabulary; anything unknown becomes `\mathrm{f}(…)`) -/

def tt (s : String) : String := "\\mathrm{" ++ (s.replace "_" "\\_") ++ "}"

def bname (n : Name) : String := tt n.eraseMacroScopes.toString

def paren (s : String) : String := "(" ++ s ++ ")"

/-- Is this rendered string atomic enough to skip parentheses? -/
def atomic (s : String) : Bool := !(s.contains ' ')

def wrap (s : String) : String := if atomic s then s else paren s

def binop : Name → Option String
  | ``Iff => some "\\iff" | ``And => some "\\land" | ``Or => some "\\lor"
  | ``LE.le => some "\\le" | ``LT.lt => some "<" | ``GE.ge => some "\\ge" | ``GT.gt => some ">"
  | ``HAdd.hAdd => some "+" | ``HMul.hMul => some "\\cdot" | ``Ne => some "\\neq"
  | ``HAppend.hAppend => some "\\mathbin{+\\!\\!+}"
  | _ => none

/-- Keep only explicit arguments (drop types, implicit args and instances). -/
def explicitArgs (f : Expr) (args : Array Expr) : MetaM (Array Expr) := do
  let info ← getFunInfoNArgs f args.size
  let mut out := #[]
  for i in [:args.size] do
    let bi := (info.paramInfo[i]?.map (·.binderInfo)).getD .default
    if bi.isExplicit then out := out.push args[i]!
  return out

partial def latex (e : Expr) : MetaM String := do
  let e ← instantiateMVars e
  match e with
  | .forallE n t b bi =>
    if b.hasLooseBVars || !bi.isExplicit then
      withLocalDecl n bi t fun x => do
        let body ← latex (b.instantiate1 x)
        let ty ← latex t
        if (← isProp t) then return s!"({ty}) \\Rightarrow {body}"
        return s!"\\forall {bname n} \\in {ty},\\ {body}"
    else
      return s!"{wrap (← latex t)} \\Rightarrow {← latex b}"
  | .lam n t b bi =>
    withLocalDecl n bi t fun x => do
      return s!"({bname n} \\mapsto {← latex (b.instantiate1 x)})"
  | .fvar id => return bname (← id.getDecl).userName
  | .lit (.natVal k) => return toString k
  | .lit (.strVal s) => return s!"\\texttt\{\"{s}\"}"
  | .sort u => return if u.isZero then "\\mathbf{Prop}" else "\\mathbf{Type}"
  | .mdata _ e => latex e
  | .proj _ i s => return s!"{wrap (← latex s)}.{i}"
  | _ =>
    let f := e.getAppFn
    let args := e.getAppArgs
    match f with
    | .const c _ =>
      let ex ← explicitArgs f args
      if c == ``Nat then return "\\mathbb{N}"
      if (c == ``ite || c == ``dite) && args.size == 5 then
        let br (e : Expr) : MetaM String := match e with
          | .lam n t b bi => withLocalDecl n bi t fun x => latex (b.instantiate1 x)
          | e => latex e
        let br' : Expr → MetaM String := if c == ``dite then br else latex
        return s!"\\textbf\{if } {← latex args[1]!} \\textbf\{ then } {← br' args[3]!} \\textbf\{ else } {← br' args[4]!}"
      if c == ``Int then return "\\mathbb{Z}"
      if c == ``Bool.true then return "\\mathrm{true}"
      if c == ``Bool.false then return "\\mathrm{false}"
      if c == ``OfNat.ofNat && args.size ≥ 2 then return ← latex args[1]!
      if c == ``Eq && ex.size == 2 then return s!"{← latex ex[0]!} = {← latex ex[1]!}"
      if c == ``Not && ex.size == 1 then return s!"\\neg {wrap (← latex ex[0]!)}"
      if c == ``False then return "\\bot"
      if c == ``Neg.neg && ex.size == 1 then return s!"-{wrap (← latex ex[0]!)}"
      if c == ``HDiv.hDiv && ex.size == 2 then
        -- integer division rounds down; on ℚ it is exact
        let ty ← whnf (← inferType e)
        let fr := s!"\\frac\{{← latex ex[0]!}}\{{← latex ex[1]!}}"
        return if ty.isConstOf ``Nat || ty.isConstOf ``Int then s!"\\left\\lfloor {fr} \\right\\rfloor" else fr
      if c == ``HSub.hSub && ex.size == 2 then return s!"{← latex ex[0]!} \\mathbin\{\\dot-} {wrap (← latex ex[1]!)}"
      if c == ``Membership.mem && ex.size == 2 then  -- `mem coll x` in Lean ≥ 4.12
        return s!"{← latex ex[1]!} \\in {← latex ex[0]!}"
      if c == ``List.length && ex.size == 1 then return s!"\\lvert {← latex ex[0]!} \\rvert"
      if c == ``List.nil then return "[\\,]"
      if c == ``List.cons && ex.size == 2 then return s!"{← latex ex[0]!} :: {← latex ex[1]!}"
      if c == ``Max.max && ex.size == 2 then return s!"\\max({← latex ex[0]!}, {← latex ex[1]!})"
      if c == ``decide && ex.size == 1 then return s!"[{← latex ex[0]!}]"
      if c == ``Exists && ex.size == 1 then
        match ex[0]! with
        | .lam n t b bi =>
          let r ← withLocalDecl n bi t fun x => do
            return s!"\\exists {bname n} \\in {← latex t},\\ {← latex (b.instantiate1 x)}"
          return r
        | p => return s!"\\exists\\ {← latex p}"
      if let some op := binop c then
        if ex.size == 2 then return s!"{wrap (← latex ex[0]!)} {op} {wrap (← latex ex[1]!)}"
      -- structure projections: `s.holder`
      if let some pinfo ← getProjectionFnInfo? c then
        if args.size > pinfo.numParams then
          let s ← latex args[pinfo.numParams]!
          let rest ← (args.extract (pinfo.numParams + 1) args.size).mapM latex
          let base := s!"{wrap s}.{tt c.getString!}"
          return if rest.isEmpty then base else s!"{base}({", ".intercalate rest.toList})"
      let fn := tt (c.componentsRev.head?.map (·.toString) |>.getD c.toString)
      if ex.isEmpty then return fn
      return s!"{fn}({", ".intercalate (← ex.toList.mapM latex)})"
    | _ =>
      if args.isEmpty then  -- let, bvar, mvar, …: fall back to the Lean pretty-printer
        return s!"\\texttt\{{toString (← ppExpr f)}}"
      let fs ← latex f
      return s!"{fs}({", ".intercalate (← args.toList.mapM latex)})"

/-! ## Deep statement hash: signature + transitive bodies of `Fw.*` definitions it mentions -/

def inScope (n : Name) : Bool := (`Fw).isPrefixOf n

partial def deepConsts (env : Environment) (todo : List Name) (seen : NameSet) : NameSet :=
  match todo with
  | [] => seen
  | c :: rest =>
    if seen.contains c || !inScope c then deepConsts env rest seen else
    let seen := seen.insert c
    let more := match env.find? c with
      | some (.defnInfo d) => d.type.getUsedConstants.toList ++ d.value.getUsedConstants.toList
      | some (.inductInfo i) => i.ctors ++ i.type.getUsedConstants.toList
      | some (.ctorInfo i) => i.type.getUsedConstants.toList
      | some ci => ci.type.getUsedConstants.toList
      | none => []
    deepConsts env (more ++ rest) seen

def stmtHash (env : Environment) (ci : ConstantInfo) : UInt64 :=
  let deps := deepConsts env ci.type.getUsedConstants.toList {}
  deps.toList.foldl (init := hash ci.type) fun h c =>
    match env.find? c with
    | some (.defnInfo d) => mixHash h (mixHash (hash c) (mixHash (hash d.type) (hash d.value)))
    | some ci' => mixHash h (mixHash (hash c) (hash ci'.type))
    | none => h

/-! ## Docstring hash: the reviewed text (English, `$$` blocks, notes), whitespace-normalised -/

/-- The docstring with every run of whitespace collapsed to one space and the ends trimmed, so re-indenting or
re-wrapping a docstring does not change it.

$$\mathrm{normDoc}(d) = w_1 \,\texttt{" "}\, w_2 \,\texttt{" "} \cdots \texttt{" "}\, w_k$$

where $w_1, \dots, w_k$ are the maximal runs of non-whitespace characters of $d$, in order. -/
def normDoc (doc : String) : String :=
  let (words, cur) := doc.toList.foldl (init := (([] : List String), "")) fun (ws, w) c =>
    if c.isWhitespace then (if w.isEmpty then (ws, w) else (w :: ws, "")) else (ws, w.push c)
  " ".intercalate (if cur.isEmpty then words else cur :: words).reverse

/-- The docstring hash: Lean's `String` hash (MurmurHash64A, deterministic across runs) of the normalised
docstring, or `0` when there is none.

$$\mathrm{mathHash}(\bot) = 0, \qquad \mathrm{mathHash}(d) = \mathrm{hash}(\mathrm{normDoc}(d))$$

A review row carrying this hash goes stale when any word of the docstring's English, `$$` math or notes changes. -/
def mathHash : Option String → UInt64
  | none => 0
  | some doc => hash (normDoc doc)

#guard normDoc "  a\n   b\t c  " == "a b c"
#guard normDoc "" == ""
#guard mathHash (some "x  $$a$$\n  y") == mathHash (some "x $$a$$ y")
#guard mathHash (some "x $$a$$") != mathHash (some "x $$b$$")
#guard mathHash none == 0

/-! ## Entries -/

structure Entry where
  name      : String
  kind      : String
  module    : String
  doc       : Option String
  english   : String          -- the docstring text before its first `$$`
  math      : List String     -- `$$…$$` blocks in the docstring
  signature : String
  autoTex   : String
  stmtHash  : String
  mathHash  : String          -- hash of the whitespace-normalised docstring (`mathHash`)
  axioms    : List String
  sorryFree : Bool
  line      : Nat
  heartbeats : Nat            -- heartbeats this entry cost (each entry has its own budget)
  error     : Option String := none  -- the export of this entry failed (lint failure)
  binders   : List String := []  -- names of a theorem's explicit, non-proof binders (for the quantifier lint)
deriving ToJson, FromJson

/-- The export order, a total key (module, line, name); names are unique in an environment, so no two entries tie
and the sorted export does not depend on the order in which the environment lists its constants.

$$\forall a, b:\quad \operatorname{before}(a, b) \iff a.\mathit{mod} < b.\mathit{mod} \lor \big(a.\mathit{mod} = b.\mathit{mod} \land (a.\mathit{line} < b.\mathit{line} \lor (a.\mathit{line} = b.\mathit{line} \land a.\mathit{name} < b.\mathit{name}))\big)$$

where $<$ on module and declaration names is the lexicographic order of their strings and on lines the order of
$\mathbb{N}$. -/
def Entry.before (a b : Entry) : Bool :=
  a.module < b.module || (a.module == b.module && (a.line < b.line || (a.line == b.line && a.name < b.name)))

/-- Two strings that differ are ordered one way or the other.

$$\forall a, b \in \mathrm{String}:\quad a \ne b \Rightarrow a < b \lor b < a$$ -/
theorem string_lt_or_gt (a b : String) (h : a ≠ b) : a < b ∨ b < a := by
  by_cases h1 : a < b
  · exact .inl h1
  · by_cases h2 : b < a
    · exact .inr h2
    · exact absurd (String.le_antisymm (String.not_lt.mp h2) (String.not_lt.mp h1)) h

/-- **The sort key is total.** Two entries with different names are ordered one way or the other, so sorting the
export by `before` has no ties (premise E3 of `Fw.Console.LandSpeed.lintAll`).

$$\forall a, b:\quad a.\mathit{name} \ne b.\mathit{name} \Rightarrow \operatorname{before}(a, b) \lor \operatorname{before}(b, a)$$ -/
theorem Entry.before_total (a b : Entry) (h : a.name ≠ b.name) : a.before b = true ∨ b.before a = true := by
  simp only [Entry.before, Bool.or_eq_true, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq]
  by_cases hm : a.module = b.module
  · by_cases hl : a.line = b.line
    · rcases string_lt_or_gt a.name b.name h with hn | hn
      · exact .inl (.inr ⟨hm, .inr ⟨hl, hn⟩⟩)
      · exact .inr (.inr ⟨hm.symm, .inr ⟨hl.symm, hn⟩⟩)
    · rcases Nat.lt_or_gt_of_ne hl with hn | hn
      · exact .inl (.inr ⟨hm, .inl hn⟩)
      · exact .inr (.inr ⟨hm.symm, .inl hn⟩)
  · rcases string_lt_or_gt a.module b.module hm with hn | hn
    · exact .inl (.inl hn)
    · exact .inr (.inl hn)

/-- **The sort key is a strict order.** No entry comes before an entry that comes before it.

$$\forall a, b:\quad \operatorname{before}(a, b) \Rightarrow \lnot \operatorname{before}(b, a)$$ -/
theorem Entry.before_asymm (a b : Entry) (h : a.before b = true) : b.before a = false := by
  simp only [Entry.before, Bool.or_eq_true, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at h
  simp only [Entry.before, Bool.or_eq_false_iff, Bool.and_eq_false_iff, beq_eq_false_iff_ne, ne_eq,
    decide_eq_false_iff_not]
  rcases h with h | ⟨hm, h | ⟨hl, h⟩⟩
  · exact ⟨String.lt_asymm h, .inl (fun e => String.lt_irrefl _ (e ▸ h))⟩
  · exact ⟨fun e => String.lt_irrefl _ (hm ▸ e), .inr ⟨Nat.lt_asymm h, .inl (fun e => Nat.lt_irrefl _ (e ▸ h))⟩⟩
  · exact ⟨fun e => String.lt_irrefl _ (hm ▸ e), .inr ⟨fun e => Nat.lt_irrefl _ (hl ▸ e), .inr (String.lt_asymm h)⟩⟩

def mathBlocks (doc : String) : List String :=
  match doc.splitOn "$$" with
  | _ :: rest => (rest.zipIdx.filter (·.2 % 2 == 0)).map (·.1.trimAscii.toString)
  | [] => []

/-- The English part of a docstring: everything before the first `$$`, trimmed. -/
def english (doc : String) : String :=
  match doc.splitOn "$$" with
  | e :: _ => e.trimAscii.toString
  | [] => ""

def kindOf : ConstantInfo → String
  | .thmInfo _ => "theorem" | .defnInfo _ => "def" | .inductInfo _ => "inductive"
  | .ctorInfo _ => "ctor" | .axiomInfo _ => "axiom" | .opaqueInfo _ => "opaque" | _ => "other"

def skip (env : Environment) (n : Name) (ci : ConstantInfo) : Bool :=
  !inScope n || n.isInternalDetail || isAuxRecursor env n || isNoConfusion env n ||
  (match ci with | .ctorInfo _ | .recInfo _ => true | _ => false) ||
  (`Fw.Wire).isPrefixOf n

/-- **Does a constant get a math-view entry?** It is imported (has a module index), `skip` keeps it, its name is not
internal and has no `.match_` part, and no component starts with `inst` (derived-instance helpers such as
`instReprWork.repr`). `entries` lists exactly these constants; the math-view facts keep a reach by this test.
$$\forall n, c,\ \operatorname{hasEntry}(n, c) \iff \operatorname{mod}(n) \ne \bot \land \lnot\operatorname{skip}(n, c) \land \lnot\operatorname{internal}(n) \land \texttt{.match\_} \not\sqsubseteq_{\mathrm{str}} n \land \lnot\exists x \in \operatorname{components}(n),\ \texttt{inst} \preceq_{\mathrm{str}} x$$
where $\sqsubseteq_{\mathrm{str}}$ is "is a substring of" and $\preceq_{\mathrm{str}}$ is "is a string prefix of". -/
def hasEntry (env : Environment) (n : Name) (ci : ConstantInfo) : Bool :=
  (env.getModuleIdxFor? n).isSome && !skip env n ci && !n.isInternal &&
    (n.toString.splitOn ".match_").length ≤ 1 && !n.components.any (fun c => c.toString.startsWith "inst")

/-- Heartbeat budget of one declaration's export, in thousands (the unit of `maxHeartbeats`). Each declaration
gets a fresh budget, so the export's total cost grows with the number of declarations without ever hitting a
global limit. -/
def declBudget : Nat := 200000

/-- Heartbeat budget of one `autoTex` rendering, in thousands; past it `autoTex` is `"?"` (not a lint failure:
the reviewed statement is the docstring math). -/
def texBudget : Nat := 50000

/-- Run `x` with a fresh heartbeat budget of `k` thousand heartbeats, catching every exception, including the
runtime ones (heartbeat timeout, max recursion) that a plain `try … catch` lets through. -/
def bounded {α} (k : Nat) (x : MetaM α) : MetaM (Except String α) :=
  withCurrHeartbeats <| withTheReader Core.Context (fun c => { c with maxHeartbeats := k * 1000 }) <|
    tryCatchRuntimeEx (Except.ok <$> x) fun e => do
      return .error (((← e.toMessageData.toString).splitOn "\n").headD "")

/-- The heartbeats spent since `start`, in thousands. -/
def spentSince (start : Nat) : CoreM Nat := do return ((← IO.getNumHeartbeats) - start) / 1000

/-- Names of the explicit and implicit binders of a theorem's type that are data (not proofs, not types, not compiler-named). -/
def dataBinders (ci : ConstantInfo) : MetaM (List String) :=
  forallTelescope ci.type fun xs _ => do
    let mut out := []
    for x in xs do
      let d ← x.fvarId!.getDecl
      if d.binderInfo.isInstImplicit || d.userName.hasMacroScopes || d.userName.isInaccessibleUserName then continue
      if (← isProp d.type) || (← whnf d.type).isSort then continue
      out := out ++ [d.userName.toString]
    return out

/-! ## Axioms: one memo shared by all entries (spec and proofs: `Fw.Spec.AxReach`)

`collectAxioms` starts every call from an empty cache, and with `loadExts := false` its per-module table is empty
too, so each entry re-walked its whole closure (96 % of the lint, research/notes/2026/10-18-land-speed.md). Here the
walk is `Fw.AxReach.query` over the same graph with one memo for the whole export; `Fw.AxReach.query_exact` proves
each result is exactly the reachable axioms, the set the old per-call walk returned. -/

/-- The constants `c` mentions, in the cases of Lean's `CollectAxioms.collect`
(Lean/Util/CollectAxioms.lean:56-67 @ v4.35.0): type and value of a definition, theorem or opaque; the type of an
axiom, constructor or recursor; the type and the constructors of an inductive; nothing for `Quot` or an unknown name.

$$\mathit{succ}(c) = \begin{cases} \mathrm{consts}(\tau_c) \mathbin{+\!\!+} \mathrm{consts}(v_c) & c \text{ a def,
theorem or opaque} \\ \mathrm{consts}(\tau_c) \mathbin{+\!\!+} \mathrm{ctors}(c) & c \text{ an inductive} \\ [\,] &
c \text{ a quotient primitive or unknown} \\ \mathrm{consts}(\tau_c) & \text{otherwise} \end{cases}$$
where $\tau_c$, $v_c$ and $\mathrm{ctors}(c)$ are the type, value and constructors of $\mathit{kenv}(c)$.
-/
def axSucc (kenv : Kernel.Environment) (c : Name) : List Name :=
  match kenv.find? c with
  | some (.axiomInfo v) => v.type.getUsedConstants.toList
  | some (.defnInfo v) => (v.type.getUsedConstants ++ v.value.getUsedConstants).toList
  | some (.thmInfo v) => (v.type.getUsedConstants ++ v.value.getUsedConstants).toList
  | some (.opaqueInfo v) => (v.type.getUsedConstants ++ v.value.getUsedConstants).toList
  | some (.quotInfo _) => []
  | some (.ctorInfo v) => v.type.getUsedConstants.toList
  | some (.recInfo v) => v.type.getUsedConstants.toList
  | some (.inductInfo v) => v.type.getUsedConstants.toList ++ v.ctors
  | none => []

/-- Is `c` declared as an axiom in the kernel environment?

$$\mathit{isAx}(c) = \mathrm{true} \iff \mathit{kenv}(c) = \mathrm{axiomInfo}(\_)$$
(false for an unknown name and for every other kind)
-/
def axIsAx (kenv : Kernel.Environment) (c : Name) : Bool :=
  match kenv.find? c with
  | some (.axiomInfo _) => true
  | _ => false

/-- The export of one declaration (`none` when it is not a math-view entry); `axs` are its axioms, sorted. -/
def entryOf (env : Environment) (n : Name) (ci : ConstantInfo) (mod : Name) (doc : Option String)
    (axs : Array Name) : MetaM (Option Entry) := do
  let line := ((← findDeclarationRanges? n).map (·.range.pos.line)).getD 0
  if line == 0 || (← isInstance n) || (← isProjectionFn n) then return none
  let start ← IO.getNumHeartbeats
  let sig ← withOptions (fun o => o.set `format.width (1000 : Nat)) do
    return toString (← PrettyPrinter.ppSignature n).fmt
  -- for a def, render its unfolding equation `f.eq_def : ∀ xs, f xs = body` instead of its type
  let auto ← match ← bounded texBudget (do
      let eqnTy? ← match ci with
        | .defnInfo _ => do
          let some eq ← (try getUnfoldEqnFor? n (nonRec := true) catch _ => pure none) | pure none
          pure (some (← getConstInfo eq).type)
        | _ => pure none
      latex (eqnTy?.getD ci.type)) with
    | .ok t => pure t
    | .error _ => pure "?"
  let binders ← match ci with
    | .thmInfo _ => dataBinders ci
    | _ => pure []
  return some {
    name := n.toString, kind := kindOf ci, module := mod.toString, doc,
    english := (doc.map english).getD "", math := (doc.map mathBlocks).getD [], signature := sig, autoTex := auto,
    stmtHash := s!"{stmtHash env ci}", mathHash := s!"{mathHash doc}", axioms := axs.toList.map toString,
    sorryFree := !axs.contains ``sorryAx, line, binders, heartbeats := ← spentSince start }

/-- The math-view entries of the declarations of the modules `want` selects (every module by default), sorted by
`Entry.before`. The module cache (`MathViewMain`) passes the modules whose key missed. -/
def entries (want : Name → Bool := fun _ => true) : MetaM (Array Entry) := do
  let env ← getEnv
  let mut out := #[]
  -- the kernel view `collectAxioms` reads (Lean/Util/CollectAxioms.lean:56,151 @ v4.35.0)
  let kenv := (env.setExporting false).toKernelEnv
  let consts := env.constants.toList
  -- the search stack holds distinct constants, so its depth stays below their number (+1 for an unknown leaf)
  let fuel := consts.length + 2
  let mut memo : Std.HashMap Name (List Name) := {}
  for (n, ci) in consts do
    if !hasEntry env n ci then continue
    let some modIdx := env.getModuleIdxFor? n | continue
    let mod := env.header.moduleNames[modIdx.toNat]!
    if !want mod then continue
    -- the declaring module's own docstring only: `findDocString?` also appends `recommended_spelling` and tactic-doc
    -- extensions found in *every* imported module (Lean/Parser/Term/Doc.lean:60-68, Parser/Tactic/Doc.lean:250-258
    -- @ v4.35.0), which would make an entry depend on modules outside its import cone (mathview-module-cache)
    let doc ← findSimpleDocString? env n
    -- one declaration can never crash the export: its failure becomes a lint failure with its name
    -- sorted like `collectAxioms`; out of fuel (not expected, see `fuel`) falls back to the old per-call walk
    let mut axs : Array Name := #[]
    match Fw.AxReach.query (axSucc kenv) (axIsAx kenv) fuel memo n with
    | some (s, m') => memo := m'; axs := s.toArray.qsort Name.lt
    | none => axs ← collectAxioms n
    match ← bounded declBudget (entryOf env n ci mod doc axs) with
    | .ok none => pure ()
    | .ok (some e) => out := out.push e
    | .error msg =>
      let line := ((← findDeclarationRanges? n).map (·.range.pos.line)).getD 0
      out := out.push {
        name := n.toString, kind := kindOf ci, module := mod.toString, doc,
        english := (doc.map english).getD "", math := (doc.map mathBlocks).getD [], signature := "",
        autoTex := "?", stmtHash := "", mathHash := s!"{mathHash doc}", axioms := [], sorryFree := false, line, heartbeats := declBudget,
        error := some msg }
  return out.qsort Entry.before

/-- The axioms a finished proof may use. -/
def standardAxioms : List String := ["propext", "Classical.choice", "Quot.sound"]

/-- Lint failures of one entry: a failed export, no docstring math or English, `sorryAx`, or a non-standard
axiom. -/
def lintEntry (e : Entry) : List String :=
  (match e.error with
    | some msg => [s!"{e.name} ({e.module}:{e.line}): export failed: {msg}"]
    | none => []) ++
  (if e.math.isEmpty then [s!"{e.name} ({e.module}:{e.line}): no $$ math in its docstring"] else []) ++
  (if e.english.isEmpty then [s!"{e.name} ({e.module}:{e.line}): no English sentence before the math"] else []) ++
  (if !e.sorryFree && e.error.isNone then [s!"{e.name} ({e.module}:{e.line}): depends on sorryAx (unfinished proof)"] else []) ++
  ((e.axioms.filter (fun a => a != "sorryAx" && !standardAxioms.contains a)).map
    fun a => s!"{e.name} ({e.module}:{e.line}): non-standard axiom {a}")

/-! ## Quantifier lint (heuristic, warning only): a theorem's explicit binders must be bound in its `$$` math -/

/-- The LaTeX spelling of a Lean binder name: subscripts, primes and trailing digits dropped (`y₀`, `g'`, `x1` all
become the stem), Greek letters mapped to their commands. `none` when the name has no recognisable stem. -/
def binderStem (n : String) : Option String :=
  let cs := n.toList.filter fun c => !(c == '\'' || ('₀' ≤ c && c ≤ '₉'))
  let cs := (cs.reverse.dropWhile Char.isDigit).reverse
  match String.ofList cs with
  | "" => none
  | "ℓ" => some "\\ell" | "σ" => some "\\sigma" | "κ" => some "\\kappa" | "λ" => some "\\lambda"
  | "α" => some "\\alpha" | "β" => some "\\beta" | "γ" => some "\\gamma" | "δ" => some "\\delta"
  | "ε" => some "\\varepsilon" | "τ" => some "\\tau" | "μ" => some "\\mu" | "φ" => some "\\varphi"
  | "π" => some "\\pi" | "ρ" => some "\\rho" | "ω" => some "\\omega" | "θ" => some "\\theta"
  | "Σ" => some "\\Sigma"
  | s => if s.all Char.isAlphanum then some s else none

/-- Does `stem` occur in `hay` as a whole token (not inside a longer word or LaTeX command; a following `_`, `'`,
`^` is a subscript, prime or power of the same variable)? -/
def hasToken (hay stem : String) : Bool :=
  let h := hay.toList.toArray
  let t := stem.toList.toArray
  let isCmd := t[0]? == some '\\'
  Id.run do
    for i in [:h.size] do
      if i + t.size > h.size then break
      if (List.range t.size).all (fun j => h[i + j]! == t[j]!) then
        let before := if i == 0 then ' ' else h[i - 1]!
        let after := if i + t.size < h.size then h[i + t.size]! else ' '
        let okBefore := !(before.isAlphanum || before == '\\')
        let okAfter := !after.isAlphanum
        if (isCmd || okBefore) && okAfter then return true
    return false

/-- The text before position `i` of `cs` that can belong to one binder list: walk back over letters, commas,
spaces, braces, parentheses, primes and subscripts, then keep only what follows the last connective. -/
def binderListBefore (cs : Array Char) (i : Nat) : String :=
  let ok (c : Char) := c.isAlphanum || c == ',' || c == ' ' || c == '_' || c == '\'' || c == '{' || c == '}' ||
    c == '\\' || c == '(' || c == ')' || c == '.'
  let rec go : Nat → Nat
    | 0 => 0
    | k + 1 => if ok cs[k]! then go k else k + 1
  let from_ := go i
  let s := String.ofList ((cs.extract from_ i).toList)
  let cut := ["\\land", "\\lor", "\\Rightarrow", "\\iff", "\\Leftrightarrow"]
  cut.foldl (fun s c => match s.splitOn c with | [] => s | ps => ps.getLast!) s

/-- Every substring of `math` where a variable can be introduced: after a `\forall` / `\exists` up to the next
colon, and the binder list before each `\in`, `\notin`, `\subseteq` or `:`. -/
def binderZones (math : String) : List String :=
  let cs := math.toList.toArray
  let startsAt (i : Nat) (p : String) := (p.toList.toArray.size > 0) && i + p.length ≤ cs.size &&
    (List.range p.length).all (fun j => cs[i + j]! == p.toList.toArray[j]!)
  Id.run do
    let mut zs : List String := []
    for i in [:cs.size] do
      for q in ["\\forall", "\\exists"] do
        if startsAt i q then
          let rest := String.ofList (cs.extract (i + q.length) cs.size).toList
          zs := (rest.splitOn ":" |>.headD "") :: zs
      for q in ["\\in", "\\notin", "\\subseteq", ":"] do
        if startsAt i q && !(q == "\\in" && startsAt i "\\infty") then zs := binderListBefore cs i :: zs
    return zs

/-- Quantifier warnings of one theorem entry: an explicit data binder whose name occurs in no binder position of
any `$$` block (so the math leaves it free). With `lenient`, a binder also passes when only its initial letter (either
case) is quantified, as for `fs` written `F` or `rows` written `R` in the math. Heuristic: it can miss a binder used
in a looser position, and flag a binder the math names differently (`lenient` also accepts `s` written `\sigma`,
`l` written `\ell`, `k` written `\kappa`; `a` written `x` is still flagged). -/
def warnEntry (lenient : Bool) (e : Entry) : List String :=
  if e.kind != "theorem" || e.error.isSome then [] else
  let zones := e.math.flatMap binderZones
  e.binders.filterMap fun b =>
    match binderStem b with
    | none => none
    | some stem =>
      let initials : List String :=
        if lenient && !stem.startsWith "\\" then
          let c := stem.front
          [c.toString, c.toUpper.toString, c.toLower.toString] ++
            (if c == 's' then ["\\sigma"] else if c == 'l' then ["\\ell"] else if c == 'k' then ["\\kappa"] else [])
        else []
      if (stem :: initials).any (fun st => zones.any (hasToken · st)) then none
      else some s!"{e.name} ({e.module}:{e.line}): binder `{b}` is not quantified in the $$ math"

/-! ## Module cache keys (task mathview-module-cache; model: `Fw.Console.LandSpeed.mkey`, `lint_modular`)

$K(m) = H(m, \mathrm{blob}(m), t, [K(i)]_{i \in \mathrm{imp}(m)})$. The blob is the module's `.olean`, the file the
export actually reads (so a stale build can never be stored under a fresh source's key); $t$ hashes the tool
(MathView*.lean, Fw/Spec/AxReach.lean, lean-toolchain, lake-manifest.json, lakefile.toml). A toolchain import
(`Init`, `Lean`, …) enters by name: the toolchain pin in $t$ covers its content. -/

/-- A 64-bit value as exactly 16 lowercase hex digits.

$$\forall x \in [0, 2^{64}):\quad \operatorname{hex}(x) = \texttt{0}^{\,16 \,\dot{-}\, |d(x)|} \mathbin{+\!\!+} d(x)$$

where $d(x)$ is the base-16 digit string of $x$ (lowercase, no leading zeros, $d(0) = \texttt{0}$), so
$|d(x)| \le 16$ and the result has 16 characters. -/
def hex64 (x : UInt64) : String :=
  let d := String.ofList (Nat.toDigits 16 x.toNat)
  String.ofList (List.replicate (16 - d.length) '0') ++ d

#guard hex64 0 == "0000000000000000"
#guard hex64 255 == "00000000000000ff"
#guard hex64 0xffffffffffffffff == "ffffffffffffffff"

/-- The identity of a blob: its 64-bit hash (Lean's `ByteArray` hash) and its byte length.

$$\forall b:\quad \operatorname{blobId}(b) = \operatorname{hex}(\mathrm{hash}(b)) \mathbin{+\!\!+} \texttt{-} \mathbin{+\!\!+} \operatorname{dec}(|b|)$$

where $|b|$ is the number of bytes and $\operatorname{dec}$ its decimal digits. -/
def blobId (b : ByteArray) : String := hex64 (hash b) ++ "-" ++ toString b.size

#guard blobId (ByteArray.mk #[1, 2]) != blobId (ByteArray.mk #[2, 1])
#guard (blobId ByteArray.empty).endsWith "-0"

/-- The canonical text a module key hashes: a version tag, the module name, its blob id, the tool hash and the keys
of its imports in import order, separated by `|` and `,` (neither occurs in a module name, a blob id or a key).

$$\forall m, b, t,\ \forall n \in \mathbb{N},\ \forall k_1, \dots, k_n:\quad \operatorname{keyText}(m, b, t, [k_1, \dots, k_n]) = \texttt{mathview-mod-v1|}\, m \,\texttt{|}\, b \,\texttt{|}\, t \,\texttt{|}\, \operatorname{join}_{\texttt{,}}(k_1, \dots, k_n)$$

where $\operatorname{join}_{\texttt{,}}$ puts one `,` between neighbours: it is $k_1$ when $n = 1$ and empty when
$n = 0$ (nothing after the last `|`). -/
def keyText (m b t : String) (imps : List String) : String :=
  "mathview-mod-v1|" ++ m ++ "|" ++ b ++ "|" ++ t ++ "|" ++ ",".intercalate imps

#guard keyText "Fw.A" "b" "t" [] == "mathview-mod-v1|Fw.A|b|t|"
#guard keyText "Fw.A" "b" "t" ["k1", "k2"] == "mathview-mod-v1|Fw.A|b|t|k1,k2"

/-- The module key, used as $K(m) = \operatorname{modKey}(m, b, t, [K(i) \text{ for each import } i])$: two 64-bit string hashes of the key text with different one-letter prefixes, as 32 hex
digits (the hash $H$ of `Fw.Console.LandSpeed.mkey`; its injectivity is the assumption `HInj`).

$$\forall m, b, t, \vec k:\quad \operatorname{modKey}(m, b, t, \vec k) = \operatorname{hex}(\mathrm{hash}(\texttt{a} \mathbin{+\!\!+} s)) \mathbin{+\!\!+} \operatorname{hex}(\mathrm{hash}(\texttt{b} \mathbin{+\!\!+} s)),\quad s = \operatorname{keyText}(m, b, t, \vec k)$$

Up to a hash collision, the key changes when the module, its blob, the tool or any import key changes. -/
def modKey (m b t : String) (imps : List String) : String :=
  let s := keyText m b t imps
  hex64 (hash ("a" ++ s)) ++ hex64 (hash ("b" ++ s))

#guard (modKey "Fw.A" "b" "t" []).length == 32
#guard modKey "Fw.A" "b" "t" ["k"] == modKey "Fw.A" "b" "t" ["k"]
#guard modKey "Fw.A" "b" "t" ["k"] != modKey "Fw.A" "b2" "t" ["k"]
#guard modKey "Fw.A" "b" "t" ["k"] != modKey "Fw.A" "b" "t2" ["k"]
#guard modKey "Fw.A" "b" "t" ["k"] != modKey "Fw.A" "b" "t" ["k2"]
#guard modKey "Fw.A" "b" "t" ["k"] != modKey "Fw.B" "b" "t" ["k"]

/-- May a module's fresh entries be stored? Only when no entry's export failed: a failure can be a heartbeat
timeout, and heartbeats depend on the Meta caches the run shares across modules, so a failure is not a function of
the key.

$$\forall E:\quad \operatorname{storable}(E) \iff \forall e \in E:\ e.\mathit{error} = \bot$$

where $\bot$ is `none`; true for the empty array ($|E| = 0$). -/
def storable (es : Array Entry) : Bool := es.all (·.error.isNone)

#guard storable #[]

end MathView
