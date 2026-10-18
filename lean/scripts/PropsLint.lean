import Lean
/-!
# The properties lint (task `lfg-props-shape`, a check.sh stage)

An environment scan, decided in Lean. Run from `lean/`:

* `lake env lean --run scripts/PropsLint.lean` lints every module under `Fw/` against
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
  project definition it unfolds to) mentions neither `impl` nor a project definition that `impl` unfolds to, except the
  ones the spec vocabulary `Incidents.vocab s` unfolds to (`forbidden`, `propHits`).
* `vocab-has-impl`: the vocabulary of `s` unfolds to `impl` itself.
* `ledger`: each row of each `registryFor s` has its `pred` and `replay` as named definitions of `Fw.Spec.Incidents`,
  its id is an incident id of the ledger, and that entry's `leanPred` and `leanReplay` are those names.

What it does not catch: a property that restates the implementation inline instead of naming it, and a property that
separates `impl` from the replay on an unrelated part of the output (both are review items, see `Fw.Spec.Props`).
-/
open Lean Meta

namespace PropsLint

/-- The module that holds every registry row. -/
def incidentsMod : Name := `Fw.Spec.Incidents
/-- The module that defines the registry structures. -/
def propsMod : Name := `Fw.Spec.Props
/-- The guarded structure types. -/
def guardedTypes : List Name := [`Fw.Spec.Props.Incident, `Fw.Spec.Props.Registry]
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

/-- **Is a module ours?** Its root is `Fw`, or it is the extra module being linted.
$$\operatorname{project}(m) \iff \operatorname{root}(m) = \texttt{Fw} \lor m = m_{\mathrm{main}}$$ -/
def isProject (main mod : Name) : Bool := mod.getRoot == `Fw || mod == main

#guard isProject `Refute `Fw.Spec.Incidents
#guard isProject `Refute `Refute
#guard !isProject `Refute `Lean.Data.Json

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

/-! ## The scan (I/O and `MetaM` glue: reads the environment and the ledger, decides with the functions above) -/

/-- The module of a declaration (the main module for a declaration of the file being linted). -/
def modOf (env : Environment) (n : Name) : Name :=
  match env.getModuleIdxFor? n with
  | some i => env.header.moduleNames[i.toNat]!
  | none => env.mainModule

/-- The type of a declaration with every leading `∀` stripped. -/
partial def resultType : Expr → Expr
  | .forallE _ _ b _ => resultType b
  | e => e

/-- The value of a definition, theorem or opaque. -/
def valueOf? : ConstantInfo → Option Expr
  | .defnInfo d => some d.value
  | .thmInfo t => some t.value
  | .opaqueInfo o => some o.value
  | _ => none

/-- Every project definition reachable from the roots through definition values (roots included when they are
project definitions). -/
partial def closure (env : Environment) (extra : Name) (roots : List Name) : List Name := Id.run do
  let mut seen : NameSet := {}
  let mut out : Array Name := #[]
  let mut todo := roots
  while true do
    match todo with
    | [] => break
    | c :: rest =>
      todo := rest
      if seen.contains c then continue
      seen := seen.insert c
      unless isProject extra (modOf env c) do continue
      if let some (.defnInfo d) := env.find? c then
        out := out.push c
        todo := d.value.getUsedConstants.toList ++ todo
  return out.toList

/-- The elements of a list expression, after `whnf` at each cons. -/
partial def listElems (e : Expr) : MetaM (List Expr) := do
  let e ← whnf e
  match e.getAppFnArgs with
  | (``List.cons, #[_, h, t]) => return h :: (← listElems t)
  | (``List.nil, _) => return []
  | _ => throwError "props-lint: not a list literal: {e}"

/-- A string literal, after `whnf`. -/
def strLit (e : Expr) : MetaM String := do
  match ← whnf e with
  | .lit (.strVal s) => return s
  | e => throwError "props-lint: not a string literal: {e}"

/-- The constructors of `Fw.Spec.Incidents.Sig` (none when the module is not loaded). -/
def sigCtors (env : Environment) : List Name :=
  match env.find? `Fw.Spec.Incidents.Sig with
  | some (.inductInfo i) => i.ctors
  | _ => []

