branch: worktree-wf_e077f1dc-fb5-1 (CI branch ci/geom-pref-off-ticking); worktree .claude/worktrees/wf_e077f1dc-fb5-1 under the main checkout
state: investigation finished, 2 of 3 pushes used, wktr.yml ACCEL_MODES env reverted. Read first: research/notes/2026/10-2x-geom-pref-off-ticking.md
CI runs: wktr 40653612323 (push 1, d79a4bab5), wktr 40657027777 (push 2, fbc187650), lean 40653612431; both wktr runs complete, success, 3 jobs, modes mid + mid-thr-off.

# verified
- Contradiction (MEASURED, re-tally of run 40648228102): prewarm "25 a / 30 tick" is the raw property-name flag; class-folded 47, oracle ticks 0. Midflip's 47 / 0 was right.
- Pref OFF steady state on main code: ticking set empty (flips after the first commit read 47 / 0 at p30, p50, p80; 8 hidden tracks unrendered).
- Transient S1, 21 tracks (13 image transforms, logo, earn x3, earnClip, earnLabel, footerGrad, footerEnd): ticks at p30 in 5 of 16 flips, p50 in 2, never p80, pref OFF only;
  followed a creation flush taken while effects were pending in 5 of 6 flips, 0 of 10 otherwise; elements HAVE a layer at the sample (layer-missing idea refuted).
- Lean: Reason/reasonOf, one theorem per branch, raw_misses_folded, golden regenerated (check.sh green at d79a4bab5, rerun at the final commit).
- Phone: no named track set explains 348 of 396 long frames (INFERRED); recalcs per frame follow the job, not the pref.
- Data: results/geom-pref-off-ticking/ (grid-r1-r2.txt, ticking-rendered-off.txt); ledger note appended to research/findings/ledger.json notes.

# open
- TS stand-ins not golden-replayed: reasonOf, keySummary in packages/measure-wktr/src/midflip.mjs (tests cover each Lean branch).
- Proposed next task: geom-sweep-paused (sweepDoc paused during a flip, WKTR then one booked phone session), before any geom-sweep-compositor.
- Done: merged main 601a94b, dry land VERDICT dry geom-pref-off-ticking, review ready.
- Scratch readers (not committed) live in the session scratchpad; rebuild from keySummary and frameSummary if needed.
