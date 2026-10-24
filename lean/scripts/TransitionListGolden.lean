import Fw.Gate.TransitionList

/-- Write (or with `--check`, verify) `packages/contracts/golden/gate/transition-list.jsonl`. Run from `lean/`:
`lake env lean --run scripts/TransitionListGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  let bad ← Fw.Gate.TransitionList.run "." (!args.contains "--check")
  return if bad == 0 then 0 else 1
