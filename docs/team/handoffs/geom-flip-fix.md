Branch: worktree-wf_af4864bd-e6c-1 (CI branch ci/geom-flip-fix). Worktree: .claude/worktrees/wf_af4864bd-e6c-1
Code at a54d893b8; 3 of 3 CI pushes used, none left
CI runs: 40508656325 (fb742cf55) green job, cell failed 640x1000 m=1 (float knot); 40512085722 (a54d893b8) success, flip cell on: 48/48 both engines; timed webkit 2/24 fail at m=0 (follow-up).
Look report: pixel share differs 57-98% for 0<m<=1 (image model, veil): not within a bound, follow-up. Note research/notes/2026/10-2x-geom-flip-fix.md, ledger note added.
Left: swipe-touch-v1 base vs flag x3 is a lead dispatch (gh workflow run chromium-counts.yml --ref ci/geom-flip-fix -f profile=swipe-touch-v1 -f runs=3 -f target=rewrite -f fw=morph.geom:on; base: -f fw=''); landing.

Verified locally: Lean check.sh green before the CI-declaration commit (re-run at the end); site vitest + tsc; gate-breakpoints tests (802); ci-paths (56); runner (3663).
Not verified: Safari/phone (not in scope); pixel look report is reported, not graded.

What changed (A1 flex row, A3b earn transform, A3c actions box, A4 quiet leave, A3a animation time kept):
- Lean: lean/Fw/Parts/MorphGeomLook.lean (flip layout statements, leave/move op models), MorphGeomGen.lean (golden lines layout, leave, move, flipCell, flipBand) -> packages/contracts/golden/morph-geom.jsonl
- Site: apps/site/src/parts/morph.geom/{geom.css,tree.ts,tree.test.ts,tracks.golden.test.ts}
- Cell: packages/gate-breakpoints/src/flip-cell.mjs (+ cli.mjs `flip`), job `flip-cell` in .github/workflows/breakpoint-gate.yml; look report packages/premise-tests/src/look.mjs (bar/cols regions)
- CI declarations: Trigger.lean cacheWriters + row, Overflow.lean width 12, OverflowGolden.lean, apps/runner/src/land.ts read.

Findings: base keeps image height (object-fit cover), flip scales images in both axes, so image y edges differ at 0<m<1 (Lean faithful .image model is wrong there): follow-up. Timed arm cannot be pinned; scrolled timed pages never flip (A5), cell marks them skipped.
Open: lead land; follow-ups geom-image-model, geom-veil-restore, WebKit timed m=0 cells, swipe-touch-v1 in cols-probe.
