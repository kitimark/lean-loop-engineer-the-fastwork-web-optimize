import Fw.Obs.Timing

/-- Write (or with `--check`, verify) `packages/contracts/golden/obs/timing.jsonl`. Run from `lean/`:
`lake env lean --run scripts/TimingGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  if args.contains "--check" then
    if ← Fw.Wire.Obs.Timing.checkGolden then
      IO.println "timing golden: up to date"; return 0
    else
      IO.eprintln "timing golden: differs from the Lean output (regenerate without --check)"; return 1
  else
    Fw.Wire.Obs.Timing.writeGolden
    IO.println "timing golden: written"; return 0
