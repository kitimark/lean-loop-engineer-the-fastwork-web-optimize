import Fw.Gate.AlignEquiv

/-- Write (or with `--check`, verify) `packages/contracts/golden/gate/align-equiv.jsonl`. Run from `lean/`:
`lake env lean --run scripts/AlignEquivGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  let bad ← Fw.Gate.AlignEquiv.run "." (!args.contains "--check")
  return if bad == 0 then 0 else 1
