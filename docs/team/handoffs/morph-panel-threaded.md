# morph-panel-threaded (part-builder, continued)

Branch `worktree-wf_65d039ea-8f9-1`, worktree `.claude/worktrees/wf_65d039ea-8f9-1`, CI branch `ci/morph-panel-threaded`, main merged at afd29aed3; last commit: `git log -1`.

CI runs:
- lean 39853827853 (46c718709) and 39855506561 (5519b5509): success.
- breakpoint-gate 39846842455 (`--gate --engines both --fw morph.panel:threaded`, f0273f680): success.
- trajectory-probe 39846814254 (four widths): chromium RED, 84 new, 0 content, all open@1 coverage (first-frame phase, see note).
  39855506403 (5519b5509, `fw=morph.panel:threaded widths=390,640 engines=chromium diagnostic`, inputs read from the step name): RED 42 new, 0 content, w=640 open@1 only;
  GPU cells with the flag: panel-effect E 3 of 4, 640 close L is a reference chord across the kink (both arms within 0.0013 of the Lean model).
- chromium-counts swipe-v1: const-bounds 39851664186, threaded 39851674587, success; equal counts, the profile never opens the panel.
- webkit-sim cost (lag=true cost=on): threaded 39846909558, const-bounds 39846941236 (r1, r2 read; r3 still running when read), bundle 39846948148 (complete).
  Result: open push Composite per frame higher than const-bounds (236-552 vs 151-213 ms), close overlaps. Negative finding.

Done: note research/notes/2026/10-2x-morph-panel-threaded.md, ledger row n=51, results/morph-panel-threaded/report.json, merge of main (Bridge.lean, FootprintRows.lean,
footprint-diff regenerated), `check.sh` green, `@fw/site` test green.
Outside the task's writes: .github/workflows/trajectory-probe.yml (GPU cells step passes `--search`), the regenerated Lean/golden footprint files.
Open: webkit-sim r3 jobs of 39846909558 and 39846941236; Safari lane and PathPix cell (follow-ups); a variant of effects on a constant-bounds panel (new variant, flags of one part are exclusive).

Conventions: see MorphPanelThreaded*.lean headers; after any source edit run `part-footprint.mjs --write`, rebuild `Fw.Parts.Contract`, `ContractsGolden --rows`, rebuild, `--diff`.
Read first: the note, then `lean/Fw/Parts/MorphPanelThreadedRun.lean`.
