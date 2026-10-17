# Sub-agent token usage profile (MEASURED, 2026-10-17)

Status: MEASURED from the session profile (93 agents, 3,932 deduplicated requests, 4,590 tool calls) and the raw agent transcripts. Items marked INFERRED are model assumptions, stated where used. Cost unit = input 1 + write(5m) 1.25 + write(1h) 2 + read 0.1 + output 5 (relative, no model price). Total 80.25M units. Price-weighted figures use an assumed opus : sonnet : haiku = 1 : 0.2 : 0.067 (INFERRED, not a price list); weighted total 71.2M.

## 0. Headline

| Component | Units | Share |
|---|---|---|
| Cache reads | ~49.8M | 62% |
| Cache writes | ~21.5M | 27% |
| Output | ~8.8M | 11% |
| Tool results carried in context (model below) | 53.0M | 66% of total |
| Top 10 agents | 26.4M | 33% |
| Workflow subagents (`wf:*`, 58 agents) | 46.5M | 58% |
| Opus share of weighted cost | 68.5M of 71.2M | 96% |

Opus is 85% of tokens but 96% of price-weighted cost; this is the main lever after context size. Median agent peaks at 137k context; growth per request is 2.2k (Q1), 3.2k (median), 5.0k (Q3) tokens.

## a) Context growth and carried cost

Method: for each request, new context = ctx(i+1) - ctx(i) - output(i); split over that request's tool results by byte share. Carried cost of a result = tokens x remaining requests x 0.1 + tokens x 1.25. Sum over 4,548 results: 10.96M tokens, 53.0M units. (Write/Edit "results" also include the echoed tool input, so their tokens are an upper bound.)

By tool (carried units, all agents):

| Tool | Calls | Tokens | Carried units | Share of 53.0M |
|---|---|---|---|---|
| Bash (all) | 3,381 | 7.30M | 35.5M | 67% |
| Read | 228 | 2.71M | 14.1M | 27% |
| Write | 369 | 0.36M | 1.7M | 3% |
| Edit | 370 | 0.36M | 0.85M | 2% |
| WebFetch + WebSearch | 105 | 0.16M | 0.56M | 1% |

By normalised Bash command (top by carried):

| Command | Calls | Tokens | Carried units |
|---|---|---|---|
| sed (mostly `sed -n a,bp` file slices) | 467 | 1.19M | 6.1M |
| cat | 230 | 0.96M | 5.4M |
| grep | 408 | 0.73M | 3.5M |
| ls | 180 | 0.44M | 2.4M |
| python3 (stdin / -I / -c analysis scripts) | 374 | 0.80M | 3.8M |
| for-loops | 105 | 0.26M | 1.1M |
| node -e | 83 | 0.19M | 0.9M |
| mkdir (chained with ls/cat in one call) | 70 | 0.18M | 0.9M |
| jq | 63 | 0.13M | 0.7M |
| wc | 45 | 0.12M | 0.6M |
| gh | 93 | 0.13M | 0.6M |
| lake build | 34 | 0.08M | 0.5M |

By result size (tokens):

| Size | Results | Tokens | Carried units | Share |
|---|---|---|---|---|
| < 500 | 1,138 | 0.27M | 1.2M | 2% |
| 500-2k | 2,020 | 2.26M | 10.1M | 19% |
| 2k-5k | 879 | 2.69M | 13.0M | 24% |
| 5k-10k | 323 | 2.23M | 11.2M | 21% |
| >= 10k | 188 | 3.52M | 17.6M | 33% |

So 4% of results (the 188 over 10k tokens) carry a third of the cost. Largest single results: plan-rev5 Read results of 18.9k-25.5k tokens at request ~2 of 178 carried 355k-482k units each (one result about 0.6% of the session); wf:apply:rev4 Read 55.6k tokens (298k units); wf:lens:04 Read 31k tokens (264k); wf:lens:03 a `jq`/log Bash result of 42.9k tokens (229k).

Top agents (context growth, units):

