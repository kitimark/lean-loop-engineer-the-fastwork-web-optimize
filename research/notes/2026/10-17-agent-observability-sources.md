---
id: 2026-10-17-agent-observability-sources
kind: note
title: "What Claude Code lets us observe about sub-agents and teammates without reading transcripts"
status: review
created: 2026-10-17
topics: [observability, hooks, opentelemetry, transcripts, console, agents]
---

# What can be observed about sub-agents and teammates, automatically

**Question.** Which sources can send per-agent tool timings, failures and retries, token and cache cost, and idle
time to the lead (through console-api), so the lead stops reading transcripts by hand?

**Answer.**
- Two sources cover all four needs, and both are local and free. (1) A **transcript tailer** reads
  `subagents/**/agent-<id>.jsonl` plus `*.meta.json`. (2) The **command hooks** we already plan, plus
  `PostToolUse`/`PostToolUseFailure` on every tool, because only these hooks report `duration_ms`.
- **OpenTelemetry** has the best timing data, but its *log events* do not name the agent, and project settings
  cannot turn it on. Treat it as optional.
- Statusline and `/cost` report totals for the session only.

**Sources.** Claude Code 2.1.302 is installed here; the build's `GIT_SHA` is `2ef144e6`.
- **Changelog:** `anthropics/claude-code` `CHANGELOG.md@c017428` (cited below as `CL:<line>`). I fetched it with
  raw.githubusercontent.
- **Binary:** the installed CLI. I read its JSON schemas and emitter code with `strings` (cited as `bin:<symbol>`).
- **Docs:** code.claude.com/docs could not be reached from this machine. WebFetch and curl both failed with
  `getaddrinfo ENOTFOUND code.claude.com`. So nothing here cites the docs pages. The changelog and the binary's own
  schema descriptions stand in for them.
- **Measurements:** run on this session's 91 sub-agent transcripts (69 top-level, 22 in workflows).

## 1. Transcript JSONL, the schema actually on disk (2.1.302)

**Layout** (MEASURED). Everything sits under `~/.claude/projects/<project>/<session>/`:
- `subagents/agent-<agentId>.jsonl` and `.meta.json`
- `subagents/workflows/<runId>/agent-<id>.jsonl`, with `.meta.json` and `journal.jsonl`
- `workflows/<runId>.json` (the run summary)
- `tool-results/*.txt`, which holds tool outputs too large to keep inline

The task's guess of `workflows/<run>/journal.jsonl` is wrong: the journals live under `subagents/workflows/`.

**Line types** (MEASURED, all 91 files):

| type | count |
|---|---|
| `assistant` | 7172 |
| `api-request-blob` | 5888 |
| `attachment` | 5566 |
| `user` | 4515 |
| `api-request` | 3728 |
| `api-request-shape` | 108 |

The table below says which line fields answer each question (MEASURED, read from real files).

| Need | Field(s) |
|---|---|
| Who | `agentId`, `sessionId`, `isSidechain`, `attributionAgent` (agent type, on `assistant` lines), `attributionSkill`, `api-request.querySource` (`agent:custom:<type>`, `agent:builtin:workflow-subagent`, …), `cwd`, `gitBranch`, `version` |
| Tool call start | `assistant` line → `message.content[].type=="tool_use"` with `id`, `name`, `input`, `caller`; line `timestamp` (ISO ms) |
| Tool call end | `user` line → `message.content[].type=="tool_result"` with `tool_use_id`, `is_error`; line `timestamp`; `sourceToolAssistantUUID`; `toolUseResult` (Bash: `stdout`, `stderr`, `interrupted`, `timedOutAfterMs`, `returnCodeInterpretation`, `backgroundTaskId`; Edit: `filePath`, `structuredPatch`, `userModified`; on errors a plain string `"Error: …"`) |
| Permission | `user.permissionDecision = {decision: accept\|reject, source: config, reasonType: classifier\|rule\|mode\|other\|subcommandResults}` |
| Usage | `assistant.message.usage`: `input_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`, `cache_creation.{ephemeral_5m_input_tokens, ephemeral_1h_input_tokens}`, `output_tokens`, `output_tokens_details`, `server_tool_use`, `service_tier`, `speed`, `iterations` |
| Model / effort | `message.model`, `requestedModel`, `advisorModel`, `effort`, `perTurnEffort`, `thinkingDurationMs` (sparse) |
| API request | `api-request`: `timestamp`, `params.model`, `params.max_tokens`, `querySource`, `requestDigest`, `cacheControl` |
| Hooks | attachments of type `hook_*` (none appear here because no hooks are configured yet; the type names come from `bin:` and include `hook_additional_context`, `hook_stopped_continuation` and `hook_permission_decision`) |
| Agent meta | `.meta.json`: `agentType`, `name`, `description`, `toolUseId`, `spawnDepth`, `requestShape` (background/foreground), `worktreeBranch`, `finished`; teammates also have `taskKind: "in_process_teammate"`, `teamName`, `model`, `permissionMode`; workflow agents have `workflowPhase` |
| Workflow journal | `{type: launched}`, `{type: started, agentId, key, label, phase}`, `{type: result, agentId, key, result}`. **No timestamps.** `workflows/<runId>.json` has `startTime`, `durationMs`, `status`, `agentCount`, `totalTokens`, `totalToolCalls`, `error` |

