# cap-diagnose handoff

State: branch worktree-agent-a075512921164a477 (task cap-diagnose); see `git log -1` for the commit.

## What changed
- Lean `lean/Fw/Ops/Identity.lean` (end of file): `capDecide` (mint | noMint reason), `Reason` (notFwPrefix,
  trailingPipe, unknownActor), `isRedirStub`/`hasStub`, theorems `capDecide_mint_iff`, `capDecide_noMint_iff`
  (exactly one reason), `capDecide_noMint_unique`, `capDecide_mint_actor`; `openDoor`/`isAgentActor` with
  `isAgentActor_iff` (agent actors = range of `capActor`), `openDoor_no_secret`, `openDoor_secret`.
- Wire ops `ops.cap`, `ops.door` (`lean/Fw/Ops/Wire.lean`), goldens `ops.cap.jsonl`, `ops.door.jsonl` (generated).
- Hook `apps/runner/hooks/cap.mjs`: `decideCap` mirrors Lean. trailingPipe (`2>&1 | tail`, cut at `&`) and unknownActor
  block with exit 2 and the reason on stderr; notFwPrefix (leading `cd`, `pnpm -s fw`) cannot be blocked (the command
  may not run fw) so it is written to `.fw-console/capmiss.jsonl`; console-api quotes the latest miss (< 2 min) in the 403.
- DEFECT fix: `POST /api/commands` refuses lead/owner/reviewer unless header `x-fw-secret` equals `.fw-console/secret`
  (`app.ts`, `cap/cap.ts openDoor`). The runner's `httpFor` sends it; tests that post agent actors read it from the dir.
- `scripts/wt-prep.sh`: `build_pids` matches argv (program `lake`, first subcommand `build`) via `ps`; test
  `sh scripts/wt-prep.sh --self-test` (not a runner test: land.readsOnly forbids undeclared reads of scripts/).

## Open items
- The secret is readable by any agent; it raises the bar from "any body" to "read .fw-console/secret". policy-from-lean
  should deny agent reads of that file.
- The hook tokenizer still cuts at `&`; fixing `2>&1` (drop redirects from argv) would remove trailingPipe at the root.
- TS stand-ins: `decideCap`, `openDoor` are mirrors checked against goldens (not Lean-run).

Read first: Identity.lean end section, then `apps/runner/hooks/cap.mjs`.