| Agent | Role | Reqs | ctx start | ctx max | Growth/req | Units | Share |
|---|---|---|---|---|---|---|---|
| plan-rev5 | plan-rev5 | 178 | 15k | 428k | 2.3k | 6.21M | 7.7% |
| lean-core | lean-prover | 106 | 7k | 312k | 2.9k | 2.53M | 3.2% |
| lean-site | lean-prover | 117 | 8k | 262k | 2.2k | 2.49M | 3.1% |
| lean-measure | lean-prover | 88 | 7k | 310k | 3.5k | 2.29M | 2.9% |
| wf:lens:04-failures-conflicts | workflow | 80 | 34k | 256k | 2.8k | 2.27M | 2.8% |
| wf:apply:plan-rev3 | workflow | 63 | 44k | 374k | 5.3k | 2.25M | 2.8% |
| wf:lens:05-case-studies | workflow | 70 | 34k | 276k | 3.5k | 2.19M | 2.7% |
| page-rev5 | page-rev5 | 70 | 16k | 297k | 4.1k | 2.16M | 2.7% |
| wf:delta:rev5 | workflow | 68 | 59k | 388k | 4.9k | 2.12M | 2.6% |
| wf:research:04-webkit-rendering-math | workflow | 82 | 35k | 276k | 3.0k | 1.92M | 2.4% |

Dominant carried sources per top agent (k units): plan-rev5 Read 1,993 then python3 937; lean-core cat 634, sed 324, `time lake` 257, lake build 210; lean-site python3 scripts 548, Write 217; lean-measure cat 397, lake build 234, git show 142; wf:lens:04 Read 535, jq 320.

## b) Delegable work

Mechanical = every tool call in the request is a search/read/run (Read, Grep, grep/find/ls/cat/sed/head/wc/jq, git, lake/pnpm/node/test runs, sleep polls, WebFetch). Of 3,932 requests: 2,440 mechanical (62%, 46.9M units, 58% of cost), 463 editing (12%, 15.4M), 981 other Bash/other (25%, 17.2M), 48 text-only. Output tokens: editing requests 1.20M (70%), mechanical 0.25M (15%), other 0.28M, text 0.05M. Of 4,590 tool calls: 2,797 mechanical, 951 other Bash, 776 edit-type, 97 other. Mechanical calls: 2,380 search/read, 415 build/test/script, 2 sleep (+25 sleep-only requests, 0.40M units).

Delegation model (INFERRED): a run of >= 3 consecutive all-mechanical requests is handed to a helper with 15k base context that returns a 1k-token summary. Parent saves the run's requests and the carried tokens of its results, and pays one delegation request (0.1 x its context + 400 output tokens) plus the summary carried. Helper pays its own cost times a price factor (same model 1.0, Sonnet 0.2, Haiku 0.067).

| Scenario | Runs | Requests | Gross parent saving | Net, same model | Net, Sonnet | Net, Haiku |
|---|---|---|---|---|---|---|
| A conservative: grep/find/ls/wc/git/jq, lake/pnpm/node runs, polls, web (no file-content reads) | 111 | 468 | 8.3M | 4.0M | 7.4M | 8.0M |
| B ceiling: A + Read, cat, sed, scripts, mcp | 297 | 2,635 | 60.6M | 29.4M | 54.4M | 58.5M |

Scenario A is about 9% of the 80.25M total. Scenario B is a ceiling, not a target: those reads feed edits and reasoning, and a 1k summary cannot replace the text the parent must quote. Plan on A plus a fraction of B (INFERRED: 10-20% of B-A, i.e. 5-10M more) for read sweeps whose answer is a list of facts (breakpoints, counts, file maps). Best agents for A: wf:lens:04 (0.86M), wf:lens:01 (0.64M), wf:lens:02 (0.62M), wf:lens:05 (0.57M), lean-core (0.40M), wf:research:04 (0.40M).

## c) Fixed spawn overhead

First-request cache write (tokens, median) by agentType:

| agentType | Agents | First write | Requests per agent |
|---|---|---|---|
| lean-prover / part-builder / measure-engineer / console-builder (custom, `.claude/agents`) | 23 | 4.0k-4.3k | 13-117 |
| researcher / math-reviewer / reviewer | 16 | 5.6k-8.6k | 6-38 |
| plan-rev5 / page-rev5 / mathrev-* / serena-setup (named, team) | 8 | 14.6k-16.1k | 7-178 |
| workflow-subagent | 39 | 15.4k (context 35k incl. read of cache) | 20-90 |
| Plan, claude-code-guide, general-purpose | 3 | 25k-32k | 4-13 |
| page-writer | 1 | 44.7k | 22 |

