import Fw.Parts.PeopleOPreview

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/parts/people-o-preview.jsonl`. -/
def main (args : List String) : IO UInt32 := Fw.Parts.PeopleOPreview.gen args
