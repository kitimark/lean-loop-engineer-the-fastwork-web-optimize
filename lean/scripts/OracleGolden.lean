import Fw.Oracle.Golden

/-! Write (or with `--check`, verify) `packages/contracts/golden/oracle/wire.jsonl` and
`fixtures.jsonl` (`Fw.Wire.Oracle.Golden`). -/

def main (args : List String) : IO UInt32 := do
  let stale ← Fw.Wire.Oracle.Golden.run "." (!args.contains "--check")
  return if stale == 0 then 0 else 1
