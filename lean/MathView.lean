import Lean
/-!
# Math view (ported from the kickoff scratch `04-mathview`, note 10/04)

Export every `Fw.*` declaration as a math-view entry.

Per declaration: kind, module, docstring, the `$$…$$` blocks found in it, the pretty-printed
signature, a *deep* statement hash (signature + bodies of every `Fw.*` definition it reaches),
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
  axioms    : List String
  sorryFree : Bool
  line      : Nat
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
    let sig ← withOptions (fun o => o.set `format.width (1000 : Nat)) do
      return toString (← PrettyPrinter.ppSignature n).fmt
    -- for a def, render its unfolding equation `f.eq_def : ∀ xs, f xs = body` instead of its type
    let eqnTy? ← match ci with
      | .defnInfo _ => do
        let some eq ← (try getUnfoldEqnFor? n (nonRec := true) catch _ => pure none) | pure none
        pure (some (← getConstInfo eq).type)
      | _ => pure none
    let auto ← try latex (eqnTy?.getD ci.type) catch _ => pure "?"
    let axs ← collectAxioms n
    let line := ((← findDeclarationRanges? n).map (·.range.pos.line)).getD 0
    if line == 0 || (← isInstance n) || (← isProjectionFn n) then continue
    out := out.push {
      name := n.toString, kind := kindOf ci, module := mod.toString, doc,
      english := (doc.map english).getD "", math := (doc.map mathBlocks).getD [], signature := sig, autoTex := auto,
      stmtHash := s!"{stmtHash env ci}", axioms := axs.toList.map toString,
      sorryFree := !axs.contains ``sorryAx, line }
  return out.qsort (fun a b => a.module < b.module || (a.module == b.module && a.line < b.line))

/-- The axioms a finished proof may use. -/
def standardAxioms : List String := ["propext", "Classical.choice", "Quot.sound"]

/-- Lint failures of one entry: no docstring math or English, `sorryAx`, or a non-standard axiom. -/
def lintEntry (e : Entry) : List String :=
  (if e.math.isEmpty then [s!"{e.name} ({e.module}:{e.line}): no $$ math in its docstring"] else []) ++
  (if e.english.isEmpty then [s!"{e.name} ({e.module}:{e.line}): no English sentence before the math"] else []) ++
  (if !e.sorryFree then [s!"{e.name} ({e.module}:{e.line}): depends on sorryAx (unfinished proof)"] else []) ++
  ((e.axioms.filter (fun a => a != "sorryAx" && !standardAxioms.contains a)).map
    fun a => s!"{e.name} ({e.module}:{e.line}): non-standard axiom {a}")

end MathView
