import Fw.Wire.ShardGolden

/-- Write (or with `--check`, verify) `packages/contracts/golden/gate/shards.jsonl`. Run from `lean/`:
`lake env lean --run scripts/ShardGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  let stale ← Fw.Wire.Shard.Golden.run "." (!args.contains "--check")
  return if stale == 0 then 0 else 1
