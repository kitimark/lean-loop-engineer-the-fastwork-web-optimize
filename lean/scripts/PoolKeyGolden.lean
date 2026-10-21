import Fw.Ci.Pool.Key

def main (args : List String) : IO UInt32 := do
  let p : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ci" / "pool-key.jsonl"
  let text := Fw.Ci.Pool.Key.goldenText ()
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != text then
      IO.println s!"pool-key golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/PoolKeyGolden.lean)"
      return 1
    IO.println "pool-key golden: up to date"
    return 0
  IO.FS.writeFile p text
  IO.println "pool-key golden: written"
  return 0
