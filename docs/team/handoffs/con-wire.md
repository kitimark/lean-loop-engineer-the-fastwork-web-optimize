# Handoff: con-wire (integration fix, lean-ops wiring, capability door, hardening, spawn guard)

Branch `worktree-agent-a48411497cfac271f`. Tests need `FW_CORE_BIN` when the worktree has no `lean/.lake`.
console-api 127 tests, runner 32, typecheck green; `FW_CORE_BIN=<fwcore> sh apps/runner/test/e2e-land.sh` green (plays the cap hook).

## Done
- Main was red because `store.state` is gone: reconciler reads the Lean board (`store.board()`: id, owner, head, landed). No Lean change
  was needed. Tests read `board()` / `readEvents()` (board has no `builders`/`landReq`).
- `Core.ops(op, fields)` (any non-state fwcore op). `POST /api/ops/path-check` -> `ops.pathCheck`; `runner/src/land.ts` sends `LAND_SCOPE`
  (policy data) and gets the verdict. TS `pathCheck` deleted.
- `spool/standin.ts` deleted. Drain decodes identity with `ops.hook` (key = agent|event|tool_use_id or ts).
- `fw` sends `{argv, command}` to `/api/agent/commands` (`send(base, cmd, argv)`); `land` takes `submit`/`argv`. `FW_ACTOR`/`--as`/`actor`
  in commands are placeholders now (server overwrites). Door/actor table in `apps/console-api/README.md`.
- `lean.ts`: unknown reply id or unparsable line -> kill (crash + replay); per-call timeout 10 s (replay chunks 120 s); tests in `crash.test.ts`.
- `apps/runner/hooks/spawn-guard.mjs` (shadow): `ops.spawn` with `unnamedReadOnly: true`, logs a `SpawnGuard` ObsRecord (`verb` = decision[:reason]) to the spool.

## Lean gaps / stand-ins
- `summarize` (tool-call aggregation for `/api/obs/summary`) is a TS stand-in in `spool/drain.ts`: `ops.usage` is token usage, no op for tool calls.
  The obs key is still built in TS from `ops.hook` fields (no `ops.obsKey`). Spool records lack `session_id`; drain passes `"spool"`.
- Role table (`ROLES` in spawn-guard.mjs: runsAs/edits per `.claude/agents` role) is INFERRED data; `alive` and `recent` are empty in shadow mode.
- `card.screen` (actor `script`) cannot be sent by an agent through the door; nothing yet produces it (screen runner / drain). e2e uses the UI door.
- A `console.landReadiness` op (with refusal reason) is still missing.

## Open
- Flaky once: one console-api run had 1 failure under load, not reproduced in 3 reruns (suspect a timing test).
- Spawn guard needs the settings block (report) added by the lead; then switch from shadow to blocking after a review of logged decisions.
