---
id: 2026-10-17-team-review-fable
kind: note
title: "Whole-team review: goal fit, process, speed, quality, and 12 ranked improvements"
date: 2026-10-17
created: 2026-10-17
status: draft
topics: [team, orchestration, review, critical-path, lean-first, measurement-validity, token-policy]
links:
  - docs/plan/PLAN.md (rev 6, a48aa54)
  - docs/team/improvements/2026-10-17.md
  - docs/team/work-graph.json (8603d7f)
  - research/notes/2026/10-17-token-usage-profile.md
  - research/notes/2026/10-17-parallel-work-measure.md
  - research/notes/2026/10-17-spk-drafts/spk-c.md
  - research/notes/2026/10-17-spk-drafts/spk-p.md
---

# Whole-team review (independent, fresh eyes)

Reviewer: Fable (`fable-team-review`), read-only. HEAD `8603d7f`. Sources: the plan, the catch-up log, the work
graph, role files, settings, handoffs, four research notes, `git log`, and the hook spool (`.fw-console/spool/`,
field names and counts only). Every claim carries CONFIRMED (file, commit or doc cited), MEASURED (computed here or
in a cited note) or INFERRED.

**Summary.** The team ships fast (167 commits and 19 merges in 6 h 25 min, MEASURED) and its infrastructure work is
real, but the experiment's own critical path (M1: the original measured) has moved the least. Of 43 open tasks, 11
are labelled M0 and only 2 of the 6-task M1 chain are ready; the whole M1 chain is serial and owned by one role on
two devices. The lead spends a measurable share of its time on hand-written bookkeeping and compaction, two of its
own rules (`fw land` only, nobody writes status) are not enforced on itself, and the measurements that M1 depends on
were taken on an oversubscribed Mac. The ranked list at the end puts the critical path first.

## A. Goal fit

| Claim | Evidence | Status |
|---|---|---|
| The plan's critical path is store-and-run + M0 closures → M1 → pilot PL3-PL6 (M2) → M4 → M5 | PLAN.md:1207-1211 | CONFIRMED |
| Open tasks by milestone: M0 11, M1 10, M2 9, M3 6, M4-M6 3, none 4 (43 open of 67) | `jq` over work-graph.json | MEASURED |
| M1 chain is serial: ci-webkit → webkit-quiet → zone-baselines → vj-vt, plus touch-wedge and measure-ts-to-lean → zone-baselines; every link but one is `measure-engineer`, devices simulator/docker; only ci-webkit and touch-wedge are ready | work-graph.json tasks `webkit-quiet`, `zone-baselines`, `vj-vt`, `touch-wedge` | MEASURED |
| `store-and-run` (artifact store, `fw run --dry`, V-j) is on the plan's critical path but has no task in the work graph; the nearest, `fw-ci`, depends on `con-plan` (a console view) | PLAN.md:1174, 1210; work-graph.json `fw-ci.deps = [ci-webkit, lean-ci-cache, con-plan]` | CONFIRMED |
| 7 of the 11 open "M0" tasks are not M0 gate conditions: lean-plan, con-plan (console Plan view), watch-lean, watch-cli, watch-web (health watch), spk-p-wake, lean-console-gaps. The M0 gate text asks for classes, the scrub check, `fwcore serve` with signed math and mutants, the step queue, and the SPK records | PLAN.md:1220 vs work-graph.json milestones | CONFIRMED |
| Side work that landed today and does not move M1-M2: team health watch (3 tasks), console Plan view (2), spawn-guard liveness/enforce (3), parallel A/B bench, explainer page, WKTR route research (M3, correctly labelled). Each was a user request or a plan item; none is wrong, but together they are 12 of 43 open tasks | catch-up log 19:34, 19:04, 19:28 entries; work graph | CONFIRMED |
| Open-task ownership: measure-engineer 15, lean-prover 9, researcher 5, lead 5, console-builder 4, part-builder 2 | `jq` over work-graph.json | MEASURED |

