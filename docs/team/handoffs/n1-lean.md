# Handoff: n1-lean

State: done on branch `worktree-agent-ad5ce5748c9cdeff3` (commit with trailer `Task: n1-lean`, on top of e781f27).
Gates: `sh lean/scripts/check.sh` green (mathview 0 failing), `cd packages/measure-chromium && pnpm test` 21/21.
`#print axioms`: only propext, Classical.choice, Quot.sound.

## What moved to Lean
- `lean/Fw/Measure/Splits.lean`: split table (HitTest in the overlay-ad detector, updateActiveStyleSheets in an
  SVG-image host), containment test, `splitCounts_sum` (nothing lost), N1 net rule (`n1Gated`, `n1_net`).
- `lean/Fw/Measure/Neutral.lean`: N0 windows of n0.mjs (`winOf`, `n0_conservation`: each event in exactly one window),
  SPK-q verdict pass/fail/missing (`verdict_pass_iff`, `verdict_load`: load not gated, `verdict_svg`: SVG type not gated).
- `lean/Fw/Measure/Arms.lean`: roles gate/finding/byDesign (`overlay_not_gate`), cross-arm level with an absent arm as
  det (`classifyU_absent`, `crossLevel_classify`). Within one arm, freeze keeps "missing from a run = quar".
- Wire ops (`lean/Fw/Measure/Wire.lean`): `measure.splits`, `measure.n0Windows`, `measure.spkq`, `measure.arms`;
  `measure.freeze` rows gain `role` (+ `reason`) and the reply a `roles` tally. `measure.classify` unchanged.
- Goldens: `packages/contracts/golden/measure/measure.{splits,n0Windows,spkq,arms,freeze}.jsonl` (regenerate:
  `cd lean && lake env lean --run scripts/MeasureGolden.lean`).

## TS stand-ins left (container has no Lean)
- `trace.mjs` SPLITS / N1_KEYS / `inside` and `n0.mjs` n0Windows are copies, checked against the goldens in
  `test/fwcore.test.mjs` (SPLITS and MAIN are now exported for that).

## Open items
- No TS caller yet for `measure.spkq` (run.mjs / host side) or `measure.arms` (CI classify step's A-vs-R table).
- `src/freeze.mjs` drops `role`/`reason`/`roles`; the refreeze task should forward them. classes.frozen.json untouched.
- mathview warns "binder ty not quantified" for Arms theorems (renamed to τ in math; warning only).

Read first: Arms.lean header, Neutral.lean header, research note 2026-10-17 hittest-and-spk-q.
