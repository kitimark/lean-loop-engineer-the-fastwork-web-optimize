import Lean
import Fw.Spec.AxReach
/-!
# Math view (ported from the kickoff scratch `04-mathview`, note 10/04)

Export every `Fw.*` declaration as a math-view entry.

Per declaration: kind, module, docstring, the pretty-printed signature, a *deep* statement hash (signature + bodies
of every `Fw.*` definition it reaches), the axioms it depends on (an unfinished proof shows as `sorryAx`), and a
mechanical LaTeX rendering of the type. The export serves math written on demand into artifacts
(docs/team/tools/math-artifact.md); `Filter` selects declarations or one module.
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

/-! ## Entries -/

structure Entry where
  name      : String
  kind      : String
  module    : String
  doc       : Option String
  signature : String
  autoTex   : String
  stmtHash  : String
  axioms    : List String
  sorryFree : Bool
  line      : Nat
  heartbeats : Nat            -- heartbeats this entry cost (each entry has its own budget)
  error     : Option String := none  -- the export of this entry failed (lint failure)
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
export by `before` has no ties.

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

def kindOf : ConstantInfo → String
  | .thmInfo _ => "theorem" | .defnInfo _ => "def" | .inductInfo _ => "inductive"
  | .ctorInfo _ => "ctor" | .axiomInfo _ => "axiom" | .opaqueInfo _ => "opaque" | _ => "other"