Things to watch for:
- **Usage is repeated** (MEASURED). One API message spans several `assistant` lines that share `message.id`: 2841
  messages here, and in 468 of them the `usage` differs from line to line. Keep only the **last line per
  `message.id`**, which matches the upsert rule in PLAN.md (line 286).
- **Tool wall time** = `tool_result.timestamp − tool_use line timestamp` (MEASURED). This includes the wait for
  permission. One `Edit` took 312 s because it waited on an `ask` rule (`Edit(/.claude/**)`). Only the hook's
  `duration_ms` excludes that wait (see §2).
- **Cache writes** are all 5-minute (MEASURED): `ephemeral_1h_input_tokens` = 0 for every agent type. A teammate
  that sits idle for more than 5 minutes pays to write its context again.

**Tool wall time** across this session's sub-agents (MEASURED):

| tool | n | total (min) | p50 (s) | max (s) |
|---|---|---|---|---|
| Bash | 3139 | 323.5 | 0.6 | 601 |
| Edit | 351 | 29.4 | 0.1 | 312 |
| WebFetch | 79 | 10.9 | 8.2 | 23 |
| Read | 223 | 1.8 | 0.4 | 6.5 |

Results and denials (MEASURED):
- 4304 tool results, of which 213 have `is_error: true`.
- 101 of the errors are `"This agent is isolated in the worktree …"`. That is a repeated mistake, and the console
  should flag it.
- There were 8 permission rejections (5 by the classifier, 3 via `subcommandResults`).

**Cache reads per agent type** (MEASURED, deduplicated):

| agent type | cache read (tokens) |
|---|---|
| workflow-subagent | 256M |
| lean-prover | 80M |
| plan-rev5 | 46M |
| measure-engineer | 43M |

## 2. Hooks

**Common input** (CONFIRMED, from `bin:` hook base-input builder and its zod schema descriptions):
- `session_id`, `transcript_path`, `cwd`, `scratchpad_dir`, `prompt_id`, `permission_mode`, `agent_id`,
  `agent_type`, `effort`.
- `agent_id` is "Present only when the hook fires from within a subagent … Absent for the main thread". It was
  added in 2.1.69 (CL:7142).
- `prompt_id` is "Same value emitted on OpenTelemetry events as the `prompt.id` attribute". That makes it the key
  for joining hook data to OTel data.

Fields added by each event (CONFIRMED from `bin:`):

