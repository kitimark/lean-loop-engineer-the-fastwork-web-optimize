---
id: 2026-10-18-plan-automation
kind: note
title: "Plan automation: a Lean land gate, a Lean scheduler (fw next), generated shared files, main-only sync, and a cut line for the next 35 h"
status: review
created: 2026-10-18
topics: [plan, work-graph, lean, fwcore, land, scheduler, spawn-prompts, generators, ci, automation]
---

# Make running the plan automatable, reproducible and Lean-provable

**Question (user, 2026-10-18).** "Can we make the plan more automatable, reproducable script and lean provable?"

**Answer.** Yes, and most of the Lean exists already: what is missing is *composition* and *wiring*, not new theory.
- **Done comes only from git.** `fw land <branch> --task <id>` asks one Lean gate op, merges with a `Task: <id>`
  trailer, and fwcore derives done from the first-parent history. Nobody edits `evidence` by hand again.
- **Start comes from one Lean op.** `fw next` = ready ∩ write-disjoint ∩ admit ∩ caps ∩ GitHub budget, critical path
  first, and it prints a spawn prompt generated from the graph (same graph and snapshot ⇒ same bytes).
- **Parts own folders; shared lists are generated.** Ports then never touch a shared file, and CI checks freshness
  and ownership. This waits until integrate-ports and the running ports land.
- **The board syncs only from `main` at HEAD,** and `fw watch` runs as one long-lived notifier.
- **Cut line:** before the 2026-10-20 13:15 deadline, build only the land gate, typed evidence, main-only sync,
  `fw next` and prompt generation (2 M + 4 S, none of them touches a file a running task writes). Generated part
  files, an hours-weighted critical path, the stale-CI cancel rule and the guard enforcement come after.

**Inputs (task context, not re-measured).** The manual-step inventory covers the lead's own tool calls,
2026-10-17 02:06 to 2026-10-18 02:04: 1,227 Bash calls, 116 merge commands, 164 commands that touched
work-graph.json and 148 spawns of about 1.95k characters each (MEASURED by regex over the transcript, in the task
context). The automation map and the shared-file conflict replay are in the same context.

## 1. What exists (CONFIRMED, @6504ec1)

| Piece | Where | State |
|---|---|---|
| Plan commands `define/drop/claim/done/milestone` | `lean/Fw/Plan/Core.lean:51` | no `release` |
| done ⇔ evidence non-empty | `tstate_done_iff`, `Core.lean:311` | evidence is never validated |
| parallel-safe groups | `groups_pairwise` / `groups_perm`, `Core.lean:781,788` | used only for display |
| glob overlap soundness | `globOv_sound`, `lean/Fw/Plan/Graph.lean:636` | not used at land time |
| critical path (by task count) | `criticalPath_longest`, `Graph.lean:574` | no hours, no slack |
| trailer → done verdicts | `lean/Fw/Plan/Trailer.lean:63,138` | 0 of the last 60 merges carry a trailer (task context) |
| `fw land --task` writes the trailer | `apps/runner/src/land.ts:31,116`; CLI `fw.ts:37-40` | the lead merged by hand instead |
| land path scope | `land.ts:51` `LAND_SCOPE = ["**", …]` | passes every path |
| admission | `admit_iff`, `lean/Fw/Sched/Admit.lean:403` | no caller |
| GitHub budget | `no_issue_when_exhausted`, `lean/Fw/Ci/Budget.lean:752` | landed 84fb01c; runner wiring is `ghb-runner` |
| reconciler step 3b name match | `apps/console-api/src/reconcile/reconciler.ts:71` | decision in TS |
| claim by name | `apps/console-api/src/spool/drain.ts:113-126` | decision in TS |
| deadline | `work-graph.json` `deadline.reportDue = 2026-10-20T13:15+07:00`, checkpoints C1-C4 | not read by Lean |

INFERRED: three watch tasks (`watch-fix`, `watch-slow`, `watch-proc-allow`) and `plan-rev7`/`plan-rev7-1` show no
evidence although later work builds on them. This is the kind of missing "done" fact that §2 removes.

## 2. `fw land <branch> --task <id>`: a Lean land gate

**Module** `Fw.Plan.Land` (new), op `plan.land`. The TS gathers facts (I/O); Lean decides; the TS then acts.

