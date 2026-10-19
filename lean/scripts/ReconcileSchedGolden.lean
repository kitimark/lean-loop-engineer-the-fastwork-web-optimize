import Fw.Console.ReconcileSched

/-- Write (or with `--check`, verify) `packages/contracts/golden/console/reconcile-sched.jsonl`. Run from `lean/`:
`lake env lean --run scripts/ReconcileSchedGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  if args.contains "--check" then
    if ← Fw.Console.ReconcileSched.checkGolden then
      IO.println "reconcile-sched golden: up to date"; return 0
    else
      IO.eprintln "reconcile-sched golden: differs from the Lean output (regenerate without --check)"; return 1
  else
    Fw.Console.ReconcileSched.writeGolden
    IO.println "reconcile-sched golden: written"; return 0
