# path-pix-lanes handoff (measure-engineer)

- Branch: `worktree-wf_b9782b57-981-1` (CI branch `ci/path-pix-lanes`); worktree `.claude/worktrees/wf_b9782b57-981-1`.
- Last code commit: 90bdc8e3 (dispatch 4). The handoff and note commit follows it; `git log -1` names it.
- CI runs (4 dispatches used of 4, no more allowed):
  - 39778557659 (d1, 1aa0944d): chromium 1+2 success; sim 2 success (27 cells, 17 L, 10 invalid); sim 1 failed (Safari tab lost).
  - 39786950659 (d2, bf0e91d6): chromium 1+2 success; sim 1 and 2 failed at the 45 min step timeout, no cells (manifest was written only at the end; load average 72).
  - 39797455671 (d3, 39200598): chromium 1+2 success; sim 1 success (A/A 27 cells: 0 E, 15 L, 12 invalid; P 13 cells: 7 L, 6 invalid); sim 2 failed in "Tool and runner facts" (`simctl list runtimes` abort, exit 134).
  - 39805943152 (d4, 90bdc8e3): chromium 1+2 success; sim 1 success (A/A 27 cells: 0 E, 21 L, 6 invalid; P 13 cells: 1 E, 8 L, 4 invalid); sim 2 failed (no Safari tab listed in 240 s, infra).
- Verified: Chromium lane in 4 runs x 2 jobs, identical (A/A 29 cells all E; P 28 E, 1 L = hero.deck_article offset 0, delta 1). Simulator lane: A/A is not E on vm 1 (two runs); causes in the note. Local through the slot: lean check.sh green, runner tests 2548 pass (one flaky `slot-span.test.ts`, unrelated), measure-webkit 336, measure-chromium 64, `ci-paths.mjs --check`, ci-paths tests 54, steps lint.
- Open: no second Simulator VM result (vm 2 failed in d3 and d4, infra); Simulator A/A needs deterministic page JS motion (rAF virtualisation, follow-up for `census-load-variance`); text layers under fractional translate stay L until the user sees strips; CA blur is Q. Strips are CI artifacts (`path-pix-webkit-<vm>`, `path-pix-chromium-<n>`, retention 30 days), not committed (Fastwork renders).
- Read first: `research/notes/2026/10-2x-path-pix.md` (results, causes, follow-ups), then `lean/Fw/Gate/PathPix.lean`.

## What exists
- Lean: `lean/Fw/Gate/PathPix.lean` (offsets, span/mask, rawOf; golden `packages/contracts/golden/gate/path-pix.jsonl`); CI table rows for `path-pix.yml` in `lean/Fw/Ci/{Trigger,Intent,Overflow,Steps}.lean`, `Pool/Caps.lean`, `lean/Fw/Ops/LakeJobsGen.lean` (regenerated), goldens `packages/contracts/golden/ci/*.jsonl`.
- Simulator lane: `packages/measure-webkit/src/pathpix-{cli,webkit,page,analyze,png}.mjs`, twin `pathpix.mjs`. Manifest written after every arm; a P arm only at offsets where arm A shows the layer (`inViewPositions`, TS stand-in composed from the golden-checked mask); shoot until two captures agree (max 6); deadline 34 min.
- Chromium lane: `packages/measure-chromium/src/pathpix{,-host,-pure}.mjs` (driver in container, analysis on host with measure-webkit `analyzeLane`). Software compositing, secondary.
- Workflow `.github/workflows/path-pix.yml`: jobs guard, site, sim (vm 1,2, `P_LAYERS` split per VM), chromium (run 1,2), report; token `[ci:path-pix]` in the commit message.
- `apps/runner/src/land.ts` PACKAGE_EXTRA_READS (land-inputs test asked for the pathpix reads).

## Conventions
- Never hand-edit generated files; regenerate from Lean (`node scripts/ci-paths.mjs --write`, golden runners) and `--check`.
- TS stand-ins: `inViewPositions` (capture list), the shoot-until-stable loop, the PNG crop/marker code; no Lean golden covers them.
- CI wait: `pnpm -s fw ci wait --branch ci/path-pix-lanes --workflow path-pix`.
