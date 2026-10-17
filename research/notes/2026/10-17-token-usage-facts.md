---
id: 2026-10-17-token-usage-facts
kind: note
title: "Claude Code sub-agent token economics: facts for a nested-helper policy"
date: 2026-10-17
status: review
created: 2026-10-17
topics: [tokens, cache, subagents, nesting, pricing, policy]
---

# Sub-agent token economics (facts for "every sub-agent may spawn cheaper helpers")

Sources. Docs = https://code.claude.com/docs/en/<page> (fetched 2026-10-17, Claude Code 2.1.302 installed).
Pricing = https://platform.claude.com/docs/en/about-claude/pricing. Transcripts = this project's session
`<session>/subagents/agent-*.jsonl` + `.meta.json` under `~/.claude/projects/<project>/`. Profile =
`<scratchpad>/profile-tok/profile.json` (93 agents: 35 transcripts under `subagents/` + 58 workflow agents).
Status tags per claim: CONFIRMED (doc quote or read transcript field), MEASURED (computed from transcripts), INFERRED.

## 1. How a sub-agent gets the Agent tool

- CONFIRMED (docs sub-agents, "Giving subagents the Agent tool"): "If you omit `Agent` from the `tools` list entirely, the
  agent can't spawn any subagents with the Agent tool." Listing `Agent` in a subagent definition's `tools:` lets it spawn
  "while the depth limit allows it".
- CONFIRMED (same page): `Agent(worker, researcher)` allowlist syntax "applies only to an agent running as the main thread
  with `claude --agent`. In a subagent definition ... any type list inside the parentheses is ignored." So a role file cannot
  restrict which types a sub-agent spawns.
- CONFIRMED (docs permissions, "Match by input parameter"): `Agent(model:opus)`, `Agent(isolation:worktree)` work in
  **deny and ask rules only** ("allow rules continue to use each tool's own specifier syntax"); `*` wildcard allowed; a call that
  omits `model` is never matched (`Agent(model:*)` does not match an unset model); the value is compared to the literal input,
  so `Agent(model:opus)` matches the alias but not a full model ID. One parameter per rule.
- CONFIRMED (docs permissions, "Agent (subagents)"): `Agent(<name>)` deny rules disable a type for everyone
  (`permissions.deny`, or `--disallowedTools`).
- Consequence for a policy "helpers must be cheaper" (INFERRED): there is no allowlist of models. The only levers are deny/ask
  rules on literal model strings (deny `Agent(model:opus)`, `Agent(model:sonnet)`, `Agent(model:*fable*)`, `Agent(model:*opus*)`,
  `Agent(model:*sonnet*)`) which are session-wide (they also bind the lead), plus the role file's `model:` for each helper type,
  plus naming the cheap helper types in the sub-agent's prompt. An omitted `model` falls back to frontmatter, not to a rule match.
- CONFIRMED (repo): `.claude/settings.json` has `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=2`, `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=6`,
  ask rule `Agent(model:*fable*)`; `.claude/agents/*.md` list no `Agent` in `tools:`.
- MEASURED: of the 18 agent types in the transcripts only `general-purpose` (no `tools:` list, tools inherited) had `Agent` in its
  request `tools` array (tools: Agent, Artifact, Bash, Edit, Read, Skill, ToolSearch, Write, DeferredToolPlaceholder,
  SubagentHandback, advisor). All custom roles with a `tools:` list had none.
- CONFIRMED (docs "Available tools"): background sub-agents (the default; every meta.json here says `requestShape: background`)
  keep only a fixed built-in set (Read, Grep, Glob, LSP, Bash, Edit, Write, WebFetch, WebSearch, Skill, ToolSearch, ... plus
  `Agent`/`ExitPlanMode` under their own conditions) and `SubagentHandback`; `Agent` is withheld at the depth limit.

## 2. Depth, concurrency, transcript attribution

- CONFIRMED (docs env-vars + sub-agents "Let subagents spawn"): `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` = "number of subagent layers
  allowed below the main conversation (default: 3)". "With [2], your subagents can delegate to a second layer of their own, and that
  second layer can't delegate further. Set `1` to turn nesting off." So 2 = lead -> sub -> sub-sub, and the sub-sub has no Agent
  tool (a fork at the limit keeps it but it errors). Default was 1 in v2.1.217-218, 3 from v2.1.219.
- CONFIRMED (local binary 2.1.302 string table): error text "Subagent nesting limit reached (depth ...). Complete this task directly
  using your tools instead of spawning another agent. If the user explicitly requested deeper nesting, ask them to raise
  CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH." The exact comparison operator was not read (minified); the doc wording is the authority.
