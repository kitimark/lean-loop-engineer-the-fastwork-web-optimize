# Handoff: gate-settle

Branch `worktree-agent-a102c4d136256e6ae` (CI ref `ci/gate-settle`), built ON the integration branch `worktree-agent-afe5e7954b26806f5` (not b37227c).
Read first: `lean/Fw/Gate/Settle.lean`, `packages/gate-breakpoints/src/{settle,page,run,summary}.mjs`.

## What exists
- Lean `Fw.Gate.Settle`: `Obs`, `Policy` (gatePolicy 2 frames, 3 quiet, eps 100 millionths, 30000 ms), `settled`, `sampleOk`, fuel-bounded
  `wait` (timeout = `unsettled`), `report`, `Verdict`/`classify`/`Cell`/`Cell.passes`. Theorems: `unsettled_never_pass/fail`,
  `sample_delay_invariant`, `Lerp.sample_delay_invariant`, `pain_notes_unsettled`, `hero_orbit_unsettled`, `park_settled_iff`,
  `signup_unsettled`, `lerp_moving_unsettled`, `notRendered_never_pass/fail`, `cell_decided`. Math lint 0 failing.
- Golden `packages/contracts/golden/gate/settle.jsonl` (`scripts/settlegen.mjs`, `--check`); TS twin `src/settle.mjs`, replayed by
  `test/settle-golden.test.mjs` (also the predicates copied inside `settleInPage`).
- Gate: `settleInPage` after load, each resize, each overlay open and in phase 0 before the declared-name scans (both arms): real rAF
  count, getAnimations, quiet frames, `:hover` only where the env can hover. Pointer parked outside the viewport (-1,-1): a point
  inside lay over a hero.orbit card; `findParkPoint` removed (no point found in 88/88). 600 ms/300 ms sleeps gone. stderr `settle ...: N ms`.

## Result (CI run 39080214138, ea1433c; run 3 of 3)
- 244/244 settled on BOTH engines. Settle per sample: chromium median 0.80 s max 1.66 s; webkit median 1.05 s max 18.1 s (3-7 frames/s).
  Jobs: chromium shards 78-90 s, webkit 154-169 s, sweeps 214 s / 331 s. Earlier runs: webkit paints at 0.3-1.7 fps with the pointer in the
  viewport (216/244 unsettled at 10 s); bringToFront did not help (removed).
- Settled failures left (real values): pain.notes 145, commission 86/46, nav.hitTest nav border colour 23,23,23 vs black (488/472),
  hero.orbit z-index 2 vs 1 at desk-rm-860/861 only (7 -> 2; z-index is not in the quiet signature). Header merge succeeded on both engines.

## Open items
- mountPanel "ready" stage still sleeps 300 ms. Commission inner/rows margins go back to integrate-ports (premise-tests run 39076735134
  refuted the skip premise; the gate flags nothing as notRendered; only docstrings carried it, no theorem).
- Header flake (nav.hitTest originOnly; WebKit run 39077507337 nav `opacity`): phase 0 parks and settles before scanning; a
  timer-driven toggle never settles (8-scan union covers it). Covered by one clean run only.
