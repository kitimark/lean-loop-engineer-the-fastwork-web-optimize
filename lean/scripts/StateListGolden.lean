import Fw.Ci.StateList


def main (args : List String) : IO UInt32 := do
  let p : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ci" / "state-list.jsonl"
  let text := Fw.Ci.StateList.goldenText ()
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != text then
      IO.println s!"state-list golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/StateListGolden.lean)"
      return 1
    IO.println "state-list golden: up to date"
    return 0
  IO.FS.writeFile p text
  IO.println "state-list golden: written"
  return 0
