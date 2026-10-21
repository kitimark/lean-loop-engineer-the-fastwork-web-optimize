# smoothness-probe handoff (measure-engineer)

State: branch `worktree-wf_acae42f5-f34-1`, last commits add Lean metrics, TS twin, Part A tables, the cadence lane and the results. CI branch `ci/smoothness-probe`.
Read first: `research/notes/2026/10-2x-smoothness-probe.md` (answer), then `docs/team/tools/smoothness-probe.md` (how to run).

Verified
- Lean `Fw.Gate.Smooth` + golden `packages/contracts/golden/gate/smooth.jsonl` (61 lines); `sh lean/scripts/check.sh` green; `reduce.mjs` replays the golden.
- gate-breakpoints tests, `node --test scripts/ci-paths.test.mjs`, `node scripts/ci-paths.mjs --check`, land-inputs test green at the last commit.
- Part A: `results/smoothness-probe/continuity.table.*` (45 trajectory runs, MEASURED, run ids per row).
- Part B: runs 39580977630, 39583122954, 39585007706 (workflow `smoothness`, 7 job samples per width); table `results/smoothness-probe/cadence.table.*`.

Finding: only 390 hero differs. The rewrite has an 83 ms frame at scroll 672 px in every rep (original 33 ms); render work, 12 vs 6 software image decodes of 15 ms or more in the traced reps (INFERRED cause). The preset does not fix it. Everything else is inside the A/A spread.

TS stand-ins (not golden-checked): `extract.mjs`, `table.mjs` (ideal-curve construction), `curveOf`, `launch.mjs`, `cadence.mjs`, `trace.mjs`, `cadence-table.mjs` (grouping; verdicts come from `reduce.mjs`).
Out-of-graph edits: `lean/scripts/check.sh` (one job line), `lean/Fw/Ops/LakeJobsGen.lean` (generated), `lean/Fw/Ci/Trigger.lean` beyond my row (`ci_triggers` entry, 3 `cacheWriters`, `#guard` lists, smooth.jsonl in the lean.yml inputs).

Open
- Which images decode twice at 390 px near 672 px scroll, and why (rewrite vs original): needs a trace with image URLs; start from the traced reps of `smoothness-390-*`.
- WebKit cadence not run: Linux WebKit software frames are about 150 ms; a macOS leg needs a measured-p90 row in `Fw.Ci.Pool.Caps`.
- Phone check of the 390 hitch is out of scope (user-booked session only).

Conventions: push `ci/smoothness-probe` with `[ci:smoothness]` and `[trajectory preset=v2-proved widths=390,1280]` in the commit message; a newer push marks older runs stale. Download artifacts with `gh run download <id> -D <dir>/<id> -p 'smoothness-*'`, build tables with `cli.mjs cadence --runs <dir> --out results/smoothness-probe`.
