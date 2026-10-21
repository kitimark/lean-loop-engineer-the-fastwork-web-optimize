import Fw.Obs.MacTelemetryWire

/-- Write (or with `--check`, verify) `packages/contracts/golden/obs/mactelemetry.jsonl`. Run from `lean/`:
`lake env lean --run scripts/MacTelemetryGolden.lean [--check | --report | --show <case index>]`; `--report` writes
`mactelemetry-window-report.json` from the committed `mactelemetry-window-input.jsonl`. -/
def main (args : List String) : IO UInt32 := do
  match args with
  | ["--show", n] =>
    let cs := Fw.Wire.Obs.MacTelemetry.cases
    match cs[n.toNat!]? with
    | some (name, rq) =>
      IO.println name
      let r := Fw.Wire.Obs.MacTelemetry.replyJson rq
      match r.getObjValAs? String "md" with
      | .ok md => IO.println md
      | .error _ => IO.println r.compress
      return 0
    | none => IO.eprintln "no such case"; return 1
  | ["--report"] =>
    Fw.Wire.Obs.MacTelemetry.writeReport
    IO.println "mac telemetry report: written"; return 0
  | _ =>
  if args.contains "--check" then
    if ← Fw.Wire.Obs.MacTelemetry.checkGolden then
      IO.println "mac telemetry golden: up to date"; return 0
    else
      IO.eprintln "mac telemetry golden: differs from the Lean output (regenerate without --check)"; return 1
  else
    Fw.Wire.Obs.MacTelemetry.writeGolden
    IO.println "mac telemetry golden: written"; return 0