- CONFIRMED (docs "Concurrent subagent limit", env-vars): `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, default 20, counts subagents
  running in the **session**, so nested helpers share the same pool as the lead's children. Over the limit the Agent tool fails
  with "Concurrent subagent limit reached ... Do not retry" (binary string agrees). Repo sets 6: a lead with 5 running sub-agents
  leaves one slot, so nested helper spawns will fail often (INFERRED from the shared counter; raise it if helpers are wanted).
- CONFIRMED (docs): transcripts are `~/.claude/projects/{project}/{sessionId}/subagents/agent-{agentId}.jsonl`.
- MEASURED (35 `.meta.json` files, no depth-2 agent exists yet in this session). Fields seen: agentType, description, spawnDepth,
  requestShape, requestNonInteractive (all 35); name (32); toolUseId (25, Agent-tool spawns only); launchedWithDefaults (24);
  finished (22); worktreePath/spawnedWithWorktree/worktreeBranch (21); model (11), effort (1, only when the spawn call passed it);
  teammates (10) add taskKind=in_process_teammate, teamName, color, planModeRequired, customAgentType, spawnedAgentType, permissionMode.
  `spawnDepth` is 1 for every Agent-tool spawn from the lead and 0 for in-process teammates (25 and 10 files).
- MEASURED: there is **no parent id field** in the meta or in the transcript line keys (`parentUuid` is the message parent inside
  the same transcript, null on the first line; `agentId`, `sessionId`, `isSidechain` identify the agent). The only link is
  `toolUseId`: the `tool_use` id of the Agent call, which I found in the main session jsonl for a depth-1 agent.
  INFERRED: a nested child's `toolUseId` will appear in its parent's `agent-*.jsonl` (spawnDepth = 2), so attribution = search
  all `subagents/*.jsonl` + the main jsonl for that id. Not yet observed; verify with the first real depth-2 run.
- Workflow agents (58 in the profile) have `wf:*` names and live under `<session>/workflows/`, not `subagents/` (MEASURED: listing).

## 3. Per-spawn fixed cost

MEASURED from the first assistant `usage` of each `subagents/agent-*.jsonl` (prompt = input + cache_creation + cache_read; all
`ephemeral_5m`, w1h = 0 in all 93 agents):

| agentType (depth) | model | first-request prompt tokens | of which cache read | tools in request / tool-schema chars | system chars |
|---|---|---|---|---|---|
| part-builder (1) | sonnet-5-5 | 7.9k to 8.5k | 3.3k to 3.9k | 7 / 8,779 | 2,029 |
| lean-prover (1) | opus-5-5 | 7.2k to 7.5k | 3.6k (one cold: 0) | 6 / 7,626 | 2,050 |
| console-builder (1) | sonnet-5-5 | 7.6k to 7.9k | 3.3k to 4.0k | 7 / 8,779 | 2,116 |
| measure-engineer (1) | sonnet-5-5 | 7.7k to 7.9k | 3.9k | 7 / 8,779 | 2,013 |
| reviewer (1) / env-ops (1) | opus / sonnet | 5.5k / 5.4k | 0 | 6 / 8,350, 7,626 | 1,772 / 1,914 |
| claude-code-guide (1) | haiku-5-5 | 25.2k | 0 | 6 / 8,350 | 53,138 |
| general-purpose (1, has Agent) | sonnet-5-5 | 32.1k | 0 | 11 / 53,805 | 2,814 |
| in-process teammates (0) | opus/sonnet | 15k to 20k | 0 (one: 8.9k) | 8 to 16 / 22k to 34k | 9.7k to 10.0k |

- MEASURED: a custom role's fixed cost is about 5.4k to 8.5k tokens: tool schemas (about 2k tokens, 7.6k to 8.8k chars), role body +
  harness text (about 0.5k), environment block (2.8k chars), MCP server instructions (3.1k chars), and the CLAUDE.md system-reminder
  blob (9.1k chars at the time). The CLAUDE.md blob is present in the first request of the part-builder (read from the
  `api-request-blob` user message); this matches docs "What loads at startup" (non-fork subagents get CLAUDE.md).
- MEASURED: the cache-read part (3.3k to 4.0k) repeats per agentType: the system+tools prefix is byte-identical for spawns of the same
  type within 5 minutes, so the second spawn of a type reads it and only writes the rest (CLAUDE.md, env, task prompt, about 4k).
  A spawn after more than 5 minutes idle for that type writes everything (7.5k to 7.9k, e.g. lean-prover a8cc42fe, console-builder a3bb5381).
  The first-request write is therefore about 3.5k to 8k tokens for a custom role (INFERRED split; the totals are MEASURED).
- Money, INFERRED from list prices (below): a part-builder spawn, cold, is 8k x $2.50 per MTok = $0.02 (Sonnet 5.5, 5m write); a Haiku 5.5
  helper with the same 8k prefix is 8k x $0.125 per MTok = $0.001. The fixed spawn cost is small compared to run cost: MEASURED median
  agent in the profile wrote 100k+ cache tokens and read 2M+ (profile totals: 17.2M write, 498M read, 1.78M output, 7.8k uncached input).
- Do fewer tools shrink it? MEASURED yes but weakly: schema chars per tool are 98 (advisor) to 2,867 (Bash); dropping Write+Edit saves about
  1.7k chars (about 450 tokens). Bash, Read and WebFetch dominate. The big levers are NOT having `ToolSearch`/inherited tools:
  general-purpose carries Artifact (37,137 chars alone), Agent (5,419 chars) and three extra system messages (agent-types list 7.8k chars,
  skills list 22.6k chars, deferred-tool names 31.2k chars), 4 to 6 times a custom role.
- MEASURED/INFERRED, MCP: a role with an explicit `tools:` list has no `ToolSearch`, hence no deferred-tool-name list; only the short
  "MCP Server Instructions" message (3.1k chars) is added. MCP tools named in `tools:` are loaded with full schemas (a teammate with
  4 mcp__serena tools had 34,017 vs 23,936 chars of tool schema, about 2.5k chars per tool). Tools inherited via ToolSearch add only
  names (docs costs: "only tool names and server instructions enter context"), which MEASURED as 31k chars of names for
  the general-purpose agent with several MCP servers connected (about 8k tokens).
- Giving a role `Agent` adds INFERRED about 5.4k chars of tool description (about 1.4k tokens) plus the available-agent-types list
  (all 10 role descriptions; counted inside the general-purpose 7.8k-char message) to every spawn of that role, whether or not it
  ever spawns a helper. Only roles that really delegate should list it.
- Fork vs fresh: CONFIRMED (docs sub-agents "How forks differ", prompt-caching "Subagents and the cache"): a non-fork subagent
  has a "Separate cache" and "doesn't read the parent's cache, because the two prefixes differ"; a fork "inherits the parent's system
  prompt, tools, and conversation history exactly, so its first request reads the parent's cache" and "costs less than a fresh
  subagent for tasks that need the same context". A fork cannot spawn forks, uses the main session's model and exact tool pool
  (so it cannot be a cheaper model), and is deniable with `Agent(fork)`. NOT MEASURED: no fork exists in these transcripts
  (all 35 are named types). A fork of a big lead context re-reads (0.05x to 0.1x) the whole lead history, so it is cheaper than
  re-explaining only when the needed context is large; a helper that needs a few lines should be a fresh, cheap-model agent.

## 4. Model and effort

- CONFIRMED (docs sub-agents "Model selection and precedence", since v2.1.251): per-invocation `model` parameter > role frontmatter
  `model` (`inherit` = main model) > `CLAUDE_CODE_SUBAGENT_MODEL` > main conversation's model. Before v2.1.251 the env var came
  first. `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` (v2.1.257+) forces one model onto all subagents, teammates and workflow agents.
  Accepted values: `sonnet`, `opus`, `haiku`, `fable`, a full ID, `inherit`. Aliases on the Anthropic API (docs model-config):
  opus = Opus 5.5, sonnet = Sonnet 5.5, haiku = Haiku 5.5, fable = Fable 5.1.
- CONFIRMED (docs): effort frontmatter overrides the session effort but not `CLAUDE_CODE_EFFORT_LEVEL`; a per-invocation `effort`
  (non-fork) overrides the frontmatter; env var beats both. Defaults: medium on Opus/Sonnet/Haiku 5.5, high on other models.
  Thinking is billed as output and cannot be turned off on the 5.5 models and Fable (docs costs).
- MEASURED (weak, confounded by task): output tokens per request by role effort: medium/sonnet 414 (335 req), high/opus 442 (562),
  high/sonnet 398 (446). Effort level shows no material difference in visible output per request. Thinking text is blanked
  in transcripts (`"thinking": ""`), but `usage.output_tokens` includes it, so the numbers do include thinking. A controlled A/B on
  the same task was not run. Total output is 1.78M tokens = 10% of the 17.2M write tokens, so effort is a second-order lever
  versus context size.
- CONFIRMED (pricing page, per MTok; hits are cache reads):

| Model | input | 5m write | 1h write | cache hit | output | ratio to Haiku 5.5 (input / output) |
|---|---|---|---|---|---|---|
| Haiku 5.5 (prompt <= 100k) | $0.10 | $0.125 | $0.20 | $0.01 | $0.50 | 1 / 1 |
| Haiku 5.5 (prompt > 100k) | $0.50 | $0.625 | $1 | $0.05 | $2.50 | 5 / 5 |
| Sonnet 5.5 | $2 | $2.50 | $4 | $0.10 (0.05x) | $10 | 20 / 20 |
| Opus 5.5 | $4 | $5 | $8 | $0.20 (0.05x) | $20 | 40 / 40 |
| Fable 5.1 | $10 | $12.50 | $20 | $0.25 (0.025x) | $50 | 100 / 100 |

  Footnotes on the page: cache hits are 0.05x base on Opus 5.5 and Sonnet 5.5, 0.025x on Fable 5.1, 0.1x on all others (Haiku 5.5).
  Opus 5 / Sonnet 5 (older) are $5/$25 and $2/$10 with hits at 0.1x. So a Haiku 5.5 helper is 20x cheaper than Sonnet 5.5 and 40x
  cheaper than Opus 5.5 on fresh input and output; on cache reads 10x and 20x cheaper. The over-100k tier makes a Haiku helper
  whose context passes 100k only 4x cheaper than Sonnet on input: keep Haiku helpers short-lived.
- Real use is read-dominated: MEASURED 498M read vs 17.2M write vs 1.78M output tokens. At Sonnet 5.5 prices (INFERRED, ignores that
  some agents ran on Opus 5.5) that is $49.8 read, $43.1 write, $17.8 output, $0.02 uncached input, so writes plus reads
  are 84% of spend and helper delegation pays by keeping heavy tool output out of the parent's re-read context, not by output cost.

## 5. Cache TTL for sub-agents

- MEASURED: all 93 agents had `w1h = 0`, all writes `ephemeral_5m`.
- CONFIRMED (docs prompt-caching, "Which TTL each request gets" and "Choose the TTL yourself"): sub-agents, workflows, in-process
  teammates, forks and compaction fall in the "Everything else" bucket: five minutes, even on a subscription (except
  server-controlled helpers). Set it with `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL=1h` or the `subagentPromptCacheTtl` setting
  (v2.1.242+), per role with `experimental: {cacheTtl: 1h}` in the sub-agent frontmatter (v2.1.248+; ignored while the subscription uses
  usage credits), or both buckets with `ENABLE_PROMPT_CACHING_1H=1`. Precedence: `FORCE_PROMPT_CACHING_5M=1` > bucket env var >
  bucket setting > role frontmatter `cacheTtl` > `ENABLE_PROMPT_CACHING_1H` > default. Only `5m`/`1h` accepted. Confirm via
  `usage.cache_creation.ephemeral_1h_input_tokens`.
- Break-even (arithmetic, INFERRED on CONFIRMED prices). Let r be the read multiplier (0.05 Sonnet/Opus 5.5, 0.1 Haiku 5.5).
  1h makes every write cost 2x instead of 1.25x: extra 0.75 x W per agent (W = tokens written over its life). Each gap longer than
  5 min and shorter than 1 h that 1h avoids saves (1.25 - r) x ctx (rewrite at 1.25x instead of read at r). One avoided
  expiry at context ctx pays if (1.25 - r) x ctx > 0.75 x W, i.e. ctx/W > 0.625 (r=0.05) or 0.65 (r=0.1). Since an agent's
  writes W are about its final context, one avoided expiry late in the run roughly breaks even; early expiries lose.
- MEASURED on this session: 14 expired-cache rewrites totalling 3.01M tokens (17.5% of the 17.2M written; gaps 5.9 to 15.7 min,
  all at 5m TTL; 13 agents had idle gaps recorded). Using 1h everywhere would cost an extra 0.75 x 17.2M = 12.9M base-input-token
  equivalents to avoid at most 3.01M x (1.25 - 0.05) = 3.6M. 1h everywhere loses about 3.6x. A selective policy wins: 1h only
  for roles that wait on the lead (reviewers, long-lived teammates idle between messages with gaps expected between 5 and 60
  min); 5m for fire-and-forget helpers whose gaps are tool-time seconds. A Haiku helper's prefix is small, so it should stay 5m.

## 6. Other token cuts

- CONFIRMED (docs env-vars): `BASH_MAX_OUTPUT_LENGTH` default 30000 chars, docs say max 150000; local 2.1.302 binary string says
  `bashOutputMaxChars` clamps to 4000-128000 and output past the cap is saved to a file with a short preview. Setting the lower bound
  (e.g. 12000) caps what a chatty command adds to every later re-read.
- CONFIRMED: `CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS` default 25,000 tokens per Read (a read with `allow_large` can pass it).
  `MAX_MCP_OUTPUT_TOKENS`: not read (past the fetched part of the page); NOT CONFIRMED.
- CONFIRMED (docs model-config, sub-agents): auto-compaction runs inside sub-agents; `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` (1-100, can only
  lower the threshold) "applies to both main conversations and subagents"; per role `autoCompactWindow` frontmatter 100000 to 1000000;
  `CLAUDE_CODE_AUTO_COMPACT_WINDOW` wins over the field. Default for native 1M models (Sonnet 5+, Haiku 5.5, Opus 4.7+, Fable)
  is about 967K tokens, so by default a sub-agent never compacts before 967K. MEASURED: largest context in the profile 428K
  (plan-rev5, 178 requests) and no `compact_boundary` in any `subagents/*.jsonl` (the main jsonl has 7). With reads at 0.05x
  but every request re-reading the whole context, a 400K-token agent pays 400K x $0.10 = $0.04 per request at Sonnet 5.5, so a role
  window of 200K to 250K (`autoCompactWindow: 200000`) bounds per-request re-read cost at the price of one compaction rebuild
  (INFERRED trade; a compaction request itself reads the prefix at the read rate while the cache is warm, docs prompt-caching).
- CONFIRMED (docs costs): `/usage` per session shows tokens by model but its `Prompt cache (main)` line covers the main conversation
  only, not sub-agents. Per-sub-agent accounting must come from the transcripts (this profile) or OpenTelemetry. `/usage`
  "Attribution" gives each subagent's share of plan usage. `/context` shows what consumes the window.
- CONFIRMED (docs prompt-caching): changing model, effort (on 4.x models), or the tool set invalidates the cache of that conversation;
  on the 5.5 models and Fable 5.1 an effort change keeps the cache. Give each helper type a fixed model and tool list.
- CONFIRMED (docs costs): "The subagent's own requests still draw on your usage"; delegating verbose output keeps it out of the
  parent's context, and a sub-agent's final summary is the only thing re-read by the parent. Agent teams use "approximately 7x more
  tokens than standard sessions" in plan mode.
- CONFIRMED (docs sub-agents): `omitClaudeMd` frontmatter skips CLAUDE.md for a role (this repo's CLAUDE.md blob is about 9.1k chars,
  about 2.3k tokens, at every spawn; a Haiku helper that needs none of it saves that on each spawn). The built-in Explore and Plan
  agents skip CLAUDE.md.

## What this changes in the plan

- Section: policy for nested helpers (agent roster / settings, PLAN section on `.claude/agents` and `settings.json`).
  1. Add `Agent` to `tools:` only for roles that delegate (Lean prover, researcher, measure-engineer candidates). It cannot be
     restricted by type inside a role file; encode "helpers are cheap-model types only" in the role body and enforce models with
     deny/ask rules (`Agent(model:opus)`, `Agent(model:sonnet)`, `Agent(model:*opus*)`, `Agent(model:*sonnet*)`), noting those rules also
     bind the lead, so prefer `ask` over `deny` for the lead's own spawns; or define cheap helper roles with `model: haiku` and
     deny `Agent(general-purpose)` and `Agent(fork)` so a nested spawn cannot silently inherit the parent's model or the 32k tool pool.
  2. Keep `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=2` (lead -> sub -> helper; helpers cannot spawn). Raise
     `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` from 6 (shared counter across all depths) or helpers will hit "Concurrent subagent limit reached".
  3. Budget one cheap helper spawn at about 5k to 8k fixed tokens (Haiku 5.5 about $0.001 cold); do not spawn helpers for work under that size
     of context or for tasks that need the parent's long context (use a fork only then, at the parent's model price).
  4. Keep the 5m default; set `experimental: {cacheTtl: 1h}` only on roles that idle between 5 and 60 minutes
     (reviewers, waiting teammates). Rule of thumb from the break-even: 1h is worth it only if an expiry is expected late in the run.
  5. Add `autoCompactWindow: 200000` to long-running builders (measured contexts reach 250K to 430K) and consider `BASH_MAX_OUTPUT_LENGTH`
     at 12000 to 15000 for builder roles.
  6. Profiling/console: attribute nested helpers through `toolUseId` (meta.json) to the `tool_use` in the parent transcript; there is
     no parent-id field. Verify on the first real depth-2 run, then record `parentAgentId` in the console's event log from that link.
