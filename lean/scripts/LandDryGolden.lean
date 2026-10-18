import Fw.Console.LandDry

/-- Write (or with `--check`, verify) `packages/contracts/golden/console/land-dry.jsonl`. Run from `lean/`:
`lake env lean --run scripts/LandDryGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  if args.contains "--check" then
    if ← Fw.Console.LandDry.checkGolden then
      IO.println "land-dry golden: up to date"; return 0
    else
      IO.eprintln "land-dry golden: differs from the Lean output (regenerate without --check)"; return 1
  else
    Fw.Console.LandDry.writeGolden
    IO.println "land-dry golden: written"; return 0
