---
id: 2026-10-18-task-preview
kind: note
title: "Task detail panel and owner-only local preview of a port-/fix- task next to the original (task-preview)"
status: draft
created: 2026-10-18
topics: [console, preview, lean, auth, worktree]
---

Question: how does the owner see what a port-/fix- task built, side by side with the original, without anyone writing status?

## Detail panel data model (CONFIRMED by code)
`GET /api/tasks/:id/detail` (`apps/console-api/src/preview/routes.ts`) returns, per task:

| field | source | refresh |
|---|---|---|
| kind (port/fix), title, deps, writes, parts | `docs/team/work-graph.json` row (`parts` = `apps/site/src/parts/<part>` in writes) | on open and on board change |
| state, owner, agent, blockers, evidence | board `plan` (derived by fwcore from the event log) | same |
| git head, source, branch, onMain, containedIn | git facts (`facts.ts`), cached 30 s keyed by the hash of all branch tips | same |
| handoff excerpt (40 lines) | `docs/team/handoffs/<task>.md` on main, an integration ref or the task branch | same |
| preview target and running preview | Lean `console.previewTarget`; manager table | polled every 2 s while building |


Nothing is stored as status. Facts are gathered by git in `facts.ts` (no decision there): the head candidates in priority
order (handoff Branch line, `ci/<task>`, `origin/ci/<task>`, a branch named like the task, the second parent of a merge
naming the task, the newest commit touching the handoff), and for each candidate: is it an ancestor of main, which
integration refs contain it, is its work beyond the newest integration ref documentation only. **Which candidate is the
head and what to show is Lean** (`console.previewTarget` = `Fw.Console.Preview.headOf`).

## Head and target (Lean, `lean/Fw/Console/Preview.lean`, `PreviewTable.lean`)
Head: the first candidate held by main or an integration ref, else the first candidate (`pickHead`). Target: head on main:
`main`; head exactly an integration tip: that ref; else the newest integration ref containing it; a head with no code
that nothing holds: the newest integration ref; else `own(head)`. No candidate but sub-tasks `<task>-*` (an umbrella):
the first integration ref holding all sub-task heads, or `main`, or `none`. `PreviewTable.lean` holds the repository facts
of all 25 `port-`/`fix-` tasks and the investigation's answer and proves `table_matches` (`decide +kernel`); the same
rows are the golden `console.previewTarget.jsonl` (the TS glue is checked against it). `targetOf_filter_invariant` proves
only that dropping integration refs that do not contain the head changes nothing (the docstring no longer claims more).

## Lifecycle
1. request: `POST /api/previews {task}` -> `console.previewAdmit` (refusal order: notOwner, taskBusy, tooMany, lowDisk,
   noTarget, noPorts). K = 2 live previews, disk floor 2048 MB, two ports from 47100..47139 (lowest free), TTL 60 min.
2. build: `git worktree add --detach <consoleDir>/preview/<id>/tree <sha>`, `pnpm install --offline --frozen-lockfile
   --filter @fw/site...`, `apps/site/scripts/build.mjs --engine aot`. Each child is a detached process group, its pid recorded.
3. serve: one detached child (`serve-child.ts`) with two `node:http` servers on 127.0.0.1: the rewrite (prerendered
   pages, media from `snapshot/site`, analytics stubbed, GET/HEAD only, no-store, paths contained by `safeFile`) and the
   original snapshot. `/__fw/compare` is a two-iframe page.
4. expire: a 30 s tick calls `console.previewTick`; every preview past its deadline is stopped (`expired_stopped`).
5. stop: `console.previewStop` returns the kill list; only table entries are killed (`stop_only_own`).
6. cleanup: kill the recorded group (`process.kill(-pid)`) only if `isOurs`: the process still has the start time
   (`ps lstart`) recorded at spawn, leads its own process group, and carries `--fw-preview=<id>` or `/<id>/tree` (a
   recycled pid never matches). `git worktree remove --force`, prune. Nothing is ever killed by name.
7. a failed build leaves the table through Lean (`console.previewFail`: `fail`, `own`; no TS-only path). A stop during a
   build sets a cancel flag: the remaining build steps do not run, the running step's group is killed, the tree is removed
   again after the step ends. A server that crashes after it was ready clears its recorded pid. On console start
   `console.previewReap` stops the previous run's recorded previews with the same `isOurs` check.

## Auth (owner proof)
Owner only. The route reads three facts and sends them to Lean as a `Proof`: `secret` (the request shows the console
secret), `cookie` (the HttpOnly SameSite=Strict owner cookie matches), `origin` (the Origin header is the console's own
loopback origin, or one in `FW_CONSOLE_WEB_ORIGIN`). `Proof.actor`: secret -> lead; cookie and origin -> user; else script.
`mayStart` admits only `user`. Theorem `agent_never_admitted`: a request that fails the cookie, or the Origin, or shows
the secret is refused (`proof_user_iff`). The cookie is minted by the one-time owner link the console prints to stdout at
startup (`/owner?t=<token>`, single use, 303 to `/`); the token and the session value are never written to a file.
Servers bind 127.0.0.1 only.
Residual risk (INFERRED): a process of the same OS user that reads the link from the console's terminal output (or a
background task's output file) before the user opens it, or reads the cookie from the browser profile, is the owner.
Agent-side wait-guard style refusal of Bash commands that call `/api/previews` is not added (it lives in
.claude/settings.json hooks, which this task may not edit).

## Limits
- Previews are logged to `.fw-console/preview/log.jsonl` and `table.json`, not to `events.jsonl` (avoids conflict with
  task-state-truth); they are runtime state, not task state. Open item: bring them into the event log with a reducer rule.
- A build needs the offline pnpm store and about 5 s to a minute; a task whose sha predates `apps/site` cannot build (it fails and cleans up).
- The compare page uses iframes; a page that frame-busts would not show side by side (open the two URLs instead).
- TS stand-ins to replace by Lean: the facts cache (`facts.ts`); git ancestry itself stays glue.

## Lean
Theorems: `headOf_noWork`, `targetOf_landed`, `targetOf_held_not_own`, `targetOf_own`, `pickHead_held`, `targetOf_filter_invariant`,
`table_matches`, `proof_user_iff`, `agent_actor_never_admitted`, `agent_never_admitted`, `admit_user`, `ports_distinct`, `live_le_K`,
`expired_stopped`, `stop_only_own`, `fail_only_own`, `tick_within_period`, plus `reach_inv`, `ports_in_range`, `tick_idem`,
`stop_partition`, `reap_all`. Goldens: `packages/contracts/golden/console/console.preview*.jsonl`.
