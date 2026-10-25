import Fw.Parts.MorphPanelRest

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/parts/morph.panel.rest.jsonl`. -/
def main (args : List String) : IO UInt32 := Fw.Parts.MorphPanelRest.gen args