Facts (all gathered by the script, none judged by it):

| Fact | Gathered by |
|---|---|
| `head`, `base`, `mainHead` | `git rev-parse` |
| `changed : List Path` | `git diff --name-only main...branch` |
| `markers : List Path` | `git grep -lE '^(<<<<<<<\|>>>>>>>\|=======$)'` on the merged tree |
| `stale : List Path` | every generator's `--check` (breakgen, scopegen, later sitegen/gen-all) |
| `checks : List (Name × Bool)` | `lake build` (forced, so cached .olean files cannot hide markers), mathview, typecheck then `pnpm test` |
| `ci : List (Workflow × Sha × Conclusion)` | `store.ciRun` rows (no new GitHub polling) |
| `task : Def` | the plan state in fwcore |

Decision:

$$\mathrm{gate}(F,t) \iff \mathit{markers}=\emptyset \land \mathit{stale}=\emptyset \land \forall c\in\mathit{checks}.\ c.\mathit{ok}
\land \forall w\in\mathrm{req}(t.\mathit{writes}).\ \mathrm{green}(w,\mathit{head}) \land
\forall p\in\mathit{changed}.\ \mathrm{gm}(t.\mathit{writes}\cup S,\ p)$$

where $S$ is the closed list of shared generated outputs (Lean constant) and $\mathrm{req}$ maps write globs to the
CI workflows whose path filters match them (one Lean table, also used to generate the workflow `paths:` filters).
The answer is `ok` or a list of typed reasons, never a free string.

Actions after `ok` (glue, no decisions): `git merge --no-ff -m "land <branch>" -m "Task: <id>"`, regenerate
committed aggregates, `worktree remove`, `branch -D`, `fw plan sync`, one "landed" message.

**Evidence.** Done is a function of history:
$\mathrm{done}(G, H) = \{\, x \in \mathrm{ids}(G) \mid \exists c \in \mathrm{firstParent}(H).\ x \in \mathrm{trailers}(c) \,\}
\cup \mathrm{legacy}(G)$. `legacy` is the evidence already in the file, frozen and typed (§3). New evidence is never
typed by hand.

**Theorems** (each docstring states the LaTeX form):
- `land_only_if_gate`: $\mathrm{step}(s, \mathrm{land}(F,t)) \ne s \implies \mathrm{gate}(F,t)$.
- `gate_writes_sound`: $\mathrm{gate}(F,t) \implies \forall p\in\mathit{changed}.\ p \in \mathrm{gm}(t.\mathit{writes}) \lor p\in S$
  (via `globOv_sound`).
- `done_of_history`: $\mathrm{done}$ depends only on $(G,H)$: equal inputs give equal done sets, and replaying
  `git log --first-parent` rebuilds the board.
- `land_idempotent`: $\mathrm{step}(\mathrm{step}(s,c),c) = \mathrm{step}(s,c)$ for a land command $c$; a re-run,
  or a trailer arriving after the record, changes nothing (the reconciler key in `land.ts:126` already dedupes;
  this proves it).
- `done_monotone`: $H \sqsubseteq H' \implies \mathrm{done}(G,H) \subseteq \mathrm{done}(G,H')$.

Golden vectors: `packages/contracts/golden/plan/land.jsonl` (each reason at least once, plus the 8 recorded
conflict shapes as marker fixtures).

## 3. Typed evidence and a plan linter

- `Evidence = commit(sha) | ci(runId) | user(date, ref) | trailer(sha)`. Parsing is a total Lean function;
  the 19 prose entries become `user(...)` or `commit(...)` once, by one migration commit.
- Op `plan.lint` (Lean, golden): ids unique and existing, acyclic (`acyclicB_iff`), title ≤ 200, evidence parses,
  `commit` evidence is an ancestor of main (a fact the script passes in). Theorem `lint_ok_inv`:
  $\mathrm{lint}(G)=\mathrm{ok} \implies \mathrm{Inv}(\mathrm{run}(\mathrm{sync}(G)))$.
- Hand edits go through typed verbs (`fw plan add|dep|cut|evidence`) that write the JSON and then run `plan.lint`,
  so the 101 python heredocs have nothing left to do.

## 4. `fw next`: a Lean scheduler and generated spawn prompts

