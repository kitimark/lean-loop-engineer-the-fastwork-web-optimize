import Lean
import Fw.Spec.Reach
/-!
# The properties lint (task `lfg-props-shape`, a check.sh stage)

An environment scan, decided in Lean. Run from `lean/`:

* `lake env lean --run scripts/PropsLint.lean` lints every built module of every `[[lean_lib]]` of `lakefile.toml`
  (`Fw`, `MathView`, `FwTest`, ...: the module `L` and every module under `L/`) against
  `../docs/team/incidents/ledger.json`;
* `lake env lean --run scripts/PropsLint.lean <dir> <Module>` also imports the compiled module `<Module>` from `<dir>`
  (for example a reviewer's probe, compiled first with `lake env lean -R <dir> -o <dir>/<Module>.olean
  <dir>/<Module>.lean`) and lints its declarations as well.

Rules (a finding is one line `props-lint: <rule> <declaration>: <detail>`; exit 1 on any finding):

* `registry-outside`: a declaration outside `Fw.Spec.Incidents` whose type ends in `Incident`/`Registry`, or whose
  type or value mentions `Incident.mk`/`Registry.mk` (every structure instance, `where` block, `⟨…⟩` and `{ r with … }`
  elaborates to the constructor). The structures' own auxiliaries in `Fw.Spec.Props` are exempt.
* `convention-at-outside`: a declaration outside `Fw.Spec.Incidents` whose statement mentions `ConventionAt`: the gate
  is `Incidents.Convention s impl P`, which takes no registry.
* `prop-mentions-impl`: in every `Incidents.Convention s impl P` that a statement mentions, the property `P` (and every
  project constant it reaches: definition values, the types of inductives, constructors, theorems, opaques and axioms,
  and the constructors of inductives) mentions neither `impl` nor a project constant that `impl` reaches, except the
  ones that the spec vocabulary `Incidents.vocab s` and the signature's types `Sig.Dom s`, `Sig.Cod s` reach
  (`forbidden`, `propHits`).
* `convention-wrapped`: outside `Fw.Spec.Incidents`, a definition whose value reaches `Incidents.Convention` (a
  wrapper), or a declaration whose type mentions `Convention` or a wrapper anywhere but as the head of a theorem's
  result type or of `¬ …` there (`misplaced`): `prop-mentions-impl` reads only statements of the form `∀ …, Convention s impl P`.
* `vocab-has-impl`: the vocabulary of `s` unfolds to `impl` itself.
* `ledger`: each row of each `registryFor s` has its `pred` and `replay` as named definitions of `Fw.Spec.Incidents`,
  its id is an incident id of the ledger, and that entry's `leanPred` and `leanReplay` are those names.

What it does not catch: a property that restates the implementation inline instead of naming it, and a property that
separates `impl` from the replay on an unrelated part of the output (both are review items, see `Fw.Spec.Props`).
-/
open Lean Meta
open Fw.Spec.Reach

namespace PropsLint

/-- The module that holds every registry row. -/
def incidentsMod : Name := `Fw.Spec.Incidents
/-- The module that defines the registry structures. -/
def propsMod : Name := `Fw.Spec.Props
/-- The guarded structure types. -/
def guardedTypes : List Name := [`Fw.Spec.Props.Incident, `Fw.Spec.Props.Registry]
/-- The gate every incident property is stated through. -/
def conventionName : Name := `Fw.Spec.Incidents.Convention
/-- The guarded constructors. -/
def guardedCtors : List Name := [`Fw.Spec.Props.Incident.mk, `Fw.Spec.Props.Registry.mk]

/-! ## Pure decisions (with `#guard` examples) -/

/-- **Exempt from `registry-outside` and `convention-at-outside`.** A declaration of module $m$ named $n$ is exempt
exactly when $m$ is `Fw.Spec.Incidents`, or $m$ is `Fw.Spec.Props` and $n$ lies in the namespace of a guarded
structure or of `ConventionAt` (their constructors, projections and generated lemmas).
$$\operatorname{exempt}(m, n) \iff m = \texttt{Fw.Spec.Incidents} \lor (m = \texttt{Fw.Spec.Props} \land \exists T \in \{\texttt{Incident}, \texttt{Registry}, \texttt{ConventionAt}\},\ T \preceq n)$$
where $T \preceq n$ is "the name $T$ is a prefix of $n$". -/
def exempt (mod n : Name) : Bool :=
  mod == incidentsMod ||
    (mod == propsMod && (guardedTypes ++ [`Fw.Spec.Props.ConventionAt]).any (·.isPrefixOf n))

#guard exempt `Fw.Spec.Incidents `Fw.Spec.Incidents.LandDry.registry
#guard exempt `Fw.Spec.Props `Fw.Spec.Props.Registry.mk
#guard !exempt `Fw.Spec.Props `Fw.Spec.Props.kills_of_rejects
#guard !exempt `Fw.Spec.Props.LandDryDemo `Fw.Spec.Props.Registry.fake
#guard !exempt `Refute `Refute.fakeReg

/-- **The `lean_lib` names of a `lakefile.toml`**, given as its lines: for every line `[[lean_lib]]`, the quoted value
of the first later line of the form `name = "…"` (spaces trimmed), in file order. A `[[lean_lib]]` with no later name
line, or whose name value is not quoted, contributes nothing.
$$\forall \ell,\ \operatorname{libNames}(\ell) = [\operatorname{name}(\ell_j) : \ell_i = \texttt{[[lean\_lib]]},\ j = \min\{j > i : \ell_j \text{ is a name line}\},\ \ell_j \text{ quoted}] \text{ in order of } i$$ -/
def libNames (lines : List String) : List String :=
  go lines false
where
  /-- `pending` is true between a `[[lean_lib]]` header and its name line. -/
  go : List String → Bool → List String
    | [], _ => []
    | l :: ls, pending =>
      let t := l.trimAscii.toString
      let rest := (t.drop 4).toString.trimAsciiStart.toString
      if t == "[[lean_lib]]" then go ls true
      else if pending && t.startsWith "name" && rest.startsWith "=" then
        let v := (rest.drop 1).toString.trimAscii.toString
        (if v.length ≥ 2 && v.startsWith "\"" && v.endsWith "\"" then [((v.drop 1).toString.dropEnd 1).toString]
          else []) ++ go ls false
      else go ls pending

#guard libNames ["[[lean_lib]]", "name = \"Fw\"", "globs = [\"Fw.*\"]", "[[lean_exe]]", "name = \"fwcore\"",
  "[[lean_lib]]", "name = \"MathView\""] == ["Fw", "MathView"]
#guard libNames ["[[lean_exe]]", "name = \"fwcore\""] == []
#guard libNames ["[[lean_lib]]"] == []
#guard libNames [] == []

/-- **A misplaced convention** (rule `convention-wrapped`). Given the names that count as a convention $W$ (the
constant `Convention` $c$ and the wrappers), the head $h$ of a theorem's result type (`none` for a definition's value),
and the other constants $U$ of the type (or value): the names of $W$ that occur anywhere but as the head $c$.
$$\forall W, c, h, U,\ \operatorname{misplaced}(W, c, h, U) = \operatorname{dedup}[x \in U \mathbin{+\!\!+} [h' : h = \mathrm{some}(h'),\ h' \ne c] : x \in W]$$ -/
def misplaced (conv : List Name) (c : Name) (head : Option Name) (others : List Name) : List Name :=
  (others ++ (head.filter (· != c)).toList).filter conv.contains |>.eraseDups

#guard misplaced [`C] `C (some `C) [`P, `impl] == []
#guard misplaced [`C, `Wrapped] `C (some `Wrapped) [] == [`Wrapped]
#guard misplaced [`C] `C (some `And) [`C, `True] == [`C]
#guard misplaced [`C] `C none [`C, `PinImpl] == [`C]
#guard misplaced [`C] `C none [] == []

/-- **The implementation's internals**: the implementation's own names $I_0$, and every project definition the
implementation unfolds to ($C_I$) that the vocabulary does not unfold to ($C_V$).
$$\operatorname{forbidden}(I_0, C_I, C_V) = I_0 \cup [c \in C_I : c \notin C_V]$$ -/
def forbidden (implRoots implClos vocabClos : List Name) : List Name :=
  (implRoots ++ implClos.filter (!vocabClos.contains ·)).eraseDups

/-- **The forbidden names a property reaches**: the names of the property's closure $C_P$ that are forbidden.
$$\operatorname{propHits}(C_P, F) = [c \in C_P : c \in F]$$ -/
def propHits (propClos forb : List Name) : List Name := propClos.filter forb.contains

-- the dry-run example: `dryOut` unfolds to `dryRun` (internal) and to `Outcome.kind` (vocabulary)
#guard forbidden [`dryOut] [`dryOut, `dryRun, `Outcome.log, `Outcome.kind] [`Outcome.kind, `Outcome.first] ==
  [`dryOut, `dryRun, `Outcome.log]
#guard propHits [`PinImpl, `dryOut] (forbidden [`dryOut] [`dryOut, `dryRun] []) == [`dryOut]
#guard propHits [`NoSilentExit, `verdictCount, `isVerdict] (forbidden [`dryOut] [`dryOut, `dryRun] []) == []
#guard propHits [`TruthfulVerdict, `Outcome.kind] (forbidden [`dryOut] [`dryOut, `Outcome.kind] [`Outcome.kind]) == []
#guard forbidden [] [] [] == []

/-- **One ledger row check.** For a row id $i$, its predicate and replay names $p, r$, and the ledger's entries as
(id, `leanPred`, `leanReplay`) triples $L$: the empty list when the first entry with id $i$ names $p$ and $r$, else
the problems.
$$\operatorname{rowCheck}(i, p, r, L) = \begin{cases} [\texttt{not in the ledger}] & \lnot\exists e \in L,\ e.\mathit{id} = i \\ [\texttt{leanPred} \mid e.p \ne p] \mathbin{+\!\!+} [\texttt{leanReplay} \mid e.r \ne r] & e = \text{the first } e \in L \text{ with } e.\mathit{id} = i \end{cases}$$ -/
def rowCheck (id pred replay : String) (ledger : List (String × Option String × Option String)) : List String :=
  match ledger.find? (·.1 == id) with
  | none => [s!"{id} is not an incident id of the ledger"]
  | some (_, p, r) =>
    (if p == some pred then [] else [s!"ledger {id} leanPred is {p.getD "missing"}, the row's pred is {pred}"]) ++
    (if r == some replay then [] else [s!"ledger {id} leanReplay is {r.getD "missing"}, the row's replay is {replay}"])

#guard rowCheck "a" "P" "R" [("a", some "P", some "R")] == []
#guard (rowCheck "a" "P" "R" [("b", some "P", some "R")]).length == 1
#guard (rowCheck "a" "P" "R" [("a", none, some "R")]).length == 1
#guard (rowCheck "a" "P" "R" [("a", some "Q", some "S")]).length == 2
#guard rowCheck "a" "P" "R" [("a", some "P", some "R"), ("a", none, none)] == []
#guard (rowCheck "a" "P" "R" []).length == 1

/-! ## The scan (I/O and `MetaM` glue: reads the environment and the ledger, decides with the functions above)

The closure, the module of a declaration and the registry rows are `Fw.Spec.Reach` (shared with the math-view facts,
`Fw.Spec.MathFacts`). -/

/-- The vocabulary of a signature, as names. -/
def vocabOf (s : Expr) : MetaM (List Name) := do
  let es ← listElems (mkApp (mkConst `Fw.Spec.Incidents.vocab) s)
  es.mapM fun e => return (← strLit e).toName

/-- `registry-outside`, `convention-at-outside`, `convention-wrapped` and `prop-mentions-impl` for one declaration. -/
def lintDecl (sc : Scope) (wrappers : List Name) (n : Name) (ci : ConstantInfo) : MetaM (List String) := do
  let env ← getEnv
  -- a reserved name (`foo.eq_1`, `foo.congr_simp`: Lean generates it on demand, in whichever module first asks, and a
  -- user cannot declare one, `Lean.Elab.checkNotAlreadyDeclared`) belongs to its base declaration
  let owner := if isReservedName env n then n.getPrefix else n
  let mod := modOf env owner
  let mut out : List String := []
  let used := ci.type.getUsedConstants.toList ++ ((valueOf? ci).map (·.getUsedConstants.toList) |>.getD [])
  unless exempt mod owner do
    let head := (resultType ci.type).getAppFn.constName?
    if head.any guardedTypes.contains then
      out := out ++ [s!"props-lint: registry-outside {n}: a value of type {head.getD .anonymous} outside {incidentsMod}"]
    for c in guardedCtors do
      if used.contains c then
        out := out ++ [s!"props-lint: registry-outside {n}: builds {c} outside {incidentsMod}"]
    if ci.type.getUsedConstants.contains `Fw.Spec.Props.ConventionAt then
      out := out ++ [s!"props-lint: convention-at-outside {n}: states ConventionAt; state Fw.Spec.Incidents.Convention s impl P"]
    if wrappers.contains owner then
      out := out ++ [s!"props-lint: convention-wrapped {n}: a definition whose value reaches {conventionName}; state ∀ …, {conventionName} s impl P as a theorem"]
    let (head, others) := match ci with
      | .thmInfo _ =>
        let (bs, rt) := typeParts ci.type
        -- `¬ Convention s impl P` (a property that fails the convention) asserts no convention
        let rt := if rt.isAppOfArity ``Not 1 then rt.appArg! else rt
        (rt.getAppFn.constName?, bs ++ rt.getAppArgs.toList.flatMap (·.getUsedConstants.toList) ++
          (if rt.getAppFn.isConst then [] else rt.getAppFn.getUsedConstants.toList))
      | _ => (none, ci.type.getUsedConstants.toList)
    let mis := misplaced (conventionName :: wrappers) conventionName head others
    unless mis.isEmpty do
      out := out ++ [s!"props-lint: convention-wrapped {n}: the type mentions {mis} other than as the head of a theorem's result type"]
  -- every `Convention s impl P` in the statement
  let apps := collectConventions ci.type
  for (s, impl, p) in apps do
    let implRoots := impl.getUsedConstants.toList.filter fun c => isProject sc (modOf env c)
    let vocab ← vocabOf s
    for v in vocab do
      unless env.contains v do
        out := out ++ [s!"props-lint: ledger {n}: vocabulary name {v} does not exist"]
    -- the signature's own types (`Sig.Dom s`, `Sig.Cod s`) are shared vocabulary, not internals of `impl`
    let sigTys := (← whnf (mkApp (mkConst `Fw.Spec.Incidents.Sig.Dom) s)).getUsedConstants.toList ++
      (← whnf (mkApp (mkConst `Fw.Spec.Incidents.Sig.Cod) s)).getUsedConstants.toList
    let vClos := closure env sc (vocab ++ sigTys)
    let iClos := closure env sc implRoots
    for r in implRoots do
      if vClos.contains r then
        out := out ++ [s!"props-lint: vocab-has-impl {n}: the vocabulary unfolds to the implementation {r}"]
    let forb := forbidden implRoots iClos vClos
    let pRoots := p.getUsedConstants.toList
    let pClos := (pRoots ++ closure env sc pRoots).eraseDups
    let hits := propHits pClos forb
    unless hits.isEmpty do
      out := out ++ [s!"props-lint: prop-mentions-impl {n}: the property {p} reaches {hits} (internals of {impl})"]
  return out
where
  /-- Every `Fw.Spec.Incidents.Convention s impl P` application in an expression. -/
  collectConventions (e : Expr) : List (Expr × Expr × Expr) :=
    (go e).reverse
  go (e : Expr) : List (Expr × Expr × Expr) :=
    let here := match e.getAppFnArgs with
      | (`Fw.Spec.Incidents.Convention, #[s, impl, p]) => [(s, impl, p)]
      | _ => []
    let sub := match e with
      | .app f a => go f ++ go a
      | .lam _ t b _ | .forallE _ t b _ => go t ++ go b
      | .letE _ t v b _ => go t ++ go v ++ go b
      | .mdata _ b | .proj _ _ b => go b
      | _ => []
    here ++ sub

/-- The name of a row field, which must be a definition of `Fw.Spec.Incidents`. -/
def rowName (env : Environment) (what : String) (e : Expr) : Except String Name :=
  match e.consumeMData with
  | .const c _ =>
    if modOf env c == incidentsMod then .ok c else .error s!"the row's {what} {c} is not a definition of {incidentsMod}"
  | e => .error s!"the row's {what} is not a named definition: {e}"

/-- `ledger`: every row of every `registryFor s` against the ledger's (id, `leanPred`, `leanReplay`) triples. -/
def lintRows (ledger : List (String × Option String × Option String)) : MetaM (List String) := do
  let env ← getEnv
  let mut out : List String := []
  for (c, r) in ← registryRows do
    let r ← whnf r
    match r.getAppFnArgs with
    | (`Fw.Spec.Props.Incident.mk, #[_, _, idE, predE, replayE]) =>
      let id ← strLit idE
      match rowName env "pred" predE, rowName env "replay" replayE with
      | .ok p, .ok q =>
        out := out ++ (rowCheck id p.toString q.toString ledger).map (s!"props-lint: ledger {c}: " ++ ·)
      | .error m, _ => out := out ++ [s!"props-lint: ledger {c} {id}: {m}"]
      | _, .error m => out := out ++ [s!"props-lint: ledger {c} {id}: {m}"]
    | _ => out := out ++ [s!"props-lint: ledger {c}: a row is not an Incident.mk literal: {r}"]
  return out

/-- The ledger's incidents as (id, `leanPred`, `leanReplay`) triples. -/
def readLedger (path : System.FilePath) : IO (List (String × Option String × Option String)) := do
  let j ← IO.ofExcept (Json.parse (← IO.FS.readFile path))
  let arr ← IO.ofExcept (j.getObjValAs? (Array Json) "incidents")
  return arr.toList.filterMap fun e => match e.getObjValAs? String "id" with
    | .ok id => some (id, (e.getObjValAs? String "leanPred").toOption, (e.getObjValAs? String "leanReplay").toOption)
    | .error _ => none

/-- The project declarations of an environment. -/
def projectDecls (env : Environment) (sc : Scope) : List (Name × ConstantInfo) :=
  env.constants.toList.filter fun (n, _) => isProject sc (modOf env n)

/-- The wrappers (rule `convention-wrapped`): the least set of non-exempt project definitions whose value mentions
`Convention` or a wrapper. -/
partial def wrappersOf (env : Environment) (decls : List (Name × ConstantInfo)) : List Name :=
  let defs := decls.filterMap fun (n, ci) => match ci with
    | .defnInfo d => if exempt (modOf env n) n then none else some (n, d.value.getUsedConstants.toList)
    | _ => none
  let rec go (w : List Name) : List Name :=
    let w' := defs.filterMap fun (n, us) =>
      if !w.contains n && us.any (fun u => u == conventionName || w.contains u) then some n else none
    if w'.isEmpty then w else go (w ++ w')
  go []

/-- Every finding of the environment. -/
def lintEnv (sc : Scope) (ledger : List (String × Option String × Option String)) : MetaM (List String) := do
  let env ← getEnv
  let decls := projectDecls env sc
  let wrappers := wrappersOf env decls
  let mut out : List String := []
  for (n, ci) in decls do
    out := out ++ (← lintDecl sc wrappers n ci)
  if (sigCtors env).isEmpty then
    out := out ++ ["props-lint: ledger: Fw.Spec.Incidents.Sig is not loaded"]
  out := out ++ (← lintRows ledger)
  return out

/-- The modules of the `lean_lib`s named `libs`: for each name `L`, the module `L` when `L.lean` exists and every
module under `L/`, kept only when its `.olean` is on the search path (built); the skipped ones are returned too. -/
def libModules (libs : List Name) : IO (Array Name × Array Name) := do
  let mut mods : Array Name := #[]
  let mut skipped : Array Name := #[]
  for l in libs do
    let root : System.FilePath := l.toString
    let mut cands : Array Name := if ← (root.withExtension "lean").pathExists then #[l] else #[]
    if ← root.isDir then
      for f in ← root.walkDir do
        if f.extension == some "lean" then
          cands := cands.push ((f.withExtension "").toString.splitOn "/" |>.foldl Name.mkStr .anonymous)
    for m in cands do
      if ← (← findOLean m).pathExists then mods := mods.push m else skipped := skipped.push m
  return (mods.qsort (·.toString < ·.toString), skipped)

end PropsLint

open PropsLint in
/-- Lint every built module of every `lean_lib` of `lakefile.toml` (no argument), plus one extra compiled module `<Module>` found in `<dir>` (for a
reviewer's probe: `lake env lean -R <dir> -o <dir>/<Module>.olean <dir>/<Module>.lean` first). Exit 1 on any
finding. -/
def main (args : List String) : IO UInt32 := do
  let (extra, dirs) ← match args with
    | [] => pure (Name.anonymous, [])
    | [dir, m] => pure (m.toName, [System.FilePath.mk dir])
    | _ => throw (IO.userError "usage: lake env lean --run scripts/PropsLint.lean [<dir> <Module>]")
  initSearchPath (← findSysroot) dirs
  let ledger ← readLedger "../docs/team/incidents/ledger.json"
  let libs := (libNames (← IO.FS.lines "lakefile.toml").toList).map String.toName
  let sc : Scope := ⟨libs, extra⟩
  let (libMods, skipped) ← libModules libs
  unless skipped.isEmpty do IO.println s!"props-lint: note: not built, not linted: {skipped}"
  let mods := libMods ++ (if extra.isAnonymous then #[] else #[extra])
  let env ← importModules (mods.map fun m => { module := m }) {} (loadExts := false)
  let ctx : Core.Context := { fileName := "<props-lint>", fileMap := default, maxHeartbeats := 0 }
  let (out, _) ← ((lintEnv sc ledger).run' {} {}).toIO ctx { env }
  for l in out do IO.println l
  if out.isEmpty then
    IO.println s!"props-lint: ok ({libMods.size} modules of {libs}, {(projectDecls env sc).length} project declarations, {(sigCtors env).length} signature(s), ledger rows match)"
    return 0
  IO.println s!"props-lint: FAILED: {out.length} finding(s)"
  return 1
