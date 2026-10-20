# Handoff: image-audit (branch worktree-wf_0a8e32fb-ee5-1, land-fix round)
Read first: `research/notes/2026/10-20-image-audit.md`.
## State
- Ranked tables (hero, morph end state, people top 12): CI run 39481653302 (3 reps, both engines).
- Lean: `lean/Fw/Engine/WebKitImage.lean`, 40 theorems. Two INFERRED premises, named in the module doc: P-resample (does CoreGraphics
  resample each repaint) and P-repaint (the opacity/transform/backdrop/nothing rows of `repaints` are 0).
- Drawn-size arm CLOSED as a MEASURED negative finding (note + `research/findings/ledger.json` mechanism row): per-copy verify 158/268
  WebKit, 154/268 Chromium; people parts flip in 3-10 of 21 WebKit cells. next: task image-arm-v2 (not this task).
- No image file outside snapshot/ is in main..HEAD; `drawn.json` (paths, sizes, sha256) stays; `arm build` writes copies to the
  gitignored `apps/site/dist/aot/images-drawn` (macOS only). `switch.mjs`: API only, no caller.
- gate-breakpoints 410 pass, apps/runner 1618 pass, ci-paths 49, land-inputs 55; measure-webkit 111 (round 2); CI ranked tables run 39481653302.
- Open: a frame-time claim needs the phone; no `[images-arm]` in a commit body. Old `ci/image-audit` is superseded.
## Writes outside the graph writes
`.github/workflows/gate-gaps.yml`, `apps/runner/src/land.ts` (PACKAGE_EXTRA_READS), `lean/Fw.lean`, tests
`packages/gate-breakpoints/test/images.test.mjs` (unchanged this round), `packages/measure-webkit/test/images-switch.test.mjs`,
`research/findings/ledger.json` (one mechanism row on the dprSized entry). TS stand-ins: `reduce.mjs`, `table.mjs`, the ladder rows in `arm-build.mjs`.
## Land-fix round (land run 39495702143 refused two legs)
- suites-a: `packages/gate-breakpoints` now declares `"@fw/visual-diff": "workspace:*"` (package.json, pnpm-lock.yaml via
  `pnpm install --lockfile-only`); `src/images/verify.mjs` imports `@fw/visual-diff/src/{engines,diff,verdict}.mjs`, `pages.mjs` resolves
  the CLI with `import.meta.resolve('@fw/visual-diff/src/cli.mjs')`. The land filter is `@fw/gate-breakpoints...` (lean/land-filter.txt,
  Lean `filterList`), so the install now takes visual-diff and its deps: no Lean change. `land.ts` `workspaceDeps` adds
  `packages/visual-diff/**` to gate-breakpoints' reads, so its four hand-listed visual-diff files in PACKAGE_EXTRA_READS were removed.
  Clean clone: `pnpm install --offline --frozen-lockfile --filter "@fw/gate-breakpoints..."` image tests pass (24).
- playwright-webkit: `cancelled-same-origin-0` is `packages/e2e-preview/src/suite.mjs:110` (`noiseChecks`): any failed same-origin request of a
  load fails it; the failed line is `GET /selling/.../service-strawberry.jpg Load request cancelled` in the compare page's original (snapshot)
  frame. The branch changes no file that load reads (`git diff main...HEAD` has no snapshot/, packages/e2e-preview, apps/console-api,
  fixture/site path); a lazy image in flight cancelled by a frame navigation is the race the suite already documents (suite.mjs:144, :339-341).
  Same leg passed on the land runs 39495148083, 39494253388 and 39493043079 (same suite code).
- Land probe (merge of main and the branch, `[ci:land]`) on `ci/land-image-audit-landfix`: run 39497453674, all 6 jobs success, VERDICT pass
  gate-breakpoints (suites-a), playwright-webkit leg success incl. `webkit/loopback/compare/cancelled-same-origin-0`: INFERRED flaky (an in-flight image cancelled by a frame navigation): the same code passed on 39497453674; no main-only failure observed.
