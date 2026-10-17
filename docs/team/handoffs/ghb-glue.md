# ghb-glue handoff (shared GitHub poller, I/O glue)

State: branch worktree-agent-a1ba20bb8c0777a97, one commit on top of 6504ec1. Decisions stay in Lean (`Fw.Ci.Budget`, ops
`ci.budget.*`); the glue only calls fwcore, runs gh and moves files. Read first: `packages/gh-budget/src/{charged,poller,wait,cli}.ts`.

## Agent-facing usage (paste into prompts)
- Wait for CI: `pnpm fw ci wait <runId>` or `pnpm fw ci wait --branch ci/<task> [--workflow <name>] [--sha S] [--since EPOCH] [--timeout S]`.
  It blocks on a local file (0 GitHub calls of its own), follows the NEWEST run per workflow on the branch, prints
  `run <id> <workflow> <conclusion>`. Exit 0 = every decisive run succeeded, 1 = a run failed, 3 = timeout (default 540 s) or
  poller stopped (rerun it), 2 = gh could not find the run, 64 = usage. Run it in the background; do not loop or poll gh.
- Budget: `pnpm fw ci budget [--json|--resume|--probe]` (0 requests; --probe = one charged `gh run list --limit 1`).
- Never `gh run watch`, never a gh loop, never `gh api`; other gh calls go through `ghCharged` (`@fw/gh-budget`).
- Without pnpm: `node packages/gh-budget/src/cli.ts wait|budget ...`. Env: `FW_GH_BUDGET_DIR` (state dir), `FW_CORE_BIN`
  (fwcore binary), `FW_GH_BIN` (gh). State: `<git common dir>/fw-gh-budget/` (state.json, runs-status.json, locks, waiters/, meta/), shared by all worktrees.

## How it works
- `ghCharged` asks `ci.budget.reserve` (or `next`), runs gh with GH_DEBUG=api only on `issue`, keeps only status line,
  x-ratelimit-*, retry-after, etag, drops the rest of the trace, calls `observe`. Never reads a token. Wait/stop = gh never called.
- The first waiter takes `poller.lock` (link(2), pid-liveness, no age rule) and polls with ONE `gh run list` per issued tick.
- Fixtures replay through the glue with a fake gh (`test/fake-gh.mjs`): gh calls == issued decisions. 1 vs 20 waiters: 6 vs 6 calls.
- `fixtures/recorded-1.jsonl` is one real `gh run list --limit 1` (two response header blocks, sanitized); `lake test` replays it, 0 problems.

## TS stand-ins (small rules, not proved in Lean; move to Lean if they grow)
verdict (exit 0 iff all decisive runs `success`), `pages = floor(rows/100)+1`, poller unregisters completed watched runs, local re-read
every 2 s, default `--timeout` 540 s, branch semantics (newest run per workflow with createdAt >= commit time; no `--workflow` = all workflows).
Deviation: run list also asks `createdAt`. Accepted residual race: two processes breaking a dead `.break` lock in the same millisecond.

## Open items / notes
- Production spawns fwcore once per decision (~98 ms); tests use a persistent fwcore (`test/util.ts fastCore`). Needs a built `lean/.lake/build/bin/fwcore` (or `FW_CORE_BIN`).
- Suites: `pnpm --filter ./packages/gh-budget test` (27 tests, ~85 s) and `pnpm --filter ./apps/runner test` (136) green; runner hooks timing test may flake under load.
- Not pushed; lead lands it.