**Reading.** The team is doing good work mostly *around* the experiment (console, hooks, policy, CI, Lean ops,
scheduling) and comparatively little *on* it: in 6 h, the measurement lanes produced two landings each
(e01f9e5/70c3370, 1d6c88c/367fec2), both still with open blockers (the original's touch wedge, WebKit per-step
jitter), and no per-zone baseline of the original exists (CONFIRMED, work graph `zone-baselines` open). The user's
G1 needs the phone, and Q1 (phone windows) is still unanswered, so M3 cannot start either.

**Cut / defer / merge (recommendations):**
- Defer `watch-web`, `con-plan` and `lean-plan` until after M1: the work graph is already readable with `jq`, and
  the lead syncs it by hand anyway. Re-label them out of M0.
- Merge `spk-p-wake` into `spawn-guard-workflows` (both are hook-payload questions for one researcher, one spool).
- Add a `store-and-run` task (owner console-builder, deps `measure-ts-to-lean`) and drop `con-plan` from `fw-ci.deps`.
- Keep `cap-actor-fix` (security) and `m0-mutants`, `math-r6`, `spk-i-record` (real M0 gate items).

## B. Proper: rules, enforcement, incidents

| Finding | Evidence | Status |
|---|---|---|
| **`fw land` is not used.** PLAN §8.2: "Every change reaches `main` only through the lead's `fw land`". 19 merges on `main`; the console event log holds 17 events, all `step.*`, 0 `land`, 0 `violation`, including the 3 merges at 19:15 made after the console started at ~19:05 with a fresh log. The git reconciler flagged nothing | PLAN.md:1025-1028; `.fw-console/events.jsonl`; `git log --merges`; land.ts:100 posts `/api/agent/commands` | MEASURED (0 land events), INFERRED (lead merged by hand) |
| **The lead hand-writes status.** 22 of 167 commits are "catch-up log" (31 KB, hand-written prose with numbers) and 12 are "work graph" edits (21 KB JSON with `owner`): 34 commits (20 %) are lead bookkeeping. CLAUDE.md:14 says "Never write status; the console derives it from events"; the graph's `about` says "No status here", but `owner` and the lead's manual `evidence` stamps are status by another name | `git log` prefixes; work-graph.json `about`; CLAUDE.md:14 | MEASURED, INFERRED (classification) |
| **Lean-first debt** is honest and listed (R32): `verdict.mjs`, `classes.mjs` thresholds, `compositeCuts`, `reduceWindows`, four console ops. It has tasks (`verdict-to-lean`, `measure-ts-to-lean`, `lean-console-gaps`). No `sorry` in 39 modules / 597 theorems | PLAN.md:1266; `grep` over `lean/Fw` | CONFIRMED, MEASURED |
| **Privacy in a public repo:** tracked files outside `snapshot/` contain only placeholder emails (`example.com`, `example.invalid`) and a one-letter `/Users/<x>` test fixture; 0 LAN IPs. All 167 commits carry the user's personal email (user-accepted, log 19:55). No scrub hook exists yet; the only guard is a one-off grep (454cbe0) | `git ls-files | xargs grep`; PLAN.md:1448 (scrub "planned for M0") | MEASURED |
| **Capability spoof (fixed in progress):** `cap.mjs:47` mapped an empty `agent_type` to the lead; 225 of 249 SubagentStops are internal forks with empty type. 8 of 8 `caps.jsonl` records were "lead". Fail-closed fix is task `cap-actor-fix` | spk-c.md "Decision 1" | CONFIRMED |
| **Spawn-guard sees a minority of spawns:** 7 SpawnGuard records (5 allow, 1 deny, 1 needsApproval) against 31 SubagentStart and 7 `Workflow` tool calls in the same window; Workflow spawns skip `PreToolUse(Agent)` (18 of 26 starts). Shadow mode blocks nothing | spool counts; spk-c.md gap 1 | MEASURED |
| **Process kills:** the `pkill -f "Google Chrome"` incident got a CLAUDE.md rule (6fba06c) but no deny rule: `settings.json` deny list has 0 entries matching `pkill`/`killall` | `jq .permissions.deny` | MEASURED |
| **Single writer / lost work:** pub-prep wrote 3 files into the main checkout (removed before merge); lean-serve and con-land were built in parallel and lean-serve removed a TS state that con-land read, breaking 6 tests (fixed by con-wire); a merge of meas-chromium-2 left a duplicate import that CI caught (ee18c6b). No lost commits found | catch-up log 20:40, 19:55; ee18c6b | CONFIRMED |
| **Review gaps:** code merges have no reviewer step; only PLAN revisions and math got adversarial review (two reviewers for rev 6, math rounds r4/r5). The role `reviewer` ran 2 agents / 88 tool records in the 2.3 h spool window. §8.2 says "every change's review stage" | spool by `agent_type`; PLAN.md:999 | MEASURED, CONFIRMED |
| **Math first-pass quality:** r4 71 of 258 disagree (27.5 %), r5 62 of 490 (12.7 %); each round is a 3-generation loop (prover → reviewer → fixer → re-review). The free-variable lint cut flagged entries 181 → 71 | catch-up log 16:58, 18:00, 18:5x; 28b18ee | MEASURED |
| **Decisions waiting on the user:** Q1 (phone windows) blocks `gap-device` and `calibration` (M3) and G1; Q31 (spawn-guard blocking) and Q32 (A/B bench window) block only agent-ops. Nothing on the M1 → M2 chain waits on the user | work graph `q1-phone`, `spawn-enforce`, `ab-bench` | CONFIRMED |
| **Permission laundering:** none found. Settings changes were "approved by you" each time (3e67d48, a0b9053, 6756bb9); the console refused the lead answering Q33 for the user (`refused.jsonl`: "actor lead may not cause step.answer") | catch-up log; `.fw-console/refused.jsonl` | CONFIRMED |
| **Incidents and root causes** (today): Mac sleep read as API stalls (caffeinate lapses) → one `caffeinate -i -w`; load1 ~430 with 0 % idle from 4 parallel clean Lean builds + Simulator reboots every ~2 min + 20 orphaned stress loops → wt-prep, Lake cache, `--keep`; CI snapshot check hit a gitignored tree twice; Lake artifact cache dropped `.olean` (67192ef); webkit-sim CI fails at warm-up on 3-vCPU runners (open) | catch-up log 16:55, 17:50, 18:40; plan.md L5 | CONFIRMED |