| Event | Extra fields | Version |
|---|---|---|
| PreToolUse | `tool_name`, `tool_input`, `tool_use_id` | — |
| PostToolUse | `tool_response`, `tool_use_id`, **`duration_ms`** ("tool execution time, excluding permission prompts and PreToolUse hooks") | 2.1.119, CL:5920 |
| PostToolUseFailure | `error`, `is_interrupt`, **`duration_ms`** | 2.1.119, CL:5920 |
| PostToolBatch | `tool_calls` | — |
| PermissionDenied | fires after the auto-mode classifier denies a call | 2.1.89, CL:6515 |
| SubagentStart | `agent_id`, `agent_type` | 2.0.43 |
| SubagentStop | `agent_id`, `agent_type`, `agent_transcript_path`, `last_assistant_message`, `stop_hook_active`, `background_tasks`, `session_crons` | CL:8256, 7412, 5331 |
| TeammateIdle | `teammate_name`, `team_name`, plus `agent_id` | 2.1.33; no longer fires from a teammate's own sub-agents since 2.1.290, CL:954 |
| TaskCreated / TaskCompleted | `task_id`, `task_subject`, `task_description`, `teammate_name`, `team_name` | — |

Do hooks fire for sub-agents and in-process teammates?
- **Sub-agents: yes.** The `agent_id` field only exists because hooks fire inside sub-agents (CONFIRMED). The
  2.1.288 fix that added `agent_id` to InstructionsLoaded for sub-agents also shows this (CL:1084).
- **In-process teammates: INFERRED yes.** They run in the same process and pass their own `agentId` and
  `agentType` into the hook input. `TeammateIdle` is built that way in `bin:`.
- **Settings file:** hooks come from the lead's project `.claude/settings.json`. Worktree agents carry the same
  checked-in file (INFERRED).

**HTTP hooks** (CONFIRMED, `bin:` HttpHookSchema; added in 2.1.63, CL:7250):
- Fields: `type: "http"`, `url`, `timeout` (seconds), `headers` (`$VAR` is expanded only for names listed in
  `allowedEnvVars`, and never for credentials), `onFailure`, `if`, `statusMessage`, `once`.
- **HTTP hooks have no `async` option.** Only command hooks have `async` and `asyncRewake`. So an HTTP hook makes
  the agent wait until the request returns or times out.
- Errors do not block by default. `onFailure: "block"` exists but is opt-in (CL:491).
- Managed settings can restrict this with `allowedHttpHookUrls` and `httpHookAllowedEnvVars`.
- The default tool-hook timeout is 10 minutes (CL:7870).
- Conclusion: PLAN.md already rejects HTTP hooks ("lose events silently"), and that is right. The cheap, safe
  pattern is a **command hook** that appends stdin to a spool file and exits 0 with no stdout. console-api then
  reads the spool.

**Measured cost** of the spool append on this machine (MEASURED):

| writer | time per call |
|---|---|
| `node -e` | 40–50 ms |
| `sh -c 'cat >> spool'` | 10–20 ms |

At about 3,100 Bash calls in a session, a hook on every tool adds 1–2.5 minutes of wall time in total, spread
across agents. You can also set `"async": true` so the hook does not block at all. That works because the
observer only writes and never decides anything.

## 3. OpenTelemetry

**Turning it on:** `CLAUDE_CODE_ENABLE_TELEMETRY=1`, plus `OTEL_{METRICS,LOGS,TRACES}_EXPORTER`,
`OTEL_EXPORTER_OTLP_{,LOGS_,METRICS_,TRACES_}ENDPOINT/PROTOCOL/HEADERS`, `OTEL_METRIC_EXPORT_INTERVAL` and
`OTEL_LOGS_EXPORT_INTERVAL`. Traces also need `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA`. All of these names appear in
`bin:` (CONFIRMED).
- **Since 2.1.282, project and local settings ignore the variables that turn export on, set the endpoint, or
  capture content** (CL:1714). CONFIRMED.
- So our checked-in `.claude/settings.json` cannot enable OTel. It has to come from user settings or the shell
  environment. Today it is unset (CONFIRMED: no OTel variables in project settings).

**Metrics** (CONFIRMED, names in `bin:`):
- `claude_code.token.usage`, `cost.usage`, `active_time.total`, `session.count`, `lines_of_code.count`,
  `commit.count`, `pull_request.count`, `code_edit_tool.decision`.
- With `OTEL_LOG_TOOL_DETAILS=1`, the token and cost metrics carry the real **agent, skill, plugin and MCP names**
  (CL:2385).
- These metrics are by agent *type*, not agent instance.

