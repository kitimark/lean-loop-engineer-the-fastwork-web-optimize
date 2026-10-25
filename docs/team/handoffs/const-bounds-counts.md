branch: worktree-wf_b76a2dc0-a43-1
worktree: .claude/worktrees/wf_b76a2dc0-a43-1
last commit: see `git log -1` on the branch (WIP commits; the final sha is in the report)
CI runs (none pushed by this task; all were dispatched earlier):
- 40196209240 WebKit Simulator flag morph.panel:const-bounds at cb4bec8: r1 success, r3 success, r2 (rerun) in progress at last check
- 40196215217 WebKit Simulator base at cb4bec8: complete, filed in the store
- 40171939293 Chromium base swipe-touch-v1 x3 at 1fac415: complete, in the store; 40171951145 Chromium flag, same
State:
- Lean module lean/Fw/Parts/ConstBoundsCounts.lean builds; golden packages/contracts/golden/parts/const-bounds-counts.jsonl and results/const-bounds-counts/tables.md are generated from results/const-bounds-counts/cells.json by lean/scripts/ConstBoundsCountsGolden.lean and replayed by the check.sh job "const-bounds-counts golden check".
- cells.json is built by results/const-bounds-counts/extract.mjs (copies integers, no decision). If flag r2 is missing, the WebKit flag side has 2 VMs and every WebKit cell is reported thin.
Verdicts so far (Lean, from the filed numbers):
- WebKit: all three zones no-win (provisional until r2 is in; flag n = 2 VMs).
- Chromium (3 runs per arm): hero no-win, rest no-win, finish cost (Layout.dirtyObjects 758 to 920 on all runs, 41 morph frames at y 5342, +4 per frame = the four inset children).
Open:
- Download r2 (`gh run download 40196209240 -n webkit-sim-r2`), rerun the extract, regenerate the golden and tables, file the run with `pnpm -s fw run --target rewrite --engines webkit --fw morph.panel:const-bounds --from-run webkit=40196209240 --sha cb4bec8`.
- The note research/notes/2026/10-2x-const-bounds-counts.md and the ledger row morph.panel-const-bounds.
Read first: the note, then lean/Fw/Parts/ConstBoundsCounts.lean (header doc).
