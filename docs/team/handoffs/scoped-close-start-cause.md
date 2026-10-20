# Handoff: scoped-close-start-cause (round 2)
State: branch `worktree-wf_da1a1d10-06c-1`; the commit is the one `git log -1` shows on `ci/scoped-close-start-cause`.
Decision: (a) with a perf finding. Not (b), not (c). Judge (`Trajectory.lean`) unchanged.
- Fresh runs (ids collide, `fw-run-dispatch-pick`; named by arms): 39508414669 flag-alone `?fw=hero.exit:scoped` hash
  8d213de6fbdd52fd, base ede2c7641aacf2d2; 39508421419 A/A `?fw=hero.exit:faithful` hash ede2c7641aacf2d2. Original arm: no config.
- Lean outcomes mac-webkit: 39508414669 hero pass, morph FAIL; 39508421419 hero pass, morph PASS; Linux hero pass in both.
- Gap g (last is-morphing sample to first without): scoped mean 78.5 / 70.6 ms (fresh / stored) against arm means 41.2 to
  66.0 for the ten non-scoped arms. Pooled permutation p 0.011 (mean log g), 0.019 (mean g); A/A pooled 0.90 / 0.74.
  The fresh run alone is p 0.12.
- Cause: start red = `bgRed(m_prev) >= redFloor g`; g is frame time; frame-time cost of scoped's per-scroll-frame inline
  writes is INFERRED, not profiled. No `StyleTreeResolver` ordering claim.
Verified:
- `lean/Fw/Parts/HeroExitCloseStart.lean`: `bgRed_lt`, `bgRed_le_iff`, `prevBound_mono`, `redFloor_anti`, `floorOk_tween`,
  `floorOk_below`, `floorOk_reject_gap`, `floorOk_mono`, `capOf_ge`, `floorOk_orig`, `scoped_writes_miss_nav_*` (about
  `frameWrites`; `driver.ts:37` also writes `pointerEvents` on the hero). `startAccepts` (alpha) removed.
- `packages/gate-breakpoints/src/trajectory/closegap.mjs` (TS stand-in, pinned to Lean literals in `test/closegap.test.mjs`).
- Check 1 (own gap): 3, 3, 5, 7 cells below the floor, all within LAG 17 ms (max slack 13 ms). Check 2 (original-gap cap)
  also rejects A/A cells at 5 original reps, so no closed per-cell colour rule at 5 reps.
- Tests: gate-breakpoints 432/432; ci-paths; land-inputs; `sh lean/scripts/check.sh` green (see final commit).
Open:
- 4 more flag-alone mac-webkit morph runs (6 total, 120 cells per arm) via the lead; orig and base there are the A/A reference.
- Profile scoped's writes during the nav close before the part fix.
- `trajectory-envelope-scope` may use the g-distribution check instead of a per-cell colour rule.
Ledger keys (the lead edits): `hero.exit.scoped.inline` (perf finding: longer close-end gaps on mac WebKit, pooled p 0.011);
candidate row for "close start colour is a frame-phase value (`bgRed(m_prev)`)".
Read first: note `research/notes/2026/10-21-scoped-close-start-cause.md`, then `HeroExitCloseStart.lean`. Also wrote `lean/Fw.lean` (import).
