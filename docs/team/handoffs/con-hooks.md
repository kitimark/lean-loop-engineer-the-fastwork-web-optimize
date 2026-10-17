# Handoff: con-hooks (observer + capability hooks, spool drain)

Branch `worktree-agent-ab4a050a2bc02701f`. Tests need `FW_CORE_BIN=<main>/lean/.lake/build/bin/fwcore` in a fresh worktree.

## Done
- `apps/runner/hooks/emit.mjs` (observer, spool-only, silent, exit 0; ~47 ms median vs 37 ms bare node), `cap.mjs`
  (PreToolUse capability), `lib.mjs`, `*.d.mts` (types for tests). Console dir = main checkout (resolved from the
  worktree `.git` file) unless `FW_CONSOLE_DIR`.
- `packages/contracts/src/obs.ts`: ObsRecord, ObsLine, CapRecord, AgentRequest, ObsSummaryRow.
- `apps/console-api/src/cap/`: HMAC check, single-use consume (`caps.used.jsonl`), `POST /api/agent/commands`
  `{argv, command}`: 403 without a valid unused capability; actor + `signedBy` (card.review) are stamped, the
  client's actor is overwritten; the Lean `may` table still decides (422).
- `apps/console-api/src/spool/`: `Drain` (spool -> `obs.jsonl`; alerts -> `step.post` by actor `script` through the
  reducer; seen only after acceptance; refused alert retried), `POST /api/spool/drain`, `GET /api/obs/summary`.
- app.ts: 2 lines (mount + `Object.assign(app, {drain})`); main.ts: drain every 2 s.

## TS stand-in (remove when lean-ops lands)
`src/spool/standin.ts`: `obsKey`, `dedupe`, `summarize` (usage join/dedupe/aggregation). One import to swap.

## Open
- `fw` (apps/runner/src, not mine) must POST to `/api/agent/commands` with `argv: process.argv.slice(2)` instead of
  `/api/commands`; `/api/commands` still trusts a self-declared actor (web/user door) and should be user-only.
- `actorFor` (cap.ts) maps holder -> identity (main=lead, /review/=reviewer, else owner); adjust to real agent types.
- Capability is anti-accident, not anti-malice: the secret file is readable by the same OS user.
- One `pnpm fw` per Bash call (the hook stops at `;`, `&`, `|`). Two identical concurrent commands consume the oldest cap.
- Transcript reconciler (usage upsert by message.id) is not built; obsKey is shaped for it.
- `.claude/settings.json` hooks block is proposed in the report, not applied.
