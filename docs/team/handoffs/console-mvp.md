# Handoff: console (console-api, console-web, contracts, fw CLI)

State at 9367dea (written by the lead from console-mvp's report and the fwcore landing).

- Start the console: `pnpm --filter @fw/console-web build`, then `pnpm --filter @fw/console-api start` (it prints a
  free port). The CLI is `pnpm fw status|step …` (apps/runner/src/fw.ts). Read apps/console-api/README.md first.
- console-api is the single writer of `.fw-console/events.jsonl` (gitignored), with SSE to console-web.
- Core switch: `apps/console-api/src/core/{index,lean,reducer,board}.ts`. `FW_CORE=ts|lean`; the default is lean when
  `lean/.lake/build/bin/fwcore` exists. fwcore landed at 9367dea and passes all 42 cases of
  `packages/contracts/golden/console-apply.jsonl` (test/conformance.test.ts, backend: lean).
- fwcore ops: console.apply, console.board, verdict, multiplicity, ticks, screen, cost, flags.resolve, lease.step and
  samples (see lean/README.md). Spawn it with LEAN_ABORT_ON_PANIC=1, using JSON lines with request ids.
- Contracts are zod schemas in packages/contracts/src/schemas.ts, with JSON Schemas in packages/contracts/schema/.
- **Open:** delete the TS stand-in reducer and board (reducer.ts, board.ts). All decisions and the board projection
  come from fwcore (`console.board`). Keep the golden file and conformance test. Validate fwcore's `samples` op output
  against the zod schemas in a test.
