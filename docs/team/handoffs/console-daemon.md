# Handoff: console-daemon

State: branch worktree-wf_8e08bb9a-7b4-1 (built on the merged preview-inspect branch worktree-wf_472752b6-0dc-1).

Done
- Lean `lean/Fw/Console/Daemon.lean`: `verified`, `startAllowed`, `stopTarget`, `restartPlan`, log line kinds
  (`logAdmits`, four secret kinds refused, one theorem each), `login_loopback`, `login_lan_or_loopback`, `rotate`.
  Op `console.daemon` in `lean/Fw/Wire/Console.lean`, 22 goldens in `lean/Fw/Ops/Golden.lean` ->
  `packages/contracts/golden/console/console.daemon.jsonl` (generated: `cd lean && lake env lean --run scripts/OpsGolden.lean`).
- CLI `apps/runner/src/console.ts`, wired as `pnpm fw console ...` in `apps/runner/src/fw.ts` ("console" is in NO_API_GROUPS,
  it needs no running console). Detached spawn of `apps/console-api/src/main.ts` (own session, stdin null, log append).
- `apps/console-api/src/main.ts`: api.json now also holds `lan`. `preview/link.ts` NO_TTY_MESSAGE points to /owner/login.
- Loopback login was already admitted by Lean (`allow` login class has no lan condition); now named by `login_loopback` and
  tested (`lan-owner.test.ts`, loopback login -> token -> session).
- Tests: `apps/runner/test/console-daemon.test.ts` (real detached console, spare port, temp dir, FW_CONSOLE_KEYCHAIN=off;
  ~95 s), `owner-link.test.ts` (no-tty: link never built). Docs: `docs/team/tools/console.md`.

Verified: console-api `pnpm test` 444 passed; runner console-daemon test 4 passed; the CLI by hand on a spare port.
Open: the user's own check of passphrase login and previews on the live console; lead updates the post-land routine memory
(step 3 = `pnpm fw console restart --lan`) and work-graph; stop does not SIGKILL a console that ignores SIGTERM.
Conventions: Lean decides, TS is glue; no TS stand-ins for decisions. Read first: `docs/team/tools/console.md`.
