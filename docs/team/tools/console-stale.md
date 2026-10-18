# console-stale: a running service must not lag main

Incident: console-api ran code from 04:12 while `workflow-claim` (21c8c42) landed at 04:48; workflow runs stayed
unbound in the ready lane for hours until a manual restart. A process reads its files once, so nothing told the lead.

Rule (Lean `lean/Fw/Obs/Stale.lean`, proved). Commit times are not used: `fw land` builds the merge commit with
`commit-tree` before its checks and fast-forwards main 23-89 s later (MEASURED over 12 lands), so `%ct` predates the
moment main moved. Each service has a base commit of `main`; an input is *changed* iff
`git log --first-parent <base>..main -- <path>` is non-empty. A service is stale iff some input is changed
(`Svc.stale_iff`); the alert lists exactly the changed paths (`Svc.mem_changed`); a restart records the current main,
the range is empty, nothing is changed (`Svc.judge_head_not_stale`, `Svc.restart_clears`). `obs.health` raises
`svc.stale` (subject = service name, detail `changed on main since its commit: <paths>`) exactly for stale services
(`Fw.Obs.Health.svcStale_iff`).

Two services, two bases (`Stack`):
- console-api: base = HEAD at its start, written to `.fw-console/api.json` (`{port, pid, commit, startedAt}`).
- fwcore: base = the commit the binary `lean/.lake/build/bin/fwcore` was built from, recorded next to it by
  `sh scripts/fwcore-build.sh` (`fwcore.commit`). A land does not rebuild the main checkout's binary, so restarting
  console-api leaves fwcore stale (`Stack.restart_without_build_stale`); a rebuild at main clears it
  (`Stack.rebuild_clears`). Without a record, the newest first-parent commit at or before the binary's mtime is the base
  (stated PREMISE: main moves up to 89 s after commit time, so a change in that window can be missed).

Measurement (TS, no decision): `apps/runner/src/watch-svc.ts` runs one `git log -1 --first-parent --format=%H
<base>..main -- <path>` per input group of `SVC_INPUTS` and passes the Bool. A failed call carries the previous value
forward and marks `svcs` stale. console-api also serves `service` in `GET /api/service` and `GET /api/health`.

What you do: when `fw watch` shows `svc.stale fwcore ...`, run `sh scripts/fwcore-build.sh`; for `svc.stale console-api
...`, stop console-api by the pid in `.fw-console/api.json` and start it again. Nothing is killed or restarted
automatically. The web dist is read per request and needs no restart.

Not done: `fw land` prints no restart hint; the alert appears on the next watch check.
Tests: `apps/runner/test/watch-svc.test.ts` (fake runner; real git with commit-tree at T-1 min, start at T, ff at T+1
min; fwcore restart/rebuild; the rule through the real fwcore), `apps/console-api/test/health.test.ts`, Lean golden
rows in `lean/Fw/Obs/Golden.lean`.