- Total first-request cost over 93 agents is about 1.6M units (2% of session). Not a primary lever.
- Tiny agents (<= 8 requests): 6 (WebFetch-limits guide 4, review-team-config 8, env-ops 7, mathrev-spec 7, wf:review:site-a 7, wf:review:parts-b 6). Counting <= 10 requests: 12 agents, first request is 13% of their cost; for the 4-request guide agent it is 43%.
- Custom roles pay about 4k, built-ins and workflow subagents 15-32k: switching the 3 built-in agents and the 12 named teammates to the slim role files would save about 11-25k tokens x 1.25 each = 0.3M units, plus tool-schema size (INFERRED cause: tool list and CLAUDE.md are the same, difference is the role prompt/tool set).

## d) Expired-cache rewrites (3.01M tokens, 14 events)

Extra cost over a warm read = tokens x (1.25 - 0.1) = 3.46M units (4.3% of session). Cause classified from the transcript gap (API retry records vs a lead message arriving):

| Cause | Events | Rewritten tokens | Extra units |
|---|---|---|---|
| API stall: requests sent, response delayed 8-26 min (lens x8 at 20:26-20:52, critique x2 at 19:41) | 10 | 2.08M | 2.4M |
| Idle teammate waiting for the lead: plan-rev5 (5.9 min, 6.9 min), page-rev5 (11.5 min) | 3 | 0.93M | 1.07M |
| Tool wait over TTL: meas-chromium-2 `for` poll 6.0 min | 1 | 0.13M | 0.16M |

Details: plan-rev5 rewrote 324k and 359k tokens; page-rev5 248k; lens agents 179k-257k each (context 180k-260k); critique 70k and 147k.

What would have avoided them:
- Lead-idle (0.93M tokens): per CLAUDE.md, TaskStop on an idle agent over 5 min and respawn from `docs/team/handoffs/<name>.md` (about 20k tokens written instead of 250k-360k). Net saving about 0.93M x 1.15 - 3 x 20k x 1.25 = 1.0M units. Never resume plan-rev5/page-rev5-style agents with context > 250k.
- API stalls (2.08M tokens): not controllable by the agent, but the loss is proportional to context. Capping context (section e, item 1) cuts it about 50% (0.6-1.2M units). A 1h-TTL write costs 2 vs 1.25 and would only pay when stalls exceed 5 min for a given agent about 40% of the time; not worth it here (INFERRED).
- Tool wait: replace the foreground `sleep` loop with `run_in_background` or Monitor so the agent is not holding a hot cache while waiting; loses nothing, avoids the rewrite.

## e) Per role

| Role (agentType) | Agents | Reqs | Units | Context read+write per req | ctx max | Output share of units | Model |
|---|---|---|---|---|---|---|---|
| workflow-subagent | 39 | 1,819 | 43.0M | 146k | 388k | 11.0% | opus |
| lean-prover | 9 | 591 | 11.5M | 139k | 312k | 12.6% | opus |
| measure-engineer | 5 | 446 | 7.6M | 121k | 244k | 11.7% | sonnet |
| plan-rev5 | 1 | 178 | 6.2M | 267k | 428k | 3.1% | opus |
| part-builder | 6 | 242 | 2.9M | 73k | 152k | 17.2% | sonnet |
| page-rev5 | 1 | 70 | 2.2M | 207k | 297k | 3.8% | opus |
| math-reviewer | 11 | 107 | 1.4M | 45k | 95k | 14.1% | opus |
| reviewer-rev5 | 1 | 50 | 1.25M | 181k | 260k | 3.8% | opus |
| console-builder | 3 | 86 | 0.8M | 49k | 102k | 23.3% | sonnet |
| page-writer | 1 | 22 | 0.6M | 92k | 137k | 43.0% | opus |
| researcher | 2 | 63 | 0.5M | 42k | 101k | 14.9% | opus |
| others (14 single/few-agent roles) | 14 | ~160 | ~2.3M | 8k-82k | 10k-134k | 1-19% | mixed |

Workflow subagent cost by stage (units): research 11 agents 13.7M, lens 5 agents 9.0M, verify 7 agents 4.4M, apply 2 agents 3.6M, mui 4 agents 2.7M, delta 2.1M, review 10 agents 2.1M, extract 3 agents 1.9M, synthesize 1.8M, critique 3 agents 1.7M.

