# flip-verify-flake handoff

State: branch worktree-wf_7d377ec7-c1b-1, fix commit 4eefcb29a, pushed as ci/flip-verify-flake with [ci:breakpoint-gate]. CI run 1: breakpoint-gate 41204138908 at 4eefcb29a, both flip-cell jobs (chromium, playwright-webkit) passed Flip verify and Flip verify repeats on the first attempt (run still finishing its look report when written). Run 2 pushed from the merge of main. Local checks done: lean check.sh green, gate-breakpoints tests 836 pass, ci-paths 56 pass, land-inputs 73 pass, plan lint 0 errors (main merged).

Cause (MEASURED from artifacts of runs 41198892838, 41196819967, 41181634194, 41190009074; passes 41194080600, 41198860679):
- A5 at 320x568: WebKit on the ARM runner is software-rendered, rAF gives 1 to 4 frames per 680 ms. The light-start open push gets no tick after the nav turns dark, so it is untaken and had no "chance". The old 3/4 quorum (`judgedEnough`) then failed the band.
- A4: `covered:false`, the probe's last frame came less than 800 ms after the leave frame because of a fixed sleep under starved rAF.
- Not a page bug: 320/320 dark-at-push pushes taken, 29/29 light-start pushes with a chance taken.

Fix (no tolerance change): Lean `lean/Fw/Parts/MorphGeomVerify.lean` (pushChance, pairsOk, retryJudged, leaveCovered, leaveOk + theorems), golden regenerated from `MorphGeomTimedGen.lean`, TS in `packages/gate-breakpoints/src/flip-verify.mjs` (per-push judge, guard-alive, dark-at-push counts as chance, `leaveReady` wait replaces the fixed sleep). 22 TS tests pass; lean check.sh green.

Offline replay: new A5 rule 12/12 on all five artifacts; A5 mutation artifacts still fail.

Open: CI evidence (first-attempt runs on ci/flip-verify-flake, about 8 needed); research note `research/notes/2026/10-31-flip-verify-flake.md` and ledger row; Flip-state cell lang flake (runs 41189419989, 41186783098) is a separate failure, out of unit.

Read first: the note, then flip-verify.mjs analyseFlipProbe / driveFlipProbe.
Conventions: push form `git branch -f ci/flip-verify-flake HEAD` then plain `git push origin ci/flip-verify-flake`; tip message must name `[ci:breakpoint-gate]`.
