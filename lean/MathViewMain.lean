import MathView
open Lean Meta

/-- The package root: the executable lives in `<root>/.lake/build/bin/`. -/
def packageRoot : IO System.FilePath := do
  let app ← IO.appPath
  let some bin := app.parent | throw (IO.userError "mathview: cannot locate its directory")
  let some build := bin.parent | throw (IO.userError "mathview: unexpected layout")
  let some lake := build.parent | throw (IO.userError "mathview: unexpected layout")
  let some root := lake.parent | throw (IO.userError "mathview: unexpected layout")
  return root

/-- Every module under `Fw/` (so new subtrees are picked up without editing this file), plus `Fw`. -/
def fwModules (root : System.FilePath) : IO (Array Name) := do
  let files ← System.FilePath.walkDir (root / "Fw")
  let mut mods : Array Name := #[`Fw]
  for f in files do
    if f.extension == some "lean" then
      let some rel := (f.withExtension "").toString.dropPrefix? (root.toString ++ "/") | continue
      mods := mods.push (rel.toString.splitOn "/" |>.foldl (fun n c => Name.mkStr n c) .anonymous)
  return mods.qsort (·.toString < ·.toString)

/-! ## Shadow lint: a bound variable also applied as a function

Rounds 8 and 9 of the math review found `\exists f.\ f(a) = f` (Obs.Health) and `\delta = \delta(R_k)`,
`(k, …, k(R_k), …)_{k \in …}` (Measure): one letter both bound as a value and applied as a function. The lint tokenises
each `$$` block and reports a name that is (1) bound, (2) applied and (3) used as a value in the same block.
- bound: a name after `\forall` / `\exists` (up to the first token that is not a name, comma or space), a name of a
  tuple `(a, b, …)` directly before `\in` / `\notin` / `\subseteq`, or a name of the comma list directly before them
  (in `x_i \in S` the base `x`, not the index `i`); comprehension subscripts `_{k \in K}` included;
- applied: a name, Greek letter, `\mathit{w}` or `\operatorname{w}` / `\mathrm{w}` directly followed by `(`, and not
  itself inside a sub- or superscript (so `\operatorname{classify}_p(` applies `classify`, not `p`);
- value: an operand of `=`, `<`, `>`, `\le`, `\ge`, `\ne` (outside any argument list `g(…)`), or an index of a variable,
  as `k` in `R_k`.
Condition (3) keeps function-valued variables legal: `\forall f, x:\ f(x) = g(x)` or `\forall B:\ d(x) \le B(r)` binds
and applies `f`, `B` but never uses them as a value. Heuristic: `\text{…}` is skipped and `\big(`-style size commands
are transparent. -/
namespace ShadowLint

/-- A token of a `$$` block. -/
inductive Tok where
  /-- a variable: a letter run, a Greek command (`\delta`) or `\mathit{w}`, primes attached -/
  | name (s : String)
  /-- an operator name: `\operatorname{w}` or `\mathrm{w}`, primes attached -/
  | op (s : String)
  /-- any other command (`\text{…}` collapses to `\text`) -/
  | cmd (s : String)
  /-- any other character, or a control symbol such as `\,` -/
  | ch (s : String)
deriving BEq, Inhabited, Repr

/-- Greek letters that name variables. -/
def greek : List String :=
  ["alpha", "beta", "gamma", "delta", "epsilon", "varepsilon", "zeta", "eta", "theta", "kappa", "lambda", "mu", "nu",
   "xi", "pi", "rho", "sigma", "tau", "phi", "varphi", "chi", "psi", "omega", "ell",
   "Gamma", "Delta", "Theta", "Lambda", "Pi", "Sigma", "Phi", "Psi", "Omega"]

/-- Size commands, dropped so that `f\big(` still reads as an application. -/
def sizeCmds : List String :=
  ["big", "Big", "bigg", "Bigg", "bigl", "Bigl", "biggl", "Biggl", "bigr", "Bigr", "biggr", "Biggr", "left", "right"]