/-- The vocabulary of a signature, as names. -/
def vocabOf (s : Expr) : MetaM (List Name) := do
  let es ← listElems (mkApp (mkConst `Fw.Spec.Incidents.vocab) s)
  es.mapM fun e => return (← strLit e).toName

/-- `registry-outside`, `convention-at-outside` and `prop-mentions-impl` for one declaration. -/
def lintDecl (extra : Name) (n : Name) (ci : ConstantInfo) : MetaM (List String) := do
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
  -- every `Convention s impl P` in the statement
  let apps := collectConventions ci.type
  for (s, impl, p) in apps do
    let implRoots := impl.getUsedConstants.toList.filter fun c => isProject extra (modOf env c)
    let vocab ← vocabOf s
    for v in vocab do
      unless env.contains v do
        out := out ++ [s!"props-lint: ledger {n}: vocabulary name {v} does not exist"]
    let vClos := closure env extra vocab
    let iClos := closure env extra implRoots
    for r in implRoots do
      if vClos.contains r then
        out := out ++ [s!"props-lint: vocab-has-impl {n}: the vocabulary unfolds to the implementation {r}"]
    let forb := forbidden implRoots iClos vClos
    let pRoots := p.getUsedConstants.toList
    let pClos := (pRoots ++ closure env extra pRoots).eraseDups
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
  for c in sigCtors env do
    let reg := mkApp (mkConst `Fw.Spec.Incidents.registryFor) (mkConst c)
    let rows ← listElems (← mkAppM `Fw.Spec.Props.Registry.rows #[reg])
    for r in rows do
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
def projectDecls (env : Environment) (extra : Name) : List (Name × ConstantInfo) :=
  env.constants.toList.filter fun (n, _) => isProject extra (modOf env n)

/-- Every finding of the environment. -/
def lintEnv (extra : Name) (ledger : List (String × Option String × Option String)) : MetaM (List String) := do
  let env ← getEnv
  let mut out : List String := []
  for (n, ci) in projectDecls env extra do
    out := out ++ (← lintDecl extra n ci)
  if (sigCtors env).isEmpty then
    out := out ++ ["props-lint: ledger: Fw.Spec.Incidents.Sig is not loaded"]
  out := out ++ (← lintRows ledger)
  return out

/-- Every module under `Fw/`, plus `Fw`. -/
def fwModules : IO (Array Name) := do
  let files ← System.FilePath.walkDir "Fw"
  let mut mods : Array Name := #[`Fw]
  for f in files do
    if f.extension == some "lean" then
      mods := mods.push ((f.withExtension "").toString.splitOn "/" |>.foldl Name.mkStr .anonymous)
  return mods.qsort (·.toString < ·.toString)

end PropsLint

open PropsLint in
/-- Lint every module under `Fw/` (no argument), plus one extra compiled module `<Module>` found in `<dir>` (for a
reviewer's probe: `lake env lean -R <dir> -o <dir>/<Module>.olean <dir>/<Module>.lean` first). Exit 1 on any
finding. -/
def main (args : List String) : IO UInt32 := do
  let (extra, dirs) ← match args with
    | [] => pure (Name.anonymous, [])
    | [dir, m] => pure (m.toName, [System.FilePath.mk dir])
    | _ => throw (IO.userError "usage: lake env lean --run scripts/PropsLint.lean [<dir> <Module>]")
  initSearchPath (← findSysroot) dirs
  let ledger ← readLedger "../docs/team/incidents/ledger.json"
  let mods := (← fwModules) ++ (if extra.isAnonymous then #[] else #[extra])
  let env ← importModules (mods.map fun m => { module := m }) {} (loadExts := false)
  let ctx : Core.Context := { fileName := "<props-lint>", fileMap := default, maxHeartbeats := 0 }
  let (out, _) ← ((lintEnv extra ledger).run' {} {}).toIO ctx { env }
  for l in out do IO.println l
  if out.isEmpty then
    IO.println s!"props-lint: ok ({(projectDecls env extra).length} project declarations, {(sigCtors env).length} signature(s), ledger rows match)"
    return 0
  IO.println s!"props-lint: FAILED: {out.length} finding(s)"
  return 1
