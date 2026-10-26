# hero-relayout-boundary handoff

## State
- Branch `worktree-wf_6bf5744f-815-1`, worktree `.claude/worktrees/wf_6bf5744f-815-1`, CI `ci/hero-relayout-boundary`.
- Last measured commit 0537be1 (Lean model, golden, flag `hero.exit:contain`).
- CI runs: lean 40268851175 (push, running); chromium-counts base and flag, gate both engines dispatched by `fw run`.
- WebKit: macOS queue full at dispatch time (2 webkit-sim runs in progress), so source-only so far.

## Verified
- `lean/Fw/Parts/HeroContainOpt.lean`: `hero_cr_flag`, `hero_wk_flag` (base false in both engines),
  `drawIn_flag_hero`, `drawIn_outside_full`, `cr_outside_full`, `wk_outside_full`, `hero_same_box`,
  `hero_height_stage`, `excess_lt_vh`, `excess_lt_454`, `extent_same`. Standard axioms only.
- Golden `packages/contracts/golden/parts/hero-contain.jsonl` (176 lines), check.sh job, trigger row.

## Open
- Gate verdict, Chromium counts per hero-exit window, note, ledger row.

## Conventions
- Flag CSS: `[data-fw-variant='contain'] > .hero { contain: size layout; }` at the end of hero.module.css.
- Node ids in the model: 8 hero, 12 accent, 15 svg, 16 path, 17 digit, 4 nav, 19 people card.

## Read first
- `research/notes/2026/10-20-hero-relayout-boundary.md`, `lean/Fw/Parts/HeroContainOpt.lean` §3-5.
