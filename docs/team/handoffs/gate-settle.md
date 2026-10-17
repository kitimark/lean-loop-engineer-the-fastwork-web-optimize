# Handoff: gate-settle

Branch `worktree-agent-a102c4d136256e6ae` (CI ref `ci/gate-settle`), built ON the integration branch `worktree-agent-afe5e7954b26806f5` (not on b37227c): the lead lands it and may resolve conflicts.
Read first: `lean/Fw/Gate/Settle.lean` (model + proofs), `packages/gate-breakpoints/src/{settle,page,run,summary}.mjs`.

## What exists
- Lean `Fw.Gate.Settle`: `Obs`, `Policy` (gatePolicy 2 frames, 3 quiet frames, eps 100 millionths, 3000 ms), `settled`, `sampleOk`,
  `wait` (fuel-bounded, timeout = `unsettled`), `report`, `Verdict`/`classify`/`Cell` (pass | fail | unsettled | notRendered), `Cell.passes`.
- Theorems: `unsettled_never_pass/fail`, `sample_delay_invariant` (Traj model), `Lerp.sample_delay_invariant` (quiet bound for rAF lerps),
  `pain_notes_unsettled`, `hero_orbit_unsettled`, `park_settled_iff`, `signup_unsettled`, `lerp_moving_unsettled`,
  `skipped_classified_notRendered`, `notRendered_never_pass/fail`, `cell_decided`. Math lint: 0 failing.
- Golden `packages/contracts/golden/gate/settle.jsonl` (generated: `node packages/gate-breakpoints/scripts/settlegen.mjs`, `--check`);
  TS twin `src/settle.mjs`, replayed by `test/settle-golden.test.mjs` (also extracts the predicates copied inside `settleInPage`).
- Gate: `page.mjs settleInPage` runs after load, after each resize and after an overlay opens (both arms): real rAF count, getAnimations
  on the probed subtree, quiet frames, pointer parked outside probed targets (`findParkPoint`, `s.mouse`). `waitResize` is one frame; the
  fixed 600 ms and the open-overlay 300 ms are gone. Unsettled -> NC rows (`summary.json unsettled`), skipped subtree -> `notRendered` list
  (`collectInPage` item `skipped`, `summary.mjs maskNotRendered`); neither is pass or fail. stderr logs `settle ...: N ms` and `resize ...: N ms`.

## Conventions
Page functions are self-contained (toString); the Node side decides with the Lean twins. cli.mjs belongs to gate-exit-verdict (not edited).

## Open items
- mountPanel/"ready" stage still sleeps 300 ms (no settle after it); the 600 ms debounce hypothesis is untested (guard: same-width stops and fresh-final).
- notRendered: Lean `Verdict`/`Cell`/theorems are generic (the flag is an input); the gate flags NOTHING. The first design flagged nodes
  under a content-visibility skip, on the premise that an auto margin there is unresolved; premise-tests (run 39076735134) refuted
  it (resolved px on both engines). commission inner/rows margin goes back to integrate-ports as a possible real difference. Only
  docstrings carried that premise; no theorem did. Commit 5b60ed8 (run 39075162003) still flags, so its `notRendered` list is not a verdict.
- Header flake (variant-regate, nav.hitTest originOnly differs between shards): the declared-name list depends on timer phase, not on
  a settled sample. Phase 0 now parks the pointer first (covers a hover left by the pointer); a timer-phase cause is NOT covered by
  settle (a timer-driven state never settles). Classified, not proven fixed.
- CI result and added seconds: see the lead report (run id in the final message).
