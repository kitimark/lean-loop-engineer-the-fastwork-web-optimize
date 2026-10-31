# flip-verify-flake: why the WebKit flip verify failed about 1 band in 12, and the fix

Date: 2026-10-31. Task `flip-verify-flake` (graph r610). Branch `worktree-wf_7d377ec7-c1b-1`, CI branch `ci/flip-verify-flake`.
Lean: `lean/Fw/Parts/MorphGeomVerify.lean` (`pushChance`, `pairsOk`, `traceOk`, `retryJudged`, `leaveCovered`, `leaveOk`), golden lines `verify*` in `packages/contracts/golden/morph-geom-timed.jsonl` (from `MorphGeomTimedGen.lean`).
Code: `packages/gate-breakpoints/src/flip-verify.mjs` (`analyseFlipProbe`, `driveFlipProbe`, `runFlipVerify`); job `flip-cell` in `.github/workflows/breakpoint-gate.yml`.

## Answer

- The failures are a harness fault, not a page glitch, so the judge's tolerances are unchanged (`verifyWindowMs` 800, `verifyFrameMs` 50/3, `verifyTolPx` 1). Two causes, both from starved requestAnimationFrame on the software-rendered Playwright WebKit runner (1 to 6 Hz during the morph). MEASURED from the saved verify JSON of failed runs 41198892838, 41196819967 (A5, 320x568) and 41181634194, 41190009074 (A4, 1920x1080, in the repeat step), against passed runs 41194080600 and 41198860679.
  - A5: the timed take is tried on every tick while the push is pending (`morph.tween/driver.ts:193`, `226-236`), and `allowed()` needs the nav to read `is-on-dark` (`morph.geom/index.tsx:53`). At 320x568 the light-start open push gets no tick after the nav turns dark, so it ends untaken with no chance to take. The old `judgedEnough` quorum asked for 3 of 4 pushes judged, so one such push plus any second starved push failed the band. The old chance counted only frames seen with the guard open.
  - A4: `covered:false`. The probe slept a fixed time after the leave frame; with 1 to 4 frames in the window, the last frame landed less than 800 ms after the leave frame, so the quiet window was not covered.
- Page evidence: 320 of 320 dark-at-push pushes were taken and 29 of 29 light-start pushes with a chance were taken across the five artifacts; the five untaken light-start pushes all had no chance (no tick after the nav turned dark). MEASURED, offline replay.
- Fix (no retry loop):
  - A5 is judged per push (`pairsOk`): a push with a chance that is untaken fails (`pairs_lost_chance_fails`); a push without one is free (`pairs_excused_free`); at least one push must be taken, so a dead guard fails (`pairs_dead_fails`). The quorum is gone. A nav that is already dark at the push counts as a chance (`pushChance`, `push_chance_dark`), and a dark-at-push push that goes untaken fails (`dark_push_untaken_fails`).
  - A pooled guard: if some push started light, at least one light-start push must have had a chance or been taken (`retryJudged`, `retry_unjudged_fails`; with no light-start push it passes, `retry_vacuous`).
  - A4 waits for a deterministic signal instead of a fixed sleep: the probe's `leaveReady(windowMs)` is true once no `is-on` frame is pending and the last frame is at least `windowMs` after the leave frame (`leaveCovered`, `leave_short_not_covered`, `leave_covered_later`); the cap is 30 s plus a 200 ms tail. An uncovered leave still fails (`leave_uncovered_fails`).
- The A5 mutation (guard reads light on every frame) still fails in every band on both engines, replayed offline on three saved mutation artifacts and on CI run 41206144214 (WebKit A5 mutation: 0 of 2 bands pass; A4 mutation: 0 of 2).
- CI, new judge, WebKit flip-cell, first attempt: 4 of 4 runs green (push 41204138908 at 4eefcb29a, push 41206144214 and dispatches 41207587068, 41207595129 at 08fc651a3, same code). Band detail for the first three (36 bands, 144 pushes): A3a, A4 and A5 each 36 of 36; in-job repeats 3 of 3 and 3 of 3 in each run; 141 of 144 pushes taken, and the 3 untaken pushes were light-start with no chance, which the new rule excuses and the old quorum counted against the band. Chromium flip-cell green in all four. MEASURED (the fourth run, 41207595129, is read from its conclusion only).
- What 4 green runs prove: little by themselves. A run holds 12 bands and the old failure rate was about 1 band in 12 on a run's first attempt, so a run failed with probability p of roughly 0.3 to 0.6 (4 failed and 2 passed among the 6 runs read here, biased because failures were picked first), and four passes in a row have chance (1-p)^4, where 1-p is 0.4 to 0.7, about 0.03 to 0.24 under the old judge. The proof is the per-push Lean judge plus the replay; CI shows no regression and that the excused case happens (3 of 144 pushes). To back "gone" with CI alone the lead should dispatch about 8 more first-attempt runs (all green rules out p of 0.3 or more at 94 percent, with the 4 already green); 28 in a row rules out p of 0.1. INFERRED rates.

## Accepted limits

- Tolerances stay. A lost frame in a light-start push that had a chance still fails.
- A4 raw frames of the failed runs 41181634194 and 41190009074 were not saved, so the new `leaveReady` wait is not replayed on them; its argument is the Lean `leaveCovered` theorem plus the CI runs above (INFERRED for the old failures).
- The two other failed runs seen on main (41189419989, 41186783098) failed in the "Flip-state cell" step (lang), not in verify. Out of unit; follow-up.
- Chromium flip-cell is not changed: its rAF is not starved and it passed in every run.

## Lesson

A judge that counts a sample (frames seen) as the unit of chance fails when the sampler is starved. State the chance from the page's own state (dark at the push) and judge each push on its own, with one pooled guard that the excuse is not used everywhere.
