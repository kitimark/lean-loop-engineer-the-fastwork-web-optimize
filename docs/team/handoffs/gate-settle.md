# Handoff: gate-settle

Branch `worktree-agent-a102c4d136256e6ae` (CI ref `ci/gate-settle`), built ON the integration branch `worktree-agent-afe5e7954b26806f5` (not on b37227c): the lead lands it and may resolve conflicts.
Read first: `lean/Fw/Gate/Settle.lean` (model + proofs), `packages/gate-breakpoints/src/{settle,page,run,summary}.mjs`.

## What exists
- Lean `Fw.Gate.Settle`: `Obs`, `Policy` (gatePolicy 2 frames, 3 quiet frames, eps 100 millionths, 30000 ms), `settled`, `sampleOk`,
  `wait` (fuel-bounded, timeout = `unsettled`), `report`, `Verdict`/`classify`/`Cell` (pass | fail | unsettled | notRendered), `Cell.passes`.
- Theorems: `unsettled_never_pass/fail`, `sample_delay_invariant` (Traj model), `Lerp.sample_delay_invariant` (quiet bound for rAF lerps),
  `pain_notes_unsettled`, `hero_orbit_unsettled`, `park_settled_iff`, `signup_unsettled`, `lerp_moving_unsettled`,
  `skipped_classified_notRendered`, `notRendered_never_pass/fail`, `cell_decided`. Math lint: 0 failing.
- Golden `packages/contracts/golden/gate/settle.jsonl` (`node packages/gate-breakpoints/scripts/settlegen.mjs`, `--check`); TS twin
  `src/settle.mjs`, replayed by `test/settle-golden.test.mjs` (also the predicates copied inside `settleInPage`).
- Gate: `settleInPage` runs after load, after each resize, after an overlay opens and in phase 0 before the declared-name scans (both arms):
  real rAF count, getAnimations on the probed subtree, quiet frames, `:hover` only where the env can hover. Pointer is parked OUTSIDE the
  viewport (-1,-1) before ready and before every settle: a point inside lay over a hero.orbit card at 860-1031 px (z-index 2 vs 1);
  `findParkPoint` was removed (it found no point in 88 of 88 samples: some probed root covers the viewport). `waitResize` is one frame;
  the 600 ms and open-overlay 300 ms sleeps are gone. Unsettled -> NC rows (`summary.json unsettled`). stderr logs `settle ...: N ms`.

## Findings (CI run 39078493093, c87d62f)
- Chromium: 244/244 settled, median 634 ms, max 1698 ms; after a real resize about 0.85 s per stop. Unsettled hover touch samples gone.
- WebKit CI paints this page at 0.3 (probes, 4 pages) to 1.7 frames/s: three frames take up to 10 s, so the 10 s budget left 216/244
  unsettled; budget now 30 s. `bringToFront` did not help (removed). Frames are CPU-bound, so WebKit settle cost is intrinsic.
- Chromium failures are settled values, not misreads: pain.notes x 145, commission h/margins 82, hero.orbit z-index 7 (parked at the corner).

## Open items
- mountPanel/"ready" stage still sleeps 300 ms. Commission inner/rows margins go back to integrate-ports (premise-tests run 39076735134
  refuted the skip premise; the gate flags nothing as notRendered; only docstrings carried it, no theorem).
- Header flake (nav.hitTest originOnly; WebKit run 39077507337 nav `opacity` listed in 3 of 4 jobs): phase 0 now parks the pointer and
  waits for settle before scanning, so a transient rule is gone in every job. A timer-driven toggle never settles; the 8-scan union covers it.
  Classified, covered only if CI shows identical lists across shards.
