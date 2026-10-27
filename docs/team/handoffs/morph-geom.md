branch: worktree-wf_e3f8d34f-d4e-1; worktree: .claude/worktrees/wf_e3f8d34f-d4e-1
last commit: see git log (the handoff's own commit); CI runs: none (no push spent)
state: partial
verified:
- check.sh green (slot, after regenerating FootprintRows/footprint-diff); dry land with --allow apps/runner/src/land.ts --allow lean/Fw/Parts/FootprintRows.lean ends VERDICT dry morph-geom; without --allow it ends VERDICT scope morph-geom (those 2 files are outside the task writes).
- runner land-inputs 73/73 and land-scope 17/17 (run directly after the land.ts reads edit), ci-paths 56/56, site test 162 pass.
- apps/site tracks.golden.test.ts (3 tests) and driver.test.ts (4) pass: all 653 golden sample lines within 1e-6.
- MorphGeomCounts.lean compiles; net-bytes theorems proved by decide +kernel.
done:
- Part apps/site/src/parts/morph.geom (tracks, driver, tree, geom.css, index.tsx, part.json), mounted in Nav, registered
  (registry/index.ts, footprint regenerated, look-change candidates + ledger row n=91, preset goldens regenerated).
- Memory decision in research/notes/2026/10-2x-morph-geom.md (veil fold first; level 0 vs 2 table).
open:
- Simulator census run for the faithful morph-frame layers (levels 1, 2 are INFERRED); then fold the veil into D in Lean layers/anims.
- Premises in lean/Fw/Ops/Premise.lean + packages/premise-tests pages (CA timing, nested cornerRadius, backdrop under masks, accelerated set).
- Per-band look premise (11 m points, both engines); breakpoint gate; Chromium 3 runs and webkit-sim 3 VMs.
- earnClip/earnLabel and backdropClip/Kb/Ub wrappers; measured layout sizes into the builder; composed-to-anims lemma.
- Browser check of geom.css (actions/logo translate resets, G top -4px) never run in a browser.
conventions: tracks.ts restates Lean in floats; change Lean `anims` and regenerate morph-geom.jsonl first, then the TS.
read first: research/notes/2026/10-2x-morph-geom.md, then tracks.ts and driver.ts.