Cheaper-tier candidates (output share under ~15% and read-heavy means the work is retrieval and checking, not generation):
- Strong: wf:extract, wf:verify (numbers, refs), wf:review, math-reviewer, reviewer (checklist-style, <= 100k context). Cost 4.4 + 2.1 + 1.9 + 1.4 + 0.4 = about 10.2M opus units; at Sonnet 0.2 saves about 8.2M weighted (INFERRED price ratio). Risk: missed defects; pilot with a cross-check on 2 reviews.
- Moderate: wf:research and wf:lens (22.7M units, reading and synthesising; output share about 11%): pilot Sonnet on one lens; potential 18M weighted if quality holds, the largest single lever but the highest quality risk.
- Keep opus: lean-prover (proof search, 11.5M), plan-rev5/page-rev5 reasoning, but reduce their context (item 1).
- Already Sonnet: measure-engineer, part-builder, console-builder. Haiku: only claude-code-guide (0.07M).

## f) Top 10 savings, ranked by estimated units

Savings overlap (the same carried tokens are counted in items 1-4); do not sum them. Percentages are of the 80.25M total.

| # | Saving | Mechanism | Est. units | % |
|---|---|---|---|---|
| 1 | Model tier for review/extract/verify/research/lens workflow stages | Price factor 0.2 on 33M opus units of low-output, read-heavy agents (INFERRED price ratio; quality pilot first) | up to 26M weighted (8M for the strong group only) | 10-32% |
| 2 | Respawn at context >= 150k from a handoff note | 46 agents cross 150k; each later request reads 125k fewer tokens (0.1 x 125k = 12.5k per request) minus 31k one-time write; halve for lost context | 17.8M gross, about 9M realistic | 11-22% |
| 3 | Range-limit large Read results (offset/limit, grep first, cap 5k tokens) | 146 Read results over 5k tokens carry 9.7M above the cap (cap 3k: 11.2M; cap 8k: 7.6M); also stops the plan-rev5 pattern of 4 x 20-25k reads at request 2 of 178 | 9.7M gross, about 5M realistic | 6-12% |
| 4 | Delegate search/test/build sweeps to a Sonnet or Haiku helper (<= 2k summary) | Scenario A, section b: removes 468 requests and carried tokens from opus context | 7.4M net | 9% |
| 5 | Cap Bash output at 5k tokens (`| tail -40`, `| head`, log to file then grep, `lake build 2>&1 | tail`) | 343 Bash results over 5k tokens carry 5.3M above the cap (cap 3k: 10.3M) | 5.3M gross | 7% |
| 6 | Stop re-reading files | 63 re-read calls (468k tokens) carried 3.1M units; track read files in the handoff note or use Serena symbol reads | 3.1M | 3.9% |
| 7 | Analysis scripts print summaries only | 374 python3/node/for calls put 1.4M tokens (6.3M carried) in context; write the table to a scratch file and print <= 30 lines | about 2.5M (40% of 6.3M, INFERRED) | 3% |
| 8 | Lead-idle expiry: TaskStop + respawn from handoff | 3 rewrites of 250-360k tokens (section d) | 1.0M | 1.3% |
| 9 | API-stall exposure: smaller lens/critique contexts and fewer concurrent big agents | Rewrite size scales with context; halving context halves the 2.08M-token loss | 0.6-1.2M | 1% |
| 10 | Slim spawn overhead and background polls | Built-in/workflow agents write 15-45k at spawn vs 4k for custom roles (0.3M); 25 sleep-only requests plus a 6-min poll (0.4M + 0.16M rewrite) go to `run_in_background`/Monitor | about 0.9M | 1.1% |

Combined, items 2-7 with overlaps removed are plausibly 15-25% of the session (the carried-context share is 66%), and item 1 is additive on top as a price lever.

## Caveats

- Per-request output tokens come from the last streamed record per request id; the carried-token attribution assumes new context is only tool results (messages and attachments are folded into them, so tokens per result are slightly high).
- Delegation, respawn and price factors are models (INFERRED); the per-result sizes and the expired-cache classification are MEASURED from the transcripts.
- Scripts: `an1.py`..`an8.py` in the session scratchpad (stdlib only).
