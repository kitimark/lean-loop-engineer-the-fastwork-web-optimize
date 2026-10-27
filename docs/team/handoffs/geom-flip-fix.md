Branch: worktree-wf_af4864bd-e6c-1 (CI branch ci/geom-flip-fix). Worktree: .claude/worktrees/wf_af4864bd-e6c-1
Last commit: a54d893b8 (push 3 of 3, the last; run id: pnpm -s fw ci wait --branch ci/geom-flip-fix --workflow breakpoint-gate --sha a54d893b8), state running
CI runs: 40508656325 (fb742cf55, push 2) complete success but the flip-cell steps end in `|| true`: they FAILED a cell: 640x1000 m=1 nav 976 px both engines (cause found: gridKnots last knot 0.9999999999999999 at h=1000, WAAPI ended K tracks neutral; fixed in a54d893b8 + test); webkit timed m=0 rows fail (lang/nav/earn, images 21 vs base 0 at 1280x800): timed leave/settle on WebKit, follow-up (task timed-take-retry domain).
Look report (same run): column/nav pixel share differs 60-98% for 0<m<=1 on both engines (m=0 equal: <=1.4%), not within a bound; cause is the image model (follow-up) plus the veil at m=1 (geom-veil-restore); cell rects are within 1 px.
Left: read run for a54d893b8, note, ledger notes, swipe-touch-v1 base vs flag (not dispatched by me; lead/dispatch), check.sh, footprint --check, review ready, dry land.
CI runs: push 1 of 3 (run id: `pnpm -s fw ci wait --branch ci/geom-flip-fix --workflow breakpoint-gate`), state running.

Verified locally: Lean check.sh green before the CI-declaration commit (re-run at the end); site vitest + tsc; gate-breakpoints tests (802); ci-paths (56); runner (3663).
Not verified: CI cell on both engines (waiting), pixel look report (CI), Safari/phone (not in scope).

What changed (A1 flex row, A3b earn transform, A3c actions box, A4 quiet leave, A3a animation time kept):
- Lean: lean/Fw/Parts/MorphGeomLook.lean (flip layout statements, leave/move op models), MorphGeomGen.lean (golden lines layout, leave, move, flipCell, flipBand) -> packages/contracts/golden/morph-geom.jsonl
- Site: apps/site/src/parts/morph.geom/{geom.css,tree.ts,tree.test.ts,tracks.golden.test.ts}
- Cell: packages/gate-breakpoints/src/flip-cell.mjs (+ cli.mjs `flip`), job `flip-cell` in .github/workflows/breakpoint-gate.yml; look report packages/premise-tests/src/look.mjs (bar/cols regions)
- CI declarations: Trigger.lean cacheWriters + row, Overflow.lean width 12, OverflowGolden.lean, apps/runner/src/land.ts read.

Findings: base keeps image height (object-fit cover), flip scales images in both axes, so image y edges differ at 0<m<1 (Lean faithful .image model is wrong there): follow-up. Timed arm cannot be pinned; scrolled timed pages never flip (A5), cell marks them skipped.
Open: remaining CI pushes (2), research note 10-2x-geom-flip-fix.md, ledger notes, review ready, dry land.
