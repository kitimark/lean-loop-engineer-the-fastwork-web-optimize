# smoothness-probe handoff (measure-engineer, round 3, final design round)
State: branch `worktree-wf_acae42f5-f34-1` (final commit in the report), CI branch `ci/smoothness-probe`, round-2 run 39589237987.
Read first: `research/notes/2026/10-2x-smoothness-probe.md`, then `docs/team/tools/smoothness-probe.md`.

Verified
- Lean `Fw.Gate.Smooth`: rate `verdict`, hitch count (frames over 60 ms), `hitchVerdict`, `across`/`agreeNeeded`, each OR-branch its own
  theorem; golden `packages/contracts/golden/gate/smooth.jsonl` (91 lines, regenerated from Lean); `sh lean/scripts/check.sh` green.
- `reduce.mjs` replays the golden; `test/smooth.test.mjs` (17) incl. the two-process trace fixture; ci-paths test and `--check`, `apps/runner` land-inputs test green.
- Part A: `results/smoothness-probe/continuity.table.*` per window x node x arm with run ids, plus the differs lists (45 runs, 1564 records).
- Part B: runs 39580977630, 39583122954, 39585007706, 39589237987 (10 job samples per width; need 7 of 10); trace tables from 39589237987 only
  (page-sink filter, 5 traced reps per job; 336 older traced windows are unfiltered and left out).

Finding: only 390 hero differs. The rewrite has one 83 ms frame at scroll 672 px in every rep; the hitch rule says original smoother 10 of 10
(rate rule 6 of 10, too coarse: 1 hitch per rep = 0.58 points, about the A/A spread). Cause INFERRED: 60 vs 30 decodes of 15 ms or more.
Round 3: the note has no per-flag Part A sentence (it points at the second table of continuity.table.md) and no preset claim.
FINDING FOR RE-PLAN: the v2-proved preset was empty (`fw {}`) at every cadence SHA (config hash = rewrite's in all 40 cells), so Part B
measured NO flag arm; the "cand" column is labelled "empty preset" (a second copy of the rewrite). A real flag arm needs a new run.

TS stand-ins (not golden-checked): `extract.mjs`, `table.mjs` (ideal curves, byArm medians, the `differences` rule), `curveOf`, `launch.mjs`,
`cadence.mjs`, `trace.mjs` (page sink, counts, slow rows), `cadence-table.mjs` (grouping, `traceTotals`; verdicts come from `reduce.mjs`).
Out-of-graph edits: `lean/scripts/check.sh` (one job line), `lean/Fw/Ops/LakeJobsGen.lean` (generated), `lean/Fw/Ci/Trigger.lean` beyond my row,
`.github/workflows/smoothness.yml` (`TRACE_REPS` 3 to 5). `land --dry` calls `LakeJobsGen.lean` and `check.sh` out of scope: declared extra writes.
Open (plus a cadence arm with real flags, see the finding)
- Which images decode twice at 390 px near 672 px scroll: a trace with image URLs (start from `smoothness-390-*` traces).
- Original hero rows for macOS WebKit; WebKit cadence leg is owned by smoothness-webkit-cadence (needs a measured-p90 row in `Fw.Ci.Pool.Caps`).
- Registry nodes for the people reveal and the nav morph inside the hero window; phone check of the 390 hitch (user-booked only).
Conventions: push `ci/smoothness-probe` with `[ci:smoothness]` and `[trajectory preset=v2-proved widths=390,1280]` in the commit message; wait with
`pnpm -s fw ci wait --branch ci/smoothness-probe --workflow smoothness`; download `gh run download <id> -D <dir>/<id> -p 'smoothness-*'`; tables with
`cli.mjs cadence --runs <dir> --out results/smoothness-probe` and `cli.mjs continuity --runs <dir> --out ... --engines chromium,macos-webkit --widths 390,1280`.
