import Fw.Serve
/-! Writes the console-board golden file from Lean (`Fw.Wire.Serve.boardGolden`) to
`golden/console-board.jsonl` and `../packages/contracts/golden/console-board.jsonl`.
Run from `lean/`: `lake env lean --run scripts/BoardGolden.lean`. `lake test` checks both files. -/
def main : IO Unit := do
  let body := String.join (Fw.Wire.Serve.boardGolden.map (· ++ "\n"))
  for p in ["golden/console-board.jsonl", "../packages/contracts/golden/console-board.jsonl"] do
    IO.FS.writeFile p body
    IO.println s!"wrote {p} ({Fw.Wire.Serve.boardGolden.length} cases)"
