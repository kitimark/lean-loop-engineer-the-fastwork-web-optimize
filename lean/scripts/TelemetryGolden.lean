import Fw.Ci.Telemetry

/-- Write (or with `--check`, verify) `packages/contracts/golden/ci/telemetry.jsonl`. Run from `lean/`:
`lake env lean --run scripts/TelemetryGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  if args.contains "--check" then
    if ← Fw.Wire.Ci.Telemetry.checkGolden then
      IO.println "ci telemetry golden: up to date"; return 0
    else
      IO.eprintln "ci telemetry golden: differs from the Lean output (regenerate without --check)"; return 1
  else
    Fw.Wire.Ci.Telemetry.writeGolden
    IO.println "ci telemetry golden: written"; return 0
