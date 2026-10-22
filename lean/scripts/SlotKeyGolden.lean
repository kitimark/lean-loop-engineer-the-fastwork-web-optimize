import Fw.Obs.Timing

/-- Write (or with `--check`, verify) `packages/contracts/golden/obs/slot-key.jsonl`. Run from `lean/`:
`lake env lean --run scripts/SlotKeyGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  if args.contains "--check" then
    if ← Fw.Wire.Obs.SlotKey.checkGolden then
      IO.println "slot-key golden: up to date"; return 0
    else
      IO.eprintln "slot-key golden: differs from the Lean output (regenerate without --check)"; return 1
  else
    Fw.Wire.Obs.SlotKey.writeGolden
    IO.println "slot-key golden: written"; return 0
