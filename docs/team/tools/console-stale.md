# console-stale: a running service must not lag main

Incident: console-api ran code from 04:12 while `workflow-claim` (21c8c42) landed at 04:48; workflow runs stayed
unbound in the ready lane for hours until a manual restart. A process reads its files once, so nothing told the lead.

Rule (Lean `lean/Fw/Obs/Stale.lean`, proved): a service `s = (name, start, inputs)` is stale iff some input group
changed on `main` strictly after `start` (`Svc.stale_iff`); the alert lists exactly the changed paths
(`Svc.mem_changed`); a restart at a time at or after every input's last change clears it (`Svc.restart_clears`,
`Fw.Obs.Health.sStale_restart`); a restart before a change does not (`Svc.stale_of_restart_older`). `obs.health`
raises `svc.stale` (subject = service name, detail `changed since start: <paths>`) exactly for those services
(`Fw.Obs.Health.svcStale_iff`).

Measurement (TS, no decision): `apps/runner/src/watch-svc.ts`.
- console-api writes `{port, pid, commit, startedAt}` to `.fw-console/api.json` and serves the same `service`
  object in `GET /api/service` and inside `GET /api/health` (next to the latest check; the body stays `null`
  before any check).
- `fw watch` reads `startedAt` (only while that pid is alive) and runs `git log -1 --format=%ct main -- <path>` for
  each input group of `SVC_INPUTS`: console-api = `apps/console-api/src`, `packages/contracts/src`; fwcore (spawned
  by console-api, so it starts with it) = `lean/Fw`, `lean/Fw.lean`, `lean/Main.lean`, lakefile, toolchain.
  A failed git call carries the previous value forward and marks `svcs` stale.
- Time is the commit time on `main`; a service started from another worktree is judged against `main` too.

What you do: when `fw watch` shows `svc.stale console-api ...`, rebuild if lean paths changed (`cd lean && lake
build`), stop console-api by the pid in `.fw-console/api.json` and start it again. Nothing is killed or restarted
automatically (a process the runner did not start is not the runner's to kill). The web dist is read per request
and needs no restart.

Not done: `fw land` does not print a restart hint (optional in the task); the alert appears on the next watch check.
Tests: `apps/runner/test/watch-svc.test.ts` (fake clock, fake git, and the incident replayed through the real
fwcore), `apps/console-api/test/health.test.ts`, Lean `#guard`/golden rows in `lean/Fw/Obs/Golden.lean`.