**Module** `Fw.Plan.Next`, op `plan.next`. Inputs: plan state, running set, the `fw watch` snapshot (load and memory
class, live agents), `Fw.Ci.Budget` status, and caps $K$ (agents) and $B$ (resource `Vec`).

Choice: walk the ready set in order (critical-path tasks first, then by `criticalPath` rank, then id); take $t$ when
$|\mathit{running}|+|\mathit{chosen}|<K$, `admit` says yes (`Admit.lean:284`: write overlap, exclusive devices,
deps landed, resource vector), `globOv` is false against every running and chosen task, and, for a task whose
writes need CI, budget headroom holds (`headroom_iff`).

**Theorems:**
- `next_cap`: $|\mathit{running}| + |\mathrm{next}(\cdot)| \le K$, and the summed demand stays within $B$.
- `next_disjoint`: $\forall a\ne b \in \mathrm{next}\cup\mathit{running}.\ \neg\mathrm{globOv}(a.\mathit{writes}, b.\mathit{writes})$.
- `next_ready`: $t\in\mathrm{next} \implies \mathrm{tstate}(t)=\mathrm{ready}$.
- `next_critical_first`: if $c$ is on the critical path, $n$ is not, both are admissible alone, and $n \in \mathrm{next}$,
  then $c\in\mathrm{next}$ or adding $c$ would break a cap or disjointness.
- `next_maximal`: no admissible ready task is left out while a cap still has room (no idle capacity).
- `next_budget`: no CI-needing task is chosen when `Fw.Ci.Budget` reports no headroom.

**Spawn prompts.** Op `plan.prompt(t)`: a pure function of the graph and a Lean rules table `Fw.Plan.Rules`
(rule id, text, trigger: always, or by writes or devices). It emits the title, writes, deps' handoff paths,
reports-to, worktree, handoff path and only the rules that the task's writes and devices trigger (Lean-first, LaTeX
docstrings, measure on CI, never push, kill by PID, scrub, rate-limit). Theorems: `prompt_rules_complete`
(every triggered rule appears) and `prompt_det` (bytes are a function of $(G,t)$). Golden:
`golden/plan/prompt.jsonl`. This removes the 133/118/110 repeated paste blocks and the late spread of the rate-limit
rule; a new rule is one row, and it reaches every later prompt.

`fw next --spawn` prints `{task, prompt}` lines. The lead still makes the actual spawn call (a harness tool, not a
shell command), and the spawn guard checks it against the same op.

## 5. Generated shared files (ports never conflict)

Adopt the design from the conflict replay (task context): each part owns `apps/site/src/parts/<id>/**`,
`lean/Fw/Parts/<Id>/**` and `golden/parts/<id>*`. The registry, App slot tree (Lean `sitegen`), Census and entry maps,
`Fw/Parts/All.lean`, per-part `scope/<id>.gen.json` (union via a `gate.scope` op), split anchors, and prepare steps as
data are all generated or collected. Lean theorem `owns_disjoint`:
$p\ne q \implies \mathrm{owns}(p)\cap\mathrm{owns}(q)=\emptyset$.

CI: every generator runs with `--check` then `git diff --exit-code`; `git ls-files` must list no combined aggregate;
`fw plan owns --base main` fails a `port-*` branch on any path outside its part. The same `owns` table feeds the land
gate's $t.\mathit{writes}$ for ports, so §2 and §5 share one rule.

The same pattern applies to fwcore's own registry: `lean/Fw/Wire.lean:448` (op list) and `lean/FwTestMain.lean`
conflicted 5 times (task context). A collected `Fw/Wire/All.lean` removes that conflict.

## 6. Board hygiene

- **Main-only sync.** `plan.sync` takes $(\mathit{blob}, \mathit{mainHead})$; Lean accepts only when
  $\mathit{blob} = \mathrm{hash}(\texttt{main:docs/team/work-graph.json})$ and `plan.lint` is ok.
  Theorem `sync_only_main`. A draft lives on a branch and cannot reach the board (fixes the early sync of a draft).
- **One watch.** `fw watch --follow` keeps running, dedupes alerts by `(code, subject)` with a Lean re-alert rule
  (`Fw.Obs.Health` already sorts and codes them), and posts each new alert once. The 42 relaunches go away. Watch
  `SCOPE` and `DEFAULT_PARAMS` become Lean-generated constants with golden vectors.
