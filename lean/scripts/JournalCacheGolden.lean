import Fw.Console.JournalFold

/-- Write (or with `--check`, verify) `packages/contracts/golden/console/journal-cache.jsonl`. Run from `lean/`:
`lake env lean --run scripts/JournalCacheGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  if args.contains "--check" then
    if ← Fw.Console.JournalFold.checkGolden then
      IO.println "journal-cache golden: up to date"; return 0
    else
      IO.eprintln "journal-cache golden: differs from the Lean output (regenerate without --check)"; return 1
  else
    Fw.Console.JournalFold.writeGolden
    IO.println "journal-cache golden: written"; return 0
