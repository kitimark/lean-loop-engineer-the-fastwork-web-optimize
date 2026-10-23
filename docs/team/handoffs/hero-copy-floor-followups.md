branch: worktree-wf_2d420399-b29-1 (CI branch ci/hero-copy-floor-followups, pushed at ee7bd519a)
worktree: .claude/worktrees/wf_2d420399-b29-1
last commit sha: see `git log -1` (main merged after the note commit 9da29014b)
CI runs: path-pix 40007968162 success (sim (2) first attempt failed in `simctl list devices` ETIMEDOUT, runner fault; re-run once with `gh run rerun --failed`, passed); the only run for this task
state: Lean lemmas, golden, TS twin, report and probes tested; note regenerated from the run's report output; final checks listed below.

Verified
- Lean `lean/Fw/Gate/PathPix.lean`: `RowLayer`, `countedBy`, `receiver_counts`, `hero_yields_to_receiver`, `yielded_counted_by_receiver`, `inside_some_mask_counted`; generic `foreignReason`; golden kind `yield` (8 rows).
- TS: `splitUnion` receivers, cell `sharedTo`, `where.outProbes`, page `EXIT_PROBES`; report prints receiving cells' grade and a probe table. TS stand-in: `probesHit` (box overlap) has no Lean twin.
- Item 3: nav-lang `button.switch` box at scrollY 813 = device x 655.8..874.8, y 72..180 (probe table, run 40007968162); x 873 is its right edge; the 2-1 did not recur; webkit-3 shows an A/A 4478-2 at nav-earn (887..1218) instead.
- Item 4: sourced negative in the note (y 0 row): no page or capture input differs; render-server variation INFERRED.
- New: webkit-3 offset 5 hero_copy P 192513-20 inside on the red deck-card artwork, 1 of 3 jobs, no receiver graded at that offset.

Open: consensus capture (A3) not built; look review is the user's; no phone.
Read first: research/notes/2026/10-2x-hero-copy-floor.md, then `packages/measure-webkit/src/pathpix-exit-report.mjs`.
