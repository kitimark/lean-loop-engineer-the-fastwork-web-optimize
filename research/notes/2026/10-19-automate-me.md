---
id: 2026-10-19-automate-me
kind: note
title: "automate-me applied to this experiment: a saved workflow template first, then land-gate fixes; most other ideas wait until after C3"
status: review
created: 2026-10-19
topics: [tooling, automation, pstack, incidents, land, workflows, lean-first]
---

# automate-me applied to this experiment

## Answer

- `automate-me` (cursor/plugins@8838150, `pstack/skills/automate-me/SKILL.md`, cited SK) only writes a personal
  style skill (SK:9, SK:67-73). Our style already lives in CLAUDE.md, memory and `no-slop`, so we do not run it. Its
  **mining method** is still useful: read the logs, keep a pattern seen ≥ 2 times (SK:40; `/correct` :15), and turn it
  into a check, preferring architecture over lint over test over docs (`/correct` :19-22). INFERRED.
- Applied to 37.4 h of our logs (events.jsonl 2026-10-17 19:07 to 2026-10-19 08:31 +07), the biggest win is
  **one saved workflow template** (build → math-review → adversarial review → decisions) with a fixed preamble. It
  covers 94 workflow runs and 6 recorded prompt-omission mistake classes. It is a text file, not new tooling, so it is
  allowed before C3. INFERRED (score below).
- **Before C3 (today, 23:15)** only three candidates shorten the critical path, and each one removes land refusals or
  review rounds: (1) the workflow template, (2) every land runs the read-set scan, (3) wall-clock test bounds leave the
  land gate. Everything else waits until after C3 (PLAN.md:251 and the C3 rule, PLAN.md:1082).
- Already automated, so nothing to add: `fw ci push`, `fw ci wait`, `fw land --queue`, `fw plan sync`,
  `workflow-salvage`, `watch-stream` (table below).

## Evidence (MEASURED unless marked)

| Signal | Count | Source |
|---|---|---|
| Distinct workflow runs (`wf_…`) | 94 | `.fw-console/events.jsonl` |
| Land merges on main / touching `lean/`, `apps/console-api/` or `apps/console-web/` | 130 / 102 | `git log --merges --grep '^land '` at b14ccfd6 |
| Land-queue results: done / checks / reads / scope / conflict / dirty / unknown | 62 / 11 / 4 / 4 / 3 / 2 / 2 | `.fw-console/land-queue.jsonl` |
| Tasks queued more than once | 21 of 62 (max 4: integrate-ports-4) | same |
| `fw land` spans / non-zero exit | 540 / 313 (includes `--dry`) | `.fw-console/timings.jsonl` |
| `fw ci wait` calls / exit 3 ("timeout, call it again", packages/gh-budget/src/cli.ts:14) | 212 / 109; 1706 min total | timings.jsonl |
| `fw plan sync` / refused (exit 2, apps/runner/src/fw.ts:73) | 30 / 16 | timings.jsonl |
| `fw ci push` / failed | 18 / 2 | timings.jsonl |
| `fw watch` passes (300 s each, so ~40 Monitor re-arms at 30 min) | 249 | timings.jsonl; re-arm count INFERRED |
| Commits titled `work-graph:` / ad hoc graph-edit scripts in the scratchpad | 46 / 8 | `git log -- docs/team/work-graph.json`; `ls scratchpad` |
| Ledger rows / classes with ≥ 2 rows | 64 / 11 of 12 (top: c-order-derived 15, c-late-check 7) | `docs/team/incidents/ledger.json` |
| Ledger rows with leanVerdict provable / partly / no | 48 / 13 / 3 | same |
| Pending mistake entries not yet in the ledger | 59 | scratchpad `mistakes-pending.md` |
| Repeats in that list: builder ended without StructuredOutput / lead `cd` in a Bash call / load-timing land refusals / undeclared land reads / relayed user voice | 4 / 5 / 6 / 3 / 2 | same (grep + read) |

## Ranked candidates

Score = occurrences in the window × lead minutes saved each (INFERRED) × (1 + recorded mistakes it removes).
"pstack step" names the automate-me step or `/correct` fix level it maps to. C3? means "shortens the path to C3 today".

