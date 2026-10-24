import Fw.Obs.LandInputsCost

/-- Write (or with `--check`, verify) `packages/contracts/golden/obs/land-inputs-cost.jsonl`. Run from `lean/`:
`lake env lean --run scripts/LandInputsCostGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  if args.contains "--check" then
    if ← Fw.Obs.LandInputsCost.checkGolden then
      IO.println "land-inputs-cost golden: up to date"; return 0
    else
      IO.eprintln "land-inputs-cost golden: differs from the Lean output (regenerate without --check)"; return 1
  else
    Fw.Obs.LandInputsCost.writeGolden
    IO.println "land-inputs-cost golden: written"; return 0
