# pathpix-consensus-capture handoff

- Branch: worktree-wf_651b0dc0-140-1 (CI branch ci/pathpix-consensus-capture)
- Worktree: .claude/worktrees/wf_651b0dc0-140-1
- Code commit measured: eae3bfab5f96a88fbb95436a0655af847da75856 (later commits: note and handoff only)
- CI: path-pix run 40026419647 (sha eae3bfab5) success, 3 jobs per engine, no re-run
- Local gates at eae3bfab5: lean check.sh green, measure-webkit tests 535 pass, ci-paths 56 pass, runner land-inputs 56 pass

## Verified (run 40026419647, report script output in research/notes/2026/10-2x-hero-copy-floor.md)
- Lean consensus rule + probeHit/probesHit twin + golden (434 lines); TS replays it; report prints probe boxes at the asked scrollY.
- WebKit (A, A2, A3): counted/varied/quiet per job 11/3/10, 13/0/11, 12/2/10. Chromium (no A3): 21/0/3 in all 3 jobs.
- webkit-1 offset 5 hero_copy: A/A and P both 192513-20 inside -> varied. webkit-2 offset 5: P-only 192513-20, A/A3 0-0 -> counted L.
- webkit-3 offset 5 was quiet this run; the A/A 4478-2 nav-earn change recurred in no job (class open).

## Open
- Chromium A3: one-entry edit in packages/measure-chromium/src/pathpix.mjs (arms list), outside task writes; lead decides.
- partsHit (CSS px floats) stays a TS stand-in; probesHit has a Lean twin.
- Limits: no majority reference (A is reference); varied hides P above the A/A floor in noisy cells (3 cells in this run).
- Class of the 192513-20 raster needs another run or a majority-reference rule. Look review is the user's; no phone.

## Read first
lean/Fw/Gate/PathPix.lean (section Consensus of the identical arms), packages/measure-webkit/src/pathpix-exit.mjs, pathpix-exit-report.mjs, the "Consensus capture" section of the note.
