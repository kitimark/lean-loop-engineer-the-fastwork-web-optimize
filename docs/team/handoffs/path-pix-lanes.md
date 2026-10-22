# path-pix-lanes handoff (measure-engineer)

- Branch: `worktree-wf_b9782b57-981-1` (CI branch `ci/path-pix-lanes`); worktree `.claude/worktrees/wf_b9782b57-981-1`.
- Last commit: 1aa0944d (first CI push).
- CI runs: 39778557659 (path-pix workflow, dispatch 1 of at most 4) in progress.
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
