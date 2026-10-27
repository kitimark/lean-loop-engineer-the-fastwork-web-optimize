# geom-look-fade handoff
Branch: worktree-wf_a3cf32ea-bfb-1. Worktree: .claude/worktrees/wf_a3cf32ea-bfb-1. CI branch: ci/geom-look-fade, 4 of 4 pushes used (tip 0f3242fb7, lanes breakpoint-gate + lean); no push left. Last commit: see git log (results/note/ledger update after run 40599995604).
CI runs: 40585096601 (push 1, skipped), 40585231399 (push 2), 40590730537 (dispatch, WebKit cancelled), 40594241212 (push 3), 40599995604 (push 4, success, all jobs). Before: 40553185213.

State: code, measurement and note done and committed.
- Lean: lean/Fw/Parts/MorphGeomLookRule.lean (pixel rule, pixel range, share, track value, count, scroll, platform fade, settled); golden `look*` lines in packages/contracts/golden/morph-geom.jsonl.
- JS stand-in: packages/premise-tests/src/look-rule.mjs, checked against the golden by test/look-rule.test.mjs (14 tests; package 17). Element attribution is reporting only.
- Harness: packages/premise-tests/src/look.mjs (fade on base, scrollY and track m asserted, PNGs and element table, real tween for timed m=1, timed Chromium only, 22 min budget, always exit 0).
- Results: research/notes/2026/10-2x-geom-look-fade.md, results/geom-look-fade/ (table-*.md, owners.md, look-summary.json), ledger note (task geom-look-fade).
- Also edited outside the task writes: .github/workflows/breakpoint-gate.yml (upload look/*/img), apps/runner/src/land.ts (premise-tests reads the golden), lean/Fw/Ci/Trigger.lean + golden/ci/triggers.jsonl.

Result: Chromium on page share at m=1 0.056-0.423 -> <= 0.0284 (641x700, picture footprint, geom-image-model round 2) and <= 0.0025 elsewhere; mid m nav/cols still 0.02-0.35 (nav-earn, nav-actions, footer blur, column images, nav.bar.1.0).

Run 40599995604 (MEASURED): timed m=0 fix works (nav <= 0.0026, page <= 0.0002; 768x1024 page 0.0101 = column3.img0 picture, same in look/on); m=1 tween verified at 12 of 12 bands (nav 0.0004-0.0042, page <= 0.0051); Chromium on equal to runs 1-3; WebKit on has 3 JSONs (runs 1, 3, 4) equal at m=1; flip cell 48/48 and verify A3a/A4/A5 12/12 on both engines, WebKit A4 flake did not recur (1 in 3 WebKit runs).
Open:
- WebKit timed: task timed-m0-webkit. Mid-m timed rows are skipped by design.
- Site causes found (new tasks): nav.bar.1.0, nav-earn, nav-actions, footer blur, column images, 641x700 picture footprint (geom-image-model r2).
- look-rule.mjs and elementTable are a JS stand-in for decisions Lean states (pixel, range, share); element attribution has no Lean rule.
- Regenerating tables needs the downloaded artifacts (flip-cell-<engine> of each run); the generator was a scratch script, not committed.
Conventions: a push runs breakpoint-gate only with `[ci:breakpoint-gate]` in the head commit message. Artifacts: flip-cell-<engine>/premise-tests/out/look/<on|timed>/ (JSON and img/). Local debug: FW_SITE_DIST=<a dist with morph.geom> CHROME_PATH=<Chrome> node src/look.mjs --bands 1280x800 --ms 0,1 --images none.
Read first: research/notes/2026/10-2x-geom-look-fade.md, then look.mjs.
