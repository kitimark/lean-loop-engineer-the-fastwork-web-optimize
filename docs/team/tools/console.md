# fw console: the console as a background process

console-api runs detached: its own session, stdin from /dev/null, stdout and stderr appended to
`.fw-console/console.log`. No terminal window opens, and none is needed. The decisions are Lean
(`Fw.Console.Daemon`, op `console.daemon`, goldens `packages/contracts/golden/console/console.daemon.jsonl`); the
CLI (`apps/runner/src/console.ts`) is I/O glue.

## Commands

| Command | What it does |
| --- | --- |
| `pnpm fw console start [--lan] [--port 8787]` | starts the console and returns after `GET /api/health` answers; prints pid, console port, preview port, LAN on/off and the log path. Refused (exit 1) when a console is verified. |
| `pnpm fw console stop` | SIGTERM to the verified pid only; waits for exit; the console's own shutdown stops the previews it owns, and `stop` checks that none of the recorded preview processes is left. |
| `pnpm fw console restart [--lan] [--port N]` | stop (if one is verified), then start. Flags are not remembered: pass `--lan` each time. |
| `pnpm fw console status` | pid, uptime, ports, LAN on/off, previews running, log path and size (warns above 50 MiB). Exit 1 when stopped. |
| `pnpm fw console logs [-n N] [-f]` | last N lines (default 50) of `console.log`; `-f` follows until Ctrl-C. |

Verified: `.fw-console/api.json` names a pid, and the port in that file answers `/api/health` with the same pid in
`x-fw-console-pid` (Lean `verified`; a stale file or a reused pid is never signalled; `stop` then says nothing is
running). A recorded pid that is alive but did not answer (a busy console) also refuses `start`
(Lean `start_refused_unverified_alive`; run `status`, then `stop`). The log rotates at 5 MiB: the old file becomes
`console.log.1` at the next start. **Accepted limit: rotation runs at start only**; a console that runs for days appends
without a bound, so `status` prints the log size and warns above 50 MiB (`pnpm fw console restart` rotates).

## Signing in

- The log holds no owner link or token because `link.ts` never builds the link without a terminal (Lean `no_file_sink`,
  `no_nontty_sink`), and a daemon test reads the whole log for it. No log-line rule exists in Lean.
  With no keychain passphrase, login is disabled and `start` prints the keychain command instead of the sign-in line.
- Sign in with the owner passphrase (keychain item `fw-console-owner`) at `http://127.0.0.1:<port>/owner/login`, or at the
  LAN address printed in the log when started with `--lan` (needs a passphrase of at least 12 characters). Loopback is
  admitted by Lean (`login_loopback`), the LAN with the right Host (`login_lan_or_loopback`). After login the browser holds
  the owner token, and previews work.
- A one-time link in your own terminal: start the console from that terminal (`pnpm --filter @fw/console-api start`) and
  run `pnpm --filter @fw/console-api owner-link` there. It signals only a console that proves itself by `/api/health`.
  A detached console has no terminal, so `owner-link` prints nothing to it.

## Post-land routine, step 3

After a land: `sh scripts/fwcore-build.sh`, rebuild `apps/console-web`, then `pnpm fw console restart --lan`. No osascript,
no new Terminal window. Read the result with `pnpm fw console status` and `pnpm fw console logs -n 30`.

## Limits

- The restart does not keep the preview table: previews are stopped with the console (they are rebuilt on demand).
- launchd or login items are out of scope: after a reboot, run `pnpm fw console start --lan` once.
- A same-UID process can read `console.log` (it holds no secret) and can signal the pid itself; this is not a boundary.
- TS stand-ins: none for decisions. The spawn, the signal, the health request and the file reads are unproved glue.

## fwcore calls, replay and timeouts

- A fresh fwcore child first replays the whole log (`console.replay`, 120 s per chunk). A call made during the replay is
  written only after the replay settles, so its 10 s deadline (`CALL_TIMEOUT_MS`) covers the call, never the queue.
  Measured 2026-10-20 (local debug run): 14,460 real events replay in 0.14 s (was 12.8 s); 4x in 0.6 s.
- The deadline rule is `Fw.Obs.Backoff.onTimeout` (op `obs.backoff`, golden `packages/contracts/golden/obs/backoff.jsonl`).
  A machine is loaded when the floor of its 1-min load average is at least `os.cpus().length`; a loaded call waits
  3 base deadlines before the kill, an unloaded one is killed at the first. TS stand-in: `backoffDecision` in
  `apps/console-api/src/core/lean.ts`, checked against the golden by `test/backoff.test.ts`.
- `FW_CORE_CALL_MS` is no longer needed as a mitigation.

