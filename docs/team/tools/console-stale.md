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

The build record. One writer: `sh scripts/fwcore-build.sh` (also what `lean/scripts/check.sh`, hence `fw land`, builds
through) reads `HEAD` BEFORE `lake build`, builds, and writes `lean/.lake/build/bin/fwcore.commit` =
`<sha of HEAD read before the build> <sha256 of the built binary>`, only after a successful build on a tree that is clean
before and after, not mid-merge or mid-rebase, with HEAD unmoved. Nothing is inferred from file times or the reflog (Lake's
artifact cache restores a binary with an old mtime, so an mtime is not the build time). `chooseBase` (Lean
`Fw.Obs.chooseBase`; TS stand-in `apps/console-api/src/core/build-base.ts`, same table in `test/build-base.test.ts` and
the `#guard`s): a record is accepted only when the sha256 of the binary now on disk equals the recorded one, and then the
base is the recorded commit (`chooseBase_accepted`, `chooseBase_at_iff`). No record, a mismatch (a plain `lake build`
replaced the binary) or a dirty build: unknown (`chooseBase_mismatch`, `chooseBase_none`), and unknown always alerts
(`chooseBase_unknown_alerts`, `unidentified_core_alerts`): `svc.unknown` with the hint to run `scripts/fwcore-build.sh`.

Which checkout. console-api judges the checkout its code runs from, `codeRoot = resolve(here, ../../..)`, for its start
commit and its core. A binary that is not `<codeRoot>/lean/.lake/build/bin/fwcore` (`FW_CORE_BIN`, another checkout)
without a matching record is unknown, and the reason says so; main's data is never used for another checkout.

Inputs are git pathspecs, and the Lean model is the same predicate (`covers`: equal, or `x/` is a prefix of the file;
`covers_self`, `covers_child`): `lean/Fw` covers `lean/Fw/Obs/Stale.lean`, not `lean/Fw.lean`.

Stated limit: the watcher's own code (`apps/runner`, `fw watch`) is not a judged service. A `fw watch` process started
before this lands keeps the old rule until it is restarted, and nothing alerts on that.

Measurement (TS, no decision): `apps/runner/src/watch-svc.ts` runs one `git log -1 --first-parent --format=%H
<base>..main -- <path>` per input group. `collectSvcs` never fails as a whole: a service it cannot identify or judge is
returned with `unknown: <reason>`; the other service is still judged.

What you do: `svc.stale fwcore ...` or `svc.unknown fwcore ...`: run `sh scripts/fwcore-build.sh` in the main checkout.
`svc.stale console-api lean/...` (child lags): restart console-api (stop it by the pid in `api.json`, start it again).
Nothing is killed or restarted automatically. In the main checkout build with the script (a land does it through
check.sh); a plain `lake build` leaves the core unknown.

Replay: the round-4 replay (plain builds around main's moves judged by the reflog) is withdrawn with the reflog rule;
the same situations are now `svc.unknown` (test "a plain `lake build` (no record) is unknown whatever main did around it").
Tests: `apps/runner/test/watch-svc.test.ts`, `apps/console-api/test/build-base.test.ts`, Lean golden rows in
`lean/Fw/Obs/Golden.lean` (`packages/contracts/golden/obs/health.jsonl`).
