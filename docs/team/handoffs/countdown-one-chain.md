# Handoff: countdown-one-chain (discovery R7, hero half)

## State
Main b269d2c8 is merged in. The gate was measured at 777c0c5d (`ci/countdown-one-chain`); later commits change docs
only. `lean/scripts/check.sh` is green, and the site, contracts and runner tests and `ci-paths` pass.

## Verified
- Lean `lean/Fw/Parts/HeroCountdownOneChain.lean`: `oneChain_writes_eq`, `order_perm`, `oneChain_rafs`, `oneChain_raf`,
  `page_lt_shared`, `page_eq_still`, `strip_schedule_still_gt`. The golden `hero.countdown.onechain.jsonl` passes
  `--check`, and `oneChain.test.ts` replays it.
- Counts (`results/countdown-one-chain/counts.md`): FireAnimationFrame -243 on swipe-v1 and -252 on swipe-touch-v1.
- Gate (`results/countdown-one-chain/gate.md`): flag run 39367028590 and no-flag base 39367037943 at the merge-base
  have equal not-ok sets, only WebKit `matchMedia =Lean|sweep:phone-rotation`. Chromium passes on both.
- Footprint regenerated (`part-footprint.mjs --write`), and `footprint.test.ts` "is fresh" passes. The preset decisions
  were regenerated with `Fw.Preset.Gen.run` after the merge conflict.

## Open
1. Frame 499 (swipe-touch-v1): the existing counts show ScheduleStyleRecalculation +1, a style-only update. The
   subscriber that reads is not identified, because the counts lane uploads no trace with stacks. The note lists the
   candidates.
2. The morph.countdown half (follow-up).
3. Preset inclusion is the lead's decision.
4. Writes outside the graph: `lean/scripts/CountdownOneChainGolden.lean` and
   `packages/contracts/golden/preset/v2-proved.decisions.jsonl` (one no-link row, generated).

## Conventions
The CI base branch `ci/countdown-one-chain-base` sits at b269d2c8.

Read first: `research/notes/2026/10-20-countdown-one-chain.md`, then the "Run" section of the Lean module.
