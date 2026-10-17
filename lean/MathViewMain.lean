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

/-- `lake exe mathview [--lint]`: print every `Fw` declaration as JSON (name, kind, module, line,
English, math, signature, machine LaTeX, deep statement hash, axioms); with `--lint`, exit 1 when
a declaration lacks `$$` math or English, depends on `sorryAx`, or on on an axiom other than
`propext`, `Classical.choice`, `Quot.sound`. -/
def main (args : List String) : IO UInt32 := do
  let root ← packageRoot
  initSearchPath (← findSysroot) [root / ".lake" / "build" / "lib" / "lean"]
  let mods ← fwModules root
  let env ← importModules (mods.map fun m => { module := m }) {} (loadExts := false)
  let ctx : Core.Context := { fileName := "<mathview>", fileMap := default }
  let st : Core.State := { env }
  let (es, _) ← (MathView.entries.run' {} {}).toIO ctx st
  if args.contains "--lint" then
    let bad := es.toList.flatMap MathView.lintEntry
    for b in bad do IO.eprintln s!"mathview: {b}"
    let thms := (es.filter (·.kind == "theorem")).size
    IO.println s!"mathview lint: {es.size} entries ({thms} theorems) in {mods.size} modules, {bad.length} failing"
    return if bad.isEmpty then 0 else 1
  IO.println (toJson es).pretty
  return 0
