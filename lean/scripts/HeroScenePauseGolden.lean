import Fw.Parts.HeroScenePause

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/parts/hero-scene-pause.jsonl`. -/
def main (args : List String) : IO UInt32 := Fw.Parts.HeroScenePause.run args
