import MathView
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


/-! ## Facts per theorem (task lfg-mathview-facts)

Each theorem entry also carries the facts of `Fw.Spec.MathFacts` (head constant, implementation argument, `Assume`
premises, killed incident, proof class, reach), `reachFromWire` and `subjectsWire`. The facts of one theorem depend on its import
cone and on two global inputs: the registered signatures and registry rows (`factsGlobals`) and the wire reach
(`wireSet`). Each theorem's facts are computed in a fresh `Core`/`Meta` state, so they do not depend on the other
declarations an export selects. -/

/-- An exported entry and, for a theorem, its facts (none for any other kind, and for a theorem whose facts were not
computed, see `withFacts`). -/
structure Stored where
  /-- The math-view entry, unchanged. -/
  entry : MathView.Entry
  /-- The facts of a theorem. -/
  facts : Option Fw.Spec.MathFacts.Facts
deriving ToJson, FromJson

/-- Heartbeat budget of the facts of one theorem, in thousands. -/
def factsBudget : Nat := 20000

/-- The global inputs of the facts: the registry rows (`Fw.Spec.MathFacts.rows`) and a text key over every registered
signature constructor `s` with its reduced `Sig.Dom s` and `Sig.Cod s`, then every row's id, row name and replay name. -/
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
`factsOf` throws any error (running out of the budget included). -/
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

/-- The wire reach `W` (`Fw.Spec.MathFacts.wireReach` over `Fw.Spec.MathFacts.goldenSources root`) by printed name. -/
def wireSet (env : Environment) (root : System.FilePath) : IO (Std.HashSet String) := do
  let w := Fw.Spec.MathFacts.wireReach env (← Fw.Spec.MathFacts.goldenSources root)
  return w.foldl (fun s n => s.insert n.toString) {}

/-- **The JSON of one entry**: `toJson` of the entry, unchanged for a non-theorem; a theorem also gets the keys
`headConst`, `implArg` (`{index, expr}` or null), `assumes`, `killOf`, `class`, `reach`, `reachFromWire` and
`subjectsWire` (`[{name, wired}]`), each null when its facts are missing; `reachFromWire` is also null when the
theorem has no subjects (`Fw.Spec.MathFacts.reachFromWire`, true only when every subject is in `W`).
`reach` keeps only the names in the set `E` of exported entry names, in order. -/
def entryJson (inWire isEntry : String → Bool) (s : Stored) : Json :=
  let j := toJson s.entry
  if s.entry.kind != "theorem" then j else
  let keys : List (String × Json) := match s.facts with
    | none => ["headConst", "implArg", "assumes", "killOf", "class", "reach", "reachFromWire", "subjectsWire"].map
        (·, Json.null)
    | some f =>
      [("headConst", toJson f.headConst),
       ("implArg", match f.implIdx with
         | some i => Json.mkObj [("index", toJson i), ("expr", toJson f.implExpr)]
         | none => Json.null),
       ("assumes", toJson f.assumes), ("killOf", toJson f.killOf), ("class", toJson f.cls.tag),
       ("reach", toJson (f.reach.filter isEntry)),
       ("reachFromWire", toJson (Fw.Spec.MathFacts.reachFromWire f.subjects inWire)),
       ("subjectsWire", Json.arr (Fw.Spec.MathFacts.subjectsWire f.subjects inWire |>.toArray.map fun (x, b) =>
         Json.mkObj [("name", toJson x), ("wired", toJson b)]))]
  keys.foldl (fun j (k, v) => j.setObjVal! k v) j

/-- The file named after `--out`, if any. -/
def outFile? (args : List String) : Option String := MathView.optArg "--out" args

/-- `lake exe mathview [--decl <name>...] [--module <M>] [--lint] [--out <file>]`: print the `Fw` declarations that
`MathView.Filter.ofArgs` keeps (every one by default) as JSON: name, kind, module, line, docstring, signature, machine
LaTeX, deep statement hash, axioms; a theorem also its facts (`entryJson`). It exits 1 when a `--decl` name is not
exported. With `--lint` it exits 1 when a kept declaration failed to export, depends on `sorryAx`, or on an axiom
other than `propext`, `Classical.choice`, `Quot.sound`. The JSON goes to `<file>` with `--out <file>`, else to
stdout unless `--lint` is given. Math is written on demand from this export (docs/team/tools/math-artifact.md). -/
def main (args : List String) : IO UInt32 := do
  let root ← packageRoot
  initSearchPath (← findSysroot) [root / ".lake" / "build" / "lib" / "lean"]
  let mods ← fwModules root
  let env ← importModules (mods.map fun m => { module := m }) {} (loadExts := false)
  let ctx : Core.Context := { fileName := "<mathview>", fileMap := default }
  let st : Core.State := { env }
  let filter := MathView.Filter.ofArgs args
  let ((rs, _), _) ← (factsGlobals.run' {} {}).toIO ctx st
  let ss ← withFacts env rs (nameIndex env) (← Prod.fst <$> ((MathView.entries filter).run' {} {}).toIO ctx st)
  let es := ss.map (·.entry)
  let wire ← wireSet env root
  let names : Std.HashSet String := es.foldl (fun s e => s.insert e.name) {}
  let missing := filter.missing (es.toList.map (·.name))
  for d in missing do IO.eprintln s!"mathview: {d}: no such exported declaration"
  let out := (Json.arr (ss.map (entryJson wire.contains names.contains))).pretty ++ "\n"
  match outFile? args with
  | some f => IO.FS.writeFile f out
  | none => unless args.contains "--lint" do IO.print out
  if !missing.isEmpty then return 1
  if args.contains "--lint" then
    let bad := es.toList.flatMap MathView.lintEntry
    for b in bad do IO.eprintln s!"mathview: {b}"
    let thms := (es.filter (·.kind == "theorem")).size
    IO.println s!"mathview lint: {es.size} entries ({thms} theorems), {bad.length} failing"
    return if bad.isEmpty then 0 else 1
  return 0