## C. Faster: where wall-clock goes

| Finding | Evidence | Status |
|---|---|---|
| **Shell-bound lanes set the wall time.** In the 2 h 19 min spool window: 1,771 Bash calls, total 353 min; the 66 calls over 60 s take 287 min (81 %) and 40 of those 66 are `measure-engineer`, 15 `lean-prover`. p50 0.3 s, p90 9.7 s, p99 358 s, max 604 s | spool `duration_ms` | MEASURED |
| The breakpoint gate takes 554 s (528 s with `--parts`, which saved nothing because every probe applies to every part); a full gate run is ~20 min on this Mac at concurrency 3 | catch-up log (part-hero-3, gate-part-filter); gate-breakpoints.md:122 | MEASURED |
| Lean lint ~17 s CPU per `check.sh`; `check-fast` 45.7 s "mostly lint" on a busy machine; cached builds 0.2 s | handoffs lean-fast, lean-sched | MEASURED |
| **The lead is a serial hub.** Busy 46 % of a 219-min window (65 % in the peak hour); 31 of 60 agent events queued behind it; follow-up gaps of 14.7 and 15.9 min between a lane's agent ending and its successor starting | parallel-work-measure.md §4, §6 | MEASURED |
| The lead compacted 12 times in 2 h 19 min; 9 matched pairs lasted 30-100 s, 552 s in total (~6.6 % of the window); the lead itself ran 191 Bash and 9 Edit calls (286 of 2,261 PostToolUse, 12.6 %) | spool PreCompact/PostCompact, null `agent_id` | MEASURED |
| **Concurrency cap hit:** "Waiting for a slot (10-agent cap): spk-hooks, breakpoint-lint, css-decisions" while finished agents stay alive: four agents whose tasks are done (explainer-rev6, lean-math-fix-r5, spk-hooks, wktr-ci) are still listed active at review time | catch-up log 19:05; work graph `evidence`; the session's active-agent list | CONFIRMED, INFERRED (they hold slots or cache) |
| Sleep-polling cost 110 agent-min in the measured window (78 in the two measurement lanes and the gate); the role text now forbids it, no hook enforces it | parallel-work-measure.md §6 row 1 | MEASURED |
| **Cache TTL:** every agent writes 5-minute cache; 3.0 M tokens were cold rewrites (14 events); the lead is 1 h | token-usage-profile.md §d | MEASURED |
| **Cost shape:** 80.25 M units; tool results carried in context 66 %; workflow subagents 58 %; Opus 85 % of tokens, 96 % of price-weighted cost; 46 agents crossed 150k context; 4 % of tool results (> 10k tokens) carry a third of the cost | token-usage-profile.md §0, §a, §f | MEASURED |
| **Model per role today:** lean-prover Opus/high (11 agents, 950 tool records = 42 % of agent tool calls), measure-engineer Sonnet/high (6 agents, 451), researcher and plan-editor Opus/high, reviewer and math-reviewer Opus. Haiku helpers exist (scout, runner) but the spool shows 0 `scout`/`runner` SubagentStarts in the window: the helper policy is not used yet | `.claude/agents/*.md`; spool SubagentStart by type | MEASURED |
| Oversized prompts / re-work: plan-rev5 reached 428k context from 4 Reads of 19-25k tokens at request 2; math fixes needed two full rounds; the deterministic-mode re-run and the gate `--parts` work produced no speed-up | token-usage-profile.md §a; catch-up log | MEASURED |

