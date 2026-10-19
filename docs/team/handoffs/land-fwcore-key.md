# land-fwcore-key handoff

## State
Branch `worktree-wf_f4119fe3-e43-1`. Round 1 builds on round 0 (469dc603, 81546e47) with these commits: ea5c35ed (Lean), 86029be8 (scan and digest tests), fcbcdb1e (strip once per link), 788db674 (premise row). Green at 788db674: check.sh (113 s), apps/runner `pnpm test` (1072 tests), contracts and ci-paths.

## What is verified
- `LandSpeed.lean`: `BinaryOfBuildReads build` is a premise about a build function, and `fwcore_nobuild_skip` takes `build`, `hb` and `hb'`. Non-vacuity is shown by `binaryOfBuildReads_satisfiable` and an `example` (states that differ at a docs path). The `cases` and `premises` docstrings have no LaTeX.
- `scripts/fwcore-build.sh` strips once per link, using the marker `fwcore.stripped`. MEASURED on macOS: a second strip changes the bytes (8a4fd2d6ff6f becomes 495249a32f9b). Without the marker, a docstring-only change (no relink) would select every fwcore user.
- The reads scan (`leanReadMisses`) covers `../` and backtick paths, `join`/`resolve` with a `"lean"` segment outside `.lake`, and lake spawns. Comments are skipped. It has two mutation tests (measure-chromium Layout.lean, apps/runner `lean/**`).
- `test/land-digest.test.ts`: 14 temp-repo tests for the fallbacks of `binDigest`, `storedDigest`, `storeDigest` and `buildClean`.

## MEASURED: docstring-only edit of lean/Fw/Console/LandQueue.lean
Setup: land pool 4, scratch runner over `checksWithReads`, `checkDeps` and `poolFor`, one run each, load 101 (before) and 177 (after).

| | before (digest unknown) | after (two-phase) |
|---|---|---|
| suites | check.sh, 8 fwcore users, reads-scan | check.sh, apps/runner, gate-breakpoints, reads-scan |
| phase-1 build | none | 0.3 s with a warm Lake cache, 22.7 s cold |
| check.sh | 55.1 s | 51.3 s |
| wall time | 444.5 s | 382.6 s (about 405 s with a cold phase 1) |
| summed check time | 1210 s | 565 s (-53%) |

- The digest stayed at 8a4fd2d6ff6f. check.sh's rebuild after phase 1 is a Lake no-op without a strip (0.7 to 2 s), so no second full build runs.
- `fw land --dry` runs no checks, so it could not measure this.

## Open items
- Accepted limits: check.sh rows, key cache, CI land lane, builder preamble. Stand-ins: the `twoPhaseChecks` glue and the digest I/O (TS, tested, not proved), and the strip-once guard (shell).

## Read first
`lean/Fw/Console/LandSpeed.lean` (after `scanDecls`), `apps/runner/src/land.ts` (`twoPhaseChecks`), `scripts/fwcore-build.sh`.
