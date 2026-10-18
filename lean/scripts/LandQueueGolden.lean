import Fw.Console.LandQueue

/-- Write (or with `--check`, verify) `packages/contracts/golden/console/land-queue.jsonl`. Run from `lean/`:
`lake env lean --run scripts/LandQueueGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  if args.contains "--check" then
    if ← Fw.Console.LandQueue.checkGolden then
      IO.println "land-queue golden: up to date"; return 0
    else
      IO.eprintln "land-queue golden: differs from the Lean output (regenerate without --check)"; return 1
  else
    Fw.Console.LandQueue.writeGolden
    IO.println "land-queue golden: written"; return 0
