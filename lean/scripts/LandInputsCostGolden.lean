import Fw.Obs.LandInputsCost

def main (args : List String) : IO UInt32 := do
  if args.contains "--check" then
    if ← Fw.Obs.LandInputsCost.checkGolden then
      IO.println "land-inputs-cost golden: up to date"; return 0
    else
      IO.eprintln "land-inputs-cost golden: differs from the Lean output (regenerate without --check)"; return 1
  else
    Fw.Obs.LandInputsCost.writeGolden
    IO.println "land-inputs-cost golden: written"; return 0
