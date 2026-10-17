# Handoff: fw-ci (console-builder)

State: branch `worktree-agent-ae01f098d8c3b8b4f`, commit with trailer `Task: fw-ci`. Runner 133 tests, console-api 201 tests green
(set `FW_CORE_BIN` to the main fwcore if the worktree has no lean build; wt-prep skips install while main builds: run `pnpm install --offline --frozen-lockfile`).

What exists
- `apps/runner/src/ci.ts` + `fw ci` dispatch in `fw.ts`; `ingest` in `run.ts` gained `opts.keepSameRun` and returns `digest`, `unchanged`.
- Real pull (scratch store, read-only): run 39043671714 on main, keys original 306e83f1..., rewrite b8e87388...; re-pull printed `unchanged`.
- Usage and rules: `docs/team/tools/fw-ci.md`.

TS stand-ins (decision logic, to move to Lean as one op `store.ciRun`): `selectCiRun` (accept/refuse, shards from job names
`counts (<target>, r<n>)`), `searchConfig` (preset/flags from the `?preset=&fw=` query), the shards-agree check. Everything else
(key, manifest validity, object paths) is fwcore `store.manifest`.

Open
- WebKit: not wired (webkit-green not passed); needs a `selectCiRun` analogue for webkit-sim artifacts.
- The manifest has no `conclusion` field (Lean); it is stored as `ci.json` inside the entries. Only `success` is ever stored.
- A push-triggered run uses workflow defaults (profile swipe-v1, preset original); nothing records the inputs besides the shards' own metadata.
Read first: `apps/runner/src/ci.ts` header, `ingest` in `run.ts`.
