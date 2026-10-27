# geom-page-diff handoff
Branch: worktree-wf_321cb628-e41-1 (no CI branch: no push made). Worktree: .claude/worktrees/wf_321cb628-e41-1. Base a16afddcc; the final commit is the branch tip.
CI runs: none of my own. Read run 40553185213 (breakpoint-gate, ci/geom-veil-restore): artifacts flip-cell-chromium, flip-cell-playwright-webkit (look JSON only, no images), site-dist.

State: investigation done. Cause (CONFIRMED by source, MEASURED by numbers and a local run): the look report's base arm pins m on the nav only
(packages/premise-tests/src/look.mjs:19-27, 66-71) and never writes the platform fade `--morph-fade` that the tween driver writes
(apps/site/src/parts/morph.tween/driver.ts:117-121); the flip arm's platform tracks fade it to opacity 0 (apps/site/src/parts/morph.geom/tracks.ts:177-178).
At the page bottom the platform fills the viewport, so ~75-100 % of the pixels outside the nav box differ: a harness artefact in the base arm; the flip is right.
Local WebKit debug run (not a result): with the fade written on base, page share at m=1 drops 0.090/0.423 to 0.001/0.000 (390x844, 1920x1080).

Verified: numbers per band from the four look JSONs (results/geom-page-diff/bands.md, table.mjs); diff images as text maps in results/geom-page-diff/local-debug/maps.txt (PNGs are refused by the render guard, not committed).
Other findings: look/timed measures nothing (0 differences; geom-timed branch installs no data-fw-morph observer, index.tsx:65-82); base scroll can land short
(local 1280x800, scrollY 6074 vs 7794; CI m=0 equal 24 of 24); 641x700 Chromium nav 0.031 unexplained.
No Lean lemma: no decision rule is the cause (glue code). Writes outside the task's graph writes: results/geom-page-diff/probe.mjs and table.mjs are inside results/geom-page-diff/**; none outside.

Open: fix task geom-look-fade (look.mjs writes the platform fade on base from generated constants, asserts equal scrollY, re-measure on CI over >= 3 jobs; timed look starts a real tween or is dropped).
Read first: research/notes/2026/10-2x-geom-page-diff.md. Ledger note: research/findings/ledger.json (task geom-page-diff).
Reproduce locally: download site-dist of run 40553185213, `FW_SITE_DIST=<dir> node results/geom-page-diff/probe.mjs --engine playwright-webkit --out <dir>` (needs pnpm install of @fw/visual-diff and @fw/gate-breakpoints).
