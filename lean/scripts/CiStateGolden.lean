import Fw.Ci.State


def main (args : List String) : IO UInt32 := do
  let p : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ci" / "ci-state.jsonl"
  let text := Fw.Ci.State.goldenText ()
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != text then
      IO.println s!"ci-state golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/CiStateGolden.lean)"
      return 1
    IO.println "ci-state golden: up to date"
    return 0
  IO.FS.writeFile p text
  IO.println "ci-state golden: written"
  return 0
