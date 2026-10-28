branch: worktree-wf_e077f1dc-fb5-1 (CI branch ci/geom-pref-off-ticking)
worktree: .claude/worktrees/wf_e077f1dc-fb5-1 (under the main checkout)
last commit: d79a4bab5 (push 1 of max 3)
CI runs: wktr 40653612323 (push 1, in progress; modes mid,mid-thr-off, arms all,all-again,all-3,all-4 via the yml env on the ci branch only); lean 40653612431

# state
- Question: why does the parked geom-prewarm note read pref OFF as 25 accelerated / 30 ticking while main's geom-webkit-midflip note reads 47 / 0.
- Verified already (MEASURED, re-tally of the prewarm artifacts, run 40648228102, pref OFF jobs j1, j3, with packages/measure-wktr/src/midflip.mjs):
  active-phase samples read rawAcc 25 (raw property-name match, no class fold) against clsAcc 47 (Lean readsAccelCls) and oracle ticking 0.
  25 = 18 transform + 1 backdrop-filter + 4 opacity + 2 filter; the 30 = 20 translate + 2 scale + 8 hidden transform tracks that
  the raw match cannot see because the layer list folds translate, scale, rotate, transform into `transform` entries (GraphicsLayer.cpp:103-124@862f17d).
  Probe differences (git diff main worktree-wf_066a7844-684-1): mid-page.mjs only adds a trace and carries held tracks into the arm; accel-cli.mjs and midflip.mjs are unchanged.
- Lean added (lean/Fw/Parts/MorphTrackAccel.lean): raw_misses_folded, Reason/reasonOf, ticksMain_eq_reason, one reasonOf_* theorem per branch;
  golden morph-track-accel.jsonl regenerated (tick lines gain "reason", 4 "raw" lines). TS stand-in: reasonOf, keySummary in midflip.mjs (tested, not golden-replayed).
- wktr.yml carries the ACCEL_MODES env: ci branch only; revert it (git checkout main -- .github/workflows/wktr.yml) before the dry land.

# open
- read the wktr artifacts (gh run download <id> -D <scratch>) with scratchpad tools keys.mjs (keySummary per flip and bin); write research/notes/2026/10-2x-geom-pref-off-ticking.md, ledger note, check.sh via fw slot, package tests, merge main, dry land, review ready.
