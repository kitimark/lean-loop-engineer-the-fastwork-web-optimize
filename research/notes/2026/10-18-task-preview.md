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

Nothing is stored as status. The task head is found by a TS stand-in (`findHead`): handoff Branch line, `ci/<task>`,
`origin/ci/<task>`, a branch named like the task, then the second parent of a merge naming the task. No reliable
task-to-branch link exists in the events (INFERRED from the investigation). The rule should move to Lean.

## Preview target (Lean, `lean/Fw/Console/Preview.lean`)
No head: `none`. Head on main: `main`. Else the first integration ref (newest first) containing the head:
`integration(ref, sha)`. Else `own(head)`. Theorem `target_deterministic`: only the candidates that contain the head matter.

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
6. cleanup: kill the recorded group (`process.kill(-pid)`), `git worktree remove --force`, prune. A failed build cleans itself.
   On console start `console.previewReap` stops the previous run's recorded previews, verifying with `ps -o command=`
   that the pid's command line holds `--fw-preview=<id>` or `/<id>/tree`. Nothing is ever killed by name.

## Auth
Owner only. Lean `mayStart` admits only actor `user` (`agent_never_admitted`). The actor is stamped by the route, never
read from the body (`cap.ts`: `SECRET_HEADER`, `secretMatches`, `actorFor`): a caller showing the console secret is stamped
`lead` and refused; the browser, which has no secret, is `user`. A foreign Origin and non-JSON content types are refused
(blocks cross-site pages). Servers bind 127.0.0.1 only.
Residual risk (INFERRED): an agent of the same OS user sending curl with no secret and no Origin is stamped `user`. The
console cannot tell it from the browser; the limit is the same as for every other user-only door in the console.

## Limits
- Previews are logged to `.fw-console/preview/log.jsonl` and `table.json`, not to `events.jsonl` (avoids conflict with
  task-state-truth); they are runtime state, not task state. Open item: bring them into the event log with a reducer rule.
- A build needs the offline pnpm store and about 5 s to a minute; a task whose sha predates `apps/site` cannot build (it fails and cleans up).
- The compare page uses iframes; a page that frame-busts would not show side by side (open the two URLs instead).
- TS stand-ins to replace by Lean: `findHead` and the facts cache (`facts.ts`).

## Lean
Theorems: `target_deterministic`, `ports_distinct`, `live_le_K`, `agent_never_admitted`, `expired_stopped`, `stop_only_own`,
plus `reach_inv`, `ports_in_range`, `tick_idem`, `stop_partition`, `reap_all`. Goldens: `packages/contracts/golden/console/console.preview*.jsonl`.
