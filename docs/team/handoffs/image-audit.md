# Handoff: image-audit (branch worktree-wf_0a8e32fb-ee5-1, land-fix round)

Read first: `research/notes/2026/10-20-image-audit.md` (Outcome, tables, "The drawn-size arm", WebKit facts).
## State
- Ranked tables (hero, morph end state, people top 12): CI run 39481653302 (3 reps, both engines); units are MiB/KiB (2^20, 2^10).
- Lean: `lean/Fw/Engine/WebKitImage.lean`, 40 theorems (`grep -c '^theorem'`). Two INFERRED premises, both named in the module doc:
  P-resample (does CoreGraphics resample each repaint; the iOS `kCGImageCachingTemporary` comment points toward cached) and
  P-repaint (the opacity/transform/backdrop/nothing rows of `repaints` are 0; only the composited-filter row cites R3).
- Drawn-size arm CLOSED as a MEASURED negative finding (note + `research/findings/ledger.json` mechanism row on the dprSized entry):
  per-copy verify 158/268 WebKit, 154/268 Chromium; people parts flip in 3-10 of 21 WebKit cells; hero unsettled; the morph 0 ppm
  pass covers only architect-1096.png (1 of 21 morph images, 4 of 7 probes). next: task image-arm-v2 (not this task).
- No image file outside snapshot/ is in main..HEAD (`git log --diff-filter=A --name-only main..HEAD`, checked). The 102 copies are
  gone; `drawn.json` (paths, sizes, sha256 only) stays. `arm build` writes copies to gitignored `apps/site/dist/aot/images-drawn`
  (sips, macOS only); the `[images-arm]` CI steps run only if the copies are in the served dist (hashFiles), so none run today.
- `switch.mjs` is an API only: no caller yet (webkit-lag-probe is not wired).
- Branch is one commit on main (squashed; main merged first).

## Verified at the final commit
- gate-breakpoints 399 pass, measure-webkit 111 pass (`pnpm test`), scripts/ci-paths 49 pass, apps/runner land-inputs + plan 69 pass
  (apps/site/dist moved out of the tree for the run), ledger-merge + premises 78 pass, `sh lean/scripts/check.sh` green.
- CI: run 39490129830 on `ci/image-audit-r2` (old `ci/image-audit` rejects a non-fast-forward push; it still holds the superseded
  history with the copies, only the user can delete it), `[images-only]`, all jobs success, images-pages/verify skipped.
- Open: a frame-time claim needs the phone; do not put `[images-arm]` in a commit body.

## Writes outside the task's graph writes
`.github/workflows/gate-gaps.yml`, `apps/runner/src/land.ts` (PACKAGE_EXTRA_READS), `lean/Fw.lean`, tests
`packages/gate-breakpoints/test/images.test.mjs` (unchanged this round), `packages/measure-webkit/test/images-switch.test.mjs`,
`research/findings/ledger.json` (one mechanism row on the dprSized entry). The graph still lists `apps/site/public/images-drawn/**` as a write; nothing uses it now.
TS stand-ins (no Lean golden): `reduce.mjs`, `table.mjs` (ranking, waste ratio), the ladder rows in `arm-build.mjs`.

## Land-fix round (land run 39495702143 refused two legs)
- suites-a: `packages/gate-breakpoints` now declares `"@fw/visual-diff": "workspace:*"` (package.json, pnpm-lock.yaml via
  `pnpm install --lockfile-only`); `src/images/verify.mjs` imports `@fw/visual-diff/src/{engines,diff,verdict}.mjs`, `pages.mjs` resolves
  the CLI with `import.meta.resolve('@fw/visual-diff/src/cli.mjs')`. The land filter is `@fw/gate-breakpoints...` (lean/land-filter.txt,
  Lean `filterList`), so the install now takes visual-diff and its deps: no Lean change. `land.ts` `workspaceDeps` adds
  `packages/visual-diff/**` to gate-breakpoints' reads, so its four hand-listed visual-diff files in PACKAGE_EXTRA_READS were removed.
  Reproduced in a clean clone: `pnpm install --offline --frozen-lockfile --filter "@fw/gate-breakpoints..."` then the image tests pass (24).
- playwright-webkit: `cancelled-same-origin-0` is `packages/e2e-preview/src/suite.mjs:110` (`noiseChecks`): any failed same-origin request of a
  load fails it; the failed line is `GET /selling/.../service-strawberry.jpg Load request cancelled` in the compare page's original (snapshot)
  frame. The branch changes no file that load reads (`git diff main...HEAD` has no snapshot/, packages/e2e-preview, apps/console-api,
  fixture/site path); a lazy image in flight cancelled by a frame navigation is the race the suite already documents (suite.mjs:139, :339).
  Same leg passed on the land runs 39495148083, 39494253388 and 39493043079 (same suite code). Result: see the CI lines below.
