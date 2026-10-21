# Handoff: webkit-cost-counters

State: branch `worktree-wf_3d6e8140-325-1`. Lean, golden, TS probe and report, CI measurement and the note are done.
Read first: `research/notes/2026/10-2x-webkit-cost-counters.md` (per-zone table, run ids, limits, open items).

## What is verified
- `lean/Fw/Measure/WkCost.lean` + `lean/scripts/WkCostGolden.lean` + `packages/contracts/golden/measure/wkcost.jsonl` (`--check`); `sh lean/scripts/check.sh` green.
- packages/measure-webkit `pnpm test` 287 pass; ci-paths 54 pass; apps/runner land-inputs 56 pass (whole runner suite 2328) after the round-2 merge.
- CI: original 3 jobs (run 39647881249), rewrite 4 jobs (39647881249, 39665776192), preset 3 jobs (39657539501). Tables in the note.

## How to run it
- Cost passes are OFF by default (`--cost off`); `--cost on` adds them, `only` skips the lag passes. No commit-token rule is landed (round 1 finding 2).
- Dispatch `webkit-sim` with `lag`, `target`, `preset`, `vms`; the lag step needs `--cost on` (one flag in `webkit-sim.yml`, not landed; a `cost` dispatch input is a follow-up).
- Download `webkit-sim-*` artifacts; `node packages/measure-webkit/src/lag/cli.mjs cost-report --original v1.json,... --rewrite r1.json,... [--preset ...]`.

## Open items
- Rewrite-arm jobs fail more often with cost passes (4 of 12 vs 0 of 3 original); cause unknown, no lag-only control.
- The 35 min sim-plan step bound is tight for lag + cost passes (Lean `SimPlan`; not touched).
- `v2-proved` is empty, so the preset arm is an A/A control; repeat once it has flags.
- Skipped-slot formula is also in `Fw.Device.Session` (task device-stats-v2): unify.
- IOSurface / slowFrame: task `xctrace-ci-probe`.

## Conventions
- Edits outside the graph write scope: `lean/Fw.lean` (import), `lean/scripts/check.sh` (golden check), `lean/Fw/Ci/Trigger.lean` and the regenerated `packages/contracts/golden/ci/triggers.jsonl` (wkcost.jsonl as a lean.yml input). `.github/workflows/webkit-sim.yml` is untouched.
- Worktree needs `pnpm install --offline --frozen-lockfile` before a push (pre-push hook runs `apps/runner/src/land.ts`).

## Round 2
- Findings 1-6 applied: cost default off (cli.mjs:25, probe.mjs lagSession), webkit-sim.yml hunks dropped, note section 5 states read-vs-commit and nominal morph end, counter renamed new-layers-per-read, main merged, counts fixed.
- Read-vs-commit and nominal-morph-end limits: note section 5. Measured SHAs: note section 2.
