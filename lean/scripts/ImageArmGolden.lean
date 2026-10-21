import Fw.Measure.ImageArm

/-! Print (or with `--check <file>`, verify) the golden vectors of the drawn-size image arm,
`packages/contracts/golden/gate/image-arm.jsonl` (Fw.Measure.ImageArm). Consumer: `packages/gate-breakpoints/src/images/armplan.mjs`,
checked by `packages/gate-breakpoints/test/images-armplan.test.mjs`. Run from `lean/`:
`lake env lean --run scripts/ImageArmGolden.lean [--check ../packages/contracts/golden/gate/image-arm.jsonl]`. -/

def main (args : List String) : IO UInt32 := Fw.Measure.ImageArm.run args
