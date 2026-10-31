# flip-verify-flake handoff

State: branch worktree-wf_7d377ec7-c1b-1. Fix commit 4eefcb29a (judge + Lean + golden), main merged after; CI branch ci/flip-verify-flake at 08fc651a3 (same code).

Cause (MEASURED from artifacts of failed runs 41198892838, 41196819967, 41181634194, 41190009074; passes 41194080600, 41198860679):
- A5 at 320x568: WebKit on the ARM runner is software-rendered, rAF gives 1 to 4 frames per 680 ms. The light-start open push gets no tick after the nav turns dark, so it ends untaken with no chance. The old 3/4 quorum (`judgedEnough`) failed the band.
- A4: `covered:false`, fixed sleep left the last frame under 800 ms after the leave frame.
- Not a page bug: 320/320 dark-at-push pushes taken, 29/29 light-start pushes with a chance taken.

Fix (tolerances unchanged): `lean/Fw/Parts/MorphGeomVerify.lean` (pushChance, pairsOk, retryJudged, leaveCovered, leaveOk + theorems), golden regenerated from `MorphGeomTimedGen.lean`, `packages/gate-breakpoints/src/flip-verify.mjs` (per-push judge, dark-at-push chance, pooled retry guard, `leaveReady` wait).

Verified: lean check.sh green; gate-breakpoints tests 836 pass; ci-paths 56; land-inputs 73; plan lint 0 errors. CI first attempt, 4 of 4 green (41204138908, 41206144214, 41207587068, 41207595129); WebKit 36/36 bands A3a/A4/A5 over three, 3 of 144 pushes untaken and excused; mutations A5 and A4 still fail.

Open: about 8 more first-attempt runs for the lead to dispatch (`gh workflow run breakpoint-gate.yml --ref ci/flip-verify-flake`; do not push a new tip while they run, the tip re-check fails older jobs); Flip-state cell lang flake (41189419989, 41186783098) is a separate failure; A4 raw frames of the failed runs were not saved.

Read first: `research/notes/2026/10-31-flip-verify-flake.md`, then flip-verify.mjs analyseFlipProbe / driveFlipProbe.
Conventions: `git branch -f ci/flip-verify-flake HEAD`, then plain `git push origin ci/flip-verify-flake`; tip message must name `[ci:breakpoint-gate]`.
