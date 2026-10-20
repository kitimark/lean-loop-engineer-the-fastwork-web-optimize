# task-preview handoff

State: branch worktree-wf_a765cd4e-98c-1, round 2 (head commit: see `git log -1`). Read first: research/notes/2026/10-18-task-preview.md.

- Lean: lean/Fw/Console/Preview.lean (headOf/targetOf, Proof/actor, admit, fail, tick, stop, reap, Reach/Inv),
  lean/Fw/Console/PreviewTable.lean (25-task investigation table, `table_matches`); wire ops console.preview{Target,Admit,Stop,Fail,
  Tick,Reap} in lean/Fw/Wire/Console.lean; goldens console.preview*.jsonl (regen: `cd lean && lake env lean --run scripts/OpsGolden.lean`).
  Wire field is `preview`, not `id`.
- API glue: apps/console-api/src/preview/{facts,manager,owner,routes,serve-child}.ts; app.ts takes an OwnerAuth, main.ts prints
  the one-time owner link to stdout. Tests: apps/console-api/test/preview.test.ts. Web: apps/console-web/src/TaskDetail.tsx.
- Owner proof: owner link -> HttpOnly SameSite=Strict cookie; routes send {secret,cookie,origin} to Lean. Dev web origin:
  FW_CONSOLE_WEB_ORIGIN=http://127.0.0.1:5173 (open the owner link and the dev server both on 127.0.0.1).
- Manual run (clean shell, worktree root): `cd lean && lake build fwcore`; `pnpm install --offline --frozen-lockfile`;
  `pnpm --filter @fw/console-web build`; `FW_CONSOLE_DIR=$PWD/.fw-console pnpm fw console start --port <free>` (own state dir in
  the worktree, so the lead's console keeps running; it returns when the health check answers); open the printed `owner link`
  once in the browser, then Preview in a port-/fix- task panel. Previews use ports 47100-47139. Stop it with
  `FW_CONSOLE_DIR=$PWD/.fw-console pnpm fw console stop` before the worktree is removed (a console left running shows up in `fw reap --list`).
- TS stand-ins: the facts cache and git ancestry gathering (facts.ts). Decisions are Lean.
- Open: previews are not in events.jsonl; residual same-UID risk (owner link in stdout, cookie in browser profile); no wait-guard
  refusal for agent Bash calls to /api/previews (hook lives in .claude/settings.json, not editable here); no end-to-end build
  test on CI (stub hooks; real build checked by hand once, port-platform: 202, serving, stop, tree gone).
