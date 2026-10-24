import Fw.Ops.LandCache
namespace Fw.Ops.LandCacheGolden

#guard Fw.Ops.LandCache.jsonl () == include_str "../../../packages/contracts/golden/ops/land-cache.jsonl"

/-- Write (or with `--check`, verify) `packages/contracts/golden/ops/land-cache.jsonl`. Run from `lean/`: `#eval Fw.Ops.LandCacheGolden.gen []` on stdin. -/
def gen (args : List String) : IO Unit := do
  let path : System.FilePath := "../packages/contracts/golden/ops/land-cache.jsonl"
  let want := Fw.Ops.LandCache.jsonl ()
  if args.contains "--check" then
    unless (← IO.FS.readFile path) == want do
      throw (IO.userError s!"land-cache: {path} is stale; regenerate with Fw.Ops.LandCacheGolden.gen []")
  else
    IO.FS.writeFile path want

end Fw.Ops.LandCacheGolden
