import Fw.Gate.RunPerm

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/gate/run-perm.jsonl`. Run from `lean/`:
`lake env lean --run scripts/RunPermGolden.lean [--cells <cells file>] [--check ../packages/contracts/golden/gate/run-perm.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Gate.RunPerm.run args
