import Fw.Parts.HeroCountdownOneChain

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/parts/hero.countdown.onechain.jsonl`. Run from
`lean/`: `lake env lean --run scripts/CountdownOneChainGolden.lean [--check <file>]`. -/
def main (args : List String) : IO UInt32 := Fw.Parts.HeroCountdownOneChain.goldenMain args
