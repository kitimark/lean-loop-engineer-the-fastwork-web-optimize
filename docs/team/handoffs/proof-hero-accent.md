# proof-hero-accent (lean-prover)

**State.** `lean/Fw/Parts/HeroAccent.lean` (imported in `lean/Fw.lean`), golden rows in
`packages/contracts/golden/engine/hero-accent.jsonl` (10 rows, variant `rewrite+?fw=hero.accent:steps`, base `rewrite`,
scenario `swipe-v1`). Branch `worktree-agent-a5b9dfedcbc3df16f`; `lean/scripts/check.sh` green.

**Theorems.** Vision: `origVal_plateau`, `exact_chain_vis` (exact 199.98/399.96 ms chain = original at every instant, no
phase premise), `clean_chain_grid` (200/400 ms chain = original on every 60 Hz sample if start phase φ = 0 or
1/25 < φ < 50/3 ms, R5), `clean_chain_phase_bad` (φ = 1/50 breaks it). Grid: `sv_sample`, `crosses_bounds`,
`crosses_origPoints`, `chg_step`. Chromium: `cr_main_le`, `cr_main_quiet_lt`, `cr_main_run_dominates` (original on main
thread); `cr_comp_step_not_le`, `cr_comp_window`, `cr_comp_run_mixed`, `cr_realChrome_step_worse` (original composited).
WebKit: `wk_frame_eq`, `wk_run_equal`.

**Findings.** Chromium: an outer `<svg>` with a running opacity animation gets a paint layer and
`kActiveOpacityAnimation` (INFERRED from source @f842f52), so the original likely runs on the compositor: then the
variant is a trade (style 240 -> 20 per 4 s, commits 0 -> 20), and worse on real Chrome's main thread. Only if the
original runs on the main thread does the variant dominate. WebKit @862f17d schedules ticks at steps
(`KeyframeEffect.cpp:2670-2722`), so the original already ticks only at steps: equality. The v1 counts (240 style,
481 paints per 4 s) suggest an older WebKit; WebKit rows are `≤o` for every stage but script.

**TS variant spec.** Per frame box j: a list of zero-duration `fill: forwards` opacity animations (Web Animations or CSS),
delays `600m + b` for each `(b, v)` in `bounds j` (b in {0, 199.98, 399.96}), m < N, 600 N >= idle (N = 4 for
2200 ms); started by the same `is-idle` class change; reduced motion unchanged. Round 200/400 needs R5.

**Open premises.** Same start S in both arms; φ (R5) for the round chain; IEEE rounding; chain covers the idle window;
Chromium compositing of the original (INFERRED; CI trace decides); 40 ms pre-wake dirties no style; WebKit version and
equal-value ticks not modelled; start frame modelled as a cycle start.

**Conventions.** Rat ms, `grind` (linear Rat), `exact_mod_cast`+`omega`, `decide +kernel` (240 frames); golden
via scratch `lake env lean --run` writing `goldenJsonl`. Read first: module header, then §4.
