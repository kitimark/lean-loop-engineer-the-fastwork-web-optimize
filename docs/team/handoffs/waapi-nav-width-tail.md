# waapi-nav-width-tail handoff (round 2)

State: branch worktree-wf_b3496b15-80f-1. Decision (a): a 100 ms base window keeps the tail (driver commit c934d86b,
pushed as ci/waapi-nav-width-tail). Verified: Lean #guards, apps/site vitest and typecheck, lean check.sh.
Not delivered: the CI run of the new driver. The lead dispatches it:
`pnpm -s fw run --trajectory --engines both --fw morph.tween:waapi --widths 390,1280 --ref ci/waapi-nav-width-tail`.
After the run, check every rewrite arm's search, then apply the tail rule in the note (hit iff R-P ≤ 100 ms → cand = pred).
Read first: research/notes/2026/10-21-waapi-nav-width-tail.md (mechanism, rule, per-rep table, cost table).

Lean (`Fw.Parts.MorphTweenOpt`, WidthTail): `baseB`/`baseDelay`/`baseW`, `base_hits`, `tail_eq_of_base`,
`tail_miss_le`, `tail_zero_of_base_still`, `dlTs_sound`, `cost`, `tailArm_model`/`tailArm_look`, `tailDecision`.
Golden: packages/contracts/golden/parts/morph-tween-waapi.tail.jsonl (new); the attr golden gained the `close` case.
TS: waapi.logic.ts `TAIL_WINDOW_MS`/`baseWindow`/`baseDelay`; waapi.driver.ts window; index.tsx `env.base`.

Findings-ledger row (the lead applies it; no edit to ledger.json or part.json here):
- n 9; id `morph.tween.waapi.navWidthTail`; part `morph.tween`; flag `morph.tween:waapi`; status `partly-proved`
- candidate: the waapi driver writes the base `--morph` from 100 ms before the 0.001 marker to the end of a close, so
  the width transition at the `is-morphing` flip starts where the original's starts
- chromium `trade`; webkit `trade` (9 extra script frames per close at 60 Hz; 24 of 41 still saved; Lean `cost`)
- mechanism: CSS 2.gBuqKVzi.css:11355-11361; JS 2.DyWL8TcE.js:12947, 13221-13243; Chromium css_animations.cc:3214-3293
  @f842f52; WebKit Styleable.cpp:604-632, StyleTreeResolver.cpp:894-898 @862f17d
- leanFor: base_hits, tail_eq_of_base, tail_miss_le, tail_zero_of_base_still, tailDecision, tail_orig_pos; leanAgainst: []
- visual: equal on a hit (R-P ≤ 100 ms); on a miss, ≤ (panelW-pillW)/1000 px (0.256 px at 1280 px), reversed
- evidence: run 39471466367 (landed driver, pre-fix: orig and base = pred within 0.02 px; cand ≠ pred), the new run pending
- premises: before-change = the previous base style without script animations (both engines, cited above)
- lesson: a CSS transition keyed on a class flip reads the previous frame's base style. Write the base only near the flip.
- next: the dispatch above; per-engine 1280/390 cand vs orig per rep
- missingWhy: the new-driver run is not dispatched; Linux WebKit probe walks no morph (walks_linux_webkit)
- userDecision: pending
Open: the 300 ms gap row is `lookChange` (no saving left; Linux WebKit only). Background transition: trajectory-close-start.
