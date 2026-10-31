import Fw.Ops.LandDry
namespace Fw.Ops.LandDryGolden

#guard Fw.Ops.LandDry.jsonl () == include_str "../../../packages/contracts/golden/ops/land-dry.jsonl"

def gen (args : List String) : IO Unit := do
  let path : System.FilePath := "../packages/contracts/golden/ops/land-dry.jsonl"
  let want := Fw.Ops.LandDry.jsonl ()
  if args.contains "--check" then
    unless (← IO.FS.readFile path) == want do
      throw (IO.userError s!"land-dry: {path} is stale; regenerate with Fw.Ops.LandDryGolden.gen []")
  else
    IO.FS.writeFile path want

end Fw.Ops.LandDryGolden