/-- Index of the `}` closing the `{` at `j` (or `cs.size`). -/
def closeBrace (cs : Array Char) (j : Nat) : Nat := Id.run do
  let mut d := 0
  for k in [j:cs.size] do
    if cs[k]! == '{' then d := d + 1
    else if cs[k]! == '}' then
      d := d - 1
      if d == 0 then return k
  return cs.size

/-- Tokenise one `$$` block (see the module note above). -/
def tokenize (m : String) : Array Tok := Id.run do
  let cs := m.toList.toArray
  let n := cs.size
  let str (a b : Nat) : String := String.ofList (cs.extract a b).toList
  let mut out : Array Tok := #[]
  let mut i := 0
  while i < n do
    let c := cs[i]!
    if c == '\\' then
      let mut j := i + 1
      while j < n && cs[j]!.isAlpha do j := j + 1
      if j == i + 1 then
        out := out.push (.ch (str i (i + 2))); i := i + 2; continue
      let cmd := str (i + 1) j
      let brace := j < n && cs[j]! == '{'
      if brace && ["text", "textbf", "textit", "texttt"].contains cmd then
        out := out.push (.cmd "\\text"); i := closeBrace cs j + 1; continue
      if sizeCmds.contains cmd then i := j; continue
      if brace && ["operatorname", "mathrm", "mathit"].contains cmd then
        let k := closeBrace cs j
        let w := str (j + 1) k
        if k < n && !w.isEmpty && w.all (fun c => c.isAlphanum || c == '?') then
          out := out.push (if cmd == "mathit" then .name w else .op w); i := k + 1; continue
      out := out.push (if greek.contains cmd then .name ("\\" ++ cmd) else .cmd ("\\" ++ cmd)); i := j; continue
    if c.isAlpha then
      let mut j := i
      while j < n && cs[j]!.isAlpha do j := j + 1
      out := out.push (.name (str i j)); i := j; continue
    if c == '\'' then
      match out.back? with
      | some (.name s) => out := out.pop.push (.name (s ++ "'")); i := i + 1; continue
      | some (.op s) => out := out.pop.push (.op (s ++ "'")); i := i + 1; continue
      | _ => pure ()
    out := out.push (.ch c.toString); i := i + 1
  return out

/-- Spacing tokens, skipped when looking at a token's neighbours. -/
def Tok.isSpace : Tok → Bool
  | .ch s => [" ", "\\ ", "\\,", "\\;", "\\:", "\\!", "~", "\n"].contains s
  | .cmd s => s == "\\quad" || s == "\\qquad"
  | _ => false

/-- The text of a name or operator name. -/
def Tok.word? : Tok → Option String
  | .name s => some s
  | .op s => some s
  | _ => none

/-- Is it a variable name? -/
def Tok.isName : Tok → Bool
  | .name _ => true
  | _ => false

/-- Relation symbols whose operands are values. -/
def rels : List Tok :=
  [.ch "=", .ch "<", .ch ">", .cmd "\\le", .cmd "\\leq", .cmd "\\ge", .cmd "\\geq", .cmd "\\ne", .cmd "\\neq"]

/-- Every name of one `$$` block that is bound, applied and used as a value there, deduplicated, in order of first
application.

