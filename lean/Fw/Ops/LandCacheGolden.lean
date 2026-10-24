import Fw.Ops.LandCache

#guard Fw.Ops.LandCache.jsonl () == include_str "../../../packages/contracts/golden/ops/land-cache.jsonl"

/-- Write (or with `--check`, verify) `packages/contracts/golden/ops/land-cache.jsonl`. Run from `lean/`: `lake env lean --run Fw/Ops/LandCacheGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  let path : System.FilePath := "../packages/contracts/golden/ops/land-cache.jsonl"
  let want := Fw.Ops.LandCache.jsonl ()
  if args.contains "--check" then
    return if (← IO.FS.readFile path) == want then 0 else 1
  IO.FS.writeFile path want
  return 0
