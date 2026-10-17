import MathView
open Lean Meta

/-- `lake exe mathview [--lint]`: print the entries as JSON; with `--lint`, exit 1 when a
theorem has no `$$…$$` math in its docstring or depends on `sorryAx`. -/
unsafe def main (args : List String) : IO UInt32 := do
  initSearchPath (← findSysroot)
  enableInitializersExecution
  let env ← importModules #[{ module := `Fw }] {} (loadExts := true)
  let ctx : Core.Context := { fileName := "<mathview>", fileMap := default }
  let st : Core.State := { env }
  let (es, _) ← (MathView.entries.run' {} {}).toIO ctx st
  if args.contains "--lint" then
    let bad := es.filter fun e => e.kind == "theorem" && (e.math.isEmpty || !e.sorryFree)
    for e in bad do
      IO.eprintln s!"mathview: {e.name} ({e.module}:{e.line}) lacks $$ math or uses sorry"
    IO.println s!"mathview lint: {es.size} entries, {bad.size} failing"
    return if bad.isEmpty then 0 else 1
  IO.println (toJson es).pretty
  return 0
