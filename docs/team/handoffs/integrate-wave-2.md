# Handoff: integrate-wave-2

State: branch `integrate-wave-2` (commit in the report). CI branch `ci/integrate-wave-2` was pushed ONCE at ef8b2cd3; never push it again (dispatch `gh workflow run <wf> -R <repo> --ref ci/integrate-wave-2`).
Read first: `research/notes/2026/10-19-integrate-wave-2.md` (all tables, run ids, MEASURED/INFERRED tags). Data: `results/integrate-wave-2/**` (plan.json maps runs to pages).

Verified (CI, Lean verdicts):
- Gate v2-proved 39220947437: Chromium pass 7049/7056 (7 excused), WebKit incomplete (291 excused, 2 bad = the same two phone-rotation cells as wave 1).
- Gate default 39220962049: Chromium fail (1 commission probe at the first desktop sweep stop), re-run 39230139617 pass; WebKit incomplete as above.
- Counts swipe-v1 / swipe-touch-v1: style recalcs -1011 / -1007 (deterministic, below band), layers +1051 / +1119; R0 vs original fails, control passes, RV vs original refused (`not comparable: preset`).
- Part engine-check: nav.hitTest 5 pass; columns 2 pass; hero.countdown unusable; g1 and platform have model-bug rows that trace to the frozen whole-page class premise or a real 12-frame tail shift (note, section "Part pages").
- F6 pilot (swipe-v1): not additive at totals (trajectories 503 vs 727..1329 frames), additive per frame on the style family.

Open items:
- Panel host stage page is 443 px wide at a 430 viewport: the driver's viewport gate refuses G2 (39224697587/39224735485) and morph.mount (39227583530). Fix the page width, then re-run G2 and the panel parts.
- Platform `engine.scene:hidden-pause` verdict OPEN (platform-scene-faithful r1 re-proving it).
- g1 combined arm: cc.Commit +10 and PrePaint +10 that no single flag shows (interaction with hero/morph.countdown strip?); people.card moves 12 tail-frame commits; both unattributed.
- Default-arm commission flake (1 of 2 gate runs); the Lean `commissionResizeStops` exemption is unused since wave 1.
- Compose-check F6 verdict is not in Lean; page-level flags (engine.scroll, morph.tween) have no part page.

Conventions: TS stand-ins live in `packages/engine-check/src/wave2.mjs` (`check`, `delta`, `zonecmp`, `f6` commands; tests in `test/wave2.test.mjs`); download runs with `gh run download <id> --dir <scratch>/<id>`.
Per-run counts files (54 MB) are not committed; the gate `summary.json` files (1 MB each) are not committed either; `summary.md` is.
Do not commit `apps/runner/src/fw.ts` (a mode-only diff in the worktree).
