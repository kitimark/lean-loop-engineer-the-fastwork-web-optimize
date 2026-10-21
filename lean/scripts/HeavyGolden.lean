import Fw.Sched.Heavy

/-- Write (or with `--check`, verify) `packages/contracts/golden/sched/heavy.jsonl`. Run from `lean/`:
`lake env lean --run scripts/HeavyGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  if args.contains "--check" then
    if ← Fw.Sched.Heavy.checkGolden then
      IO.println "heavy golden: up to date"; return 0
    else
      IO.eprintln "heavy golden: differs from the Lean output (regenerate without --check)"; return 1
  else
    Fw.Sched.Heavy.writeGolden
    IO.println "heavy golden: written"; return 0
