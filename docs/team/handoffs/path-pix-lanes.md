# path-pix-lanes handoff (measure-engineer)

- Branch: `worktree-wf_b9782b57-981-1` (CI branch `ci/path-pix-lanes`); worktree `.claude/worktrees/wf_b9782b57-981-1`.
- Last commit: 90bdc8e3 (dispatch 4, main merged).
- CI runs (4 dispatches max, 4 used):
  - 39778557659 (d1, 1aa0944d): chromium 1+2 success; sim 2 success (27 cells, 17 L, 10 invalid); sim 1 failed (tab lost).
  - 39786950659 (d2, bf0e91d6): chromium 1+2 success (A/A 29 E; P 28 E 1 L, identical to d1); sim 1 and 2 FAILED by the 45 min step timeout, no cells (manifest was written only at the end). vm 2 got through A, A2 and 5 of 6 P arms in 45 min (runner load average 72); vm 1 lost ~20 min to two failed A attempts (simctl screenshot failed, runAsync timed out).
  - 39797455671 (d3, 39200598): chromium 1+2 success (identical to d1/d2); sim 1 success: A/A 27 cells (0 E, 15 L, 12 invalid), P 13 cells (7 L, 6 invalid); sim 2 FAILED in "Tool and runner facts" (`simctl list runtimes` aborted, exit 134, CoreSimulator not up yet). Time: A 11 min (one failed attempt), A2 7 min, P arms 1-4 min each. Causes read from the FRAME_A2 strips: the headline word differs (the chain is at another phase when the timers are held: held after a 6 s settle), the avatar stack order and the demo's typed text differ (JS motion on rAF time), and screens of offsets 2 and 7 are not stable within one load (sameA and sameB false).
  - 39805943152 (d4, 90bdc8e3, the last dispatch): queued. Changes over d3: no settle before the timer hold (headline phase), videos paused at 0, shoot until two captures agree (max 6), `tries`/`video` per row, the facts step tolerates a simctl abort, deadline 34 min.
- Local checks: measure-webkit 335 (+ new tests) and measure-chromium 64 pass through the slot; runner test has 1 failure unrelated to this task (slot-span.test.ts "a 40 s wait against a near-zero median" came with main). Not yet run on the final commit: check.sh, runner tests, dry land.
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