def skip (env : Environment) (n : Name) (ci : ConstantInfo) : Bool :=
  !inScope n || n.isInternalDetail || isAuxRecursor env n || isNoConfusion env n ||
  (match ci with | .ctorInfo _ | .recInfo _ => true | _ => false) ||
  (`Fw.Wire).isPrefixOf n

/-- Heartbeat budget of one declaration's export, in thousands (the unit of `maxHeartbeats`). Each declaration
gets a fresh budget, so the export's total cost grows with the number of declarations without ever hitting a
global limit. -/
def declBudget : Nat := 200000

/-- Heartbeat budget of one `autoTex` rendering, in thousands; past it `autoTex` is `"?"` (not a lint failure). -/
def texBudget : Nat := 50000

/-- Run `x` with a fresh heartbeat budget of `k` thousand heartbeats, catching every exception, including the
runtime ones (heartbeat timeout, max recursion) that a plain `try … catch` lets through. -/
def bounded {α} (k : Nat) (x : MetaM α) : MetaM (Except String α) :=
  withCurrHeartbeats <| withTheReader Core.Context (fun c => { c with maxHeartbeats := k * 1000 }) <|
    tryCatchRuntimeEx (Except.ok <$> x) fun e => do
      return .error (((← e.toMessageData.toString).splitOn "\n").headD "")

/-- The heartbeats spent since `start`, in thousands. -/
def spentSince (start : Nat) : CoreM Nat := do return ((← IO.getNumHeartbeats) - start) / 1000

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

/-! ## Filter: the declarations one export keeps (`--decl`, `--module`) -/

/-- The declarations an export keeps: the names in `decls`, or every name when `decls` is empty, inside `module`, or
inside every module when it is unset. -/
structure Filter where
  decls : List String := []
  module : Option String := none
deriving Repr

/-- Whether `f` keeps the declaration named `decl` of the module `mod`. -/
def Filter.keeps (f : Filter) (mod decl : String) : Bool :=
  (f.decls.isEmpty || f.decls.contains decl) && f.module.all (· == mod)

/-- `f` keeps a declaration iff the name list is empty or holds its name, and the module is unset or is its module. -/
theorem Filter.keeps_iff (f : Filter) (mod decl : String) :
    f.keeps mod decl = true ↔ (f.decls = [] ∨ decl ∈ f.decls) ∧ (f.module = none ∨ f.module = some mod) := by
  cases f with
  | mk ds m =>
    cases m <;> simp [Filter.keeps, List.isEmpty_iff]

/-- The default filter keeps every declaration of every module. -/
theorem Filter.keeps_default (mod decl : String) : ({} : Filter).keeps mod decl = true := rfl

/-- A listed name in the selected module is kept. -/
theorem Filter.keeps_listed (ds : List String) (mod decl : String) (h : decl ∈ ds) :
    ({ decls := ds, module := some mod } : Filter).keeps mod decl = true :=
  (Filter.keeps_iff _ _ _).2 ⟨.inr h, .inr rfl⟩

/-- A name missing from a non-empty name list is dropped, whatever the module. -/
theorem Filter.keeps_unlisted (f : Filter) (mod decl : String) (hne : f.decls ≠ []) (h : decl ∉ f.decls) :
    f.keeps mod decl = false := by
  cases hk : f.keeps mod decl
  · rfl
  · rcases ((Filter.keeps_iff f mod decl).1 hk).1 with e | e
    · exact absurd e hne
    · exact absurd e h

/-- A declaration of a module other than the selected one is dropped, whatever the name list. -/
theorem Filter.keeps_other_module (f : Filter) (m mod decl : String) (hm : f.module = some m) (hne : m ≠ mod) :
    f.keeps mod decl = false := by
  cases hk : f.keeps mod decl
  · rfl
  · rcases ((Filter.keeps_iff f mod decl).1 hk).2 with e | e
    · rw [hm] at e; exact absurd e (by simp)
    · rw [hm] at e; exact absurd (Option.some.inj e) hne

#guard ({} : Filter).keeps "Fw.A" "Fw.A.t"
#guard ({ decls := ["Fw.A.t"] } : Filter).keeps "Fw.A" "Fw.A.t"
#guard !({ decls := ["Fw.A.t"] } : Filter).keeps "Fw.A" "Fw.A.u"
#guard ({ module := some "Fw.A" } : Filter).keeps "Fw.A" "Fw.A.u"
#guard !({ module := some "Fw.A" } : Filter).keeps "Fw.B" "Fw.B.u"
#guard !({ decls := ["Fw.A.t"], module := some "Fw.B" } : Filter).keeps "Fw.A" "Fw.A.t"

/-- The value after the first `flag` that has a following argument, if any. -/
def optArg (flag : String) : List String → Option String
  | f :: v :: rest => if f == flag then some v else optArg flag (v :: rest)
  | _ => none

#guard optArg "--out" ["--lint", "--out", "x.json"] == some "x.json"
#guard optArg "--out" ["--lint", "--out"] == none
#guard optArg "--out" [] == none
#guard optArg "--module" ["--module", "a", "--module", "b"] == some "a"
#guard optArg "--out" ["--out", "--out", "y"] == some "--out"

/-- The names given after each `--decl`, up to the next argument that starts with `--`, in order. -/
def declArgs (args : List String) : List String :=
  (args.foldl (init := (false, ([] : List String))) fun (on, acc) a =>
    if a == "--decl" then (true, acc)
    else if a.startsWith "--" then (false, acc)
    else if on then (on, acc ++ [a]) else (on, acc)).2

#guard declArgs [] == []
#guard declArgs ["--decl", "A", "B", "--out", "f", "--decl", "C"] == ["A", "B", "C"]
#guard declArgs ["--out", "f", "A"] == []
#guard declArgs ["--decl", "--module", "M"] == []

/-- The filter of a command line: `--decl <name>...` and `--module <M>`. -/
def Filter.ofArgs (args : List String) : Filter :=
  { decls := declArgs args, module := optArg "--module" args }

#guard (Filter.ofArgs []).keeps "Fw.A" "Fw.A.t"
#guard (Filter.ofArgs ["--decl", "Fw.A.t", "--module", "Fw.A"]).keeps "Fw.A" "Fw.A.t"
#guard !(Filter.ofArgs ["--module", "Fw.A"]).keeps "Fw.B" "Fw.B.t"

/-- The names of `f.decls` that no exported entry carries, in order. -/
def Filter.missing (f : Filter) (names : List String) : List String :=
  f.decls.filter (!names.contains ·)

/-- A name is reported missing iff it was asked for and no entry carries it. -/
theorem Filter.mem_missing (f : Filter) (names : List String) (d : String) :
    d ∈ f.missing names ↔ d ∈ f.decls ∧ d ∉ names := by
  simp [Filter.missing]

#guard ({ decls := ["A", "B"] } : Filter).missing ["A"] == ["B"]
#guard ({ decls := ["A"] } : Filter).missing ["A"] == []
#guard ({} : Filter).missing [] == []

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
  return some {
    name := n.toString, kind := kindOf ci, module := mod.toString, doc, signature := sig, autoTex := auto,
    stmtHash := s!"{stmtHash env ci}", axioms := axs.toList.map toString,
    sorryFree := !axs.contains ``sorryAx, line, heartbeats := ← spentSince start }

/-- The math-view entries of the declarations that `f` keeps (every declaration by default), sorted by
`Entry.before`. -/
def entries (f : Filter := {}) : MetaM (Array Entry) := do
  let env ← getEnv
  let mut out := #[]
  -- the kernel view `collectAxioms` reads (Lean/Util/CollectAxioms.lean:56,151 @ v4.35.0)
  let kenv := (env.setExporting false).toKernelEnv
  let consts := env.constants.toList
  -- the search stack holds distinct constants, so its depth stays below their number (+1 for an unknown leaf)
  let fuel := consts.length + 2
  let mut memo : Std.HashMap Name (List Name) := {}
  for (n, ci) in consts do
    if skip env n ci then continue
    let some modIdx := env.getModuleIdxFor? n | continue
    let mod := env.header.moduleNames[modIdx.toNat]!
    if !f.keeps mod.toString n.toString then continue
    -- the declaring module's own docstring only: `findDocString?` also appends `recommended_spelling` and tactic-doc
    -- extensions found in *every* imported module (Lean/Parser/Term/Doc.lean:60-68, Parser/Tactic/Doc.lean:250-258
    -- @ v4.35.0), so the doc of an entry would depend on modules that merely mention it
    let doc ← findSimpleDocString? env n
    if n.isInternal || (n.toString.splitOn ".match_").length > 1 then continue
    -- derived-instance helpers (`instReprWork.repr`, `instToJsonCmd.toJson`, ...)
    if n.components.any (fun c => c.toString.startsWith "inst") then continue
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
        name := n.toString, kind := kindOf ci, module := mod.toString, doc, signature := "",
        autoTex := "?", stmtHash := "", axioms := [], sorryFree := false, line, heartbeats := declBudget,
        error := some msg }
  return out.qsort Entry.before

/-- The axioms a finished proof may use. -/
def standardAxioms : List String := ["propext", "Classical.choice", "Quot.sound"]

/-- Lint failures of one entry: a failed export, a dependence on `sorryAx`, or a non-standard axiom. -/
def lintEntry (e : Entry) : List String :=
  (match e.error with
    | some msg => [s!"{e.name} ({e.module}:{e.line}): export failed: {msg}"]
    | none => []) ++
  (if !e.sorryFree && e.error.isNone then [s!"{e.name} ({e.module}:{e.line}): depends on sorryAx (unfinished proof)"] else []) ++
  ((e.axioms.filter (fun a => a != "sorryAx" && !standardAxioms.contains a)).map
    fun a => s!"{e.name} ({e.module}:{e.line}): non-standard axiom {a}")

def lintProbe (doc : Option String) (axs : List String) : Entry :=
  { name := "Fw.Probe.t", kind := "theorem", module := "Fw.Probe", doc, signature := "", autoTex := "",
    stmtHash := "", axioms := axs, sorryFree := !axs.contains "sorryAx", line := 1, heartbeats := 0 }

#guard lintEntry (lintProbe none ["propext"]) == []
#guard lintEntry (lintProbe (some "A plain sentence.") ["propext", "Quot.sound"]) == []
#guard lintEntry (lintProbe none ["sorryAx"]) == ["Fw.Probe.t (Fw.Probe:1): depends on sorryAx (unfinished proof)"]
#guard lintEntry (lintProbe (some "A plain sentence.") ["Fw.ax"]) == ["Fw.Probe.t (Fw.Probe:1): non-standard axiom Fw.ax"]
#guard (lintEntry { lintProbe none [] with error := some "boom" }).length == 1

end MathView
