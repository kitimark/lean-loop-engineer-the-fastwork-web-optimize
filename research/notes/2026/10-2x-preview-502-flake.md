---
id: 2026-10-2x-preview-502-flake
kind: note
title: "Why the preview e2e saw HTTP 502 'preview server not reachable' in 3 to 5 of 1000 loads: an idle-socket reuse race between the arm app's Agent and the rig's tap"
status: final
created: 2026-10-22
authors: [agent:console-builder]
topics: [console-api, e2e-preview, flake, node-http]
---

# Preview 502 flake

Question: where does the 502 of `apps/console-api/src/preview/arm-app.ts` come from in 3 to 5 of 1000 compare loads
(found in `research/notes/2026/10-21-webkit-cancelled-flake.md`), and what fixes it without a retry?

## Answer

- Each 502 is `ECONNRESET` ("read ECONNRESET" or "socket hang up") on a **reused** keep-alive socket that had been idle
  5995 to 5999 ms. 6 s is the idle limit of the rig's **tap** (a Node `http` server with the default `keepAliveTimeout`
  5 s plus the 1 s buffer): the tap closed the socket while the arm app's `http.Agent` sent the next request into it.
  MEASURED (idle time logged at the 502 path; three events, runs below).
- Why the Agent did not close first: Node's client Agent reads a server's `Keep-Alive: timeout=N` hint only when the Agent
  has a `timeout` option of its own. `Agent.prototype.keepSocketAlive` (Node v24.22.0 lib/_http_agent.js:632-666) applies
  the hint with `else if (serverHintTimeout < agentTimeout)` (:655); `agentTimeout` is `this.options.timeout || 0`
  (:637), so with no `timeout` the test never holds and the idle socket is kept without limit. CONFIRMED (source).
  The tap also copied the preview server's reply headers, among them `Keep-Alive: timeout=65`, so the hint it gave was
  65 s while it closed at 6 s. INFERRED from `rig.mjs` (`res.writeHead(r.statusCode, r.headers)`); the fix below removes it
  and the 502 is gone, but I did not log the header on the wire.
- The same missing idle limit sat in the preview port's compare proxy (`proxy.ts`, its own Agent). MEASURED: proxy 502 in
  39608748473 (shard 4 #4) and 39614957481 (#20); cause INFERRED (same Agent and tap path, not logged then); 0 after the fix in 20 runs.
- The preview server (`serve-child.ts`) has `keepAliveTimeout` 65 s, so in the console the same race exists only at 66 s idle;
  the 502 in the e2e was the tap's 6 s. The product code is fixed too, because the Agent's blind spot is the same.

## Fix (no retry)

- `apps/console-api/src/preview/upstream.ts` (new): `previewAgent(maxSockets)` builds the Agent with `timeout: 30_000`; the
  Agent then sets `socket.setTimeout(min(timeout, hint - 1 s))` on a socket it keeps (:641-663) and destroys an idle one
  before the server does. `arm-app.ts` and `proxy.ts` use it, and `log502` writes
  `preview-502 {who, code, syscall, msg, reused, idleMs, path}` to stderr at their 502 path.
- `packages/e2e-preview/src/rig.mjs`: the tap no longer passes the hop-by-hop headers (`Connection`, `Keep-Alive`, ...) of the
  preview server's reply on; Node adds the tap's own, true hint (`timeout=5`).
- A retry is not used: the cause is a documented-in-source blind spot of the Agent, not an unavoidable race of a correct
  client, and a retry would also hide a real preview-server death. The test `apps/console-api/test/preview-upstream.test.ts`
  pins the behaviour: the Agent's kept socket gets `hint - 1 s`; a bare keep-alive Agent gets none.

## Evidence (GitHub `ubuntu-24.04-arm`, Playwright WebKit, node 24.22.0; temporary workflow, removed in the final commit)

Compare only, 10 jobs x 100 loads = 1000 loads per run.

| run | code | result |
|---|---|---|
| 39605321202 | log of the upstream error, all 6 targets, 1200 loads | 0 x 502 (these runs are not sensitive; compare iframes are) |
| 39606786469 | log only, compare | 3 x 502, `ECONNRESET`, `reused: true` (2 x `GET /`, 1 module) |
| 39608748473 | log only, compare | 2 x 502: 1 arm (`read ECONNRESET`, `reused: true`), 1 proxy `/preview/e2e-fixture/compare` (not logged) |
| 39612143767 | + idle time | 3 x 502, `idleMs` 5999, 5995, 5995 |
| 39608784186 | Agent `timeout` only (tap still copies the hint) | 1 x 502: the hint was a lie, the limit did not help |
| 39612204002, 39614945069 | Agent `timeout` + tap fix (`arm-app.ts` only) | green, green |
| 39614957481 | same | 1 x 502 on `/preview/e2e-fixture/compare` (`proxy.ts` without a limit) |

Every unfixed run had 1 to 3 events in 1000 loads, the old rate. Once `proxy.ts` used the same Agent:

- **10 green 1000-load compare repeats** (head commit message carries `[long]`; 100 loads x 10 jobs, 0 failed checks, 0
  `preview-502` lines): 39627999647, 39628014718, 39629760037, 39631364784, 39631568360, 39633157418, 39634660133,
  39634961753, 39636558737, 39637984172. MEASURED. (`pnpm fw ci wait` printed `success -> fail` for three of them; the run
  conclusion is success and out/webkit.json of 39629760037 holds 23000 ok checks (10 x 2300, every shard reached #100) and no FAIL line; the temporary workflow's out.txt was truncated at exit, which may also explain the waiter label (INFERRED), so that label is the
  waiter's, not the run's.)
- 10 more green runs of all six targets, 20 loads each (1200 loads per run), same code: 39618779756, 39618810266, 39620413621,
  39621625829, 39622143204, 39623220025, 39623595049, 39624582807, 39625065660, 39626417194. MEASURED.

Total 20 runs, 22000 loads on the final code, 0 x 502. Before the fix: 8 events in 3000 compare loads.

## A third flake, found on the way

`webkit/loopback/compare/o-frame/fonts-loaded#1` failed in 3 of about 80 jobs (runs 39608784186 twice, 39614957481 once; the
original arm shows `Google Sans` but not `Playpen Sans Start Selling`), always on the first load of a job, in runs that were
red for the 502 too. Cause INFERRED: the face loads when text that uses it is laid out, which on a cold first load can come
after `document.fonts.ready` resolved. Fix: `frameFacts` waits up to 5 s until each wanted family has a loaded face; the
check still fails when one never loads. After it, 0 failures in 20 runs x 10 jobs. It waits on a lazy load; it is not a
retry.

## Other changes

- `suite.mjs` `controlLoad` keeps the result of `leavePage`: a still-open landing request is pushed to `failed`
  (`openFailure`, test in `leave.test.mjs`) and counts as cancelled for that control.
- `docs/team/tools/preview-e2e.md`: flags `--only/--repeat/--trace/--provoke`, the landing-page rule, the tap's headers.
- `10-21-webkit-cancelled-flake.md`: rate (2 in 2400 natural loads), source of the count of 6 (`out/webkit.json`, INFERRED), and
  the 18 land runs read: their ids were not kept; the note now says so and names the four it has.

## Open

- The `success -> fail` label of `pnpm fw ci wait` for a workflow without a Lean row.
- The font wait is not traced; if `fonts-loaded` fails again with the wait in place the cause is not timing.
