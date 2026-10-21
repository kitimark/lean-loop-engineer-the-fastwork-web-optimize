import Fw.Sched.NodeBudget

open Fw.Sched.NodeBudget

/-- Files this script writes, relative to `lean/`, with their Lean text. -/
def files : List (System.FilePath × String) :=
  [("../packages/contracts/golden/sched/node-budget.gen.json", genText),
   ("../packages/contracts/golden/sched/node-budget.jsonl", goldenText)]

/-- Write (or with `--check`, verify) the node-budget files. Run from `lean/`:
`lake env lean --run scripts/NodeBudgetGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  if args.contains "--check" then
    let mut bad := 0
    for (p, t) in files do
      let cur ← try IO.FS.readFile p catch _ => pure ""
      if cur != t then
        IO.eprintln s!"node-budget: {p} differs from the Lean output (regenerate without --check)"; bad := 1
    if bad == 0 then IO.println "node-budget: generated files equal the Lean output"
    return bad
  else
    for (p, t) in files do IO.FS.writeFile p t
    IO.println "node-budget: written"; return 0
