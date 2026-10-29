branch worktree-wf_bb119790-00f-1 (ci branch ci/geom-recalc-source), worktree .claude/worktrees/wf_bb119790-00f-1, last commit 1576aad26 (pushed)
CI runs: wktr 40792245957 (push 1, c536e5c0f, success, 3 jobs, verdict engine-internal in idle and flip in all 3 jobs; data in results/geom-recalc-source/r1);
wktr 40795367330 (push 2 of max 3, 1576aad26, adds pre-callback recalc count per frame and the diagnostic arm rs-idle-cancel, queued).
Run 1 facts (MEASURED): all-paused idle 95-103 recalcs per 100 frames, every recalc updates 0 elements (lastStyleUpdateSize 0), no mutation or raf key, only a gc timer interval; swallowing page rAF or timers leaves 98-100.

Task geom-recalc-source (graph r560): name the source of the one style recalc per frame left when every running animation is paused (WKTR, pref OFF).
State
- Lean decision lean/Fw/Device/RecalcSource.lean (thresholds fixed before data, golden packages/contracts/golden/device/recalc-source.jsonl, check.sh job + Trigger row wired). Committed 96cd00fe9.
- TS stand-in packages/measure-wktr/src/recalc-source.mjs (replays the golden; jobOf report glue is not golden-replayed); probe arms rs-* in src/mid-page.mjs (rsArm, rsWindow, wrappers for rAF, timers, CSSOM, MutationObserver); mode recalc-thr-off in src/accel-cli.mjs; temporary ACCEL_MODES edit in .github/workflows/wktr.yml (REVERT before land).
- Verified: measure-wktr package tests 102 pass (fw slot). Probe never ran in a real page yet: the push is the first run; a page error shows as report.error / rows missing.
Open
- Wait: pnpm -s fw ci wait --branch ci/geom-recalc-source --workflow wktr; fetch with pnpm -s fw ci <runId>; 3 jobs needed; at most 2 more pushes.
- Verdict per job and overall: node-side recalcTally prints it in the run log; store results under results/geom-recalc-source/.
- Note research/notes/2026/10-2x-geom-recalc-source.md, ledger note, revert wktr.yml, check.sh + tests via fw slot, ci-paths + land-inputs tests, required reads (LandSpeed.checkShReads, land.ts), merge main, plan lint, dry land (VERDICT dry geom-recalc-source), fw review ready.
Conventions
- Frame = stretch between two MessageChannel tasks after a rendering update; keys kind:what (mut/raf/timer/cssom/anim); page interns keys in rs.kt.
- Block arms run last (they swallow page callbacks). Dirty-element scans are not in the verdict.
Read first: lean/Fw/Device/RecalcSource.lean header, then mid-page.mjs "Task geom-recalc-source".