**Log events** (CONFIRMED, emitter code in `bin:`):
- `tool_result` carries `tool_name`, `tool_use_id`, `success`, `duration_ms`, `error_type`, `error` (needs
  details), `tool_parameters`, `tool_input_size_bytes`, `tool_result_size_bytes`, `decision_source` and
  `decision_type`.
- `api_request` carries `model`, `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_creation_tokens`,
  `cache_creation_5m_tokens`, `cache_creation_1h_tokens`, `cost_usd`, `duration_ms`, `ttft_ms`, `request_id`,
  `query_source`, `effort` and `speed`.
- `api_error` carries `status_code`, `attempt` and `duration_ms`. `api_retries_exhausted` carries
  `total_attempts` and `total_retry_duration_ms`.
- `tool_decision` carries `decision`, `source`, `permission_mode` and `classifier_*`.
- `hook_execution_complete` carries `total_duration_ms` and the success, blocking, error and cancelled counts.
- Every event gets `event.timestamp`, `event.sequence`, `prompt.id` and `user.id`; `session.id` is added when the
  include setting allows it.
- **Events carry no `agent_id`.** The emitter (`wi(...)`) maps the agent context only to `workflow.run_id` and
  `workflow.name`. On `api_request`, `query_source` gives the agent type but not which instance.
- So per-agent event attribution is **not available from OTel logs** (CONFIRMED, `bin:` Pdn/wi).

**Traces (beta):**
- `claude_code.llm_request` and `claude_code.tool` spans carry `agent_id` and `parent_agent_id` (CL:5559,
  CL:5326).
- Other spans: `claude_code.tool.execution`, `tool.blocked_on_user` (the permission wait, shown separately),
  `subagent.spawn` (`agent_id`, `agent_type`, `parent_agent_id`), `hook`, `interaction`, `compaction` (names in
  `bin:`).
- Background sub-agent spans nest under the Agent tool span that started them.
- This is the only OTel signal that is attributed per agent (CONFIRMED).

**Receiving it locally:** any OTLP/HTTP endpoint works, either an `otelcol` on localhost or a `/v1/{logs,traces,
metrics}` route on console-api (INFERRED: standard OTLP exporter; protobuf is the default, JSON with
`OTEL_EXPORTER_OTLP_PROTOCOL=http/json`).

**Privacy toggles** (CONFIRMED):
- `OTEL_LOG_USER_PROMPTS` (prompts are `<REDACTED>` by default)
- `OTEL_LOG_ASSISTANT_RESPONSES`
- `OTEL_LOG_TOOL_DETAILS` (tool parameters and real names)
- `OTEL_LOG_TOOL_CONTENT` (tool output on spans, CL:1561)
- `OTEL_LOG_RAW_API_BODIES` (full bodies, CL:6131)

`user.email` and `organization.id` are added from the account (`bin:` fNt). These count as personal data, so keep
the export local and never commit what it captures.

## 4. Statusline, /cost and other surfaces

- **statusLine stdin** (CONFIRMED, `bin:` schema): `session.{total_cost_usd, total_api_duration_ms,
  total_duration_ms, total_lines_added, total_lines_removed, model_usage}`, `rate_limits`, and `prompt_cache`
  (hit ratio, misses, likely cause; CL:3141, CL:2911).
- These totals cover the **session** and are refreshed on each render. They are not per agent.
- **`subagentStatusLine`**: one row per sub-agent, with `agentType` (CL:643), model and effort (CL:4102). It is
  display-only; a script could log it (INFERRED).
- **`/cost` and `/usage`** are interactive only.
- **Workflow `wf_*.json`** gives `durationMs`, `status` and `agentCount` for each run (MEASURED). In a killed run,
  `totalTokens` and `totalToolCalls` were 0, so they are unreliable.

## Comparison

