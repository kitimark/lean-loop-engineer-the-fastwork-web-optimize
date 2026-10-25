import Fw.Parts.ConstBoundsCounts

/-- Print the golden, the table with `--table`, or with `--check <golden> <table>` verify `packages/contracts/golden/parts/const-bounds-counts.jsonl` and `results/const-bounds-counts/tables.md`. -/
def main (args : List String) : IO UInt32 := Fw.Parts.ConstBoundsCounts.run args
