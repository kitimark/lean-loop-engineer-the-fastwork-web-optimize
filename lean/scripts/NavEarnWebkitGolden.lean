import Fw.Parts.NavEarnWebkit

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/parts/nav.earn.webkit.jsonl`. -/
def main (args : List String) : IO UInt32 := Fw.Parts.NavEarnWebkit.gen args