| Source | What it gives | Latency | Per-agent attribution | Privacy risk | Effort to wire |
|---|---|---|---|---|---|
| Transcript tailer (`agent-*.jsonl` + meta) | tool start/end, name, input, `is_error`, error text, permission decisions, full usage incl. 5m/1h writes, model, effort, timestamps for idle gaps | file append; tail ~1 s | **yes**: `agentId`, `attributionAgent`, meta `name`/`agentType`/`teamName` | high (full inputs and outputs on disk; read locally, emit only derived numbers) | medium: a tailer plus deduplication by `message.id`; the schema is undocumented and changes between versions |
| Command hooks → spool | `duration_ms` (pure execution), failures, `is_interrupt`, denials, start/stop/idle edges, `prompt_id` | synchronous, < 50 ms | **yes**: `agent_id`, `agent_type` (+`teammate_name`) | medium (tool_input/response in payload; the hook can drop them) | low: already planned (`emit.mjs`); add PostToolUse(`*`) |
| HTTP hooks | same payload | blocks the agent until reply or timeout | yes | medium | low, but no `async` and events are lost when the service is down; rejected |
| OTel metrics | tokens, cost, active time, lines | 60 s default export interval | agent **type** only (with TOOL_DETAILS) | low–medium (email attr) | low env vars, but user scope only + collector |
| OTel log events | `tool_result.duration_ms`/success, `api_request` cost/duration/ttft/cache 5m/1h, `api_error` attempts, `tool_decision`, hook timings | ~5 s batch | **no** `agent_id` (only `query_source` type, `workflow.run_id`, `prompt.id`) | medium (prompts redacted by default) | medium: OTLP receiver |
| OTel traces (beta) | per-request and per-tool spans incl. permission wait, sub-agent spawn tree | batch | **yes**: `agent_id`, `parent_agent_id` | medium–high with content flags | high: beta flag, protobuf OTLP traces receiver |
| statusLine / subagentStatusLine | session cost, API time, cache hit ratio; rows per sub-agent | each render | session only / per row, display | low | low, but sampling only |
| Workflow run JSON + journal | run duration, status, agent → label/phase | at end | agentId ↔ label | low | trivial |

## Recommendation: the cheapest reliable combination

| Need | Primary | Cross-check |
|---|---|---|
| Per-agent tool timings | PostToolUse + PostToolUseFailure command hook (matcher `*`, `async: true`, spool append) → `duration_ms` + `agent_id` | transcript `tool_result.ts − tool_use.ts` gives wall time; the difference is the permission wait |
| Failures / retries | PostToolUseFailure + PermissionDenied hooks; transcript `is_error` + error-text classes (for example "isolated in the worktree"); retries = same `agent_id`+`tool_name`+similar input after a failure | OTel `api_error.attempt` only if OTel is on |
| Token + cache cost | transcript tailer: last `usage` per `message.id`, split 5m/1h writes, keyed by `agentId` → priced by console-api | statusLine `session.total_cost_usd` as a whole-session check |
| Idle time | TeammateIdle / SubagentStop / SubagentStart hook edges; gaps between assistant timestamps per `agentId`; flag gaps over 5 min (the cache expires, MEASURED all-5m writes) | — |

Turn OTel on only for deep dives. Use traces (the only per-agent OTel signal) in the user scope with a local
collector. Do not make it a dependency.

## What this changes in the plan

- **PLAN.md, hooks row (line 333):** add `PostToolUse` (matcher `*`, `async: true`) and `PostToolUseFailure`
  (all tools, not only Bash) and `PermissionDenied` to the observer `emit.mjs`. The emitted record keeps only
  `agent_id`, `agent_type`, `tool_name`, `tool_use_id`, `duration_ms`, `error`/`is_interrupt` and `prompt_id`, and
  drops `tool_input` and `tool_response`. HTTP hooks stay excluded, because they cannot be async (they block the
  agent and lose events).
- **PLAN.md, observers row (line 286) and §8.5:** the transcript tailer
  1. reads `subagents/**/agent-*.jsonl` + `.meta.json`, and `workflows/<run>.json`;
  2. keeps the last usage per `message.id`, with `ephemeral_5m`/`ephemeral_1h` kept separate;
  3. derives tool wall time, the permission wait (wall time minus hook `duration_ms`), `is_error` classes and idle
     gaps per `agentId`.
- **PLAN.md, Lean `Fw/Wire` decoders:** add decoders for the PostToolUse/PostToolUseFailure payloads and for the
  transcript `usage` record, built from the field lists above.
- **PLAN.md, tooling, OTel:** mark it optional, enabled in the user scope only (project settings cannot enable it
  since 2.1.282). Note that log events carry no `agent_id`.
