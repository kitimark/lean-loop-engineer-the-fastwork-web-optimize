# path-pix-lanes handoff (measure-engineer)

- Branch: `worktree-wf_b9782b57-981-1` (CI branch `ci/path-pix-lanes`); worktree `.claude/worktrees/wf_b9782b57-981-1`.
- Last commit: bf0e91d6 on `ci/path-pix-lanes` (dispatch 2); later commits on the branch follow it.
- CI runs: 39778557659 (dispatch 1, commit 1aa0944d): chromium 1 and 2 success, sim 2 success, sim 1 FAILED (Safari tab lost after arm A: Runtime.evaluate timeout). 39786950659 (dispatch 2, commit bf0e91d6): queued. At most 4 dispatches; 2 used.
- Simulator lane in dispatch 1 (vm 2): A/A 27 cells 0 E, 17 L, 10 invalid (repeat captures of one load differ: P4 fails at offsets 1307, 3269+); the frame diff was not recorded. Dispatch 2 adds: wait for images near the fold, double freeze, per-arm retry after reconnect, `frames` diagnostics (whole-frame diff bbox, `strips/FRAME_A2_<i>.png` thumbnails) in cells.json.
- Chromium lane result (run 39778557659, both jobs identical): frames 430x932 (beginFrame screenshots are in CSS px, page dpr 3), 6 declared layers, 9 offsets; A/A 29 cells all E; P 29 cells, 28 E and 1 L (hero.deck_article offset 0: 2 px inside and 1 outside differ by 1 level).
- Later commits (after 1aa0944d): handoff, `apps/runner/src/land.ts` PACKAGE_EXTRA_READS (land-inputs test asked for them). Runner tests 2493 pass; measure-webkit 335 and measure-chromium 64 pass; check.sh green.
- Verified locally: 12 node tests (`packages/measure-webkit/test/pathpix*.test.mjs`), `scripts/ci-paths.mjs --check`, `scripts/ci-paths.test.mjs` (54), steps lint, wallclock lint. Queued via slot, not yet read: measure-webkit, measure-chromium, runner tests; `lean/scripts/check.sh`.
- Open: no Docker daemon here, so the Chromium driver (`packages/measure-chromium/src/pathpix.mjs`) has its first real run on CI; on a failure read `error.json` in the artifact `path-pix-chromium-<run>`. Calibration cells (A/A and P per lane) and the research note `research/notes/2026/10-2x-path-pix.md` are written after the run. Sim slot token 9bec9c5c-cf3 (owner path-pix-lanes) to release if still held.

## What exists
- Lean: `lean/Fw/Gate/PathPix.lean` (offsets, span/mask, rawOf, golden `packages/contracts/golden/gate/path-pix.jsonl`); CI table rows for `path-pix.yml` in `lean/Fw/Ci/{Trigger,Intent,Overflow,Steps}.lean`, `Pool/Caps.lean`, `lean/Fw/Ops/LakeJobsGen.lean` (regenerated), goldens `packages/contracts/golden/ci/*.jsonl`.
- Simulator lane: `packages/measure-webkit/src/pathpix-{cli,webkit,page,analyze,png}.mjs`, twin `pathpix.mjs`.
- Chromium lane: `packages/measure-chromium/src/pathpix{,-host,-pure}.mjs` (driver in container, analysis on host with measure-webkit `analyzeLane`).
- Workflow `.github/workflows/path-pix.yml`: jobs guard, site, sim (vm 1,2), chromium (run 1,2), report; token `[ci:path-pix]` in the commit message.

## Conventions
- Never hand-edit generated files; regenerate from Lean (`node scripts/ci-paths.mjs --write`, golden runners) and `--check`.
- Findings so far (local Simulator debug run, not a result): viewport 430x775 dpr 3; A vs A2 (two loads) showed L cells in left hero cards before the image-decode wait was added; `?fwl=` searches are not prerendered, so P arms client-render while A hydrates (state in the note).
- Read first: the task block in `docs/team/work-graph.json` (path-pix-lanes), then `lean/Fw/Gate/PathPix.lean`.