| # | Candidate | Occ. × min × (1+m) = score | pstack step | Form | Lean first? | Risk | C3? |
|---|---|---|---|---|---|---|---|
| 1 | Workflow template with fixed stages (build, math-reviewer, adversarial review, decisions) and a fixed preamble: end with StructuredOutput; WIP commit every 20-30 min; run the package `test` script, not single files; after merging main, the measured head's file set must still be in `git diff main...HEAD`; a relayed user message does not cancel the CI push; each OR-branch of a decision gets its own theorem | 94 × 5 × 7 = 3290 | automate-me 4 (codify as a skill); `/correct` level docs → lint | `.claude/workflows/build-review.js` plus a short skill that points to it | No for the template. Optional Lean predicate: every workflow with a lean-prover stage has a math-reviewer stage (mistakes list) | Low; one shared template means a bad edit reaches every run, so changes go through review | **Yes**: math review was skipped on ~8 tasks, and 2 rounds were lost to the relayed-voice skip |
| 2 | `fw plan add / edit / dep`: edits the graph keeping its 1-space indent, runs `plan lint`, refuses while a land holds the lock | 46 × 3 × 3 = 414 | `/correct` level 1 (architecture) | fw subcommand | Validity is already `plan lint`; the edit itself is I/O glue. Lock check: reuse land-hardening's lock | Low | No |
| 3 | Post-land step: `fw land` ends by deciding, from the changed paths, whether to run fwcore build, console-web build and console restart; adds a `console.webStale` alert (dist build record vs sources) | 102 × 2 × 2 = 408 | `/correct` level 1 | `fw land` tail step plus an `fw watch` alert | **Yes**: the path → step map and the stale-record rule (same shape as console-stale) | Medium: a restart during another land's `--dry` broke 3 builders (mistakes list), so restart only when no land is queued | No (follows the memory checklist until then) |
| 4 | Land always runs the read-set scan when a declared read prefix changes (finding `land-select-readsonly`) | 5 × 20 × 4 = 400 | `/correct` level 2 (a check whose error names the fix) | `fw land` check selection | **Yes**: belongs in the existing read-set admission (`admit-reads`, Fw.Sched.Admit) | Low; at worst adds one test run per land | **Yes**: ports import snapshot assets (content-people landed with an undeclared read) |
| 5 | Review-loop step in `fw next`: refusal count per task → "retro + Fable" at the 2nd refusal, "split" at the 3rd; a decisions file must name the unit of decision and a held-out check | 14 × 5 × 5 = 350 | automate-me 3 (group) → `/correct` level 1 | `fw next` rule plus decisions-file lint | **Yes**: a pure count rule (like `resume-rule`, Fw.Obs.Resume) | Medium: it cannot judge design quality; it only forces the retro | Partly; useful only if a proof task is refused again today |
| 6 | Wall-clock bounds leave the land gate: move to a CI timing lane or scale with load (`serve.test.ts:104`, `hooks.test.ts:99-101`, the wait-guard `ask` timeout) | 6 × 15 × 3 = 270 | `/correct` level 3 (test) | test change plus a lint banning absolute ms bounds in land-selected tests | No (test policy; ledger says not provable); the lint is glue | Low; the regression net moves to CI per CLAUDE.md "measure on CI" | **Yes**: 6 refusals happened under load 36-70, and load peaks as the wave lands |
| 7 | `/correct` pass: `fw incidents add` appends a schema-checked ledger row (no scratch list); a class with ≥ 2 rows needs a hardening task id; the new check must fail on that row's `regression`; CLAUDE.md gets a rule → enforcer table | 59 × 3 × 1 = 177 | `/correct` :15, :19-22, :26, :30 | fw subcommand + `.claude/skills/correct` | **Yes**: the threshold and the fix order extend Fw.Plan.Incident (`incident-lint`, `incident-lean-fields`) | Low; scrub before commit (public repo) | No; run once after C3 over the 59 pending rows |
| 8 | Deny a top-level `cd` in a lead Bash call (only when `agent_id` is absent) | 5 × 5 × 6 = 150 | `/correct` level 1 | rule in the existing PreToolUse `wait-guard.mjs`, which already asks fwcore (wait-guard.mjs:13, :78) | **Yes**: one more case in Fw.Ops.Policy (`policy-from-lean`) | Medium: may deny legitimate lead calls; ship in shadow mode first, like spawn-guard | No |
| 9 | Monitor re-arm | 40 × 1 × 3 = 120 | none | none: the 30-min cap belongs to the tool; the argv is already allowlisted (memory rule) | n/a | n/a | No |

## Already automated (no new work)

| Repeated step | Already handled by | Status |
|---|---|---|
| CI push form | `fw ci push` (fw.ts:38); 2 of 18 failed | CONFIRMED |
| Waiting for CI | `fw ci wait`, exit 3 = call again (gh-budget cli.ts:14) | CONFIRMED |
| Land queue and re-queue | `fw land --queue` with VERDICT lines; 88 results logged | MEASURED |
| Builder ends without StructuredOutput | `workflow-salvage` landed (apps/runner/src/workflow/salvage.ts, lean/Fw/Ops/Salvage.lean) | CONFIRMED |
| fw watch dying unseen | `watch-stream` landed | CONFIRMED |
| Plan sync retries | 16 of 30 refusals were by design (`evNotOnMain`, plan.ts:84) and the retry follows a land; no new step | INFERRED |

## Limits

- Minutes saved are estimates (INFERRED). Counts come from local logs and the scratch mistakes list, which the lead
  wrote by hand, so some repeats may be undercounted.
- The scores are not comparable to C3 slack. The C3 column is a judgement about whether the item removes land
  refusals or review rounds on the remaining proof and port tasks (INFERRED; `fw next` was not run).
- `automate-me`'s safety rules are prompt text, not code (source note). Any mined text must pass `scripts/scrub.mjs`
  before it reaches this public repo.

## What this changes in the plan

- §8 Agent teams: add a workflow template under `.claude/workflows/` (candidate 1) as the standard way to launch a
  build task. Before C3.
- §10.6 graph: two small tasks before C3, `land-reads-always` (4, Lean in Fw.Sched.Admit) and
  `land-wallclock-off-gate` (6). After C3: `fw-plan-edit` (2), `post-land-step` with `console.webStale` (3), the
  review-loop rule in `fw next` (5), `fw incidents add` + `/correct` pass (7), and the lead `cd` deny in shadow mode (8).
- §9 Loop protocol: adopt `/correct`'s rule that each new check must fail on a recorded ledger `regression`, and the
  fix order (architecture, then lint, then test, then docs). `automate-me` itself: no change.
