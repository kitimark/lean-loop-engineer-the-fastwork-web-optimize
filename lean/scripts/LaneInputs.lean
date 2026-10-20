import Fw.Store.Layout

/-! Check that `Fw.Store.Lane.inputs` (the table `fw run` dispatches against) equals the `workflow_dispatch` inputs the
four measurement workflows declare. One canonical source: the workflow file. The parse is by indentation: under
`  workflow_dispatch:` and `    inputs:`, an input is a line `      <name>:` (6 spaces); deeper lines (descriptions, options)
and comments are skipped; the block ends at the first line indented 4 or less that is not a comment.
Run from `lean/`: `lake env lean --run scripts/LaneInputs.lean [--check]` (`--check` is the default; the flag is accepted
for symmetry with the golden checks). -/

open Fw.Store

/-- Spaces at the start of a line. -/
def indentOf (l : String) : Nat := (l.toList.takeWhile (· == ' ')).length

/-- The input names a workflow file declares under `workflow_dispatch.inputs`, in file order. -/
def dispatchInputsOf (text : String) : List String := Id.run do
  let mut st := 0            -- 0 before workflow_dispatch, 1 inside it, 2 inside its inputs, 3 done
  let mut out : List String := []
  for l in text.splitOn "\n" do
    let t := String.ofList (l.toList.dropWhile (· == ' '))
    if t.isEmpty || t.startsWith "#" then continue
    let n := indentOf l
    if st == 0 then
      if n == 2 && t == "workflow_dispatch:" then st := 1
    else if st == 1 then
      if n == 4 && t == "inputs:" then st := 2
      else if n ≤ 2 then st := 3
    else if st == 2 then
      if n ≤ 4 then st := 3
      else if n == 6 && t.endsWith ":" then out := out ++ [String.ofList t.toList.dropLast]
  return out

#guard dispatchInputsOf "on:\n  push:\n    branches: [x]\n  workflow_dispatch:\n    inputs:\n      a:\n        description: >-\n          text\n        type: string\n      # c\n      b:\n        default: 1\npermissions:\n  contents: read\n" == ["a", "b"]
#guard dispatchInputsOf "on:\n  workflow_dispatch:\npermissions:\n  x:\n" == []

def laneName : Lane → String
  | .chromiumCounts => "chromium-counts"
  | .webkitSim => "webkit-sim"
  | .breakpointGate => "breakpoint-gate"
  | .trajectory => "trajectory-probe"

def main (_args : List String) : IO UInt32 := do
  let mut bad := 0
  for l in Lane.all do
    let path : System.FilePath := ".." / ".github" / "workflows" / l.file
    let text ← try IO.FS.readFile path catch _ => do
      IO.println s!"lane inputs: cannot read {path}"
      bad := bad + 1
      continue
    let got := dispatchInputsOf text
    if got == l.inputs then
      IO.println s!"lane inputs: {laneName l}: {l.inputs.length} inputs equal Fw.Store.Lane.inputs"
    else
      IO.println s!"lane inputs: {laneName l}: the workflow declares {got} but Lane.inputs is {l.inputs}"
      bad := bad + 1
  return if bad == 0 then 0 else 1
