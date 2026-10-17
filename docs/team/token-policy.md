# Token-usage policy for the agent team (proposal r2, 2026-10-17)

Decision document for the request "every sub-agent can spawn sub-agents with optimal models to help each task; design how to
optimise the agents' token usage". Nothing here is applied yet. Section 7 is the change list for the lead to approve, and the
review log at the end records how each review finding was handled.

Sources and tags: **[F§n]** = `research/notes/2026/10-17-token-usage-facts.md` section n; **[P§x]** =
`research/notes/2026/10-17-token-usage-profile.md` section x; **[I]** = `docs/team/improvements/2026-10-17.md`;
**[O]** = `research/notes/2026/10-17-agent-observability-sources.md`; **[PLAN]** = `docs/plan/PLAN.md` §8.3/§8.4;
**[repo]** = file read at `00c09bf`; **[pj]** = the profiler's `profile.json` for this session. Each claim also carries
CONFIRMED / MEASURED / INFERRED as in those notes. Session baseline: 93 agents, 3,900 requests, 80.25M cost units
(MEASURED [pj] `totals`; the profile note's 3,932 comes from its separate transcript scripts, not from the profiler).

**Units.** The profiler's "units" weigh input 1, 5m write 1.25, read **0.1**, output 5, with no model price [P§0]. The real read
multiplier on Opus/Sonnet 5.5 is 0.05 (CONFIRMED [F§4]). Figures marked "(r = 0.1 units)" are in profiler units; their read part
is about twice the real one. "Real units" below are Opus-5.5-base-price units with each model's real price and r.

## 0. Decisions in one table

| # | Decision | Main evidence |
|---|---|---|
| D1 | Four slim helper roles: `scout`, `runner` (Haiku 5.5), `checker`, `patcher` (Sonnet 5.5); `patcher` is spawned by the lead only (depth 1) until C18 and the worktree-cwd check pass | Haiku is 40x cheaper than Opus 5.5 on input/output, 20x on reads (CONFIRMED [F§4]); PLAN: depth-2 spawns are read-only helpers |
| D2 | `Agent` tool for 5 long-running roles now (lean-prover, researcher, measure-engineer, console-builder, plan-editor), part-builder after C18; they may spawn only `scout`, `runner`, `checker` | role spawns cost ~3.4k extra tokens if `Agent` is listed (INFERRED [F§3]) |
| D3 | Keep depth 2; raise the session concurrency cap 6 -> **10** (the PLAN value); lead and parents share it (section 3) | shared counter across depths, over-limit error says "Do not retry" (CONFIRMED [F§2]); [PLAN] sets 10 |
| D4 | Context hygiene caps: Bash output 16k chars, Read 8k tokens, compaction window 200k on long roles | tool results carried in context = 66% of units (model, INFERRED attribution, r = 0.1 units [P§a]) |
| D5 | page-writer Opus -> Sonnet; reviewer, math-reviewer and the workflow verify/review stages stay Opus until the 6.1 math-review A/B passes | output share 43% on page-writer (MEASURED [P§e]); verify/review are mostly math-reviewer agents [pj] |
| D6 | TTL by expected wait as [PLAN] says: 5m for helpers and fresh reviewers; no new 1h setting in this policy (plan-editor's 1h dropped) | 1h everywhere loses ~3x (INFERRED on CONFIRMED prices [F§5], recomputed in the log); `cacheTtl` frontmatter CONFIRMED only for sub-agents |
| D7 | Profiler gets real model prices, carried-cost, parent->child rollup and a policy audit; the break-even rule and audit predicate go to Lean first | profile used price weights 1 : 0.2 : 0.067 that disagree with the price list (see 1.1) |

## 1. Cost model

### 1.1 Request cost

For a request on model m (prices per MTok, CONFIRMED [F§4]):

```
cost = p_m x ( I + 1.25 W + r_m R + 5 O )        I uncached input, W cache write (5m), R cache read, O output
```

| Model | p_m relative to Opus 5.5 ($4/MTok) | read multiplier r_m | read price relative to Opus base |
|---|---|---|---|
| Opus 5.5 | 1 | 0.05 | 0.05 |
| Sonnet 5.5 | 0.5 | 0.05 | 0.025 |
| Haiku 5.5, prompt <= 100k | 0.025 | 0.1 | 0.0025 |
| Haiku 5.5, prompt > 100k | 0.125 | 0.1 | 0.0125 |
| Fable 5.1 | 2.5 | 0.025 | 0.0625 |

- With the real r = 0.05 on Opus/Sonnet 5.5 the session split is reads 45%, writes 39%, output 16% (INFERRED rescale of [P§0];
  agrees with the $ split in [F§4]). In real units the session is 51.3M, Opus 92% of it (INFERRED pricing on MEASURED tokens [pj]).
- Correction: the profile's price weights opus : sonnet : haiku = 1 : 0.2 : 0.067 were INFERRED [P§0]; the list prices give
  **1 : 0.5 : 0.025** (CONFIRMED [F§4]). So Opus -> Sonnet saves 50%, not 80%.
- The profile's "strong" group (10.2M = 4.4 + 2.1 + 1.9 + 1.4 + 0.4 [P§e]) double-counts: math-reviewer (1.42M) sits inside the
  verify and review stages, reviewer inside `wf:critique` and `wf:verify-refs`. The distinct workflow-subagent agents of the
  extract, verify and review stages are 6.93M (verify 4.13M + `wf:review:rev4` 0.92M + extract 1.88M, r = 0.1 units, MEASURED [pj]),
  so Sonnet on them would save ~3.5M (r = 0.1 units), ~2.6M real units with page-writer, about 5% of real cost (INFERRED).
  Research/lens (22.7M, r = 0.1 units) would save ~11.4M in the same units (INFERRED).
- Fable reads cost only 1.25x Opus but writes and output 2.5x (CONFIRMED [F§4]); `Agent(model:*fable*)` stays **ask**.

### 1.2 Break-even for delegating a sweep

Symbols (parent P, helper H): T = tokens the sweep's raw results would add to P's context; S = summary tokens returned;
N = P's remaining requests; C = P's context; k = requests P would spend on the sweep inline; F = helper fixed prefix;
Pp = prompt P writes for the helper (output tokens); O = output tokens of the whole sweep; rho = p_H / p_P; t_H = helper wall
time; TTL_P = parent's cache TTL (5 min for sub-agents, 1 h for the lead).

```
inline     K = (k-1) r_P C + T (1.25 + r_P N) + 5 O
delegated  D = 5 Pp + S (1.25 + r_P N) + rho H + E
           H = 1.25 (F + T) + r_H k_H (F + T/2) + 5 O,     k_H = max(k, 2)   (a helper needs >= 2 requests: call, then summary)
           E = 1[t_H > TTL_P and P has no other work meanwhile] x (1.25 - r_P) C
delegate when K - D > q K                              (q = chance the helper's answer is unusable and P redoes the sweep)
```

The first term of K is the parent re-reading its whole context on every sweep request; the second is the result being re-read
on every later request (the profile's "carried cost": 53.0M = 66%, a model with INFERRED attribution in r = 0.1 units, not
MEASURED [P§a]). E is the parent's own cache expiring while it waits: it then rewrites C at 1.25 instead of reading it at r_P.

Numbers from the profile: C = 140k (lean-prover 139k, workflow 146k context per request, MEASURED [P§e]); F = 8k (custom
role first prompt 5.4k-8.5k, MEASURED [F§3]); N = 30 (INFERRED: about half of a lean-prover's 66 requests [P§e]);
S = 1k, Pp = 400, O = 500 per request (INFERRED). Then 1.25 + r_P N = 2.75 for an Opus parent.

| Helper (Opus parent) | Break-even T, k = 1 (k_H = 2) | Example k = 5, T = 20k, E = 0: K -> D (Opus units) |
|---|---|---|
| Haiku scout | ~1.0k (set by S: only needs S < T) | 95.5k -> 6.2k |
| Sonnet checker | ~4.2k | 95.5k -> 30.7k |
| Opus (same model) | ~10.7k | 95.5k -> 57k |

All values are INFERRED arithmetic on the MEASURED and CONFIRMED inputs above (with k_H = 1 they would be 0.95k / 4.1k / 10.3k).
95.5k Opus units is about $0.38 per sweep at $4/MTok. If the helper outlives the parent's TTL while the parent idles,
E = 1.2 x 140k = 168k, more than the whole inline cost K = 95.5k: delegation then loses even with a Haiku helper.

Rules from this: delegate only if the helper is expected to finish in **< 4 min** (sub-agent parent) or the parent has other
work meanwhile; the lead (1 h TTL) can wait up to ~50 min. The parent's own 1.25 T write already costs more than a whole Haiku
helper run (25k vs 1.4k here), so a Haiku helper pays whenever the summary is much smaller than the raw output. Above 100k
prompt tokens Haiku costs 5x its own base price but is still 2-4x cheaper than Sonnet (input 0.5 vs 2, write 0.625 vs 2.5,
read 0.05 vs 0.10, output 2.5 vs 10 $/MTok, CONFIRMED [F§4]). Delegation pays more early in a parent's life (large N).

### 1.3 Rules of thumb (about 4 chars per token, INFERRED)

| Situation | Do |
|---|---|
| Output you expect is < 2k tokens (~8 KB, ~100 lines) | inline, filtered |
| Search/read sweep over > 3 files or > 8 KB whose answer is a list of facts (paths, breakpoints, counts) <= 1k tokens, done in < 4 min | `scout` (Haiku) |
| Sweep that would read > 100k tokens (~400 KB) | split over several scouts; if it cannot be split, still one `scout` (Haiku > 100k is 2-4x cheaper than Sonnet) |
| Build/test/measure run, log > 100 lines | inline with log to a file + `grep`/`tail` (free); `runner` only for several runs or a diagnosis over many log lines |
| Waiting > 1 min | per [PLAN] Waiting: a bounded foreground wait (a blocking command with a timeout, or Monitor with an until-condition); never a sleep-poll loop of model requests (a 6-min poll cost a 0.13M-token rewrite, MEASURED [P§d]); a wait over the agent's TTL costs (1.25 - r) C, so a long or unknown wait ends with a handoff note |
| You need verbatim text to edit it | inline `Read` with offset/limit; never delegate |
| Judgement over > 20 KB (diagnose a failure, cross-check numbers, review a diff hunk against a checklist) | `checker` (Sonnet); not for adversarial math, number or privacy review (stays Opus, D5) |
| Mechanical edits to many named files (e.g. 71 docstring fixes [I]) | lead spawns `patcher` (Sonnet) at depth 1 with absolute paths; nobody touches those files until it returns |
| Same-model helper | only if T > ~10k tokens and no cheaper tier can do it |

Scale of the win: Scenario A of the profile (grep/find/ls/git/jq, build runs, polls; 468 requests) nets 8.0M with a Haiku helper
(r = 0.1 units and the old 0.067 Haiku factor; at real r = 0.05 about half of its read part, INFERRED); read sweeps that return
facts add a realistic 5-10M more in the same units (ceiling 58.5M; MEASURED/INFERRED [P§b]).

## 2. Model tier table

### 2.1 Helpers (new roles)

| Helper | Model / effort | Spawned by | Task types | Tools |
|---|---|---|---|---|
| `scout` | haiku / low | lead or a role with `Agent` | grep, find, ls, read-and-extract, git log/show, `gh search code`, upstream lookups in `.cache/upstream` | Read, Grep, Glob, Bash, Serena `find_symbol`, `get_symbols_overview` (no Edit/Write) |
| `runner` | haiku / low | lead or a role with `Agent` | run one named build/test/measure command, log to the scratchpad path given in the prompt, report exit code and first errors | Bash, Read, Grep, Glob (no Edit/Write) |
| `checker` | sonnet / medium | lead or a role with `Agent` | diagnose a failing build/test from its log, cross-check a hunk against a checklist | Read, Grep, Glob, Bash (no Edit/Write) |
| `patcher` | sonnet / low | lead only (depth 1) until C18 + the cwd check | mechanical edits to absolute paths named in the prompt | Read, Edit, Grep, Glob (no Bash, so no git) |

Effort low for Haiku helpers: effort is a second-order lever (output 1.78M = 10% of writes; no material output difference by
effort, MEASURED weak [F§4]).

### 2.2 Existing roles

| Role | Now [repo] | Proposed | Evidence |
|---|---|---|---|
| lean-prover | opus / high | **keep**. `model: sonnet` for docstring-only Lean tasks is **pending** the lean-doc-fix-r4 math-review result; adopt only if its r5 disagree rate <= the Opus r3 fixes' rate | 11.5M units, proof search (MEASURED [P§e]); the docstrings are the LaTeX statements the user reviews (CLAUDE.md); r4 found 71 disagreements in them [I] |
| math-reviewer | opus / high | **keep**; pilot sonnet/high on one batch with both models; switch only if Sonnet recall = 100% of the Opus disagreements the lead adjudicates as true **and** Sonnet precision >= 90% | 1.4M, output 14.1% (MEASURED [P§e]); 71 of 258 disagree in r4 [I] |
| reviewer | opus / medium | **keep** for adversarial reviews; checklist checks may go to `checker` | reviewer-rev5 1.25M at 181k context (MEASURED [P§e]) |
| researcher | opus / high | **keep**, add `Agent` + scouts | 0.5M (MEASURED [P§e]); synthesis needs Opus (INFERRED) |
| plan-editor | opus / high | **keep**, add `Agent` + compaction window; no TTL change (teammate; `cacheTtl` frontmatter CONFIRMED only for sub-agents [F§5]) | plan-rev5 6.2M, 428k context, 2 idle rewrites of 324k/359k (MEASURED [P§d,e]); plan-rev5 was an in-process teammate (agentType `plan-rev5` [pj]) |
| page-writer | opus / medium | **sonnet / medium** | 0.6M with 43% output share = generation from given notes (MEASURED [P§e]); design tokens fixed (INFERRED low risk) |
| part-builder | sonnet / medium | keep; `Agent` only after C18 ([PLAN] template has `disallowedTools: … Agent`) | 2.9M (MEASURED [P§e]) |
| console-builder | sonnet / medium | keep | 0.8M (MEASURED [P§e]) |
| measure-engineer | sonnet / high | keep | 7.6M; determinism work (MEASURED [P§e]) |
| env-ops | sonnet / medium | keep | 7 requests; nothing to save (MEASURED [P§c]) |
| general-purpose (built-in) | inherit | avoid; use a named role | 32.1k first prompt vs 5.4k-8.5k for a custom role (MEASURED [F§3]) |

The lead still escalates per call (`model: opus`/`effort: high`) for part-builder and measure-engineer as [PLAN] §8.3 says.

### 2.3 Workflow stages (58 `wf:*` agents = 58% of units, MEASURED [P§0])

| Stage | Proposed model | Evidence |
|---|---|---|
| extract | sonnet | read-heavy, output < 15% (MEASURED [P§e]) |
| verify, review | **keep opus** until the 6.1 math-review A/B passes | 9 of the 10 `wf:review:*` and `wf:verify:A/B` are `math-reviewer`; the other verify agents check numbers, claims/privacy, math and Lean automation, where errors are expensive [pj] |
| research, lens | pilot sonnet on one lens, keep opus until compared | 22.7M (r = 0.1 units), biggest lever, highest quality risk [P§e] |
| apply, delta, synthesize, critique | opus | edits and judgement (INFERRED) |

Whether a workflow script can set the model per agent is not checked here (INFERRED; check the workflow-authoring skill).

## 3. Nested spawning rules

| Rule | Value |
|---|---|
| Roles with `Agent` | lean-prover, researcher, measure-engineer, console-builder, plan-editor; part-builder after C18 |
| Roles without | reviewer, math-reviewer (fresh, independent, short: 6-38 requests [P§c]), page-writer, env-ops, all helpers |
| Types a sub-agent may spawn | `scout`, `runner`, `checker` only (read-only, as [PLAN] requires for depth 2); `patcher` is depth-1 only |
| Enforcement | role body text (a type list in a role's `Agent(...)` is ignored for sub-agents, CONFIRMED [F§1]); settings **ask** on `Agent(model:*fable*)`, `Agent(general-purpose)`, `Agent(fork)` (ask/deny on `model:` works, allow does not, CONFIRMED [F§1]); nested Opus is caught by the profiler audit P4, not by an ask rule, because the lead escalates per call |
| Spawn call | a sub-agent spawning a helper passes `subagent_type` only, never `model` or `isolation`; the lead may pass `model`/`effort` per call ([PLAN] §8.3) |
| Depth | keep `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=2`: lead -> role -> helper; helpers cannot spawn (CONFIRMED [F§2]) |
| Concurrency | session cap **10** (shared across depths, CONFIRMED [F§2]; the over-limit error says "Do not retry"). Each parent runs <= 1 helper at a time; <= 2 only while the lead has <= 3 direct agents running (3 + 6 = 9). Lead <= 5 direct agents when they use helpers (5 + 5 = 10). Parallel `runner` builds also count against RAM, the real limit per [PLAN] (16 GB) |
| Helper return | <= 1,000 tokens (~40 lines, 4 KB): line 1 the answer or `pass`/`fail`; then `path:line - fact` bullets with CONFIRMED/INFERRED; then `Not checked:`; anything longer goes to a scratchpad file and only its path is returned |
| Edits | helpers are read-only, except `patcher` (depth 1) on absolute paths the prompt names; the spawner leaves those files alone until it returns |
| Commits | no helper commits (`patcher` has no Bash; others' body forbids git writes) |
| Reporting | a helper's final message is its return value to its parent; it never messages the lead and writes no handoff note |
| Helper prompt | <= 15 lines: question, paths, output format, size cap; helpers skip CLAUDE.md (`omitClaudeMd`, CONFIRMED [F§6]), so the prompt repeats any rule they need |

Cost of giving a role `Agent`: ~1.4k tokens of tool text plus the agent-type list (~2k) in every spawn, used or not
(INFERRED [F§3]): ~3.4k x (1.25 + 0.05 x 66) = ~15k Opus units per lean-prover run, below one sweep's saving (1.2).
This is why short roles do not get it.

Open checks (INFERRED until run on the first nested spawn):
- an `ask` rule hit inside a background sub-agent probably fails instead of prompting the user;
- whether a depth-2 helper spawned by a worktree sub-agent starts in the parent's worktree or in the main checkout (decides
  whether `patcher` may ever be nested; C4's body refuses paths outside the worktree it is given either way);
- whether in-process teammates (researcher, plan-editor) get the `Agent` tool and whether `cacheTtl` applies to them.

## 4. Context hygiene

| Practice | Rule | Evidence |
|---|---|---|
| Bash output | never print more than ~150 lines: `grep -n`, `head`, `tail -40`, `wc -l` first; quiet flags (`-q`, `--silent`, `--reporter=dot`) | Bash = 67% of carried units; 343 results > 5k tokens carry 5.3M above a 5k cap (sizes MEASURED, carried units a model in r = 0.1 units [P§a,f]) |
| Long output | write to a scratchpad file, then read excerpts: `cmd > "$LOG" 2>&1; echo "exit=$?"; grep -nE 'error' "$LOG" \| head -40` | same |
| Bash cap | `BASH_MAX_OUTPUT_LENGTH=16000` (past the cap the output goes to a file with a preview, CONFIRMED [F§6]) | profile suggests 12k-15k for builders [F§6] |
| `lake build` | `lake build > "$LOG" 2>&1; echo "exit=$?"; grep -nE '^(error\|warning)' "$LOG" \| head -40; tail -3 "$LOG"` | `time lake` + `lake build` = 467k carried units on lean-core alone (MEASURED sizes, r = 0.1 units [P§a]) |
| Analysis scripts | python3/node/jq write their table to a file and print <= 30 lines | 374 calls, 6.3M carried units (r = 0.1 units [P§f]) |
| Read | `grep -n` to locate, then `Read` with offset/limit <= 150 lines; whole file only to edit it; never `cat`/`sed -n` a file > 200 lines | 146 Reads > 5k tokens carry 9.7M above a 5k cap (r = 0.1 units); plan-rev5 read 4 x 20-25k at request 2 of 178 (MEASURED [P§a,f]) |
| Read cap | `CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS=8000` (default 25,000, CONFIRMED [F§6]) | <= 7.6M gross (INFERRED truncation model, r = 0.1 units [P§f]); realistic ~4-5M, because an over-cap Read fails and the agent re-reads in chunks (INFERRED); count the extra retry requests after rollout (P2) |
| Re-reads | do not re-read a file you read or edited unless it changed; list read files in the handoff | 63 re-reads, 468k tokens, 3.1M carried (MEASURED count, r = 0.1 units [P§f]) |
| Symbols | prefer Serena `find_symbol` over reading whole source files (scout has it, C1) | INFERRED |
| Compaction | `autoCompactWindow: 200000` on lean-prover, plan-editor, researcher, measure-engineer, part-builder, console-builder (default ~967k, CONFIRMED [F§6]) | median context peak 137k, max 428k; 46 of 93 agents pass 150k (MEASURED [P§0,f]) |
| Handoff by size | at the next milestone after ~45 tool rounds (~150k at the median 3.2k growth per request), write the handoff, finish, and let the parent respawn | respawn at >= 150k: ~4M realistic at the real r = 0.05 (the note's ~9M is r = 0.1 units [P§f item 2]; INFERRED rescale) |
| Handoff by idle | idle > the agent's own TTL and context > 30k -> `TaskStop` + fresh agent from the handoff (`agent-idle.py` verdict, already TTL-aware [repo]); never resume a context > 250k | 3 lead-idle rewrites, 0.93M tokens; respawn saves ~1.0M (MEASURED/INFERRED [P§d]) |
| Handoff size | <= 30 lines as CLAUDE.md says | 7 of 12 handoffs exceed 30 lines (34-52), MEASURED by `wc -l` |
| Cache TTL | by expected wait as [PLAN] says; helpers and fresh reviewers 5m; this policy adds no 1h setting | 1h pays only if an expiry is expected late in a run (INFERRED [F§5]); `autoCompactWindow` 200k already removes the 324k/359k rewrites that a 1h plan-editor would have avoided |

## 5. The lead's own usage

The lead runs Opus with 1 h cache writes (MEASURED [I]: 100% 1 h, 1.49M tokens) and lives longest, so every token it reads
is re-read on every later lead request (INFERRED). The lead also reviews results (CLAUDE.md), so it reads what it must judge.

| Delegate (spawn) | Do inline |
|---|---|
| Locating facts in research notes or the plan (which section, which number) -> `scout` with the question | notes the lead must review or decide on: `Read` with offset/limit; decisions, user answers, task list |
| Running `agent-profile.py` / `agent-idle.py` over many agents -> `runner` returning the table rows asked for | `git status`, `git log --oneline -n 20`, `git diff --stat` |
| Reviewing a worktree branch diff -> `reviewer` (adversarial) or `checker` (checklist) | commits and `fw land` to `main` (lead only, CLAUDE.md) |
| Several build/test runs or a failure diagnosis -> `runner` / `checker` | one build/test: log to a file + `grep`/`tail` (a filtered excerpt is ~1k tokens, about S) |
| Searches across many files of the repo or `.cache/upstream` -> `scout` | small edits to settings, CLAUDE.md, role files (ask-guarded); reading reports (<= 300 chars) and handoffs (<= 30 lines) |

Also: spawn named roles, never general-purpose (32.1k vs 5.4k-8.5k first prompt, MEASURED [F§3]); pass `model: sonnet`
per spawn when a normally-Opus role gets a mechanical task that has no pending pilot (2.2); respawn rather than resume idle
agents (section 4).

## 6. Measurement

### 6.1 Metrics, baselines, targets

Baseline = this session up to the policy commit (MEASURED [P§0-f], [pj]). Targets are INFERRED goals for the next comparable
stretch of work, compared per request so session length cancels out. They are derived from sections 1-4; the savings
estimates there overlap, so the unit target is a range.

| Metric | Baseline | Target |
|---|---|---|
| Cost units per request | 20.6k (80.25M / 3,900) | <= 16k (-20%); -30% is an aspiration |
| $ per request (real prices, section 1.1) | to compute with change P1 (~13.2k real units, INFERRED) | -15% to -25% (tier moves ~5%, the rest from hygiene and helpers) |
| Carried tool-result share of units | 66% (53.0M, model, r = 0.1 units) | <= 45% |
| Results >= 10k tokens | 188 of 4,548 (4%), 33% of carried | <= 1% |
| Bash results > 5k tokens / Read results > 5k tokens | 343 / 146 | <= 50 / <= 30 |
| Re-read calls | 63 | <= 15 |
| Agents with context peak > 150k | 46 of 93 | <= 15% |
| Median context peak | 137k | <= 100k |
| Expired-cache rewrites | 14 events, 3.01M tokens | <= 1M tokens |
| Opus share of tokens | 85% | <= 75% (extract + page-writer moves give 75%, INFERRED [pj]); lower only after the A/Bs pass |
| Helper share of a parent's subtree $ | n/a (0 helpers; only general-purpose had `Agent` [F§1]) | 5-15% |
| Haiku helper context > 100k | n/a | metric only (still cheaper than Sonnet, 1.2); not a violation |
| Policy violations (non-helper nested type, nested patcher, nested opus/fable, general-purpose, fork) | n/a | 0 |
| Spawn overhead share | 1.6M units, 2% | <= 4% (more, smaller spawns) |

Method: run `agent-profile.py --cutoff <policy-commit time>` for the baseline and again after; compare per role. Two A/Bs
on the same input: one math-review batch on Opus and Sonnet (criterion in 2.2: recall on lead-adjudicated true disagreements
100%, precision >= 90%); one Lean sweep inline vs `scout` (units and wall time).

### 6.2 Profiler changes (`docs/team/tools/agent-profile.py`)

| # | Change | Why |
|---|---|---|
| P1 | Price table per model ID (section 1.1, incl. per-model r and the Haiku > 100k tier); output `usd` per request, agent, role, and `usd_by_model` | units ignore prices and use r = 0.1 for all [P§0] |
| P2 | Carried cost per tool result (method of [P§a]: new context split over the request's results by bytes; tokens x (1.25 + r x remaining requests)); size histogram; counts > 5k / > 10k per tool and command; Read retries after an over-cap error | the main lever is not visible in the profiler today; it lived in scratchpad scripts `an1..an8.py` [P caveats] |
| P3 | Subtree rollup using the existing `parent` link (meta `toolUseId`, [F§2]): children, helper count, helper $, summary tokens (size of the Agent tool_result in the parent), parent cache expiry while a helper ran (term E) | prove that helpers cost less than they save, per parent |
| P4 | Policy audit: nested child type not in {scout, runner, checker}, nested patcher, nested model opus/fable, general-purpose or fork spawns, helper summary > 1k tokens; Haiku context > 100k reported as a metric only | section 3 is only partly enforceable by settings |
| P5 | `ctx_cross_150k` per agent and requests after the crossing | handoff rule (section 4) |
| P6 | `--compare <profile.json>`: per-metric before/after table normalised per request | section 6.1 |
| P7 | `agent-idle.py`: add verdict `handoff` when context > 150k (today only `respawn` at idle > TTL and ctx > 30k [repo]) | section 4 |

Lean first (CLAUDE.md): the price table, the request cost, the break-even `delegate` verdict (1.2, including term E) and the
audit predicate are pure decisions, so they are specified and proved in Lean first (`lean/Fw/Ops/Tokens.lean`, next to
lean-ops' usage merge and budget alerts [I]) with theorems (cost monotone in T and N; `delegate` monotone in T, antitone in
t_H) and golden vectors (C16). P1/P2/P4 in Python come after C16 and are a temporary stand-in checked against those goldens.

## 7. Change list (proposed, not applied)

| # | File | Edit |
|---|---|---|
| C1 | `.claude/agents/scout.md` (new) | `model: haiku`, `effort: low`, `tools: Read, Grep, Glob, Bash, mcp__serena__find_symbol, mcp__serena__get_symbols_overview` (~1.3k chars of schema), `disallowedTools: Edit, Write`, `omitClaudeMd: true`, `maxTurns: 40`. Body: read-only (no git writes, no redirects outside the scratchpad path given in the prompt); no personal data or Fastwork code in replies; return format and 1k cap from section 3 |
| C2 | `.claude/agents/runner.md` (new) | `model: haiku`, `effort: low`, `tools: Bash, Read, Grep, Glob`, `disallowedTools: Edit, Write`, `omitClaudeMd: true`, `maxTurns: 20`. Body: run only the command named; log to `<scratchpad path given in the prompt>/<name>.log`; return `exit=<n>`, duration, first <= 40 error lines, log path |
| C3 | `.claude/agents/checker.md` (new) | `model: claude-sonnet-5-5`, `effort: medium`, `tools: Read, Grep, Glob, Bash`, `disallowedTools: Edit, Write`, `omitClaudeMd: true`, `maxTurns: 40`. Body: answer the one question with evidence; same return contract |
| C4 | `.claude/agents/patcher.md` (new) | `model: claude-sonnet-5-5`, `effort: low`, `tools: Read, Edit, Grep, Glob`, `omitClaudeMd: true`, `maxTurns: 60`. Body: edit only the absolute paths given in the prompt, which must lie under the worktree the prompt names; refuse otherwise; no other change; no personal data or Fastwork code; no handoff note; return the list of edits made (<= 1k tokens) |
| C5 | lean-prover, researcher, measure-engineer, console-builder, plan-editor (`.claude/agents/*.md`); part-builder after C18 | add `Agent` to `tools:`; add `autoCompactWindow: 200000` (all six, part-builder included); append the "Helpers" paragraph below |
| C6 | `.claude/agents/plan-editor.md` | body: "Read PLAN.md by section with offset/limit, never whole" (no TTL change) |
| C7 | `.claude/agents/page-writer.md` | `model: claude-opus-5-5` -> `claude-sonnet-5-5` |
| C8 | `.claude/agents/reviewer.md`, `math-reviewer.md` | body only: "Read with offset/limit; grep before reading" (no `Agent`, no model change until the 6.1 pilot) |
| C9 | `.claude/settings.json` `env` | `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` "6" -> "10" (the [PLAN] value); add `BASH_MAX_OUTPUT_LENGTH: "16000"`, `CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS: "8000"` (keep depth "2") |
| C10 | `.claude/settings.json` `permissions.ask` | add `Agent(general-purpose)`, `Agent(fork)`; keep `Agent(model:*fable*)`. No ask on `model:*opus*`: the lead escalates part-builder and measure-engineer per call ([PLAN] §8.3) and must not be prompted for it; nested Opus goes to the P4 audit |
| C11 | `CLAUDE.md`, Team | add: "**Helpers:** lean-prover, researcher, plan-editor, measure-engineer and console-builder (part-builder after the plan amendment) may spawn `scout`/`runner` (Haiku) and `checker` (Sonnet) per `docs/team/token-policy.md`; only the lead spawns `patcher`. Helpers are read-only unless named for an edit, never commit, write no handoff, and return <= 1k tokens to their spawner, not the lead." |
| C12 | `CLAUDE.md`, Rules | add: "**Context:** never print > ~150 lines into context: filter (`grep -n`, `tail -40`), send long output to a scratch file and read excerpts; Read with offset/limit; do not re-read unchanged files." |
| C13 | `CLAUDE.md`, Cache-aware resumes | "idle < 5 min" -> "idle < its own TTL"; "when its context is small" -> "when its context is < 30k tokens; never resume one > 250k" |
| C16 | `lean/Fw/Ops/Tokens.lean` (new, lean-ops or a lean-prover) — **before C14** | price table, cost, `delegate` verdict with term E, audit predicate, theorems with LaTeX docstrings, goldens for C14 |
| C14 | `docs/team/tools/agent-profile.py` (after C16) | P1-P6 (section 6.2), each its own commit; P1/P2/P4 are a temporary Python stand-in checked against the C16 goldens |
| C15 | `docs/team/tools/agent-idle.py` | P7 |
| C17 | `research/notes/2026/10-17-token-usage-profile.md` | correction lines: price weights are 1 : 0.5 : 0.025 (CONFIRMED [F§4]), not 1 : 0.2 : 0.067; item 1 of §f becomes ~16M at most; the "strong" group's 10.2M double-counts math-reviewer and reviewer: distinct extract/verify/review workflow-subagent cost 6.9M -> saves ~3.5M (math-reviewer/reviewer excluded, they stay Opus); item 2's ~9M is r = 0.1 units (~4M at r = 0.05) |
| C18 | `docs/plan/PLAN.md` §8.3/§8.4 (plan-editor) | amend: helper roles `scout`/`runner`/`checker` as the depth-2 read-only helpers (`patcher` depth 1 only); part-builder template drops `Agent` from `disallowedTools`; concurrency stays 10 with the per-parent helper limit of section 3; TTL and Waiting unchanged (this policy follows them) |

"Helpers" paragraph for C5 (role body, 5 lines):

> Helpers (`docs/team/token-policy.md`): for a search/read sweep whose raw output would pass ~8 KB but whose answer fits
> in 1k tokens, spawn `scout`; for build/test runs where you need several runs or a diagnosis, `runner`; for checklist
> judgement over > 20 KB, `checker`. Spawn no other type, never pass `model` or `isolation`, run 1 helper at a time (2 only if
> told so), and delegate only work a helper finishes in < 4 min unless you have other work meanwhile; never sleep-poll for it.
> One build/test run stays inline: log to a file, then `grep`/`tail`.

## Review log (r1 -> r2)

Numbers were re-checked against `profile.json` [pj] and the notes before changing them.

| # | Sev | Finding | Resolution |
|---|---|---|---|
| 1 | blocker | 2.3 sent verify/review to Sonnet, against 2.2 | fixed: extract -> sonnet; verify, review keep Opus until the A/B. Verified: 9 (not 8) of the 10 `wf:review:*` agents, plus `wf:verify:A/B`, are math-reviewer |
| 2 | major | "strong group 10.2M saves ~5.1M" double-counts | fixed in 1.1 and C17: 4.13 + 0.92 + 1.88 = 6.93M (verified [pj]), saves ~3.5M r = 0.1 units, ~2.6M real units incl. page-writer |
| 3 | major | "one checker" for > 100k sweeps raises cost | fixed in 1.2/1.3; P4 and 6.1 keep Haiku > 100k as a metric only. Verified prices [F§4] |
| 4 | major | break-even ignores the parent's cache expiry | fixed: term E, "< 4 min" rule, carried into C16 and P3. Verified (1.25 - 0.05) x 140k = 168k > 95.5k |
| 5 | minor | k labels and break-even values | fixed: example column k = 5 (95.5k / 6.2k / 30.7k / 57k re-verified); k_H = max(k, 2) gives ~1.0k / ~4.2k / ~10.7k (the review's 0.95 / 4.1 / 10.3k are for k_H = 1, noted); 1.3 uses ~10k |
| 6 | major | savings in r = 0.1 units | fixed: units note at top, tags on Scenario A, 53.0M (model, INFERRED attribution), carried figures; respawn ~9M -> ~4M |
| 7 | major | Read cap 7.6M tagged MEASURED | fixed: <= 7.6M gross INFERRED, ~4-5M realistic, retries counted by P2 |
| 8 | major | 1h on plan-editor conflicts with respawn rule; plan-rev5 was a teammate | fixed: 1h dropped (D6, 2.2, C6, 4); idle rule TTL-aware (4, C13); teammate `cacheTtl` added to open checks. Verified agentType `plan-rev5`, phase team [pj] |
| 9 | major | silent conflicts with PLAN §8.3/§8.4 | fixed: aligned on TTL-by-wait, foreground bounded Waiting, cap 10, part-builder `Agent` deferred, patcher depth 1; C18 amends PLAN for the helper roles and part-builder |
| 10 | major | ask on `Agent(model:*opus*)` breaks per-call escalation | fixed: dropped from C10; nested Opus via P4; spawn-call rule split lead vs sub-agent |
| 11 | major | 6 x 2 helpers + 6 = 18 > 12 | fixed: cap 10, <= 1 helper per parent (2 only while the lead has <= 3 agents), lead <= 5 direct with helpers; RAM noted |
| 12 | major | lead rules on builds and notes | fixed: one build inline with log + grep/tail; notes the lead reviews read with offset/limit; scout only to locate facts |
| 13 | major | lean-prover Sonnet for docstrings before its pilot | fixed: pending lean-doc-fix-r4 result with the r5-vs-r3 disagree-rate criterion |
| 14 | major | nested patcher and worktree cwd unverified | fixed: patcher depth 1 only; C4 refuses paths outside the named worktree; cwd check added to open checks |
| 15 | minor | "1h everywhere loses ~3.6x" | fixed: 0.75 x (17.2 - 3.01)M / (3.01M x 1.2) = 2.95, so ~3x (D6) |
| 16 | minor | 3,932 vs 3,900 requests | fixed: 3,900 from [pj] totals (agent sum also 3,900); 3,932 explained as the note's own count; 20.6k per request |
| 17 | minor | $ -40% and Opus <= 60% not derived | fixed: Opus token share after the moves = 75% (computed [pj]); $ -15-25%; units -20% with -30% as aspiration |
| 18 | minor | one-sided math-reviewer pilot criterion | fixed: recall 100% on lead-adjudicated true disagreements and precision >= 90% |
| 19 | minor | C14 before C16 breaks Lean first | fixed: C16 listed before C14; Python P1/P2/P4 marked as temporary stand-in |
| 20 | minor | scout lacks Serena; `$SCRATCH` undefined | fixed: Serena `find_symbol`/`get_symbols_overview` in C1; scratchpad path given in the prompt (C1, C2) |
| 21 | minor | "builders" ambiguous; patcher keeps CLAUDE.md | fixed: C11 names the roles; C4 adds `omitClaudeMd: true` and the needed rules in its body |