- **Hours and slack.** Optional `est` (hours) on `Def`. Lean computes the weighted longest path and
  $\mathrm{slack} = \mathrm{reportDue} - \mathrm{now} - \mathrm{cp}_h$. Theorems: `cpH_longest` (the weighted version of
  `criticalPath_longest`) and `cut_restores_slack` (cutting the returned set makes slack ≥ 0 when such a set exists
  among the cuttable tasks).
- **Release.** Add `Cmd.release(task, reason)`, sent when `obs.health` reports `agent.gone`, or `agent.stalled`
  past its limit. Theorem `exec_inv` extended (release keeps `Inv`), plus `release_ready`: a released task with landed
  deps is `ready` again.
- **Capability canon.** `cd x && pnpm fw …` normalises to `pnpm fw …` by one Lean function the hook mirrors
  (golden), which fixes the 7 refused calls.

## 7. What stays manual, and why

| Step | Why it stays with a person |
|---|---|
| User decisions (D1/D2, Q-answers, paid runners) | they are the user's, recorded as `user(...)` evidence |
| Pushing `main`, remotes, repo creation | CLAUDE.md rule: only the user does it |
| Real-phone sessions | need the user's hands and booked time; the lead relays one step at a time |
| Content of a merge conflict | judgment; the gate only detects it and refuses |
| PLAN prose and the report text | writing, reviewed by the user |
| The spawn call itself | a harness tool call by the lead; `fw next` prepares it |

## 8. Prioritized tasks and the cut line

Running tasks whose files these tasks must not touch: ports (`apps/site/src/parts/**`), `engine-*`
(`lean/Fw/Engine/**`, `lean/Fw/Measure/EngineCheck.lean`, `apps/runner/src/engine-check.ts`), `ghb-glue`
(`packages/gh-budget/**`), `ghb-runner` (`apps/runner/src/{run,ci,watch-collect,fw}.ts`) and `integrate-ports`
(`packages/gate-breakpoints/src/**`, `apps/site/src/App.tsx`, `apps/site/src/registry/index.ts`,
`lean/Fw/Gate/Scope.lean`). Lean tasks that register an op serialise on `lean/Fw/Wire.lean` and
`lean/FwTestMain.lean` (so the deps below chain them).

| # | id | Size | Deps | Writes | Note |
|---|---|---|---|---|---|
| 1 | `pa-land-lean` | M | — | `lean/Fw/Plan/Land.lean`, `lean/Fw/Wire/PlanLand.lean`, `lean/Fw/Wire.lean`, `lean/FwTestMain.lean`, `golden/plan/land.jsonl` | §2 theorems |
| 2 | `pa-land-cli` | S | 1 | `apps/runner/src/land.ts`, `apps/runner/test/land*.ts` | gate op replaces `LAND_SCOPE`; markers, gen-check, cleanup, sync. Avoids `fw.ts` (dispatch exists) |
| 3 | `pa-evidence-lint` | S | 1 | `lean/Fw/Plan/Lint.lean`, `lean/Fw/Wire/PlanLint.lean`, `lean/Fw/Wire.lean`, `lean/FwTestMain.lean`, `golden/plan/lint.jsonl`, `docs/team/work-graph.json` (one migration) | §3; lead lands the migration |
| 4 | `pa-sync-main` | S | 3 | `apps/runner/src/plan.ts`, `lean/Fw/Plan/Lint.lean` | §6 main-only sync |
| 5 | `pa-next-lean` | M | 3 | `lean/Fw/Plan/Next.lean`, `lean/Fw/Plan/Rules.lean`, `lean/Fw/Wire/PlanNext.lean`, `lean/Fw/Wire.lean`, `lean/FwTestMain.lean`, `golden/plan/{next,prompt}.jsonl` | §4 incl. prompts |
| 6 | `pa-next-cli` | S | 5, `ghb-runner` | `apps/runner/src/next.ts`, `apps/runner/src/fw.ts` | waits for ghb-runner (fw.ts) |
| — | **cut line** (2026-10-20 13:15 deadline; build above, ~10 agents still busy) | | | | |
| 7 | `pa-release` | S | 5 | `lean/Fw/Plan/Core.lean`, `apps/console-api/src/spool/drain.ts` | §6 release; drain claim rule to Lean |
| 8 | `pa-watch-follow` | S | `ghb-runner` | `apps/runner/src/watch.ts`, `lean/Fw/Obs/**` | §6; generated SCOPE/params |
| 9 | `pa-hours-slack` | M | 3 | `lean/Fw/Plan/Graph.lean`, `docs/team/work-graph.json` (est) | §6 slack and cut set |
| 10 | `parts-split-infra` | L | `integrate-ports`, all `port-*` | §5 files (App.tsx, registry, Scope.lean, gate-breakpoints, Fw.lean, Golden.lean) | touches every running port's shared files: strictly after |
| 11 | `wire-all-gen` | S | 1, 3, 5 | `lean/Fw/Wire.lean`, `lean/FwTestMain.lean`, `lean/scripts/gen-wire.mjs` | §5 for fwcore ops |
| 12 | `pa-ci-cancel-stale` | S | `ghb-runner` | `lean/Fw/Ci/Cancel.lean`, `apps/runner/src/ci.ts` | cancel non-latest or stale-base runs |
| 13 | `pa-guards-enforce` | M | 5, 8 | `apps/runner/hooks/spawn-guard.mjs`, `apps/console-api/src/reconcile/reconciler.ts` | feed `alive`, enforce, step 3b to Lean |
| 14 | `pa-cap-canon` | S | — | `apps/runner/hooks/cap.mjs`, `lean/Fw/Ops/Identity.lean` | §6 capability canon |

