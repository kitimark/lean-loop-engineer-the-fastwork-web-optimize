import MathView
import Fw.Spec.ConeMiss
import Fw.Spec.MathFacts
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

/-! ## Dangling-where lint: symbols defined after the `$$` block

Rounds 9 (`layers_additive`) and 10 (`crossLevel_classify`) of the math review found a `where $A_\tau = …$` clause
placed after the `$$` block. The export keeps the English before the first `$$` and the `$$` blocks only, so the
clause is dropped and `A_\tau` reads as undefined in the math. The lint reports a text segment that directly follows a
`$$` block, starts with `where`, `with`, `(where` or `(with` (lower case: `Where a card sits …` is an English
sentence), and has an inline snippet `$…$` whose left-hand side (`definedSym`: the first name before `=`, or the
snippet itself when the prose goes on with `is`/`are`) occurs in that block. A hit is an error (exit 1), except in
`Fw.Measure.*`, where it is still a warning (`warnOnly`, TODO(where-cleanup)); both counts are printed with the lint
summary. -/
namespace WhereLint
open ShadowLint

/-- Does the text start a `where` / `with` clause? -/
def clauseHead (s : String) : Bool :=
  let t := s.trimAscii.toString
  ["where ", "with ", "(where ", "(with ", "where\n", "with\n"].any fun (p : String) => t.startsWith p

/-- Relation tokens that end the left-hand side of a defining snippet. -/
def defRels : List Tok := [.ch "=", .cmd "\\coloneqq", .cmd "\\equiv", .cmd "\\iff"]

/-- Does the text start with the word `w` (followed by a space or a line break, after leading blanks)? -/
def startsWord (s w : String) : Bool :=
  let t := s.trimAsciiStart.toString
  t.startsWith (w ++ " ") || t.startsWith (w ++ "\n")

/-- The symbol an inline snippet `m` defines, given the text `after` it: the first name or operator name of its
left-hand side, the tokens before its first `=`, `\coloneqq`, `\equiv` or `\iff` (`A` in `A_\tau = …`, `d` in
`(d_1, r_1) = …`). A snippet without such a relation is a left-hand side only when the text after it starts with `is`
or `are` (`$m$ is the first …`); otherwise it defines nothing (`neither $\mathrm{true}$ nor …`).

$$\forall m, a,\quad \operatorname{definedSym}(m, a) = \begin{cases} \operatorname{firstWord}(T_{<r}) & r = \min\{\, j \mid T_j \in \mathit{Rel} \,\} \text{ exists} \\ \operatorname{firstWord}(T) & \text{no } T_j \in \mathit{Rel} \text{ and } a \text{ starts with the word is or are (after blanks)} \\ \bot & \text{otherwise} \end{cases},\quad T = \operatorname{tokenize}(m),\ \mathit{Rel} = \{=, \backslash\mathrm{coloneqq}, \backslash\mathrm{equiv}, \backslash\mathrm{iff}\},\ \operatorname{firstWord}(L) = \text{the first name or operator name of } L \ (\bot \text{ if none})$$

A snippet defines the first symbol on the left of its equation sign, or itself when the prose says it "is" something. -/
def definedSym (m after : String) : Option String :=
  let ts := (tokenize m).toList
  match ts.findIdx? (defRels.contains ·) with
  | some r => (ts.take r).findSome? Tok.word?
  | none => if startsWord after "is" || startsWord after "are" then ts.findSome? Tok.word? else none

#guard definedSym "A_\\tau = 1" "" == some "A"
#guard definedSym "(d_1, r_1) = \\operatorname{takeDigits}(cs)" "" == some "d"
#guard definedSym "\\mathrm{STALE} = \\mathrm{staleMs}" "." == some "STALE"
#guard definedSym "m" " is the first step" == some "m"
-- the noise the first-word rule produced: a value named in prose is not a definition
#guard definedSym "\\mathrm{true}" " nor " == none
#guard definedSym "\\rho.\\mathrm{role}" " in the list" == none

/-- The symbols defined after a `$$` block and used inside it, one list per offending block.

