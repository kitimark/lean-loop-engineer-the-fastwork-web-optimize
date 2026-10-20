# Handoff: ci-telemetry

Branch `worktree-wf_784427d0-f38-1` (CI branch `ci/ci-telemetry`). State: Lean spec, producer, GitHub action + wiring,
collector, docs, first measured note are done. Read first: `docs/team/tools/ci-telemetry.md`, then
`research/notes/2026/10-20-ci-telemetry.md`.

## Verified
- Lean `Fw.Ci.Telemetry` (round trip, slow verdict reusing `Fw.Obs.Timing`), goldens `packages/contracts/golden/ci/telemetry.jsonl`.
- CI (GitHub, Linux arm64): premise-tests (2 runs), breakpoint-gate (1 run, 1 unrelated webkit smoke timeout), lean (1 run)
  upload `telemetry-<job>`; `pnpm -s fw ci telemetry github <run id>` stores them and prints the step table. Queue time
  and steps come from the in-job jobs API with `contents: read` only.
- Tests: `node --test scripts/ci-telemetry/cli.test.mjs`, `scripts/ci-paths.test.mjs`, `apps/runner` tests + tsc.
- Not run: CircleCI, webkit-sim (Simulator boot), chromium-counts (wired, the same action).

## Round 2 (fixes of the 6 review findings)
- Step keys: `keysFrom` in Lean gives a repeated step name `#1`, `#2`; `keysFrom_nodup`, `spans_steps_nodup`, golden case, #guards.
- CPU model: `parseCpuModel` (cpuinfo, then `lscpu`, then implementer/part) with a node test; the CI record 39324688269 shows the implementer/part value (taken before the lscpu ordering fix); the lscpu path awaits the next record.
- Exit backfill: `backfillExits` in the collector, always from `gh run view --json jobs`, vitest case of run 39314718340.
- Note: job counts 6, provenance of the old-producer gate and lean tables stated. Gate/lean tables stay old-producer.

## Open
- Verdicts need 3 runs per lane on the same class; run `fw ci telemetry github <id>` on new runs to build history.
- CircleCI: apply the config lines of the tool doc (circleci-pilot owns `.circleci/**`).
- Collect webkit-sim and chromium-counts once to confirm the macOS probes and the `sim-boot` span.
- Candidates to investigate: gate job body (700 to 805 s, webkit CPU-bound), gate queue time, setup-lean 5 GB lake cache.

## Conventions
- Producer never fails a job (every command but `step` exits 0 on error). Step names containing "telemetry" are dropped.
- Runner class `ubuntu24-arm64-4c` (the first gate and lean records carry the old doubled-arch class); a class change starts a new baseline.
- TS stand-ins (not checked against a Lean golden): `scripts/ci-telemetry/lib.mjs` probes and normalisation (node tests
  plus fwcore decode of its output), the collector's gh / CircleCI glue and table printer in `apps/runner/src/ci-telemetry.ts`.
- Writes outside the task graph: `apps/runner/src/land.ts` (`PACKAGE_EXTRA_READS`), `apps/runner/src/fw.ts` (dispatch),
  the five workflows, `lean/Fw/Ci/Trigger.lean` rows + regenerated `triggers.jsonl`, `lean/Fw/Wire.lean`, `lean/scripts/check.sh`.
