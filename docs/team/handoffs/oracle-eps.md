# oracle-eps handoff

- Branch `worktree-wf_dbb77429-5d3-1`, worktree `.claude/worktrees/wf_dbb77429-5d3-1`; main merged at aad99bc8.
- No CI runs (Lean check, package tests and the dry land ran locally through `fw slot`).

## State
- `lean/Fw/Oracle/Core.lean`: `sumOk` = `sumEps` (old rule, sum within `eps`) or `roundOk` at the reply's
  `precision` (fewest decimals ≤ `maxDec` = 9, up to `noise` = 10⁻¹² of binary-float error). `validate` uses
  `sumOk`, `validateEps` keeps the old rule for the conservativity theorem.
- Theorems: `validate_conservative` (old ok ⇒ new ok, same answer), `roundTo_sumOk` (≤ 255 options rounded half
  up to any d decimals pass), `rounded_sumOk_wf`, `roundOk_within` (accepted sum within n·half d of 1),
  `roundTo_idem`. Axioms: standard only.
- Goldens: `Fw/Oracle/Golden.lean` cases `roundedSum`, `floatSum` (accepted), `tieSum` (accepted), `overSum`
  (schema failure); regenerate with `lake build Fw.Oracle.Golden` then `lake env lean --run scripts/OracleGolden.lean`.
- `lean/Fw/Oracle/ReplayWire.lean`: a `#guard` reply summing 0.99 now passes; its "unclear" case uses 0.03.

## Verified (MEASURED, `results/jev/eps-rescore.json`)
- Jev D1 valid 106 → 115 of 116 (holdout 31 → 33), D2 83 → 83; no reply valid before is rejected now.
- Claude arms re-validated, not re-run: Haiku D1 37 → 53, Sonnet D1 87 → 95, D2 unchanged.
- Re-run: `node results/jev/rescore-eps.ts <fwcore built before oracle-eps>` from the repo root (reads
  `.fw-console/oracle.jsonl` and `.cache/jev` of the checkout).

## Open
- `results/jev-arms-clean/table.md` still lists the old Claude-arm validity (outside this task's writes).
- 62 Haiku D1 answers sum to 1.01 to 1.04 at three decimals: not a rounding, stay rejected.
