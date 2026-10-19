# land-lane handoff

State: branch worktree-wf_e5423bd4-ebd-1; the land lane exists and was proved on CI with a Lean-only and a runner-only probe.

What it is
- `lean/Fw/Console/LandTier.lean`: `tier` (allowlist `remoteIds`) and `laneVerdict`; golden `packages/contracts/golden/console/land-tier.jsonl`; fwcore ops `console.landTier`, `console.landLane`.
- `apps/runner/src/checks.ts`: `fw checks --affected --base <rev> [--tier local|remote] [--list]`; selection is land.ts `selectChecks`; one `VERDICT <pass|fail|skipped> <id>` line and a `TIMING` line per check.
- `.github/workflows/land.yml`: push `ci/land-*` with `[ci:land]` in the head commit, or workflow_dispatch. Builds fwcore, then runs the remote tier.

Verified
- Lean check.sh green; runner tests (checks.test.ts, 39+ tests) green; ci-paths test green.
- CI probes: see the report (run ids, phase timings).

Open items
- Real-ledger test in apps/runner/test/incidents.test.ts fails on CI: evidence commits live on local main, origin/main is behind (only the user pushes main). The lane correctly fails.
- apps/console-api preview-facts-gen.test.ts skips when pinned objects are missing in the clone; the lane counts it as a skip and fails.
- apps/console-api crash.test.ts "a crash fails the in-flight call" failed once on the arm runner (timing); watch for a repeat.
- Possibly flaky watch.test.ts (collectAgents newest session wins) failed once on CI.
- fw land does not wait on the lane yet; no key cache (fwcore build ~3.5 min); no macOS runners.

Conventions
- TS stand-ins: land.ts selectChecks/inScope, `skippedCount` (strips ANSI, reads vitest and node:test summaries), the `fw checks` glue.
- Never hand-edit LakeJobsGen.lean or the ci goldens; regenerate with ci-paths --write and lake test -- --write-ci-trigger-golden.

Read first: lean/Fw/Console/LandTier.lean, apps/runner/src/checks.ts, .github/workflows/land.yml.
