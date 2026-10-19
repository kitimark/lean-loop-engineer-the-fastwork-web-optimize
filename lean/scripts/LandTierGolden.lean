import Fw.Console.LandTier

/-- Write (or with `--check`, verify) `land-tier.jsonl`. -/
def main (args : List String) : IO UInt32 := do
  if args.contains "--check" then
    if ← Fw.Console.LandTier.checkGolden then
      IO.println "land-tier golden: up to date"; return 0
    else
      IO.eprintln "land-tier golden: differs from the Lean output (regenerate without --check)"; return 1
  else
    Fw.Console.LandTier.writeGolden
    IO.println "land-tier golden: written"; return 0
