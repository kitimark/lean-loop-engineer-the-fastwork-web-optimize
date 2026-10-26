# hero-relayout-boundary handoff

## State
- Branch `worktree-wf_6bf5744f-815-1`, worktree `.claude/worktrees/wf_6bf5744f-815-1`, CI `ci/hero-relayout-boundary`.
- Last pushed sha 26bd7b1 (FlagDelta allowlist for the declared `contain`); measured CSS unchanged since 0537be1.
- CI runs: lean 40268851175 failed (stale goldens, fixed later); chromium-counts base 40268899311 and flag
  40268902395 succeeded; gate 40268905824 failed only on the declared `contain` item; gate 2 at 26bd7b1 (dispatched,
  `fw run --gate --engines both --fw hero.exit:contain`); webkit-sim base and flag at 26bd7b1 dispatched (3 VMs each).

## Verified
- `lean/Fw/Parts/HeroContainOpt.lean`: `hero_cr_flag`, `hero_wk_flag` (base false in both engines),
  `drawIn_flag_hero`, `drawIn_outside_full`, `cr_outside_full`, `wk_outside_full`, `hero_same_box`,
  `hero_height_stage`, `excess_lt_vh`, `excess_lt_454`, `extent_same`. Standard axioms only.
- Golden `packages/contracts/golden/parts/hero-contain.jsonl` (176 lines), check.sh job, trigger row.
- Chromium hero-exit window totalObjects -35.3% (`results/hero-relayout-boundary/chromium.json`).
- Gate 1: geometry equal at every probe on both engines; the only failing item was the declared style.

## Open
- Gate 2 verdict, WebKit counts, ledger row `hero.exit.contain` (n allocated at land), note status.

## Conventions
- Flag CSS: `[data-fw-variant='contain'] > .hero { contain: size layout; }` at the end of hero.module.css.
- Node ids in the model: 8 hero, 12 accent, 15 svg, 16 path, 17 digit, 4 nav, 19 people card.
- Chromium window = zones y00000 and y00500; extractor `results/hero-relayout-boundary/extract-chromium.mjs`.

## Read first
- `research/notes/2026/10-20-hero-relayout-boundary.md`, `lean/Fw/Parts/HeroContainOpt.lean` §3-5.
