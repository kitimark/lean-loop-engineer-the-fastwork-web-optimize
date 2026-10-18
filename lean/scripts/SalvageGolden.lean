import Fw.Ops.Salvage

/-! Write (or with `--check`, verify) `packages/contracts/golden/ops/salvage.jsonl` from `Fw.Ops.Salvage.goldenText`.
Consumer: `apps/runner/test/workflow-salvage.test.ts`. Run from `lean/`: `lake env lean --run scripts/SalvageGolden.lean [--check]`. -/

/-- Write the golden file, or with `--check` exit 1 when it differs from the Lean output. -/
def main (args : List String) : IO UInt32 := do
  let p : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ops" / "salvage.jsonl"
  let text := Fw.Ops.Salvage.goldenText
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != text then
      IO.println s!"salvage golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/SalvageGolden.lean)"
      return 1
    IO.println "salvage golden: up to date"
    return 0
  IO.FS.writeFile p text
  IO.println "salvage golden: written"
  return 0
