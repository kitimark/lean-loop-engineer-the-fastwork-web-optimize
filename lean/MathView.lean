import Lean
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
deriving ToJson

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

/-- The export of one declaration (`none` when it is not a math-view entry). -/
def entryOf (env : Environment) (n : Name) (ci : ConstantInfo) (mod : Name) (doc : Option String) :
    MetaM (Option Entry) := do
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
  let axs ← collectAxioms n
  return some {
    name := n.toString, kind := kindOf ci, module := mod.toString, doc,
    english := (doc.map english).getD "", math := (doc.map mathBlocks).getD [], signature := sig, autoTex := auto,
    stmtHash := s!"{stmtHash env ci}", mathHash := s!"{mathHash doc}", axioms := axs.toList.map toString,
    sorryFree := !axs.contains ``sorryAx, line, heartbeats := ← spentSince start }

def entries : MetaM (Array Entry) := do
  let env ← getEnv
  let mut out := #[]
  for (n, ci) in env.constants.toList do
    if skip env n ci then continue
    let some modIdx := env.getModuleIdxFor? n | continue
    let mod := env.header.moduleNames[modIdx.toNat]!
    let doc ← findDocString? env n
    if n.isInternal || (n.toString.splitOn ".match_").length > 1 then continue
    -- derived-instance helpers (`instReprWork.repr`, `instToJsonCmd.toJson`, ...)
    if n.components.any (fun c => c.toString.startsWith "inst") then continue
    -- one declaration can never crash the export: its failure becomes a lint failure with its name
    match ← bounded declBudget (entryOf env n ci mod doc) with
    | .ok none => pure ()
    | .ok (some e) => out := out.push e
    | .error msg =>
      let line := ((← findDeclarationRanges? n).map (·.range.pos.line)).getD 0
      out := out.push {
        name := n.toString, kind := kindOf ci, module := mod.toString, doc,
        english := (doc.map english).getD "", math := (doc.map mathBlocks).getD [], signature := "",
        autoTex := "?", stmtHash := "", mathHash := s!"{mathHash doc}", axioms := [], sorryFree := false, line, heartbeats := declBudget,
        error := some msg }
  return out.qsort (fun a b => a.module < b.module || (a.module == b.module && a.line < b.line))

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

end MathView
