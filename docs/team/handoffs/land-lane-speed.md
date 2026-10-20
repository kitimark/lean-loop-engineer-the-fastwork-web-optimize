# land-lane-speed handoff

State: branch worktree-wf_753f9266-a12-1. The land lane (`.github/workflows/land.yml`) is a matrix of four legs; Lean decides the split.

Done and verified
- `lean/Fw/Console/LandLegs.lean`: `shardA`/`shardB`, `pickFor`, `engineRuns`, `legsOk`; theorems for each branch; golden `packages/contracts/golden/console/land-legs.jsonl`
  and `lean/land-legs.txt` (the matrix), written by `lean/scripts/LandLegsGolden.lean`, checked by a `check.sh` stage. `sh lean/scripts/check.sh` green.
- fwcore ops `console.landLeg`, `console.landLegs` (`lean/Fw/Wire/Console.lean`).
- `apps/runner/src/checks.ts`: `--leg <name>` (needs `--tier remote`; digest stays over the whole tier; prints `LANE leg=.. engine=.. checks=..`).
  `apps/runner/src/land-remote.ts`: `legsPass` vetoes a `success` run with a leg that did not pass. Tests: `apps/runner/test/land-legs.test.ts`;
  `pnpm test` in apps/runner green (46 files), `node --test scripts/ci-paths.test.mjs` green.
- Probes (MEASURED, ids in `research/notes/2026/10-20-land-lane-speed.md`): before 39345070296 / 39342064962, after 39343920706, 39344448520.
- TS stand-ins: none beyond replays of Lean goldens (`legsPass`, `--leg` filter call the fwcore ops).

Open
- Webkit leg is the critical path (setup 44-51 s, install 27-78 s, suite 58-72 s). A main-seeded webkit cache would cut 40-50 s.
- WebKit `compare/page-errors` flaked once (2 cancels, expects 0 or 13), run 39343920706.
- `other` (33-102 s per land: poll granularity and landing steps) and setup-lean (38-51 s) are untouched.
- Runner queue is a larger share now (four runners per land); watch `fw watch` for queue spikes.

Conventions: matrix list in land.yml must equal `lean/land-legs.txt` (test); new legs/shards go in Lean first, then `lake env lean --run scripts/LandLegsGolden.lean`.
Read first: `research/notes/2026/10-20-land-lane-speed.md`, `docs/team/tools/land.md` (section "The lane runs as parallel legs").
