# Handoff: console-daemon (round 2)

State: branch worktree-wf_8e08bb9a-7b4-1, round 2 on top of 38b8290a (commit named in the report).

Done
- Lean `lean/Fw/Console/Daemon.lean`: `verified`, `unverifiedAlive`, `startAllowed r a alive`, `stopTarget`, `restartPlan`,
  `rotate`, `logWarns` (50 MiB), login theorems; one theorem per branch. No `$$` blocks. The log-admission rule (Line,
  logAdmits, `line` op kind, goldens) is deleted: the guarantee is `no_file_sink`/`no_nontty_sink` plus the whole-log test.
- Op `console.daemon` (`lean/Fw/Wire/Console.lean`): start takes `alive`, reason `unverifiedAlive`; rotate returns `warn`.
  Goldens: `cd lean && lake env lean --run scripts/OpsGolden.lean` -> `packages/contracts/golden/console/console.daemon.jsonl`.
- CLI `apps/runner/src/console.ts`: one Lean call per probe; start refuses a live silent pid; start prints the keychain hint
  when `GET /owner/login` is 503; stop checks `kill(-pid,0)` plus recorded `pstart`; `logs -f` reopens on a new inode;
  `status` prints log size and warns.
- Tests: `apps/runner/test/console-daemon.test.ts` (7 tests, real detached console, FW_CONSOLE_KEYCHAIN=off, fake preview
  group, live silent pid, rotation follow); `lan-owner.test.ts` loopback login then preview route with the fw_preview cookie.
  `scripts/wallclock-allow.json` has the 120_000 hang-cap entry.

Verified: runner 1145 passed (40 files), console-api 444 passed (27 files), ci-paths 40 passed, `sh lean/scripts/check.sh` green.
Accepted limits: rotation at start only (console.md, Daemon.lean doc, start output); stop never SIGKILLs a console that
ignores SIGTERM; the user's own check of passphrase login and previews on the live console is the final confirmation.
Open: lead updates the post-land routine memory (`pnpm fw console restart --lan`) and the work-graph.
Read first: `docs/team/tools/console.md`.
