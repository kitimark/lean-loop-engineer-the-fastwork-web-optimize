# Handoff: image-audit (branch worktree-wf_0a8e32fb-ee5-1, round 2)

Read first: `research/notes/2026/10-20-image-audit.md` (Outcome, tables, "The drawn-size arm", WebKit facts).
## State
- Ranked tables (hero, morph end state, people top 12): CI run 39481653302 (3 reps, both engines); units are MiB/KiB (2^20, 2^10).
- Lean: `lean/Fw/Engine/WebKitImage.lean`, 40 theorems (`grep -c '^theorem'`). Two INFERRED premises, both named in the module doc:
  P-resample (does CoreGraphics resample each repaint; the iOS `kCGImageCachingTemporary` comment points toward cached) and
  P-repaint (the opacity/transform/backdrop/nothing rows of `repaints` are 0; only the composited-filter row cites R3).
- Drawn-size arm CLOSED as a MEASURED negative finding (note + `research/findings/ledger.json` note row on the dprSized entry):
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
- CI: run RUN_ID_PENDING on `ci/image-audit` with `[images-only]` (audit jobs only, reordered setup-pnpm steps): see the note.
- Open: a frame-time claim needs the phone; do not put `[images-arm]` in a commit body.

## Writes outside the task's graph writes
`.github/workflows/gate-gaps.yml`, `apps/runner/src/land.ts` (PACKAGE_EXTRA_READS), `lean/Fw.lean`, tests
`packages/gate-breakpoints/test/images.test.mjs` (unchanged this round), `packages/measure-webkit/test/images-switch.test.mjs`,
`research/findings/ledger.json` (one note row). The graph still lists `apps/site/public/images-drawn/**` as a write; nothing uses it now.
TS stand-ins (no Lean golden): `reduce.mjs`, `table.mjs` (ranking, waste ratio), the ladder rows in `arm-build.mjs`.
