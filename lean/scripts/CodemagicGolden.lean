import Fw.Ci.Codemagic

def main (args : List String) : IO UInt32 := do
  let p : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ci" / "codemagic.jsonl"
  let text := Fw.Ci.Codemagic.goldenText
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != text then
      IO.println s!"codemagic golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/CodemagicGolden.lean)"
      return 1
    IO.println "codemagic golden: up to date"
    return 0
  IO.FS.writeFile p text
  IO.println "codemagic golden: written"
  return 0