$$\forall d,\quad \operatorname{dangling}(d) = \big[\,D_i \;\big|\; (m_i, t_i) \in \operatorname{after}(d),\ \operatorname{clause}(t_i),\ D_i \ne [\,]\,\big],\quad D_i = [\,v \in \operatorname{dedup}(\operatorname{defs}(t_i)) \mid v \in \operatorname{words}(m_i)\,],\quad \text{for a docstring } d \text{ with } \operatorname{split}_{\$\$}(d) = [s_0, s_1, \dots]:\ \operatorname{after}(d) = [(s_{i-1}, s_i) \mid i \ge 2 \text{ even}],\ \operatorname{clause}(t) \iff t \text{ (leading blanks dropped) starts with where, with, (where or (with, followed by a space, or with where or with followed by a line break},\ \operatorname{defs}(t) = [\,v \mid j \text{ odd},\ \operatorname{definedSym}(u_j, u_{j+1}) = v \ne \bot\,] \text{ for } \operatorname{split}_{\$}(t) = [u_0, u_1, \dots] \ (u_{j+1} = \varepsilon \text{ past the end}),\ \operatorname{words}(m) = \text{the names and operator names of } m$$

Pairs each `$$` block with the text up to the next `$$` and keeps the clauses that define a symbol of the block. -/
def dangling (doc : String) : List (List String) :=
  let parts := (doc.splitOn "$$").toArray
  (List.range parts.size).filterMap fun i =>
    if i % 2 == 0 && i ≥ 2 && clauseHead parts[i]! then
      let words := (tokenize parts[i - 1]!).toList.filterMap Tok.word?
      let segs := (parts[i]!.splitOn "$").toArray
      let defs := (List.range segs.size).filterMap fun j =>
        if j % 2 == 1 then definedSym segs[j]! (segs[j + 1]?.getD "") else none
      let used := defs.eraseDups.filter words.contains
      if used.isEmpty then none else some used
    else none

-- positive: the r10 `crossLevel_classify` shape and a parenthesised `(with …)`
#guard dangling "Cross. $$c(A_\\tau) = B_\\tau$$ where $A_\\tau = 1$ and $B_\\tau = 2$." == [["A", "B"]]
#guard dangling "Gone. $$g(o) = 1$$\n\n(with $o = (t, A)$.) Done." == [["o"]]
-- negative: an English `Where` sentence, a clause about a symbol not in the block, the fix (definition inside `$$`)
#guard dangling "Hit. $$h(x) = 1$$ Where a value lands, $x$." == []
#guard dangling "Ok. $$h(x) = 1$$ where $y = 2$ is not in the math." == []
#guard dangling "Inside. $$h(A_\\tau) = 1,\\quad A_\\tau = 2$$ One sentence." == []
-- left-hand sides only: a clause that names `true`/`false` in prose defines neither; `$h$ is …` defines `h`
#guard dangling "Env. $$f(x) = \\mathrm{true}$$ where $\\bot$ equals neither $\\mathrm{true}$ nor $\\mathrm{false}$." == []
#guard dangling "Hold. $$g(h) = 1$$ where $h$ is the holder." == [["h"]]

/-- The dangling-where findings of one entry, one per offending `$$` block. -/
def lintEntry (e : MathView.Entry) : List String :=
  (dangling (e.doc.getD "")).map fun vs =>
    s!"{e.name} ({e.module}:{e.line}): a where/with clause after the $$ block defines {vs}, which the export drops"

/-- Does a dangling clause in module `mod` only warn? TODO(where-cleanup): `Fw.Measure.*` keeps a warning until the
task zone-baseline-lean has moved its clauses into the `$$` blocks; then drop this exception (every module errors).

$$\forall \mathit{mod},\quad \operatorname{warnOnly}(\mathit{mod}) \iff \mathit{mod} \text{ starts with the string } \texttt{Fw.Measure.}$$

Only the measurement modules are still let off with a warning. -/
def warnOnly (mod : String) : Bool := mod.startsWith "Fw.Measure."

#guard warnOnly "Fw.Measure.Arms" && !warnOnly "Fw.Obs.Health" && !warnOnly "Fw.MeasureX"

end WhereLint

/-- The value after the flag `flag`, if any.

$$\forall \mathit{flag}, a = [a_1, \dots, a_n]:\quad \operatorname{optArg}(\mathit{flag}, a) = \begin{cases} \mathrm{some}(a_{j+1}) & S \ne \emptyset,\ j = \min S \\ \bot & S = \emptyset \end{cases},\qquad S = \{\, i \in \mathbb{N} \mid 1 \le i \le n - 1,\ a_i = \mathit{flag} \,\}$$

(1-indexed; $\bot$ is `none`; $S = \emptyset$ when $n \le 1$). The first occurrence that has a following argument
wins. -/
def optArg (flag : String) : List String → Option String
  | f :: v :: rest => if f == flag then some v else optArg flag (v :: rest)
  | _ => none

#guard optArg "--out" ["--lint", "--out", "x.json"] == some "x.json"
#guard optArg "--out" ["--lint", "--out"] == none
#guard optArg "--out" [] == none
#guard optArg "--store" ["--store", "a", "--store", "b"] == some "a"
#guard optArg "--out" ["--out", "--out", "y"] == some "--out"

/-- The file named after `--out`, if any. -/
def outFile? (args : List String) : Option String := optArg "--out" args

/-! ## Module cache (task mathview-module-cache)

With `--store <dir>` the export is computed per module and kept in `<dir>/<K(m)>.json` (compact JSON of the module's
entries), keyed by `MathView.modKey`. A run imports every module as before, reads the entries of every module whose
key is stored, exports only the declarations of the other modules, stores those (atomically: a temporary file, then
a rename; only when `MathView.storable`), merges, and sorts by `MathView.Entry.before`. The lint lines are then
computed from the merged entries exactly as in a full run.

Why a module's entries depend only on its import cone (the premise `ConeLocal` of
`Fw.Console.LandSpeed.lint_modular`; the analysis is in docs/team/handoffs/mathview-module-cache.md): the environment
is imported with `loadExts := false`, so every extension *state* keeps its initial value
(Lean/Environment.lean:2428-2433 @ v4.35.0) and only the per-module entry arrays are set; unexpanders, delaborators,
aliases, instances and scoped attributes added by other modules are invisible, and docstrings, declaration ranges,
projection and auxiliary-recursor tags are read from the declaring module's own entries
(Lean/EnvExtension.lean:118-122,163-170). The one lookup that scans every module, the docstring suffix of
`findDocString?`, is not used (see `MathView.entries`). The lint rules are functions of one entry each. -/

/-- The lint program's sources (with the axiom memo it runs), embedded when this binary is compiled: a stale binary
hashes the sources it was built from, so it can never store its output under the key of newer sources. A change
to any of them rebuilds this file (it imports `MathView`, which imports `Fw.Spec.AxReach`). -/
def toolSources : List (String × String) :=
  [("MathView.lean", include_str "MathView.lean"), ("MathViewMain.lean", include_str "MathViewMain.lean"),
   ("Fw/Spec/AxReach.lean", include_str "Fw/Spec/AxReach.lean"),
   ("Fw/Spec/MathFacts.lean", include_str "Fw/Spec/MathFacts.lean"),
   ("Fw/Spec/Reach.lean", include_str "Fw/Spec/Reach.lean")]

/-- The build inputs of the tool hash read at run time: the toolchain pin, the manifest and the lakefile with its
options. -/
def toolFiles : List String := ["lean-toolchain", "lake-manifest.json", "lakefile.toml"]

/-- The tool hash $t$: a module key over the blob ids of `toolSources` and `toolFiles`, in order.

$$t = \operatorname{modKey}\bigl(\texttt{(tool)},\ \operatorname{join}_{\texttt{;}}(f_1\texttt{=}\operatorname{blobId}(c_1), \dots, f_8\texttt{=}\operatorname{blobId}(c_8)),\ \texttt{""},\ [\,]\bigr)$$

where $(f_i, c_i)$ are the 5 embedded sources, then the 3 files read under `root`. Throws when a file in
`toolFiles` is missing. (`cachedEntries` keys modules by $t$ mixed with the facts key of `factsGlobals`.) -/
def toolHash (root : System.FilePath) : IO String := do
  let mut parts : Array String := toolSources.toArray.map fun (f, s) => f ++ "=" ++ MathView.blobId s.toUTF8
  for f in toolFiles do
    parts := parts.push (f ++ "=" ++ MathView.blobId (← IO.FS.readBinFile (root / f)))
  return MathView.modKey "(tool)" (";".intercalate parts.toList) "" []

/-- The blob of a module: the id of each of its `.olean` parts that exists (the files `importModules` reads).

$$\operatorname{oleanBlob}(o) = \operatorname{join}_{\texttt{;}}\bigl[\operatorname{blobId}(\mathrm{bytes}(p)) \mid p \in [o,\ o\texttt{.server},\ o\texttt{.private}],\ p \text{ exists}\bigr]$$

The empty string when no part exists. -/
def oleanBlob (olean : System.FilePath) : IO String := do
  let mut ids : Array String := #[]
  for p in [olean, olean.addExtension "server", olean.addExtension "private"] do
    if ← p.pathExists then ids := ids.push (MathView.blobId (← IO.FS.readBinFile p))
  return ";".intercalate ids.toList

/-- The key of module `m` (`MathView.modKey`), memoised in `memo`; `none` for a module outside the package build (a
toolchain module, covered by the toolchain pin in $t$ and entered as `ext:<name>` in the key of a module that
imports it). Throws when `m` is not among the imported modules. -/
partial def modKeyOf (env : Environment) (build : String) (t : String)
    (memo : IO.Ref (Std.HashMap Name (Option String))) (m : Name) : IO (Option String) := do
  if let some k := (← memo.get)[m]? then return k
  let olean ← findOLean m
  let k ← if !olean.toString.startsWith build then pure none else do
    let some idx := env.getModuleIdx? m | throw (IO.userError s!"mathview: module {m} is not imported")
    let imps := env.header.moduleData[idx.toNat]!.imports
    let mut ks : Array String := #[]
    for i in imps do
      ks := ks.push ((← modKeyOf env build t memo i.module).getD s!"ext:{i.module}")
    pure (some (MathView.modKey m.toString (← oleanBlob olean) t ks.toList))
  memo.modify (·.insert m k)
  return k

/-! ## Facts per theorem (task lfg-mathview-facts)

Each theorem entry also carries the facts of `Fw.Spec.MathFacts` (head constant, implementation argument, `Assume`
premises, killed incident, proof class, reach) and `reachFromWire`. The facts of one theorem depend on its import
cone and on two global inputs: the registered signatures and registry rows (`factsGlobals`, mixed into every module
key, so a registry change recomputes every module) and the wire reach (`wireSet`, computed after the merge on every
run, never stored). Each theorem's facts are computed in a fresh `Core`/`Meta` state, so a full run and a cached run
give the same bytes. -/

/-- An exported entry and, for a theorem, its facts (none for any other kind, and for a theorem whose facts were not
computed, see `withFacts`): what the module store keeps per declaration.
$$\mathrm{Stored} = \mathrm{Entry} \times \mathrm{Option}(\mathrm{Facts})$$ -/
structure Stored where
  /-- The math-view entry, unchanged. -/
  entry : MathView.Entry
  /-- The facts of a theorem. -/
  facts : Option Fw.Spec.MathFacts.Facts
deriving ToJson, FromJson

/-- Heartbeat budget of the facts of one theorem, in thousands.
$$\mathrm{factsBudget} = 20000$$ -/
def factsBudget : Nat := 20000

/-- The global inputs of the facts: the registry rows (`Fw.Spec.MathFacts.rows`) and a text key over every registered
signature constructor $s$ with its reduced `Sig.Dom s` and `Sig.Cod s`, then every row's id, row name and replay name.
$$\operatorname{factsGlobals} = \bigl(R,\ \operatorname{join}_{\texttt{\textbackslash n}}([\texttt{sig}\ s\ \operatorname{whnf}(\mathrm{Dom}\ s)\ \operatorname{whnf}(\mathrm{Cod}\ s) : s \in \operatorname{sigCtors}] \mathbin{+\!\!+} [\texttt{row}\ \iota\ \rho\ r : (\iota, \rho, r) \in R])\bigr)$$ -/
def factsGlobals : MetaM (List Fw.Spec.MathFacts.Row × String) := Fw.Spec.MathFacts.plainUnfold do
  let rs ← Fw.Spec.MathFacts.rows
  let mut parts : Array String := #[]
  for s in Fw.Spec.Reach.sigCtors (← getEnv) do
    let dom ← whnf (mkApp (mkConst `Fw.Spec.Incidents.Sig.Dom) (mkConst s))
    let cod ← whnf (mkApp (mkConst `Fw.Spec.Incidents.Sig.Cod) (mkConst s))
    parts := parts.push s!"sig {s} {dom} {cod}"
  for r in rs do parts := parts.push s!"row {r.id} {r.row} {r.replay}"
  return (rs, "\n".intercalate parts.toList)

/-- The `Fw` constants of the environment by their printed name (the `name` field of an entry). -/
def nameIndex (env : Environment) : Std.HashMap String Name :=
  env.constants.map₁.fold (init := {}) fun m n _ => if MathView.inScope n then m.insert n.toString n else m

/-- **The facts of the theorem entries** of `es`, each by `factsOf` in a fresh `Core`/`Meta` state within
`factsBudget`; none for a non-theorem, for a printed name missing from `names` or from the environment, and when
`factsOf` throws any error (running out of the budget included).
$$\operatorname{withFacts}(es) = [(e,\ \phi(e)) : e \in es],\quad \phi(e) = \begin{cases} \operatorname{factsOf}(n_e) & e.\mathrm{kind} = \texttt{theorem},\ n_e = \mathit{names}(e.\mathrm{name}) \text{ defined},\ n_e \in \mathrm{env},\ \operatorname{factsOf}(n_e) \text{ returns within the budget without error} \\ \bot & \text{otherwise} \end{cases}$$ -/
def withFacts (env : Environment) (rs : List Fw.Spec.MathFacts.Row) (names : Std.HashMap String Name)
    (es : Array MathView.Entry) : IO (Array Stored) := do
  let ctx : Core.Context := { fileName := "<mathview>", fileMap := default }
  es.mapM fun e => do
    if e.kind != "theorem" then return { entry := e, facts := none }
    let some n := names[e.name]? | return { entry := e, facts := none }
    let some ci := env.find? n | return { entry := e, facts := none }
    let x := MathView.bounded factsBudget (Fw.Spec.MathFacts.factsOf n ci rs)
    let (r, _) ← (x.run' {} {}).toIO ctx { env }
    return { entry := e, facts := r.toOption }

/-- The wire reach $W$ (`Fw.Spec.MathFacts.wireReach` over `Fw.Spec.MathFacts.goldenSources root`) by printed name. -/
def wireSet (env : Environment) (root : System.FilePath) : IO (Std.HashSet String) := do
  let w := Fw.Spec.MathFacts.wireReach env (← Fw.Spec.MathFacts.goldenSources root)
  return w.foldl (fun s n => s.insert n.toString) {}

/-- **The JSON of one entry**: `toJson` of the entry, unchanged for a non-theorem; a theorem also gets the keys
`headConst`, `implArg` (`{index, expr}` or null), `assumes`, `killOf`, `class`, `reach` and `reachFromWire`, each
null when its facts are missing; `reachFromWire` is also null when the theorem has no subjects
(`Fw.Spec.MathFacts.reachFromWire`).
$$\operatorname{entryJson}(e, \phi) = \begin{cases} \operatorname{toJson}(e) & e.\mathrm{kind} \ne \texttt{theorem} \\ \operatorname{toJson}(e) \cup \{h, a, A, k, c, \mathit{reach}, \operatorname{reachFromWire}(S, W)\} & \phi = (h, a, A, k, c, \mathit{reach}, S) \\ \operatorname{toJson}(e) \cup \{\text{the 7 keys} \mapsto \mathrm{null}\} & \phi = \bot \end{cases}$$ -/
def entryJson (inWire : String → Bool) (s : Stored) : Json :=
  let j := toJson s.entry
  if s.entry.kind != "theorem" then j else
  let keys : List (String × Json) := match s.facts with
    | none => ["headConst", "implArg", "assumes", "killOf", "class", "reach", "reachFromWire"].map (·, Json.null)
    | some f =>
      [("headConst", toJson f.headConst),
       ("implArg", match f.implIdx with
         | some i => Json.mkObj [("index", toJson i), ("expr", toJson f.implExpr)]
         | none => Json.null),
       ("assumes", toJson f.assumes), ("killOf", toJson f.killOf), ("class", toJson f.cls.tag),
       ("reach", toJson f.reach), ("reachFromWire", toJson (Fw.Spec.MathFacts.reachFromWire f.subjects inWire))]
  keys.foldl (fun j (k, v) => j.setObjVal! k v) j

/-- The stored entries under key `k`, or `none` when absent or unreadable (then the module is recomputed). -/
def readStored (store : System.FilePath) (k : String) : IO (Option (Array Stored)) := do
  let f := store / (k ++ ".json")
  unless ← f.pathExists do return none
  try
    match (Json.parse (← IO.FS.readFile f)) >>= fromJson? with
    | .ok es => return some es
    | .error _ => return none
  catch _ => return none

/-- Store `es` under key `k`: write a temporary file named by key and process id, then rename it into place, so a
reader in another worktree sees either no file or the whole file. Returns whether it was stored. -/
def writeStored (store : System.FilePath) (k : String) (es : Array Stored) : IO Bool := do
  try
    let tmp := store / s!".tmp.{k}.{← IO.Process.getPID}"
    IO.FS.writeFile tmp (toJson es).compress
    IO.FS.rename tmp (store / (k ++ ".json"))
    return true
  catch _ => return false

/-- The incremental export over the store `store`, with the facts of every theorem (`withFacts`, given the registry
rows `rs` and the facts key `gk` of `factsGlobals`, which is mixed into the tool hash); also writes `stats` (counts,
phase times in ms, then `miss <module>` lines). -/
def cachedEntries (env : Environment) (root store : System.FilePath) (stats : Option String)
    (rs : List Fw.Spec.MathFacts.Row) (gk : String) : IO (Array Stored) := do
  let t0 ← IO.monoMsNow
  IO.FS.createDirAll store
  let t := MathView.modKey "(facts)" (MathView.blobId gk.toUTF8) (← toolHash root) []
  let build := (root / ".lake" / "build").toString ++ "/"
  let memo ← IO.mkRef ({} : Std.HashMap Name (Option String))
  let mut keys : Array (Name × String) := #[]
  for m in env.header.moduleNames do
    if let some k ← modKeyOf env build t memo m then keys := keys.push (m, k)
  let t1 ← IO.monoMsNow
  let mut hits : Array Stored := #[]
  let mut hitMods : NameSet := {}
  let mut missKeys : Array (Name × String) := #[]
  for (m, k) in keys do
    match ← readStored store k with
    | some es => hits := hits ++ es; hitMods := hitMods.insert m
    | none => missKeys := missKeys.push (m, k)
  let t2 ← IO.monoMsNow
  let ctx : Core.Context := { fileName := "<mathview>", fileMap := default }
  let (freshEs, _) ← ((MathView.entries (want := fun mod => !hitMods.contains mod)).run' {} {}).toIO ctx { env }
  let fresh ← withFacts env rs (nameIndex env) freshEs
  let t3 ← IO.monoMsNow
  let mut stored := 0
  for (m, k) in missKeys do
    let es := fresh.filter (·.entry.module == m.toString)
    if MathView.storable (es.map (·.entry)) then
      if ← writeStored store k es then stored := stored + 1
  let t4 ← IO.monoMsNow
  if let some f := stats then
    let misses := missKeys.toList.map (fun (m, _) => s!"miss {m}\n")
    IO.FS.writeFile f (s!"modules {keys.size}\nhits {hitMods.size}\nmisses {missKeys.size}\nstored {stored}\n" ++
      s!"ms keys {t1 - t0} read {t2 - t1} export {t3 - t2} store {t4 - t3}\n" ++ String.join misses)
  return (hits ++ fresh).qsort fun a b => MathView.Entry.before a.entry b.entry

/-- `--dependents <x>`: the package modules (those whose `.olean` is under `.lake/build/`) whose import cone contains
`x`, in import order, computed by `Fw.Spec.ConeMiss.dependents` (proved exact by `mem_dependents`) over
`env.header.moduleNames` restricted to the package, with each module's direct imports restricted to the package (a
toolchain module imports no package module, so no cone path leaves the package). These are the modules the module
cache recomputes after an edit of `x` alone. Throws when that order is not topological (`topoFrom`, the premise of
`mem_dependents`) or `x` is not a package module. -/
def dependentsOf (env : Environment) (root : System.FilePath) (x : String) : IO (List String) := do
  let build := (root / ".lake" / "build").toString ++ "/"
  let mut pkg : Array Name := #[]
  for m in env.header.moduleNames do
    if (← findOLean m).toString.startsWith build then pkg := pkg.push m
  let names : NameSet := pkg.foldl (·.insert ·) {}
  let mut imps : Std.HashMap String (List String) := {}
  for m in pkg do
    let some idx := env.getModuleIdx? m | throw (IO.userError s!"mathview: module {m} is not imported")
    let is := env.header.moduleData[idx.toNat]!.imports.toList.map (·.module) |>.filter names.contains
    imps := imps.insert m.toString (is.map toString)
  let imp : String → List String := fun m => imps.getD m []
  let order := pkg.toList.map toString
  unless Fw.Spec.ConeMiss.topoFrom imp [] order do
    throw (IO.userError "mathview: the module order is not topological")
  unless order.contains x do throw (IO.userError s!"mathview: {x} is not a package module")
  return Fw.Spec.ConeMiss.dependents imp order x

/-- `lake exe mathview [--lint] [--out <file>]`: print every `Fw` declaration as JSON (name, kind, module, line,
English, math, signature, machine LaTeX, deep statement hash, docstring hash, axioms; a theorem also its facts:
`headConst`, `implArg`, `assumes`, `killOf`, `class`, `reach`, `reachFromWire`, see `entryJson`); with `--lint`, exit 1 when
a declaration lacks `$$` math or English, depends on `sorryAx`, or on an axiom other than
`propext`, `Classical.choice`, `Quot.sound`, or when its `$$` math binds a name that it also applies as a function
and uses as a value (`ShadowLint`), or when a `where` / `with` clause after a `$$` block defines a symbol of that
block (`WhereLint`; in `Fw.Measure.*` that clause only warns, TODO(where-cleanup)). With `--out <file>` the JSON export is also written to
`<file>` (the same bytes as the plain export on stdout), so one run serves both the lint and the export;
`scripts/mathview-cached.sh` keeps that file keyed by a hash of the sources. With `--store <dir>` the export is
computed per module and reused from `<dir>` (`cachedEntries`; `--stats <file>` records hits and misses); the output is
the same bytes as without it, except the `heartbeats` field of a reused entry. `--dependents <module>` prints instead
one line per module whose import cone contains `<module>` (`dependentsOf`) and exits 0, or fails with an error when
`<module>` is not a package module or the module order is not topological. -/
def main (args : List String) : IO UInt32 := do
  let root ← packageRoot
  initSearchPath (← findSysroot) [root / ".lake" / "build" / "lib" / "lean"]
  let mods ← fwModules root
  -- `loadExts := false` is a premise of the module cache (see the module-cache note above)
  let env ← importModules (mods.map fun m => { module := m }) {} (loadExts := false)
  if let some x := optArg "--dependents" args then
    for d in ← dependentsOf env root x do IO.println d
    return 0
  let ctx : Core.Context := { fileName := "<mathview>", fileMap := default }
  let st : Core.State := { env }
  let ((rs, gk), _) ← (factsGlobals.run' {} {}).toIO ctx st
  let ss ← match optArg "--store" args with
    | some store => cachedEntries env root store (optArg "--stats" args) rs gk
    | none => do withFacts env rs (nameIndex env) (← Prod.fst <$> (MathView.entries.run' {} {}).toIO ctx st)
  let es := ss.map (·.entry)
  let wire ← wireSet env root
  let render : Unit → String := fun _ => (Json.arr (ss.map (entryJson wire.contains))).pretty ++ "\n"
  if let some f := outFile? args then IO.FS.writeFile f (render ())
  if args.contains "--lint" then
    let shadow := es.toList.flatMap ShadowLint.lintEntry
    -- TODO(where-cleanup): `warnOnly` lets Fw.Measure.* off with a warning until zone-baseline-lean lands
    let (whereWarnEs, whereBadEs) := es.toList.partition (WhereLint.warnOnly ·.module)
    let wheres := whereBadEs.flatMap WhereLint.lintEntry
    let bad := es.toList.flatMap MathView.lintEntry ++ shadow ++ wheres
    for b in bad do IO.eprintln s!"mathview: {b}"
    let strict := es.toList.flatMap (MathView.warnEntry false)
    let warns := es.toList.flatMap (MathView.warnEntry true)
    for w in warns do IO.eprintln s!"mathview: warning: {w}"
    let whereWarns := whereWarnEs.flatMap WhereLint.lintEntry
    for w in whereWarns do IO.eprintln s!"mathview: warning: {w}"
    let thms := (es.filter (·.kind == "theorem")).size
    IO.println s!"mathview lint: {es.size} entries ({thms} theorems) in {mods.size} modules, {bad.length} failing ({shadow.length} bound-and-applied, {wheres.length} dangling-where), {warns.length} quantifier warnings ({strict.length} counting a renamed binder as free), {whereWarns.length} dangling-where warnings (Fw.Measure)"
    return if bad.isEmpty then 0 else 1
  if (outFile? args).isNone then IO.print (render ())
  return 0
