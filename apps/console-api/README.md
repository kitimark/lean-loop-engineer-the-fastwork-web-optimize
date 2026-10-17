# Console (console-api, console-web, runner, contracts)

Nobody writes status. `console-api` is the single writer of `.fw-console/events.jsonl` (main checkout root,
gitignored); every board field is a projection of that log. Inputs are typed commands the reducer may refuse.

## Run

```sh
pnpm install
pnpm --filter @fw/console-web build        # once; console-api then serves the UI
pnpm --filter @fw/console-api start        # picks a free port, prints it, writes .fw-console/api.json
# UI dev with hot reload (proxies /api to the port in api.json):
pnpm --filter @fw/console-web dev
# agents:
pnpm fw status
pnpm fw step post --id s1 --title "Plug in the phone" --kind action --as script
pnpm fw step answer s2 yes --as user
pnpm fw step done s1 --as user
pnpm fw send '{"type":"card.open","key":"c1","actor":"owner","card":"A","owner":"o","needsDevice":false}'
pnpm test                                   # all vitest suites
```

`fw` exits 2 and prints `refused: <reason>` when the reducer refuses. Env: `FW_ACTOR` (default `owner`),
`FW_API` (base URL), `FW_CONSOLE_DIR`, `PORT` (default 0 = free port).
Actor is self-declared for now; a capability hook is to replace it (PLAN §8.5).

## Decision backend (`src/core/`)

All decisions come from `fwcore` (Lean): `console.apply` is the reducer, `console.board` the board. There is no TS
fallback. `Core { apply, board, close }` in `index.ts`; `lean.ts` spawns `lean/.lake/build/bin/fwcore` with
`LEAN_ABORT_ON_PANIC=1`. console-api refuses to start (exit 1) if the binary is missing and prints
`build it with: cd lean && lake build`. `FW_CORE_BIN` overrides the path (tests).

Crash handling: a dead fwcore fails the in-flight calls (HTTP 500 `decision core failed`), is logged as an incident
(stderr and `.fw-console/incidents.jsonl`), and is respawned on the next call. Stderr output is logged as an incident.

Tests (`pnpm test` at the root runs `lake build` first, or prints a loud skip message if `lake` is absent):
golden conformance (`packages/contracts/golden/console-apply.jsonl`, 42+ cases, Lean only), `samples` op vs the zod
schemas, crash/restart, API. The golden file is now static (it was generated from the removed TS reducer).
JSON Schemas: `pnpm --filter @fw/contracts gen` -> `packages/contracts/schema/`.

## Doors and actors (who can produce which actor)
| Door | Used by | Actor |
|---|---|---|
| `POST /api/agent/commands` `{argv, command}` | `pnpm fw ...` (every `fw` command) | stamped from the PreToolUse capability (`cap.mjs`): `lead` (main), `reviewer` (agent type matches `review`), else `owner`. Never `user`, `script`, `git`. The actor in the body is overwritten. No valid unused capability: 403 |
| `POST /api/commands` | the web UI (the user's buttons) only; also tests | whatever the body says (self-declared, including `user`) |
| reconciler, spool drain (inside console-api) | git facts, alerts | `git`, `script` |

Whether the stamped actor may send that command is still decided by the Lean `may` table (422). Ops for clients:
`POST /api/ops/path-check` forwards to Lean `ops.pathCheck`. `LeanCore` kills and restarts (with log replay) a child
that answers with an unknown id, an unparsable line, or not within the per-call deadline (10 s; replay 120 s).
