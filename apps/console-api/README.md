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

One interface `Core { apply, board }`. `FW_CORE=ts` uses the stand-in `reducer.ts` (marked
`replaced by fwcore console.apply`); `FW_CORE=lean` spawns `lake exe fwcore` in `lean/` (JSON lines
`{"id","op":"console.apply","state","event"}` -> `{"id","state","outcome"}`; override with `FW_CORE_CMD`).
Unset: lean when `lean/.lake/build/bin/fwcore` exists, else ts. Board derivation (`board.ts`) is TS for both.

Golden cases: `packages/contracts/golden/console-apply.jsonl` (state+event -> state'+outcome). Check a backend with
`FW_CORE=lean pnpm --filter @fw/console-api test`. Regenerate from the TS table: `pnpm --filter @fw/console-api gen:golden`.
JSON Schemas: `pnpm --filter @fw/contracts gen` -> `packages/contracts/schema/`.
