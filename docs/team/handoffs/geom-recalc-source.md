branch worktree-wf_bb119790-00f-1 (ci branch ci/geom-recalc-source), worktree .claude/worktrees/wf_bb119790-00f-1, results commit 60bab8937 (CI pushes: 3 of 3 used)
CI runs, all complete (success, 3 WKTR jobs each, mode recalc-thr-off, pref OFF):
- 40792245957 (c536e5c0f) r1; 40795367330 (1576aad26) r2; 40797685228 (ee443d434) r3. Data in results/geom-recalc-source/r1..r3, table.txt, verdict.txt.

Task geom-recalc-source (graph r560): name the source of the one style recalc per frame left when every running animation is paused (WKTR, pref OFF).
Result (MEASURED): Lean verdict engine-internal for idle in 9 of 9 jobs, flip in 7 of 9 (2 no-frames, flips did not engage in r3 j1 and j2); overall engine-internal. No mutation or rAF key in any recalc frame; every readable recalc of the observed idle arm updates 0 elements (forced-flush arm: 2 read, both 18); swallowing rAF or timers and cancelling all animations leave 93-100 per 100; hiding body leaves 0-11, empty body 0.
Next step: task geom-recalc-bisect (probe only): hide one body child at a time, then one [data-fw] part, find the subtree taking idle below 25 per 100; then read the WebKit path. No page-side fix.

State
- Lean decision lean/Fw/Device/RecalcSource.lean, golden packages/contracts/golden/device/recalc-source.jsonl, check.sh job and Trigger row wired.
- TS stand-in packages/measure-wktr/src/recalc-source.mjs (replays the golden; jobOf is glue, not replayed); probe in src/mid-page.mjs (rsArm, rsWindow); mode recalc-thr-off in src/accel-cli.mjs. wktr.yml mode edit reverted.
- Note research/notes/2026/10-2x-geom-recalc-source.md, ledger note added, land.ts read-list has the golden.
- Verified before the final steps: measure-wktr package tests 102 pass (fw slot).
Open
- check.sh, package tests, ci-paths test, land-inputs test via fw slot after the last commit; merge main; plan lint; dry land (VERDICT dry geom-recalc-source); fw review ready with run:<id> evidence.
Conventions
- Frame = stretch between two MessageChannel tasks after a rendering update; keys kind:what; page interns keys in rs.kt. cancel/hide/empty are diagnostics outside the Lean decision and run last.
Read first: the note above, then lean/Fw/Device/RecalcSource.lean header, then mid-page.mjs "Task geom-recalc-source".
