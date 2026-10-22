# oracle-eps handoff

- Branch `worktree-wf_dbb77429-5d3-1`, worktree `.claude/worktrees/wf_dbb77429-5d3-1`; main merged at 76f51b05
  (round 2). Last commit: see `git log -1` (round-2 commit "oracle-eps: round 2 ...").
- No CI runs. Local: check.sh green at 787d9ba9 (Lean unchanged since), ci-paths 54/54, land-inputs 56/56, dry `VERDICT dry oracle-eps`.

## State
- `lean/Fw/Oracle/Core.lean`: `sumOk` = `sumEps` (old rule) or `roundOk` at the reply's `precision` (≤ 9 decimals,
  binary-float noise 10⁻¹²). `validate` uses `sumOk`; `validateEps` keeps the old rule for the conservativity theorem.
- Theorems: `validate_conservative`, `roundTo_sumOk`, `rounded_sumOk_wf`, `roundOk_within`, `roundTo_idem`.
- Goldens: `Fw/Oracle/Golden.lean` cases `roundedSum`, `floatSum`, `tieSum`, `overSum`.
- `results/jev/rescore-eps.ts` (TS stand-in, I/O and counting): validates and scores every logged Jev reply and every
  Claude-arm answer file (first run and clean run) with an old and the new fwcore; `--write` writes
  `results/jev/eps-rescore.json` and the marked block at the end of `results/jev-arms-clean/table.md` (idempotent).
  Run from the checkout holding `.fw-console/oracle.jsonl` and `.cache/jev` (the main checkout):
  `node <worktree>/results/jev/rescore-eps.ts <fwcore built before oracle-eps> --write`.

## Verified (MEASURED, `results/jev/eps-rescore.json`)
- Valid old → new, D1: Jev 106 → 115, Haiku first 101 → 114, clean 37 → 53, Sonnet first 29 → 34, clean 87 → 95.
  D2 unchanged. No answer valid before is rejected now; right / rows and certify are unchanged.
- Old-rule counts reproduce the invalid column of the generator's table (15, 79, 87, 29 invalid).

## Open
- `scripts/jev-arms-clean.mjs table` regenerates `table.md` without the oracle-eps block; rerun rescore-eps after it.
- 62 Haiku D1 clean answers sum to 1.01 to 1.04 at three decimals: not a rounding, stay rejected.
