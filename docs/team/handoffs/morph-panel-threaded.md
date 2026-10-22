# morph-panel-threaded (part-builder, continued)

Branch `worktree-wf_65d039ea-8f9-1`, worktree `.claude/worktrees/wf_65d039ea-8f9-1`, CI branch `ci/morph-panel-threaded`, last commit 5519b5509 (main merged at afd29aed3).

CI runs:
- lean 39853827853 (46c718709): success (the init cost lint fix 7d920e0f3 holds). Run on 5519b5509: pending, find with `gh run list --branch ci/morph-panel-threaded`.
- breakpoint-gate 39846842455 (`--gate --engines both --fw morph.panel:threaded`, f0273f680): success.
- trajectory-probe 39846814254 (push, `fw=morph.panel:threaded`, 4 widths): chromium RED, 84 `new` units, all coverage, 0 content. Cause: the first sample
  after the push lands at m 0.07 or 0.20 (bimodal, frame phase); see the note. Re-run with the GPU cells on 5519b5509 (push line, widths 390,640 diagnostic): pending.
- chromium-counts (swipe-v1, runs 3): const-bounds 39851664186, threaded 39851674587, both success. Earlier 39847001498/39847006724 failed (not read).
- webkit-sim cost (lag=true cost=on vms=3): threaded 39846909558, const-bounds 39846941236, bundle 39846948148: running when last read.

Open: webkit-sim results; note research/notes/2026/10-2x-morph-panel-threaded.md, ledger row, results/morph-panel-threaded/report.json; full checks; dry land.
Outside the task's writes: .github/workflows/trajectory-probe.yml (GPU cells step passes `--search`), merged Bridge.lean/FootprintRows/footprint-diff regenerated.
