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

/-- The file named after `--out`, if any. -/
def outFile? : List String → Option String
  | "--out" :: f :: _ => some f
  | _ :: rest => outFile? rest
  | [] => none

/-- `lake exe mathview [--lint] [--out <file>]`: print every `Fw` declaration as JSON (name, kind, module, line,
English, math, signature, machine LaTeX, deep statement hash, docstring hash, axioms); with `--lint`, exit 1 when
a declaration lacks `$$` math or English, depends on `sorryAx`, or on on an axiom other than
`propext`, `Classical.choice`, `Quot.sound`. With `--out <file>` the JSON export is also written to
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
    let bad := es.toList.flatMap MathView.lintEntry
    for b in bad do IO.eprintln s!"mathview: {b}"
    let strict := es.toList.flatMap (MathView.warnEntry false)
    let warns := es.toList.flatMap (MathView.warnEntry true)
    for w in warns do IO.eprintln s!"mathview: warning: {w}"
    let thms := (es.filter (·.kind == "theorem")).size
    IO.println s!"mathview lint: {es.size} entries ({thms} theorems) in {mods.size} modules, {bad.length} failing, {warns.length} quantifier warnings ({strict.length} counting a renamed binder as free)"
    return if bad.isEmpty then 0 else 1
  if (outFile? args).isNone then IO.print (render ())
  return 0
