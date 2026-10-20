import Fw.Console.LandLegs

/-- Write (or with `--check`, verify) `land-legs.jsonl`. -/
def main (args : List String) : IO UInt32 := do
  if args.contains "--check" then
    if ← Fw.Console.LandLegs.checkGolden then
      IO.println "land-legs golden: up to date"; return 0
    else
      IO.eprintln "land-legs golden: differs from the Lean output (regenerate without --check)"; return 1
  else
    Fw.Console.LandLegs.writeGolden
    IO.println "land-legs golden: written"; return 0
