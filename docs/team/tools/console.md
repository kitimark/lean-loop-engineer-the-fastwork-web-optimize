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
- **Login return link** (Lean `console.loginReturn`, `Fw/Console/PreviewReturn.lean`). A browser (HTML GET) without the owner session that
  opens a preview arm link or a `/preview/<id>/` path is redirected (303) to the console `/owner/login?r=<nonce>` on the same host name;
  after the login it lands on the exact link (path and query). The server holds the link under a random nonce for 10 minutes (at most
  256, single use); only the nonce travels, never a cookie. Lean decides: the method is GET and the request wants HTML (HEAD, POST and API
  requests keep 401 with no Location); the host name is well formed and is one of the console's host names (loopback names plus the LAN
  address, passed from `OwnerAuth.hostNames`); the link is on a live arm port (or a live preview path on the preview port), starts with
  one `/`, is at most 2000 characters and holds only A-Z a-z 0-9 `. : , - _ @ = & / ?` (no `%`, `#`, `\`, space or quote); and fewer than
  256 references are held (`heldCount`; a full store logs in plain). Anything else logs in plain and lands on `/`. After the login Lean
  checks the link against the current table and the host again: live, the link; stopped, `/?tab=builds&note=stopped` (the Builds tab with
  "That preview has stopped; press Open."); never an unknown target. The theorem `landing_sound` concludes the host is one of the console's
  hosts. TS keeps the nonce map (random nonce, dropping expired entries, single use) and reads the facts; it uses Lean's `location`
  unchanged. The console-port redirect has no return.
- A one-time link in your own terminal: start the console from that terminal (`pnpm --filter @fw/console-api start`) and
  run `pnpm --filter @fw/console-api owner-link` there. It signals only a console that proves itself by `/api/health`.
  A detached console has no terminal, so `owner-link` prints nothing to it.

## Post-land routine, step 3

After a land: `sh scripts/fwcore-build.sh`, rebuild `apps/console-web`, then `pnpm fw console restart --lan`. No osascript,
no new Terminal window. Read the result with `pnpm fw console status` and `pnpm fw console logs -n 30`.

## Builds tab: Open and the search box

- Every row has **Open** (the rewrite arm at the row's search) and **Open compare**. If no preview of the row's commit serves, the
  console starts it, waits for it to serve, then sends the new tab to the link.
- The search box takes a pasted search such as `?preset=v2-proved&fw=morph.mount:shift-dormant,...`. `POST /api/builds/open` checks it
  first with Lean `console.buildsSearch` (`Fw.Console.BuildsOpen.validate`): the charset (A-Z a-z 0-9 `. : , - _ @ = &`, one leading `?`,
  at most 2000 characters), then the site's rules (one `?preset=`, presets with `extends`, parts, variants, impls, requires, conflicts).
  A refusal lists every reason and starts nothing; an accepted search opens in its canonical form (preset first) in main's build.
- Reuse, wait, rebuild or start is Lean `console.buildsOpen` (`decide`); the link text (`fullUrl`) uses the console's LAN address when
  LAN is on, else loopback. The link has no token or cookie. **Copy link** copies it. The phone still needs the owner login to start a build.
- Recent searches are in this browser's localStorage (`fw-console.builds.recentSearches`, 10 entries); the server keeps none.
- Gates are unchanged: starting and stopping go through the owner proof of `pm.start`/`pm.stop`; a serving preview is only linked, as in
  `GET /api/previews`. The request names a row id or a search string, never a commit, a path or a command; the search is a client-side query.
- Agreement: `apps/console-api/test/builds-search.test.ts` runs the golden vectors (`packages/contracts/golden/console/console.buildsSearch.jsonl`,
  from `Fw/Ops/Golden.lean`) against `apps/site/src/registry/resolve.ts`, and the live registry through `fwcore`.
- TS stand-ins: none for decisions. `readRegistry` (reads `part.json` and the preset files), the route and `apps/console-web/src/buildsOpen.ts`
  (localStorage, clipboard) are glue. Known gaps: resolve.ts reads preset and variant names with `in`/`presets[name]` (names such as
  `constructor` pass there; Lean refuses them as unknown); Lean is stricter on charset and length; unknown parameters are dropped from the
  canonical search; part order comes from the directory listing.

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
- `console.query` runs `Fw.Plan.fastView` (hash indexes, proved equal to `view`): 22 ms on the real log, 229 ms at 4x
  (was 0.63 s and 33 s; local debug run; `research/notes/2026/10-20-fwcore-query-speed.md`).
- `FW_CORE_CALL_MS` is no longer needed as a mitigation.

