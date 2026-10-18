# console-stale: the code that RUNS must not lag main

Incident: console-api ran code from 04:12 while `workflow-claim` (21c8c42) landed at 04:48; workflow runs stayed
unbound in the ready lane for hours until a manual restart. A process reads its files once, so nothing told the lead.

Design rule: when the code a running process executes cannot be identified, that is an alert (`svc.unknown`), never silence.

Rule (Lean `lean/Fw/Obs/Stale.lean`, proved). Commit times are not used: `fw land` builds the merge commit with
`commit-tree` before its checks and fast-forwards main 23-89 s later (MEASURED over 12 lands), so `%ct` predates the
moment main moved. Each piece of running code has a base commit of `main`; an input is *changed* iff
`git log --first-parent <base>..main -- <path>` is non-empty (history model `touched`). A service is stale iff some input
is changed (`Svc.stale_iff`); the alert lists exactly the changed paths (`Svc.mem_changed`); judging at the head of main
changes nothing (`Svc.judge_head_not_stale`) and landing more commits never clears a stale one (`Svc.judge_stale_append`).
`obs.health` raises `svc.stale` (subject = service name) exactly for stale services (`svcStale_iff`) and `svc.unknown`
(detail `cannot identify the code that runs: <reason>`) exactly for services with a reason (`svcUnknown_iff`,
`unknown_service_alerts`).

What runs, not what is on disk (`Stack`, three bases):
- console-api: its own inputs (`apps/console-api/src`, its `package.json`, `pnpm-lock.yaml`, `packages/contracts/...`)
  against its start commit, AND the fwcore inputs against the build commit of the fwcore child it holds. console-api
  keeps ONE long-lived `fwcore` child (`core/lean.ts ensure()`); at every spawn it writes `coreCommit` (or `coreUnknown`
  with the reason) into `.fw-console/api.json` next to `commit`.
- fwcore (the binary on disk): the fwcore inputs against the commit it was built from.
- A rebuild on disk changes only the disk: console-api stays stale until it restarts or the child respawns
  (`rebuild_without_restart_api_stale`); the restart after a rebuild clears everything
  (`restartApi_after_rebuild_clears`); a restart without a rebuild spawns a child as old as the disk
  (`restartApi_without_rebuild_stale`).

The build record. One writer: `sh scripts/fwcore-build.sh` reads `HEAD` BEFORE `lake build`, builds, and writes
`lean/.lake/build/bin/fwcore.commit` only on a clean tree that is not mid-merge or mid-rebase. A plain `lake build` writes
no record. `chooseBase` (Lean `Fw.Obs.chooseBase`; TS stand-in `apps/console-api/src/core/build-base.ts`, same table
in `test/build-base.test.ts` and the `#guard`s): a record not older than the binary (binary mtime <= record mtime) is the
base; otherwise (older or no record) the base is the newest ref move of `main` (reflog) at or before the binary's mtime;
if there is none, or two moves share that second, the build is unknown (`svc.unknown`).

Measurement (TS, no decision): `apps/runner/src/watch-svc.ts` runs one `git log -1 --first-parent --format=%H
<base>..main -- <path>` per input group. `collectSvcs` never fails as a whole: a service it cannot identify or judge is
returned with `unknown: <reason>`; the other service is still judged.

What you do: `svc.stale fwcore ...` or `svc.unknown fwcore ...`: run `sh scripts/fwcore-build.sh` in the main checkout.
`svc.stale console-api lean/...` (child lags): restart console-api (stop it by the pid in `api.json`, start it again).
Nothing is killed or restarted automatically. `lean/scripts/check.sh` still runs a plain `lake build` (the check slots do
not run a console); in the main checkout, build with the script.

Replay (MEASURED against the real reflog of main; binary built by a plain `lake build` 20 s before main moved, no record):
dfc1d70, b5669db and 96a6129 each give `svc.stale fwcore ...` (base = first parent from the reflog).
Tests: `apps/runner/test/watch-svc.test.ts`, `apps/console-api/test/build-base.test.ts`, Lean golden rows in
`lean/Fw/Obs/Golden.lean` (`packages/contracts/golden/obs/health.jsonl`).
