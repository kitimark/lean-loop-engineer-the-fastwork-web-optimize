import Fw.Ci.WorkflowLint

def main (args : List String) : IO UInt32 := do
  let p : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ci" / "workflow-lint.jsonl"
  let text := Fw.Ci.WorkflowLint.goldenText
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != text then
      IO.println s!"workflow-lint golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/WorkflowLintGolden.lean)"
      return 1
    IO.println "workflow-lint golden: up to date"
    return 0
  IO.FS.writeFile p text
  IO.println "workflow-lint golden: written"
  return 0