$$\operatorname{shadow}(m) = \big[\,v \in \operatorname{applied}(m) \mid v \in \operatorname{bound}(m) \land v \in \operatorname{value}(m)\,\big]
\ \text{(first occurrences only)}$$ -/
def shadowed (m : String) : List String := Id.run do
  let ts := tokenize m
  let n : Int := ts.size
  let tk (i : Int) : Tok := if i < 0 || i ≥ n then .ch "" else ts[i.toNat]!
  let nxt (i : Int) : Int := Id.run do
    let mut j := i + 1
    while j < n && (tk j).isSpace do j := j + 1
    return j
  let prv (i : Int) : Int := Id.run do
    let mut j := i - 1
    while j ≥ 0 && (tk j).isSpace do j := j - 1
    return j
  let isScriptMark (t : Tok) := t == .ch "_" || t == .ch "^"
  -- script[i]: token i sits in a sub- or superscript (right after `_`/`^`, or in a `_{…}`/`^{…}` group)
  let mut script : Array Bool := #[]
  let mut groups : List Bool := []
  for i in [:ts.size] do
    let direct := isScriptMark (tk (i - 1 : Int))
    let inGroup := groups.headD false
    if ts[i]! == .ch "{" then groups := (direct || inGroup) :: groups
    else if ts[i]! == .ch "}" then groups := groups.drop 1
    script := script.push (direct || inGroup)
  let sc (i : Int) : Bool := if i < 0 || i ≥ n then false else script[i.toNat]!
  let appliedAt (i : Int) : Bool := tk (nxt i) == .ch "(" && !sc i
  -- an application's argument list: `(` right after a name, an operator name, `}` or `)`
  let appParen (k : Int) : Bool :=
    let p := tk (prv k)
    p.word?.isSome || p == .ch "}" || p == .ch ")"
  let listy (t : Tok) := t.isName || t == .ch "," || t.isSpace
  let mut bound : List String := []
  let mut binder : Array Bool := Array.replicate ts.size false
  for i in [:ts.size] do
    let t := ts[i]!
    if t == .cmd "\\forall" || t == .cmd "\\exists" then
      let mut j : Int := i + 1
      while j < n && listy (tk j) do
        if let .name s := tk j then bound := s :: bound; binder := binder.set! j.toNat true
        j := j + 1
    if t == .cmd "\\in" || t == .cmd "\\notin" || t == .cmd "\\subseteq" then
      let mut j := prv i
      if tk j == .ch ")" then
        let mut d : Nat := 0
        let mut k := j
        while k ≥ 0 do
          if tk k == .ch ")" then d := d + 1
          else if tk k == .ch "(" then
            d := d - 1
            if d == 0 then break
          k := k - 1
        if k ≥ 0 && !appParen k then
          for q in [(k + 1).toNat:j.toNat] do
            if let .name s := ts[q]! then
              if !script[q]! && !appliedAt q then bound := s :: bound; binder := binder.set! q true
      else
        while j ≥ 0 && listy (tk j) do
          if (tk j).isName && isScriptMark (tk (j - 1)) then j := j - 2; continue
          if let .name s := tk j then bound := s :: bound; binder := binder.set! j.toNat true
          j := j - 1
  let mut applied : List String := []
  let mut value : List String := []
  let mut parens : List Bool := []  -- per open `(`: is it an argument list?
  for i in [:ts.size] do
    let t := ts[i]!
    if let some w := t.word? then
      if appliedAt i && !applied.contains w then applied := applied ++ [w]
    if t == .ch "(" then parens := appParen i :: parens
    else if t == .ch ")" then parens := parens.drop 1
    else if let .name s := t then
      if !binder[i]! then
        -- an index of a variable: `k` in `R_k`
        if isScriptMark (tk (i - 1 : Int)) && (tk (i - 2 : Int)).isName then value := s :: value
        else if !script[i]! && !appliedAt i && !isScriptMark (tk (i + 1 : Int)) && !(parens.headD false) &&
            (rels.contains (tk (prv i)) || rels.contains (tk (nxt i))) then
          value := s :: value
  return applied.filter fun v => bound.contains v && value.contains v

