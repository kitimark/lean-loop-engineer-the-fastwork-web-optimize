# oracle-eps handoff

- Branch `worktree-wf_dbb77429-5d3-1`, worktree `.claude/worktrees/wf_dbb77429-5d3-1`; main merged at 393f8223
  (round 3). Last code commit 0a23ac7a; this handoff is the commit after it.
- No CI runs. Local at 0a23ac7a: check.sh green (axioms included), contracts 11/11, ci-paths + jev-expand 79/79,
  land-inputs 56/56; dry land: see the report's `dry`.

## State
- `lean/Fw/Oracle/Core.lean`: `sumOk` = `sumEps` (old rule) or `roundOk (max d 1)` at the reply's `precision` d
  (≤ 9 decimals, binary-float noise 10⁻¹²): whole-number replies are judged at one decimal, so `[1,1,0,0]` and
  `[0,0,0,0]` fail. `validateEps` keeps the old rule for `validate_conservative`.
- Theorems: `validate_conservative`, `rounded_sumOk`, `rounded_sumOk_wf`, `roundTo_sumOk` (all three take
  `1 ≤ d`), `roundOk_within`, `roundTo_idem`, `sumOk_cases`.
- Goldens: `Fw/Oracle/Golden.lean` cases `roundedSum`, `floatSum`, `tieSum`, `overSum`, `wholeSum`, `zeroSum`.
- `lean/scripts/ExpandGolden.lean` (jev-file-context-ablation's): the paired strict over-sum is 0.65 + 0.45, since
  0.6 + 0.5 over 14 options is a one-decimal rounding under `sumOk`; responses unchanged.
- `results/jev/rescore-eps.ts` (TS stand-in): run from the main checkout,
  `node <worktree>/results/jev/rescore-eps.ts <main fwcore> --write`; round 3 rerun left
  `eps-rescore.json` and `table.md` byte-identical (no logged whole-number off-sum reply).

## Verified (MEASURED, `results/jev/eps-rescore.json`)
- Valid old → new, D1: Jev 106 → 115, Haiku first 101 → 114, clean 37 → 53, Sonnet first 29 → 34, clean 87 → 95.
  D2 unchanged; rejectedNow 0 everywhere; right / rows and certify unchanged.

## Open
- `scripts/jev-arms-clean.mjs table` drops the oracle-eps block of `table.md` (finding 5).
- `results/jev-file-context-ablation/d1x.json` was scored in strict mode under the old rule; re-score after land.
