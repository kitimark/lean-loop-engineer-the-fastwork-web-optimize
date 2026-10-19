import Fw.Console.LandRemote

/-- Write (or with `--check`, verify) `land-remote.jsonl`. -/
def main (args : List String) : IO UInt32 := do
  if args.contains "--check" then
    if ← Fw.Console.LandRemote.checkGolden then
      IO.println "land-remote golden: up to date"; return 0
    else
      IO.eprintln "land-remote golden: differs from the Lean output (regenerate without --check)"; return 1
  else
    Fw.Console.LandRemote.writeGolden
    IO.println "land-remote golden: written"; return 0
