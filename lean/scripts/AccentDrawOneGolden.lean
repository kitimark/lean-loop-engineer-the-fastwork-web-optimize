import Fw.Parts.HeroAccentOpt

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/parts/hero.accent.drawone.jsonl`. Run from
`lean/`: `lake env lean --run scripts/AccentDrawOneGolden.lean [--check <file>]`. -/
def main (args : List String) : IO UInt32 := Fw.Parts.HeroAccentOpt.drawRun args