-- round 8 (Obs.Health.hungB): `f` bound by `\exists`, applied as `f(a)`, compared as `= f`
#guard shadowed "\\exists f.\\ f(a) = f" == ["f"]
-- round 9 (SelfCheck.check_sound): `\delta` bound in a tuple, applied as `\delta(R_k)`
#guard shadowed "\\forall (k, c, \\delta) \\in X:\\ \\delta = \\delta(R_k)" == ["\\delta"]
-- round 9 (classifyAllU): `k` bound by the comprehension, an index in `R_k` and applied as `k(R_k)`
#guard shadowed "\\big[\\,(k,\\ k(R_k))\\,\\big]_{k \\in \\operatorname{keys}(\\mathcal{R})}" == ["k"]
-- the fix: bind `\tau` and keep `k(…)` for the function
#guard shadowed "\\big[\\,(\\tau,\\ k(R_\\tau))\\,\\big]_{\\tau \\in \\operatorname{keys}(\\mathcal{R})}" == []
-- a function-valued variable, bound and applied but never a value
#guard shadowed "\\forall f, x:\\ f(x) = g(x)" == []
#guard shadowed "\\forall B, x:\\ \\operatorname{unfit}(B, x) \\Rightarrow d(x) \\le B(r)" == []
-- a subscript application `\operatorname{classify}_p(R)` applies `classify`, not `p`
#guard shadowed "\\forall p, R:\\ \\operatorname{classify}_p(R) = p" == []
#guard tokenize "f'(x)" == #[.name "f'", .ch "(", .name "x", .ch ")"]
#guard tokenize "\\text{a(b)}\\big(" == #[.cmd "\\text", .ch "("]

/-- The shadow-lint failures of one entry, one per offending name and `$$` block. -/
def lintEntry (e : MathView.Entry) : List String :=
  e.math.flatMap fun m => (shadowed m).map fun v =>
    s!"{e.name} ({e.module}:{e.line}): `{v}` is bound and also applied as a function `{v}(…)` in the same $$ math"

end ShadowLint

/-- The file named after `--out`, if any. -/
def outFile? : List String → Option String
  | "--out" :: f :: _ => some f
  | _ :: rest => outFile? rest
  | [] => none

/-- `lake exe mathview [--lint] [--out <file>]`: print every `Fw` declaration as JSON (name, kind, module, line,
English, math, signature, machine LaTeX, deep statement hash, docstring hash, axioms); with `--lint`, exit 1 when
a declaration lacks `$$` math or English, depends on `sorryAx`, or on on an axiom other than
`propext`, `Classical.choice`, `Quot.sound`, or when its `$$` math binds a name that it also applies as a function
and uses as a value (`ShadowLint`). With `--out <file>` the JSON export is also written to
`<file>` (the same bytes as the plain export on stdout), so one run serves both the lint and the export;
`scripts/mathview-cached.sh` keeps that file keyed by a hash of the sources. -/
def main (args : List String) : IO UInt32 := do
  let root ← packageRoot
  initSearchPath (← findSysroot) [root / ".lake" / "build" / "lib" / "lean"]
  let mods ← fwModules root
  let env ← importModules (mods.map fun m => { module := m }) {} (loadExts := false)
  let ctx : Core.Context := { fileName := "<mathview>", fileMap := default }
  let st : Core.State := { env }
  let (es, _) ← (MathView.entries.run' {} {}).toIO ctx st
  let render : Unit → String := fun _ => (toJson es).pretty ++ "\n"
  if let some f := outFile? args then IO.FS.writeFile f (render ())
  if args.contains "--lint" then
    let shadow := es.toList.flatMap ShadowLint.lintEntry
    let bad := es.toList.flatMap MathView.lintEntry ++ shadow
    for b in bad do IO.eprintln s!"mathview: {b}"
    let strict := es.toList.flatMap (MathView.warnEntry false)
    let warns := es.toList.flatMap (MathView.warnEntry true)
    for w in warns do IO.eprintln s!"mathview: warning: {w}"
    let thms := (es.filter (·.kind == "theorem")).size
    IO.println s!"mathview lint: {es.size} entries ({thms} theorems) in {mods.size} modules, {bad.length} failing ({shadow.length} bound-and-applied), {warns.length} quantifier warnings ({strict.length} counting a renamed binder as free)"
    return if bad.isEmpty then 0 else 1
  if (outFile? args).isNone then IO.print (render ())
  return 0
