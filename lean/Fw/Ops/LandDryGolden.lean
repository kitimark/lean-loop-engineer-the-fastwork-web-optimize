import Fw.Ops.LandDry
namespace Fw.Ops.LandDryGolden

#guard Fw.Ops.LandDry.jsonl () == include_str "../../../packages/contracts/golden/ops/land-dry.jsonl"

#guard Fw.Ops.LandDry.depsJsonl () == include_str "../../../packages/contracts/golden/ops/land-dry-deps.jsonl"

def gen (args : List String) : IO Unit := do
  let path : System.FilePath := "../packages/contracts/golden/ops/land-dry.jsonl"
  let depsPath : System.FilePath := "../packages/contracts/golden/ops/land-dry-deps.jsonl"
  let want := Fw.Ops.LandDry.jsonl ()
  if args.contains "--check" then
    unless (← IO.FS.readFile path) == want do
      throw (IO.userError s!"land-dry: {path} is stale; regenerate with Fw.Ops.LandDryGolden.gen []")
    unless (← IO.FS.readFile depsPath) == Fw.Ops.LandDry.depsJsonl () do
      throw (IO.userError s!"land-dry: {depsPath} is stale; regenerate with Fw.Ops.LandDryGolden.gen []")
  else
    IO.FS.writeFile path want
    IO.FS.writeFile depsPath (Fw.Ops.LandDry.depsJsonl ())

end Fw.Ops.LandDryGolden