**Why the cut falls there (INFERRED).** Tasks 1-6 remove the largest costs: landings (116 merges, 20 failed) and
graph edits (164 commands). They touch only new files plus `land.ts`/`plan.ts`, so they run beside the experiment.
Task 9 would need estimates on about 95 open tasks, which costs lead time the deadline does not leave. Task 10 would
collide with every running port and with integrate-ports. Tasks 7, 8 and 12-14 save less, and enforcing guards in
the middle of the experiment risks blocking live work.

## Review (adversarial, same day) and the lead's decision

An adversarial reviewer read this note and checked it against the code. Corrections:

- **The trailer count is wrong.** 31 of the last 60 merges on main carry a `Task:` trailer (MEASURED). Lean already has `plan.trailers` (`lean/Fw/Wire/Console.lean:103`).
- **`fw land` already exists, and the lead never used it.** It already does most of what this note calls missing:
  - readiness from Lean (`land.ts:85`);
  - the checks (`land.ts:93-98`);
  - the Lean `path-check` (`land.ts:102`);
  - the rebase, and recording `task.done`.

  The real gaps:
  - `LAND_SCOPE = **` (`land.ts:51`) makes the path check pass any file;
  - the cleanup is unsafe: it uses `branch -D`, removes worktrees without a liveness check, and rebases running agents' branches;
  - "CI green on head" can never hold after a rebase.
- **Vacuous theorems** (purity restated): `prompt_det`, `done_of_history`, `sync_only_main`, `land_only_if_gate`.
- **False as stated:** `owns_disjoint` (prefix globs) and `cut_restores_slack` (it needs subset selection).
- **The forced `lake build` is not needed.** A conflict marker changes the source hash, so lake rebuilds anyway (INFERRED). The earlier miss came from the build target not covering the module.

**Decision (lead).** Before the deadline:

1. **`pa-land`** (S-M), fixing `fw land` so the lead lands every branch through it.
   - The scope comes from `task.writes` ∪ S, where S is handoffs plus generated files. The decision is in Lean, with a non-vacuous path-matching theorem.
   - Marker check.
   - Safe cleanup: `branch -d` only; refuse a live agent's worktree or one with uncommitted changes.
   - Merge, never rebase, a branch an agent still holds.
   - CI is advisory.
   - Never push, never force, merge only into the lead's main checkout.
2. **`pa-evidence-lint`** (S): lint only, plus a back-fill of evidence from `Task:` trailers.
3. **`pa-sync-main`** (S): a TS check that sync runs from main at HEAD.

Everything else waits until after the deadline: the `fw next` scheduler, prompt generation, release, watch-follow, the parts split, wire-all-gen, stale-run cancel, enforced guards and capability canonicalisation. `pa-hours-slack` is dropped.
