# Handoff: countdown-one-chain (discovery R7, hero half)

## State
- CI ref `ci/countdown-one-chain`. The code is at 75b08603; the note, results and handoff are in the next commit.
- `sh lean/scripts/check.sh` is green.

## Verified
- `lean/Fw/Parts/HeroCountdownOneChain.lean` proves:
  - `oneChain_writes_eq` and `order_perm`: the same writes and states as faithful.
  - `oneChain_rafs`, `oneChain_raf`, `page_lt_shared` and `page_eq_still`: one callback per frame.
  - `strip_schedule_still_gt`, the negative lemma for strip.
- `lean/scripts/CountdownOneChainGolden.lean --check` passes on the golden `hero.countdown.onechain.jsonl`.
  `oneChain.test.ts` replays the golden through `startFaithful`.
- Counts (MEASURED, `results/countdown-one-chain/counts.md`), FireAnimationFrame and FunctionCall:
  - swipe-v1: -243, runs 39313828270 / 39313898978.
  - swipe-touch-v1: -252, runs 39313842964 / 39313910496.
  - Style and layout are equal except swipe-touch-v1 frame 499: +1 forced recalc, 10 elements.
- Gate (`results/countdown-one-chain/gate.md`):
  - Run 39313815482: the hero.countdown row passes on both engines. 4 commission items fail; they also fail on
    ci/exit-scoped-var.
  - Scoped run 39318057726: 0 failing readings. It is "refused" only because out-of-scope cells count as not-run.

## Open
1. Footprint regeneration (morph-layers owns it). `footprint.test.ts` "is fresh" fails until then: `driver.ts` gained
   lines.
2. The morph.countdown half, after morph-layers.
3. Frame 499: find which subscriber reads layout (needs a trace with stacks); decide whether the group runs last in the
   shared frame.
4. Writes outside the graph: `lean/scripts/CountdownOneChainGolden.lean` and
   `packages/contracts/golden/preset/v2-proved.decisions.jsonl` (one no-link row).

Read first: `research/notes/2026/10-20-countdown-one-chain.md`, then the "Run" section of the Lean module.
