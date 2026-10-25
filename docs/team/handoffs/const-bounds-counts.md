branch: worktree-wf_b76a2dc0-a43-1
worktree: .claude/worktrees/wf_b76a2dc0-a43-1
last commit: see `git log -1` on the branch (the final sha is in the report)
CI runs (none pushed by this task; all dispatched earlier), all complete:
- 40196209240 WebKit Simulator flag morph.panel:const-bounds at cb4bec8: r1, r2 (rerun), r3 success
- 40196215217 WebKit Simulator base at cb4bec8: success, filed in the store
- 40171939293 Chromium base swipe-touch-v1 x3 at 1fac415: success; 40171951145 Chromium flag, same
Verified:
- Lean module lean/Fw/Parts/ConstBoundsCounts.lean builds; golden packages/contracts/golden/parts/const-bounds-counts.jsonl and
  results/const-bounds-counts/tables.md are generated from results/const-bounds-counts/cells.json (results/const-bounds-counts/extract.mjs
  copies integers, no decisions) and replayed by the check.sh job "const-bounds-counts golden check".
- Verdicts (Lean, 3 VMs per arm on WebKit, 3 runs per arm on Chromium): WebKit hero / finish / rest no-win. Chromium hero and rest
  no-win, finish cost (Layout.dirtyObjects 758 to 920, Layout records equal, Paint +1).
- Ledger row morph.panel-const-bounds has its webkit and chromium cells and one note; no visClass added (part.json has none).
Open:
- The WebKit no-win is "not observed": the Simulator step walk ends before the page-end morph frames (INFERRED). Follow-up: a WebKit
  end-dwell lane.
- Filing the flag run with `pnpm -s fw run --target rewrite --engines webkit --fw morph.panel:const-bounds --from-run webkit=40196209240
  --sha cb4bec8e4019024c2b73abb702443af3ab482aab` was slow (> 10 min); check the store before repeating.
- Writes outside the task: lean/Fw/Console/LandSpeed.lean, apps/runner/src/land-reads.gen.ts, packages/contracts/golden/console/land-speed.jsonl
  (check.sh reads declared for the land-inputs test).
Read first: research/notes/2026/10-2x-const-bounds-counts.md, then the header doc of lean/Fw/Parts/ConstBoundsCounts.lean.
