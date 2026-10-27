# geom-look-fade handoff
Branch: worktree-wf_a3cf32ea-bfb-1. Worktree: .claude/worktrees/wf_a3cf32ea-bfb-1. CI branch: ci/geom-look-fade (3 pushes used; the branch tip on origin is 7775f52b4, later commits are not measured).
CI runs: 40585096601 (push 1, no marker, every workflow skipped), 40585231399 (push 2), 40590730537 (dispatch, WebKit flip-cell cancelled at the timeout), 40594241212 (push 3). Before: 40553185213.

State: code, measurement and note done and committed.
- Lean: lean/Fw/Parts/MorphGeomLookRule.lean (pixel rule, pixel range, share, track value, count, scroll, platform fade, settled); golden `look*` lines in packages/contracts/golden/morph-geom.jsonl.
- JS stand-in: packages/premise-tests/src/look-rule.mjs, checked against the golden by test/look-rule.test.mjs (14 tests; package 17). Element attribution is reporting only.
- Harness: packages/premise-tests/src/look.mjs (fade on base, scrollY and track m asserted, PNGs and element table, real tween for timed m=1, timed Chromium only, 22 min budget, always exit 0).
- Results: research/notes/2026/10-2x-geom-look-fade.md, results/geom-look-fade/ (table-*.md, owners.md, look-summary.json), ledger note (task geom-look-fade).
- Also edited outside the task writes: .github/workflows/breakpoint-gate.yml (upload look/*/img), apps/runner/src/land.ts (premise-tests reads the golden), lean/Fw/Ci/Trigger.lean + golden/ci/triggers.jsonl.

Result: Chromium on page share at m=1 0.056-0.423 -> <= 0.0284 (641x700, picture footprint, geom-image-model round 2) and <= 0.0025 elsewhere; mid m nav/cols still 0.02-0.35 (nav-earn, nav-actions, footer blur, column images, nav.bar.1.0).

Open:
- Timed m=0 fix (copy the flip arm's is-on-dark onto base, 900 ms wait) is the last two commits and is NOT measured on CI: the next gate run shows it (look/timed, expect m=0 about 0 and m=1 tween verified at all bands).
- WebKit 'on' has 2 JSONs of 3 (third job cancelled at the 60 min timeout, caused by WebKit timed, now dropped); WebKit flip verify A4 flaked at 11 of 12 bands in run 40585231399 (baseline passed).
- WebKit timed: task timed-m0-webkit. Mid-m timed rows are skipped by design.
- look-rule.mjs and elementTable are a JS stand-in for decisions Lean states (pixel, range, share); element attribution has no Lean rule.
Conventions: a push runs breakpoint-gate only with `[ci:breakpoint-gate]` in the head commit message. Artifacts: flip-cell-<engine>/premise-tests/out/look/<on|timed>/ (JSON and img/). Local debug: FW_SITE_DIST=<a dist with morph.geom> CHROME_PATH=<Chrome> node src/look.mjs --bands 1280x800 --ms 0,1 --images none.
Read first: research/notes/2026/10-2x-geom-look-fade.md, then look.mjs.
