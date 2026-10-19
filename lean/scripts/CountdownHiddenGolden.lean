import Fw.Parts.HeroCountdownHidden

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/parts/hero.countdown.hidden.jsonl`. Run from
`lean/`: `lake env lean --run scripts/CountdownHiddenGolden.lean [--check <file>]`. -/
def main (args : List String) : IO UInt32 := Fw.Parts.HeroCountdownHidden.run args
