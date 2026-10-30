import Fw.Plan.Claims

/-! Print (`--check <file>` to verify) `packages/contracts/golden/plan/claims.jsonl` (Fw.Plan.Claims), or `--serve` the claim lint
to `packages/plan-lint/src/claims-lint.ts`. Run from `lean/`: `lake env lean --run scripts/ClaimsGolden.lean [--check <file> | --serve]`. -/

def main (args : List String) : IO UInt32 := Fw.Plan.Claims.run args