**Where the hours would come back (INFERRED estimates, see the ranked list):** the M1 measurement chain is ~4
serial device-bound tasks of 1-2 h each on one role; splitting it across devices (CI runners for Chromium, the
Simulator for WebKit) and starting `zone-baselines` for Chromium without waiting on `webkit-quiet` removes one or
two links. The lead's bookkeeping (34 commits, ~9 min of compaction, 191 Bash calls) is 20-30 % of its turns; a
generated log and `fw land` with auto-logging would return most of that. Stopping finished agents frees slots.

## D. Better: evidence quality and orchestration design

| Finding | Evidence | Status |
|---|---|---|
| **Measurement validity is the weakest link.** WebKit per-step Layout/Paint/InvalidateLayout stay quarantined; base-mode counts correlate with host load (r 0.55-0.94, n = 6, confounded with pass order); the Mac ran at load 130-450 with 0 % idle during the runs. Chromium: the original's touch run wedges at low load, so "the class table for the original is from before that change" and no original touch counts exist | meas-webkit.md:8-17; meas-chromium.md:16-26; catch-up log 17:50 | MEASURED |
| CI runners gave a clean classification on 3 separate quiet machines (33 deterministic / 20 stable / 9 quarantined) in 5 min; this is a better counts-of-record environment than a Mac running 10 agents | catch-up log "CI third run" | MEASURED |
| Determinism re-scope (per-type classes, V-i) is sound and proved (`Fw/Measure/Classes`), but the gate still relies on "run twice, compare byte-for-byte" in the measure-engineer role text, which the plan now says is unreachable | PLAN.md:152; measure-engineer.md body | CONFIRMED (contradiction) |
| Lean coverage is wide (39 modules, 597 theorems, 1,175 math rows agree, 62 stale) and catches real errors (the false aging bound, 4bd850f). But the proved pieces are mostly *ops* (SpawnGuard, PathCheck, Sched, Serve); the experiment's own decision rules (`verdict.mjs`, class thresholds, WebKit cuts) are still TS | catch-up log 18:00; R32 | CONFIRMED |
| Mutants (V-r) do not exist yet: no `lean/FwTest/Mutants/`; `m0-mutants` is ready but unstarted. Until then "wrong spec, correct proof" (R6) is covered by math review only | plan.md:8; work graph | CONFIRMED |
| Review depth: code lands unreviewed; plan and math get two-reviewer passes. Research notes carry statuses consistently (good); the catch-up log mixes MEASURED numbers with narrative and has been corrected twice (17:50 load1, L5 orphan loops) | plan.md L5; catch-up log 18:40 | CONFIRMED |
| **Orchestration design:** roles are well-scoped and slim (custom roles write ~4k tokens at spawn vs 15-32k for built-ins); handoffs exist for 22 of 24 done tasks; the work graph is the right artefact but is hand-synced. Workflows (multi-agent `Workflow` tool) carried 58 % of cost and bypass spawn-guard; single named agents are cheaper and visible | token-usage-profile.md §c; `ls docs/team/handoffs`; spk-c.md | MEASURED |
| Hook spool keeps 9 fields and drops `source`, `background_tasks`, `teammate_name`, so SPK-p part 2 (wake) cannot be answered from it; the emit allow-list is also what keeps the public repo free of payload text (good trade, needs a count field) | spk-p.md "Missing"; emit.mjs:23-33 | CONFIRMED |
| Health watch (`fw watch`) is being built as three tasks before any stall has been observed in v2 (0 StopFailure, 3 TeammateIdle in the spool). R7 ("over-engineering before the first measurement") applies | spool; PLAN.md:1241 | MEASURED, INFERRED |

