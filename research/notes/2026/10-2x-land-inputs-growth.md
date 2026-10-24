# land-inputs vitest grew with no co-runner: cause, model, fix

Status: MEASURED (per-test durations, local runs through `fw slot`, load 3.6-7); the growth history is INFERRED.
Unit: the land-inputs step (`apps/runner/test/land-inputs.test.ts`) alone. Local-machine timings; the effect on
the alert rate is read on later dry lands.

## Before: where the 35 s go

Two runs of the unmodified file (vitest `--reporter=json`, `fw slot run --kind test`), ms per test:

| test | run 1 | run 2 |
|---|---|---|
| fixture: "a change outside the inputs leaves the key ..." | 26348 | 24291 |
| real key stable between two calls | 3924 | 3889 |
| new selection is a superset (every tracked path) | 3905 | 3998 |
| PACKAGE_EXTRA_READS exercised | 1313 | 1106 |
| the other 52 tests | 1567 | 1444 |
| file | 37057 | 34728 |

One test holds 70 percent. It calls `inputKey` 1867 times on a 99-file fixture (9 checks, 226 globs): once per outsider
path and twice per glob of every check, so the calls grow with checks x globs. Each call spawned `git ls-files`
(8 ms) and ran the recursive scope test `inScope` over every file, which split all globs again for every path
(335 ns per file-glob pair on the real root; 4229 files x 368 globs = 1.0 s for the largest check).

## Cause

- Spawn per key: 1867 x 8 ms = 14.9 s of the fixture test (MEASURED: removing only the compiled scope left 16.2 s).
- Scope test per pair: pairs = files x globs summed over calls (4.6 M fixture, 6.2 M real) at 335 ns.
- Both grow with the declared reads: every new package or part adds globs, so calls and pairs grow faster than the
  tracked-file count (+6-7 percent). That the 45-60 percent step growth is this product is INFERRED: the glob history
  is not recorded per run.

## Fix

- `apps/runner/src/land-inputs.ts`: `scopeOf(globs)` splits the globs once per list (kept by list content) and
  matches by index; `trackedFiles(root)` runs `git ls-files` once per state of the index (stat identity of the index
  file, which git rewrites by rename). `inputKey` and `inScope` in `land.ts` use them. The test file
  holds the original recursion as an oracle and compares every tracked path x every check's globs, plus an exhaustive
  small alphabet; a second test shows an added or removed file is seen.

## After (same runs, alternating)

| test | before (2 runs) | globs only | globs + listing, run 1 | run 2 |
|---|---|---|---|---|
| fixture | 26348 / 24291 | 16214 | 1564 | 1582 |
| real key | 3924 / 3889 | 2047 | 1102 | 1072 |
| superset | 3905 / 3998 | - | 2826 | 2694 |
| file | 37057 / 34728 | 22668 | 7444 | 7202 |

The step falls 36 s -> 7.3 s (-80 percent). Remaining: the superset test (reads each package.json per path, 2.7 s),
hashing 21 k real files twice (1.0 s), the walks of `escapes`.

## Lean model

`lean/Fw/Obs/LandInputsCost.lean`: `cost = spawns x 8 ms + pairs x pairNs + hashed x hashUs + calls x fixed`, three
modes (orig, globs, cached). Proved: the modes are ordered (`cost_globs_le_orig`, `cost_cached_le_globs`), monotone in
pairs and calls, `callsBound` monotone in checks and globs, the kept listing spawns at most once, and the six measured
rows are within 35 percent (`rows_in_band`). Golden: `packages/contracts/golden/obs/land-inputs-cost.jsonl`, replayed
by the test file. The orig fixture row is under-predicted by 29 percent: plain node runs the same loop in 19.1 s,
vitest in 24-26 s (INFERRED: vitest's transform and instrumentation, not isolated).

## Follow-ups

- Golden generation has no script row in `lean/scripts/check.sh` (outside this task's writes): the rows were rendered
  with a scratch `main` over `rowJson`; add `LandInputsCostGolden.lean --check`.
- Superset test: read each package.json once, not per path.
- Read the effect on later dry lands: land-inputs vitest p50 in `.fw-console/timings.jsonl` after this lands.
