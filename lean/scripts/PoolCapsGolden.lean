import Fw.Ci.Pool.Caps

def main (args : List String) : IO UInt32 := do
  let p : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ci" / "pool-caps.jsonl"
  let text := Fw.Ci.Pool.Caps.goldenText
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != text then
      IO.println s!"pool-caps golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/PoolCapsGolden.lean)"
      return 1
    IO.println "pool-caps golden: up to date"
    return 0
  IO.FS.writeFile p text
  IO.println "pool-caps golden: written"
  return 0