## Ranked improvements (impact first; at most 12)

Effort: S < 1 agent-hour, M 1-3 h, L > 3 h. Effects are INFERRED unless marked. "User" = needs the user's decision.

| # | Change | Why (evidence) | Expected effect | Effort | Owner | Deps / User |
|---|---|---|---|---|---|---|
| 1 | **Make the M1 chain parallel and device-split.** Split `zone-baselines` into `zone-baselines-chromium` (deps: touch-wedge, measure-ts-to-lean; runs on CI runners via `fw-ci`) and `zone-baselines-webkit` (deps: webkit-quiet); add the missing `store-and-run` task; drop `con-plan` from `fw-ci.deps`; give the WebKit half a second measure-engineer | §A: serial 4-link chain, one role, 2 of 6 ready; store-and-run missing; CI classes 33/20/9 on quiet runners (MEASURED) | M1 reached 1-2 links (2-4 h) earlier; baselines taken on quiet machines (validity) | S (graph) + M (tasks) | lead (graph), measure-engineer ×2, console-builder | none |
| 2 | **Use CI runners as the Chromium counts lane of record; keep the Mac for WebKit and builds.** Pin the runner image, record load/CPU in run meta, require `--runs 3` on separate jobs | §D: Mac load 130-450 during counts; per-step jitter correlates with load (r up to 0.94, n = 6); CI already green in 5 min (MEASURED) | Removes host-load confound from Chromium classes; frees ~2 cores and the Docker VM locally; webkit-quiet can run with fewer neighbours | M | measure-engineer | #1 (`fw-ci`) |
| 3 | **Stop finished agents and enforce it.** `TaskStop` every agent whose task has `evidence`; add a SubagentStop/TeammateIdle hook rule (Lean `obs.health` already planned) that lists done-but-alive agents on the lead's next turn | §C: cap of 10 hit while 4 done agents stay alive (CONFIRMED); 5-min cache means they cost a cold rewrite if resumed (MEASURED 3.0 M tokens today) | 2-4 slots freed now; fewer cold rewrites (~1 M units/day) | S | lead now; console-builder for the hook | none |
| 4 | **Land only through `fw land`, and let it write the log.** The lead runs `fw land <branch>`; the land command appends the catch-up entry (title, commit, tests) from the card and the agent's ≤ 300-char report; the reconciler's violation list becomes visible on the board | §B: 0 land events for 19 merges; 22 hand-written log commits (MEASURED); PLAN §8.2 rule unenforced on the lead | Removes ~20 % of lead commits and the matching model turns; the "nobody writes status" rule holds for the lead too; violations become detectable | M | console-builder (land/log), lead (habit) | `fw land` exists (840f7d6) |
| 5 | **Shift math review left.** Lean-prover spawns `checker` (Sonnet) on its own docstrings against a 6-item checklist (free variables, quantifier order, Nat/Int semantics, hypotheses, edge cases, plain sentence) before handoff; math-reviewer rounds then re-review only entries the checker passed | §B: r4 27.5 % and r5 12.7 % disagree (MEASURED); each round is three agent generations | Halves the disagree rate per round (INFERRED); one fewer Opus round per module (~1-2 M units per round) | S (role text) | lean-prover role, lead | helpers already allowed (D2) |
| 6 | **Re-label and defer non-gate "M0" work.** Move lean-plan, con-plan, watch-* , spk-p-wake, lean-console-gaps out of M0 (to "ops" or M1+); merge spk-p-wake into spawn-guard-workflows | §A: 7 of 11 open M0 tasks are not in the M0 gate text (CONFIRMED); R7 | M0 closes on its real conditions (mutants, math-r6, SPK-i, cap-actor-fix); 2-3 agent slots to M1 | S | lead (graph), plan-editor (§10.1 note) | none |
| 7 | **Fix the breakpoint gate's cost at the source:** a Lean-checked probe scope per part (`gate-probe-scope`) and shard the matrix across CI (already 8 shards there) so a local part run is ≤ 2 min | §C: 554 s / 528 s with `--parts` (MEASURED); CI gate 5 min 06 s | Local part iteration 9 min → ~2 min per fix (INFERRED); part-builders stop sleep-waiting | M | lean-prover + measure-engineer | gate-part-filter done |
| 8 | **Add the scrub pre-commit now, not at M0.** `lefthook` or a `git add` wrapper running the 454cbe0 grep (emails, `/Users/`, LAN IPs, device ids) on staged files; same check in `fw land` | §B: repo is public; the only guard is a one-off grep (CONFIRMED); V-k pre-commit ≤ 30 s | Removes the one irreversible risk class; ~1 s per commit | S | console-builder or env-ops | none |
| 9 | **Deny `pkill -f`/`killall` in settings; allow `kill <pid>`** | §B: incident happened (R31), rule in prose only, 0 deny rules (MEASURED) | One incident class closed | S | lead (settings edit, asks the user) | **User** (`.claude/**` ask rule) |
| 10 | **Deprecate `Workflow` spawns for build work; spawn named roles.** Keep workflows for research fan-out only; all editing agents go through `Agent(name, isolation: worktree)` so spawn-guard and the spool see them | §C/§D: workflows = 58 % of cost, bypass spawn-guard (18 of 26 starts), write 15k at spawn vs 4k | Guard coverage ~100 %; ~0.3 M units/day; cheaper named respawns from handoffs | S | lead | none |
| 11 | **Model mix:** keep lean-prover on Opus but set `effort: medium` for docstring/fix tasks; run `reviewer` and `math-reviewer` on Sonnet after a 2-review cross-check; actually use `scout`/`runner` (0 helper spawns so far) by adding one worked example to each role file | §C: Opus 96 % of weighted cost; review roles have output share < 15 % (MEASURED); helpers unused | 10-30 % of spend (INFERRED, token-usage-profile.md §f item 1); no wall-clock cost | S | lead (role files) | pilot first (D5) |
| 12 | **Ask the user Q1 now with a concrete proposal** (two fixed 45-min windows, free-play phone yes) and book session 1 as original vs v1-g0.0m on iOS 27 | §B: Q1 blocks gap-device, calibration and G1; plan.md rank 2 idea | M3 chain can start; the first G1 data point exists before M2 | S | lead → **User** | none |

Not ranked but worth noting: regenerate the WebKit determinism table with `--warmup 1` and load stamps before any
plan quotes it (meas-webkit.md item 6); rewrite the measure-engineer role's "byte-for-byte" sentence to the per-type
class rule; add a `background_tasks` count to `emit.mjs` so SPK-p part 2 can close.

## What this changes in the plan

- §10.1 (work graph): add `store-and-run`; split `zone-baselines` by engine; move the console Plan view and health
  watch out of M0; drop `con-plan` from `fw-ci`.
- §8.2 "Who commits": state that `fw land` is the lead's *only* landing command and that the land command writes the
  catch-up entry; record today's 19 hand merges as the baseline the reconciler should have flagged.
- §8.5 "Nobody writes status": extend to the lead's log and work-graph `evidence`; both become generated.
- §4.2 / §1.2 V-i: name GitHub runners as the Chromium counts environment of record; the Mac is for WebKit.
- §5.3: add the prover-side `checker` pass before math review; report the per-round disagree rate as a metric.
- §8.3: deny `pkill -f`/`killall`; add the scrub pre-commit to the enforced list.
- §12.1: Q1 asked with a concrete proposal; Q31/Q32 stay low priority.
