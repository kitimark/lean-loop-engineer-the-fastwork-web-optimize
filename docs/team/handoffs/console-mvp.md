# Handoff: console-mvp (console-api, console-web, runner, contracts)

State: console decisions are Lean-only. Branch `worktree-agent-a1fcdda233720c6f2`, based on main 9367dea.

## Done
- TS stand-in reducer and board removed (`reducer.ts`, `board.ts`, `gen-golden`, table tests). `src/core/lean.ts`
  is the only backend: `console.apply` and `console.board` via `fwcore`, spawned with `LEAN_ABORT_ON_PANIC=1`.
- `Core.board` is now async (Store.board, `/api/board`, SSE).
- console-api exits 1 at start if the binary is missing, message includes `cd lean && lake build`.
- fwcore crash: in-flight calls fail (HTTP 500 `decision core failed: ...`), incident logged to stderr and
  `.fw-console/incidents.jsonl`, process restarted lazily on the next call.
- Crash race fixed (lean.ts): calls fail only in `crashed()` (once per child, on exit or error); stdin EPIPE just kills the child. Tests use `stopForTest()` (SIGSTOP, so the call is truly in flight; the old flake was the child answering before SIGKILL landed) then `await killForTest()` (resolves after incident, restart count and rejection). 50 runs under 20 busy loops: 0 failures.
- Tests: golden conformance (Lean only), `samples` op vs zod (`test/samples.test.ts`), crash/restart, missing binary, API.
- Root `pnpm test` runs `pnpm lean:build` first (skips with a loud stderr message if `lake` is absent); `pnpm typecheck` added.

## Notes
- `packages/contracts/golden/console-apply.jsonl` is static now; extend it by hand (or from Lean) and keep
  `lean/golden/` in step.
- `console.board` is only checked through `samples` and the API test; no golden file for board yet.
- Actor is still self-declared (capability hook is open, PLAN section 8.5).
- Per-call cost is O(state) (stateless `console.apply`); a stateful `fwcore serve` is the later step.

## Open
- Golden cases for `console.board` (contracts + lean).
- A crash during startup replay fails startup (by design: no silent partial state).
