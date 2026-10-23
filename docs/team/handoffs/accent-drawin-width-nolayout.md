branch: worktree-wf_11e76b9c-61d-1 (CI branch ci/accent-drawin-width-nolayout)
worktree: .claude/worktrees/wf_11e76b9c-61d-1
last commit: see git log (CI-pushed commit 3c1ab9970; later commits: :is() selector, results, ledger, note, this handoff)
CI runs: 40010696479 (fa6c56c6a, skipped by the guard: no [ci:webkit-sim] token; not a dispatch); 40010826238 (3c1ab9970, [ci:webkit-sim] [swap-lane] [swap-fw:accent-nolayout-full]): r1 r2 success, r3 cancelled (never finished), report jobs skipped. 1 dispatch of 2 used.
verified: Lean StyleDiffAccent (full_inRest_nolayout, wkLayoutFrames_values and crLayoutFrames_values for all n, no sorry), check.sh green (slot), site tests 6559 pass, golden regenerated from Lean.
result: rest windows >=24 Layout rows 0/56 (arm) vs 18/28 and 19/28 (faithful a, b); rows per capture 19.4 vs 225.0 and 232.8 (draw-nolayout: 122.3). Swap windows median 13 vs 14, 96.5 vs 107.8 and 109.8 rows per capture, unresolved:overlap.
design: flag hero.accent:draw-nolayout-full = draw-nolayout + `transition: none` on .drawingIn; width set once at the draw-in start (1 layout frame per cycle). Look change: the text after the word jumps instead of gliding. No same-look layout-free width exists (text is in flow).
report: results/accent-draw-nolayout/full-swap-report.{md,json} built by swap-report from the r1 and r2 artifacts (cancelled r3 skipped the report jobs); summary-full.json.
open: hero-exit Layout per frame and pixel numbers (accent-nolayout-measure); user look review.
writes outside graph: .github/workflows/webkit-sim.yml (FW token), lean/Fw/Parts/FootprintData.lean + golden/parts/footprint.gen.json (regenerated), golden/preset/v2-proved.decisions.jsonl (regenerated), results/accent-draw-nolayout/**.
read first: research/notes/2026/10-2x-accent-draw-nolayout.md (last section), lean/Fw/Engine/StyleDiffAccent.lean
