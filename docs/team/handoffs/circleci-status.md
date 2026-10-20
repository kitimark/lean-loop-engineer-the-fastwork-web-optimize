# circleci-status handoff

State: branch worktree-wf_d9735227-281-2, see `git log -1`. CircleCI health card + router input, mirrors gh-status.

What exists
- `lean/Fw/Obs/CiStatus.lean`: verdict (healthy/degraded/unknown) per lane, freshness, `usable` router input, 14 golden cases,
  theorems per branch (verdictOf_degraded, _healthy_iff, _unknown_keeps, _unknown_fresh, usable_iff/_stale/_not_healthy,
  arm_ignores_macos). Golden: `packages/contracts/golden/obs/ci-status.jsonl` (regenerate: `cd lean && lake env lean --run scripts/ObsGolden.lean`).
- `apps/console-api/src/ops/ci-status.ts`: parse of `https://status.circleci.com/api/v2/summary.json` (no token), poll-on-demand
  cache (one read per 120 s, 429/503 Retry-After honoured, no timer), TS stand-in of the verdict (golden-checked, test/ci-status.test.ts).
- Route `GET /api/ci-status` (ops/routes.ts): `arm.usable` / `macos.usable` are the router inputs; `fresh`, `readAt`, `states`, `incidents`.
- `apps/console-web/src/Health.tsx`: `CiCard` next to `GhCard` (polls the route every 60 s; the route reads the page at most every 120 s).

Verified: console-api test (594), console-web test+typecheck, ci-paths test, land-inputs test, lean check.sh (see report).

Conventions: Arm components = Docker Jobs, Machine Jobs, Pipelines & Workflows, CircleCI API (no Arm-only component exists; INFERRED).
Statuspage documents no rate limit; page sends cache-control max-age=10.

Writes outside the task's graph writes: `lean/Fw.lean` (1 import line), `lean/scripts/ObsGolden.lean` (runs the new golden).

Open / TS stand-ins
- Verdict is a TS stand-in (Fw/Wire is outside this task): add an fwcore op `obs.ciStatus` and call it from ci-status.ts.
- The land router (task `route-*`, lean/Fw/Ci/Route*.lean) should read `GET /api/ci-status` `arm.usable`; the poller serves the
  cache only while the console runs.
- Health card shows only after the first `fw watch` health line (same placement as GhCard).
