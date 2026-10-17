---
kind: kickoff-note
id: 07-claude-code-agent-teams
title: Claude Code agent team configuration for v2, optimized for token usage
date: 2026-10-17
status: draft for user review
claude_code_version_checked: 2.1.301 (local `claude --version`)
docs_fetched: 2026-10-17 from https://code.claude.com/docs/en/*.md and https://platform.claude.com/docs/en/about-claude/*.md
---

# Claude Code agent teams for v2 (kickoff note 07)

Status words:
- **CONFIRMED**: a doc page, a source file or a v1 record is cited.
- **INFERRED**: my reasoning; it needs a spike or a measurement before it carries a decision.

Docs were read on 2026-10-17 against Claude Code 2.1.301, the version installed here. Every field used below
requires that version or an older one (CONFIRMED: version notes on each field in the pages cited).

---

## 0. Answer first

1. **Model and effort are now real per-role levers for teammates as well as subagents.**
   - v1 recorded that teammates ignore the definition's `effort` (`fixes/AGENT_ROLES.md` L289-295).
   - That has changed. For an **in-process** teammate, Claude Code applies the definition's `model`, `effort`,
     `tools`, `disallowedTools`, `autoCompactWindow` and body (CONFIRMED: agent-teams, "Use subagent definitions for
     teammates").
   - Split-pane teammates do **not** get the per-role `effort` or `autoCompactWindow` (same section).
   - So v2 commits `"teammateMode": "in-process"` at project level. `teammateMode` is valid in any settings file
     (CONFIRMED: settings-reference `teammateMode`).
2. **Context, not output, was v1's bill, and v2's settings attack it directly.**
   - v1 facts: cache reads were about 96 % of all tokens; 75 % of usage ran with more than 150k tokens of context;
     Opus was about 97 % of the ~$13,500 (v1 `research/loop-distillation/README.md` L266-271, L426-437).
   - **Per-role `autoCompactWindow` caps context.** It takes a token count from 100000 to 1000000 and needs
     v2.1.296+ (CONFIRMED: sub-agents frontmatter).
   - **`subagentPromptCacheTtl: "1h"` stops cold re-reads.** On a cold wake the cost moves from a cache read at 0.05x
     to a cache write at 1.25x base input (§4).
   - **An `Explore` override on Haiku 5.5.** The built-in Explore otherwise runs on the lead's model (CONFIRMED:
     sub-agents "Built-in subagents").
   - **Deterministic gates run as hooks or scripts, never as agents.** This was v1's own conclusion
     (`loop-distillation` §6.4).
3. **Roster: one lead, about 10 role definitions, at most 3 teammates alive at once.**
   - Teammates are used only where agents must talk to each other: two engine researchers who cross-check, and later
     experiment owners.
   - Everything that edits code runs as a **named worktree subagent** (`name` plus `isolation: "worktree"` on the
     call). That keeps the definition's effort and gives it its own worktree. It also avoids the v1 `EnterWorktree`
     trap (I-272).
   - The model ladder is **Haiku low → Sonnet medium → Opus high → Fable (per call only, behind an `ask` rule)**.
4. **Model choice:**
   - Opus 5.5 for the lead, engine maths, measurement code, proofs, reviews and experiments.
   - Sonnet 5.5 for the React parts and the console.
   - Haiku 5.5 for the librarian and for search.
   - Fable 5.1 is never a default. It costs 2.5x Opus per token, and on a subscription it may bill usage credits
     (CONFIRMED: pricing; model-config "Fable and usage credits").
5. **Token usage per role is measured three ways:**
   - **Local transcript meter (works today).** Port v1's meter: `~/.claude/projects/<proj>/<session>/subagents/agent-*.jsonl`
     carries `message.usage` (CONFIRMED: sub-agents "Resume subagents"; v1 `research/management/tools/usage.mjs`).
   - **Hooks for live cost cards.** `SubagentStop` passes `agent_transcript_path`, and `TeammateIdle` passes
     `teammate_name` + `agent_id` (CONFIRMED: hooks).
   - **OpenTelemetry (optional).** `claude_code.token.usage` / `cost.usage` carry `model`, `effort` and `agent.name`.
     It must be enabled in **user** settings or the shell: since v2.1.282, project settings ignore the telemetry
     switches (CONFIRMED: settings-reference "Variables Claude Code ignores in env").

Draft files are in §6 (settings.json) and §7 (agent definitions). Open questions for the user are in §10.

---

## 1. What v1 ran, and what it cost (evidence)

| v1 fact | Source |
|---|---|
| 5 agent definitions: `bundle-mapper` (sonnet/medium, read-only), `fix-owner` (opus/high, worktree), `fix-reviewer` (opus/high, read-only), `toolsmith` (opus/high, worktree), `wave-integrator` (opus/high, worktree) | v1 `.claude/agents/*.md` frontmatter |
| Roster plus "model / effort per task" table; Fable was a per-call opt-in only | v1 `fixes/AGENT_ROLES.md` L7-17, L317-339 |
| Session readout after 4 d 8 h: $8,576 (Opus $8,342, Sonnet $214, Haiku $20); whole project ~$13,500, Opus ~97 % | v1 `research/loop-distillation/README.md` L266-267 |
| 81 % of usage came from subagents; 75 % ran with >150k context; cache reads ~96 % of tokens | same, L269-271 |
| "Routing, lookups, summaries and 'is the phone connected?' never needed Opus"; the clerk moved to Sonnet only on 5 Oct | same, L428-430 |
| The user's recurring check prompts added ~200 M tokens by re-reading the lead's long context; "a script would have answered it" | same, L432-434 |
| "Idle agents cost too … no work, no listener" | same, L435-436 |
| Every agent loaded a 9,467-word rulebook (~12-16k tokens), ~8 % of cache reads | same, L339-342 |
| Fixed gates (pixel gates, cost cards) "would have been cheaper and more deterministic as scripted workflows than as agents re-reading 15,000 tokens of rules" | same, L417-420 |
| 442 agents started; 160 in the first 29 h made queues longer, not work faster | same, L450-453 |
| Teammates never call `EnterWorktree`: in a team it moved the whole session (I-272); the lead creates the worktree and passes absolute paths | v1 `memory/agent-teams-not-workflows.md` |
| Every spawn is named `<role>-<topic>`, and each spawn prompt carries the peer directory | v1 `memory/agent-spawn-names.md` |
| The lead delegates research to helpers and keeps decisions, landing and user contact | v1 `memory/lead-delegates-research.md` |
| A recurring problem area gets an owner agent with an exit metric; the owner parks when the tools carry the area | v1 `memory/lead-delegates-areas-measures.md` |
| The user wants agent teams (named, visible) rather than hidden Workflow scripts | v1 `memory/agent-teams-not-workflows.md` |
| v1 settings: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, `worktree.baseRef: "head"`, long allow/ask/deny lists, a `git-guard` and `fg-guard` PreToolUse hook | v1 `.claude/settings.json` |

What v2 keeps from v1:
- named roles;
- a lead that only decides and lands;
- worktree per editor;
- read-only reviewers with a fresh context;
- Fable only as an opt-in.

What v2 drops:
- Opus as the default for everything;
- agents acting as gates;
- a long shared rulebook;
- area-owner "mgmt" agents. Their job moves to console-api plus hooks (INFERRED; it depends on note 06's console design).

---

## 2. Verified platform facts this design depends on

All CONFIRMED unless marked. URLs are in "Sources".

### 2.1 Enabling teams and the team shape
- Teams are enabled with `{"env": {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"}}` in settings.json (agent-teams,
  "Enable agent teams").
- **An interactive session is required.** `-p` and SDK sessions never spawn teammates (same section).
- With teams on, an Agent call **from the main conversation** that carries `name` becomes a teammate. Two exceptions:
  a fork, or a call that passes `isolation` on the call itself.
  - An `isolation` value in the **definition** does not prevent the teammate launch. The teammate then runs in the
    main session's working directory (sub-agents "Subagent names"; agent-teams "How Claude starts agent teams").
- Claude may name subagents on its own, so teams can form unasked (same).
- **One team per session. No nested teams: teammates cannot spawn teammates. The lead is fixed** (agent-teams
  "Limitations").
- **In-process teammates' subagents always run in the foreground**, so the teammate waits for them (same).
- **`/resume` does not restore in-process teammates** (same). Durable state must live in files or console-api, not
  in a teammate's memory.
- Teammates load CLAUDE.md, MCP servers and skills like a normal session, plus the spawn prompt. They do not load the
  lead's history (agent-teams "Context and communication").
- **Teammates start with the lead's permission mode.** Per-teammate modes cannot be set at spawn, and teammate
  permission prompts appear in the lead (agent-teams "Permissions").
- The team config lives at `~/.claude/teams/{team}/config.json` and must not be hand-edited. There is **no
  project-level team file**: a `.claude/teams/teams.json` is just an ordinary file (agent-teams "Architecture").
  Reusable roles therefore go in `.claude/agents/*.md`.
- The docs give a token warning: "approximately 7x more tokens than standard sessions when teammates run in plan
  mode". They recommend Sonnet for teammates, small teams and focused spawn prompts, and shutting teammates down when
  done (costs "Agent team token costs", "Manage agent team costs").

### 2.2 How a teammate's model and effort are chosen
- **Model order** (agent-teams "Specify teammates and models"):
  1. the model named in the spawn prompt;
  2. the definition's `model`;
  3. `CLAUDE_CODE_SUBAGENT_MODEL`;
  4. the lead's model.
  - `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` removes sources 1 and 2.
  - `teammateDefaultModel` was removed in v2.1.234.
  - **Rule for the lead: do not name a model in a spawn prompt unless you mean to override the role.**
- **What a definition applies to a teammate:**

  | Field | In-process teammate | Split-pane teammate |
  |---|---|---|
  | `tools` | yes, plus `SendMessage` and the Task tools | yes |
  | `model` | yes | yes |
  | `disallowedTools` | yes | no |
  | `effort` | yes | no |
  | `autoCompactWindow` | yes | no |
  | body | appended to the system prompt | replaces the system prompt |
  | `skills` | no | no |
  | `mcpServers` | no | yes |

  `isolation` and `permissionMode` are not in the list of applied parts (agent-teams "Use subagent definitions for
  teammates"; INFERRED: not applied, consistent with the "Permissions" section).
- **Subagents.** The model order is per-call `model`, then frontmatter, then `CLAUDE_CODE_SUBAGENT_MODEL`, then the
  main model. A family alias equal to the main family resolves to the main model's exact ID, including `[1m]`
  (sub-agents "Choose a model").
  - Effort comes from frontmatter `effort`, or from a per-invocation `effort` parameter (v2.1.292+), which is new
    since v1.
  - **`CLAUDE_CODE_EFFORT_LEVEL` overrides both**, so v2 must not set it in project env (sub-agents "Choose an effort
    level"; env-vars).
- **Effort levels.** Opus 5.5, Sonnet 5.5 and **Haiku 5.5** all support `low` to `max`. v1 noted that Haiku had no
  effort; Haiku 5.5 does. The defaults are `medium` on Opus 5.5, Sonnet 5.5 and Haiku 5.5.
  - `max` "may show diminishing returns and is prone to overthinking" (model-config "Adjust effort level", "Choose an
    effort level").
  - These models can't turn thinking off, and thinking is billed as output. Effort is therefore the output-cost lever
    (costs "Adjust extended thinking").

### 2.3 Frontmatter fields (verified list)
- Source: sub-agents "Frontmatter reference". Only `name` and `description` are required. Unknown keys are ignored
  **silently**; `claude --debug` logs `does not recognize or apply` for typos (v2.1.296+).
- The fields, all CONFIRMED:
  - `name`, `description`, `tools`, `disallowedTools`;
  - `model` (`sonnet|opus|haiku|fable|<full id>|inherit`);
  - `permissionMode`, `maxTurns`;
  - `autoCompactWindow` (plain integer 100000-1000000; `200k` is read as 200 and rejected);
  - `skills`, `mcpServers`, `hooks`;
  - `memory` (`user|project|local`);
  - `background`, `omitClaudeMd`;
  - `effort`;
  - `isolation` (`worktree`);
  - `color` (`red|blue|green|yellow|purple|orange|pink|cyan`);
  - `initialPrompt`;
  - `experimental.cacheTtl` (`5m|1h`).
- Full model IDs are accepted in `model` (example given: `claude-opus-5-5`). v2 **pins full IDs** for
  reproducibility, because the model is an experimental variable (INFERRED choice).
- A `tools` entry such as `Agent(x, y)` restricts spawnable types only for `claude --agent` main threads. In a
  subagent definition, `Agent` just enables nesting (sub-agents "Restrict which subagents can be spawned").
- `permissionMode` is ignored when the main session is in `bypassPermissions`, `acceptEdits` or `auto` (sub-agents
  "Permission modes").

### 2.4 Settings keys and env vars used in the draft
- **Context and caching keys.** `teammateMode`, `subagentPromptCacheTtl`, `autoCompactWindow`, and
  `worktree.{baseRef,symlinkDirectories,sparsePaths,bgIsolation}` are all "Any file" scope (settings-reference).
  - `worktree.baseRef` defaults to `"fresh"` (`origin/<default>`). `"head"` branches from the local HEAD, which is
    what v1 used.
- **Env vars.** `CLAUDE_CODE_SUBAGENT_MODEL`, `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` (default 3),
  `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` (default 20; teammates follow their own limits),
  `CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION` (default 200) and `CLAUDE_CODE_ENABLE_TODO_TOOLS` (env-vars).
- **Project/local `env` cannot set these** (settings-reference "Variables Claude Code ignores in env", v2.1.282+):
  - `CLAUDE_CODE_ENABLE_TELEMETRY`;
  - the `OTEL_*_EXPORTER` selectors (except `none`);
  - `OTEL_LOG_TOOL_DETAILS` and the other content flags;
  - the OTLP endpoint variables.

  They go in `~/.claude/settings.json` or the shell.
- **Project `permissions.allow` and `additionalDirectories` apply only after the workspace trust dialog.** Deny and
  ask rules always apply (permissions "Project allow rules and workspace trust").
- **Permission rules can match Agent parameters:** `Agent(model:opus)` and `Agent(isolation:worktree)`. The match is
  literal: `Agent(model:opus)` matches the alias, not a full ID, and an omitted parameter never matches (permissions,
  parameter matching).
- **Task tools are off by default on Opus 5.5 / Sonnet 5.5 / Haiku 5.5** (on only for Opus 4.7, Sonnet 4.6, Haiku 4.5
  and earlier). Opt in with `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`. In-process teammates follow the session (tools-reference
  "Task tool availability"). Without them there is no shared task list and `TaskCompleted` will not fire on
  `TaskUpdate`.

### 2.5 Hooks for teams
All from hooks.md, CONFIRMED:

| Event | Input | Control | Matcher |
|---|---|---|---|
| `TeammateIdle` | `teammate_name`, `agent_id` (v2.1.290+), and `team_name` (deprecated) | exit 2 means "keep working, here is feedback"; `{"continue": false, "stopReason"}` stops the teammate | none |
| `TaskCreated` / `TaskCompleted` | `task_id`, `task_subject`, `task_description?`, `teammate_name?`, `agent_id?` | exit 2 blocks the creation or completion. `TaskCompleted` also fires when a teammate ends its turn with in-progress tasks | none |
| `SubagentStart` | `agent_id`, `agent_type`; fires on spawn, on resume, and **each time an in-process teammate handles a new message** | can return `additionalContext`, which is injected once, so the cache stays intact | agent type |
| `SubagentStop` | `agent_id`, `agent_type`, `agent_transcript_path`, `last_assistant_message`; also fires for internal agents, with an empty `agent_type` | blocks like Stop | agent type |

- Every hook input carries `agent_id` / `agent_type` when the hook fires inside a subagent or in-process teammate
  ("Common input fields"; INFERRED: `agent_type` is present for teammates spawned from a definition; spike it).
- The command form `{"command": "node", "args": [...]}` runs without a shell ("Exec form and shell form").

---

## 3. The v2 roster

The repo layout follows note 06 §2.2 (`apps/site`, `apps/console-web`, `apps/console-api`, `packages/*`, `lean/`,
`research/`, `refs/`, `results/`).

### 3.1 Principles
1. **One question per agent, ended when answered.** Fewer agents are alive at once (v1 §6.6 point 3).
   - Hard cap, enforced by a lead rule plus the `TeammateIdle` hook: **≤ 3 teammates** and **≤ 4 worktree
     subagents**. `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=6` is a backstop.
2. **Teammate only if the agent must talk to peers over many turns.** Every other role is a subagent, which costs less
   because its result is summarized back (agent-teams "Compare with subagents").
3. **Code-editing roles are named worktree subagents.** The lead calls `Agent(name: "<role>-<topic>",
   subagent_type: "<role>", isolation: "worktree")`.
   - The name makes it addressable by `SendMessage`; `isolation` on the call keeps it a subagent with its own
     worktree.
   - This is CONFIRMED by combining sub-agents "Subagent names" with "Resume subagents". That both work together in
     one call is INFERRED: check it in the first spike.
4. **Gates are code.**
   - The parity diff, tests, `lake build`, `kb lint`, the usage meter and device runs are `pnpm fw …` / `lake`
     commands.
   - Hooks run them (`TaskCompleted`, `TeammateIdle`), not agents. An agent is spawned only to *interpret* a failing
     gate.
5. **Escalate by call, not by default.** When a cheaper role gets stuck, the lead re-runs it with a per-call `model`
   (`opus`) or `effort` (v2.1.292+). Fable needs the user's approval through an `ask` rule (§6).
6. **Small shared context.**
   - Root `CLAUDE.md` stays ≤ 1,500 words (note 06 §6.4).
   - Role knowledge sits in the agent body (≤ 400 words) plus on-demand skills. Agent bodies are loaded only by that
     role; skills only when invoked (costs "Move instructions from CLAUDE.md to skills").

### 3.2 Roster table

`cW` is the per-role `autoCompactWindow`. All models are pinned full IDs:
- `opus` = `claude-opus-5-5`
- `sonnet` = `claude-sonnet-5-5`
- `haiku` = `claude-haiku-5-5`
- `fable` = `claude-fable-5-1`

| Lane | Role (definition) | Instance names | Runs as | Model / effort | cW / maxTurns | Writes | Why this model |
|---|---|---|---|---|---|---|---|
| — | **lead** (main session; no file) | `main` | session | opus / `medium` (raise to `high` with `/effort` on planning days) | project 400000 / — | `main` by `--ff-only` merge; `research/decisions/` | decides, lands, talks to the user. Medium is Opus 5.5's tuned default; `ultrathink` handles one-off deep turns (model-config) |
| Research | **engine-researcher** | `eng-chromium`, `eng-webkit` | **teammate** | opus / `high` | 400000 / 200 | `research/notes/**`, `refs/upstream/excerpts/**`, `packages/cost-model/<engine>/fixtures/**` | deriving the cost maths from cc/viz/Blink and WebCore/RemoteLayerTree source is the hardest reading job. Two teammates cross-check each other's claims (the "competing hypotheses" pattern) |
| Research | **source-locator** | unnamed | subagent (foreground, from eng-*) | sonnet / `low` | 150000 / 40 | nothing | "where is X computed, file:line@sha": mechanical but needs C++ comprehension |
| Research | **ref-librarian** | `lib-<topic>` | subagent | haiku / `low` | 100000 / 60 | `refs/**` only | fetches and pins upstream sources (`pnpm fw src:fetch`), writes reference cards, runs `pnpm kb lint`. 100000 keeps Haiku 5.5 under its >100K-prompt price step (§4) |
| Research | **Explore** (override of the built-in) | unnamed | subagent | haiku / `low` | 100000 / — | nothing | otherwise Explore runs on the lead's Opus (CONFIRMED). Every role's codebase search becomes Haiku |
| Build | **part-builder** | `part-<slug>` | named worktree subagent | sonnet / `medium`; per call `opus` for scroll-driven or hero parts | 200000 / 150 | `apps/site/src/parts/<slug>/**`, the part's flag entry in `packages/parts` | parity diff plus unit tests make done-ness checkable, so Sonnet suffices |
| Build | **console-builder** | `console-<feature>` | named worktree subagent | sonnet / `medium` | 200000 / 150 | `apps/console-web/**`, `apps/console-api/**` (not `src/core`) | ordinary UI and API work behind contract tests |
| Measure | **measure-engineer** | `meas-<plugin>` | named worktree subagent | opus / `high` | 300000 / 200 | `packages/measure-*/**`, `packages/cost-model/src/**`, `packages/stats/**` | measurement code decides A/B comparability for every experiment. In v1 this was the toolsmith on Opus/high for the same reason |
| Proof | **lean-prover** | `lean-<module>` | named worktree subagent | opus / `high`; per call `fable` (ask) for a stuck theorem | 300000 / 300 | `lean/**`, `packages/contracts/fixtures/**` (oracle outputs) | long compile-feedback loops (`lake build`, lean-lsp goals). Correctness is machine-checked, so effort `high` is enough and `max` is not needed |
| Experiment (phase 3+) | **experiment-owner** | `exp-<hypothesis>` | **teammate** | opus / `high`; per call `fable` for long multi-part hypotheses | 400000 / 300 | `results/experiments/<date>-<slug>/**`, flag presets | interprets noisy data against the cost-model prediction and talks to eng-* about the mechanism (v1's fix-owner) |
| Review | **reviewer** | `review-<topic>` | subagent, fresh | opus / `high` (`xhigh` per call for measurement code or for Lean spec fidelity) | 300000 / 80 | nothing (verdict in its reply) | adversarial, fresh context. Checks that the *statement* proved is the claim made, and that the numbers are not cherry-picked |
| — | *(no agent)* parity, tests, lake, kb lint, usage, device runs | — | scripts + hooks | — | — | `results/index/*.jsonl`, console-api DB | v1 L417-420: gates are cheaper and more deterministic as code |

Notes:
- **Teammates alive at once.** Usually `eng-chromium` + `eng-webkit` in the research phase. In the experiment phase,
  up to 3 `exp-*` while the `eng-*` are shut down and brought back by message when needed (agent-teams: "brings it
  back in the same session … restores any conversation").
- **"Teams" in the user's request.** A session has exactly one agent team, so the lanes are groups inside that one
  team, not separate teams. Running a lane as its own Claude session with its own team, linked by cross-session
  messaging, is possible later. It is not recommended at the start: there would be two leads and two permission
  surfaces (INFERRED).
- **The lead's own context is the biggest single cost** (v1 L432-434).
  - The lead spawns for any multi-file read or web lookup (v1 `memory/lead-delegates-research.md`) and keeps one
    line per agent in its context.
  - Recurring checks are scripts (`pnpm fw status`), not `/loop` prompts that re-read the lead's context.

---

## 4. Token-budget rationale (prices and arithmetic)

### 4.1 List prices

Per million tokens (CONFIRMED: platform pricing page, fetched 2026-10-17):

| Model | Input | 5m cache write | 1h cache write | Cache hit | Output |
|---|---|---|---|---|---|
| Fable 5.1 | $10 | $12.50 | $20 | $0.25 (0.025x) | $50 |
| Opus 5.5 | $4 | $5 | $8 | $0.20 (0.05x) | $20 |
| Sonnet 5.5 | $2 | $2.50 | $4 | $0.10 (0.05x) | $10 |
| Haiku 5.5, prompt ≤ 100K | $0.10 | $0.125 | $0.20 | $0.01 | $0.50 |
| Haiku 5.5, prompt > 100K | $0.50 | $0.625 | $1 | $0.05 | $2.50 |

- All four have a 1M context window and 128K max output (models overview).
- The Haiku 5.5 price step counts *all* input tokens of a request, cache reads included (pricing "Long context
  pricing").

### 4.2 What one request costs at context C, warm vs. cold

| Model | C | Warm (cache hit) | Cold (5m expired: rewrite) | Cold / warm |
|---|---|---|---|---|
| Opus 5.5 | 150k | $0.030 | $0.75 | 25x |
| Sonnet 5.5 | 150k | $0.015 | $0.375 | 25x |
| Haiku 5.5 | 80k | $0.0008 | $0.010 | 12.5x |
| Haiku 5.5 | 150k | $0.0075 | $0.094 | 12.5x |
| Fable 5.1 | 150k | $0.0375 | $1.875 | 50x |

Arithmetic: C × price ÷ 10^6. For example, 150,000 × $0.20 / 10^6 = $0.03.

### 4.3 What the numbers imply
1. **Cold wakes are the expensive event.**
   - Subagents and in-process teammates are in the "everything else" cache bucket. They get a **5-minute TTL even on
     a subscription** unless you choose otherwise (CONFIRMED: prompt-caching "Which TTL each request gets"; agent-teams
     "Token usage").
   - A teammate woken every 10-30 minutes pays a full rewrite on every wake.
   - With `subagentPromptCacheTtl: "1h"` it pays a 1.6x-pricier write once, then reads at 0.05x on each wake within
     the hour.
   - INFERRED: this is net cheaper whenever wakes come 5-60 minutes apart, which is the normal rhythm of a team
     waiting on builds and measurements. Verify it with the meter's cacheCreation / cacheRead split per role (§8).
2. **Capping the context caps the per-turn cost linearly.**
   - An Opus teammate at 400k costs $0.08 per warm request, against $0.03 at 150k.
   - `autoCompactWindow` per role (400k researchers, 300k builders of measurement and proofs, 200k Sonnet builders,
     100k Haiku) bounds this.
   - Compaction is itself a large request (costs "Why usage climbs"), so windows are not set lower than about 2x the
     role's working set (INFERRED).
3. **Haiku 5.5's 100K step.**
   - `autoCompactWindow: 100000` (the minimum allowed) keeps most Haiku requests in the cheap tier.
   - Requests near the boundary can cross it before compaction triggers (INFERRED; watch the meter).
   - Even above the step, Haiku is 4x cheaper than Sonnet on cache reads.
4. **Output is where effort bites.**
   - Thinking is billed as output: $20/M on Opus, $10/M on Sonnet.
   - Mechanical roles run at `low`. Implementation roles run at `medium`, the tuned default.
   - `high` is reserved for derivation, proofs, measurement code and review.
   - `max` is not a default for any role (model-config warns of overthinking).
5. **Fable vs Opus.**
   - Cache hits are similar: $0.25 against $0.20.
   - Output costs 2.5x and a cold write 2.5x.
   - Use Fable only where long autonomous work saves *turns*: a stuck Lean proof, or an L-size multi-part hypothesis.
   - It is a per-call opt-in behind an `ask` rule, as in v1 (`AGENT_ROLES.md` L296-299, L331).

### 4.4 Illustrative per-job envelopes

INFERRED. These are for setting expectations, not for budgeting. Cache writes of new tokens are ignored, the turn
counts are guesses, and the meter will replace them.

| Job | Model / effort | Assumption | Estimate |
|---|---|---|---|
| One site part (`part-builder`) | Sonnet / medium | 200 requests × 80k warm + 2k out each | 16 M × $0.10 + 0.4 M × $10 ≈ **$5.60** (Opus ≈ $11.20) |
| One engine topic (`eng-*`) | Opus / high | 400 × 200k + 4k out | 80 M × $0.20 + 1.6 M × $20 ≈ **$48** |
| Lead, one working day | Opus / medium | 2,000 × 300k + 1.5k out | 600 M × $0.20 + 3 M × $20 ≈ **$180** |
| A reference batch (`ref-librarian`) | Haiku / low | 300 × 60k + 1k out | 18 M × $0.01 + 0.3 M × $0.50 ≈ **$0.33** |

The lead row shows why the lead must stay lean: in v1 the lead plus its recurring checks were the largest single
consumer (v1 L432-434).

---

## 5. Display mode, permissions, worktrees, skills, MCP, plugins, output styles

- **Display mode: `in-process`, committed.** It is the only mode in which per-role `effort` and `autoCompactWindow`
  apply (§2.2).
  - The user can still view teammates: arrow keys plus Enter, and Ctrl+T for the task list (agent-teams "Talk to
    teammates directly").
  - Split panes (tmux is installed here; `it2` is not) remain a per-session `claude --teammate-mode tmux` choice for
    demos, at the cost of losing per-role effort.
- **Permission mode is left to the user** (open question §10).
  - Teammates inherit the lead's mode, and every teammate prompt lands in the lead, so allow-lists matter more than
    modes.
  - Under `auto` the classifier reviews tool calls and agent messages (agent-teams "Messages between agents"). That
    adds classifier requests: INFERRED cost, measure before choosing.
  - Prefer `default` mode plus a good allow-list, or `acceptEdits`.
- **Worktrees.**
  - `worktree.baseRef: "head"` is kept from v1: commit before you spawn, because a worktree has only committed files.
  - `symlinkDirectories: [".cache"]` shares the pinned upstream sparse clones (Chromium and WebKit are large) across
    worktrees. INFERRED: verify it does not clash with note 06's `.cache/artifacts` symlink.
  - `node_modules` is **not** symlinked: pnpm per-package links may break (INFERRED). Note 06 §6.3 covers shared
    caches instead.
  - The v1 rule holds: **teammates never call `EnterWorktree`**. The current docs do not mention the team case. v1
    observed it (I-272), so it stays a hard rule. `guard.mjs` denies `EnterWorktree` when `agent_id` is present.
- **Skills (`.claude/skills/<name>/SKILL.md`).** These replace rulebook bulk. Proposed:

  | Skill | For | Notes |
  |---|---|---|
  | `kb-add` | ref-librarian, eng-* | |
  | `part-contract` | part-builder | |
  | `measure-plan` | measure-engineer, exp-* | |
  | `lean-workflow` | lean-prover | |
  | `land` | lead only | `disable-model-invocation: true` |
  | `cost-report` | anyone | |

  - Skill frontmatter supports `model` and `effort`, and `context: fork` with `agent` (CONFIRMED: skills "Frontmatter
    reference").
  - The `skills:` preload in an agent definition works for subagents only, not teammates (§2.2). Teammate bodies
    therefore say "invoke skill X first".
- **MCP (`.mcp.json`, note 06 §2.2).** `serena` (read tools only), `lean-lsp` and `chrome-devtools`.
  - MCP tool definitions are deferred by default (costs "Reduce MCP server overhead"), so they cost little until used.
  - In-process teammates ignore a definition's `mcpServers` (§2.2). Servers must therefore be project-level, and roles
    narrow access through `tools`.
  - Serena supports both `typescript` and `lean4` (CONFIRMED: `oraios/serena` `src/solidlsp/ls_config.py` @ `d9e4c79`
    lines 130 and 172).
  - `oOo0oOo/lean-lsp-mcp` exposes Lean diagnostics, goal states and hover (CONFIRMED: repo metadata via `gh api`,
    pushed 2026-09-30, and its README as mirrored on mcpservers.org). The lean-prover's tools include
    `mcp__lean-lsp`.
- **Plugins: not used in v2 at the start.** Plugin subagents ignore `permissionMode`, `mcpServers` and `hooks`
  (sub-agents frontmatter table), which would weaken guards. Packaging the finished "loop kit" as a plugin is a later
  option (INFERRED).
- **Output styles: none.** An output style does not reach non-fork subagents (sub-agents "What loads at startup"),
  so it buys nothing for the team.
- **Optional saving.** `includeGitInstructions: false` drops the git snapshot that every subagent otherwise gets. In
  v1 that snapshot also misled agents about their branch (v1 `AGENT_ROLES.md` L254-256). The cost is losing the
  built-in commit guidance; the `land` skill and lefthook replace it (INFERRED; open question).
- **Not used: the `memory` field.** `refs/` and `research/` are the single knowledge store (note 06 §4). A second
  per-agent memory directory would fork it.

---

## 6. Draft `.claude/settings.json` (committed)

```jsonc
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    // Default for any spawn without a definition model (e.g. general-purpose helpers): Sonnet, not the lead's Opus.
    "CLAUDE_CODE_SUBAGENT_MODEL": "claude-sonnet-5-5",
    // lead -> worker -> one helper layer; no deeper trees (v1: "keep helpers one level deep").
    "CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "2",
    "CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS": "6",
    "CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION": "300",
    // Shared task list + TaskCompleted gate. UNCERTAIN whether a project-env value is read early enough (docs say
    // "export before you start"); spike, fallback = shell alias `CLAUDE_CODE_ENABLE_TODO_TOOLS=1 claude`.
    "CLAUDE_CODE_ENABLE_TODO_TOOLS": "1"
    // NOT set here on purpose: CLAUDE_CODE_EFFORT_LEVEL (would override every role's effort),
    // CLAUDE_CODE_AUTO_COMPACT_WINDOW (would override every role's window), telemetry vars (ignored in project env).
  },
  "teammateMode": "in-process",
  "subagentPromptCacheTtl": "1h",
  "autoCompactWindow": 400000,
  "worktree": { "baseRef": "head", "symlinkDirectories": [".cache"] },
  "permissions": {
    "allow": [
      "Bash(pnpm fw *)", "Bash(pnpm kb *)", "Bash(pnpm turbo run *)", "Bash(pnpm test*)",
      "Bash(pnpm lint*)", "Bash(pnpm typecheck*)", "Bash(pnpm -F * test*)",
      "Bash(lake build*)", "Bash(lake test*)", "Bash(lake exe *)", "Bash(lake env lean *)",
      "Bash(git status*)", "Bash(git diff*)", "Bash(git log*)", "Bash(git show*)",
      "Bash(git worktree list*)", "Bash(git worktree add .claude/worktrees/*)",
      "Bash(git rebase main)", "Bash(git merge --ff-only *)",
      "Bash(gh api repos/*)", "Bash(gh search code *)", "Bash(rg *)",
      "WebFetch(domain:code.claude.com)", "WebFetch(domain:platform.claude.com)",
      "WebFetch(domain:chromium.googlesource.com)", "WebFetch(domain:source.chromium.org)",
      "WebFetch(domain:webkit.org)", "WebFetch(domain:lean-lang.org)",
      "WebFetch(domain:mui.com)", "WebFetch(domain:ui.shadcn.com)",
      "mcp__serena__initial_instructions", "mcp__serena__get_symbols_overview", "mcp__serena__find_symbol",
      "mcp__serena__find_referencing_symbols", "mcp__serena__find_declaration",
      "mcp__serena__find_implementations", "mcp__serena__get_diagnostics_for_file",
      "mcp__lean-lsp"
    ],
    "ask": [
      // Fable only with the user's consent (per-call opt-in, as in v1). Matches literal call params only.
      "Agent(model:fable)", "Agent(model:claude-fable-5-1)",
      "Edit(/.claude/**)", "Write(/.claude/**)", "Edit(/CLAUDE.md)",
      "Edit(/packages/measure-*/src/**)"   // measurement code: user sees each change (v1 ioscap pattern)
    ],
    "deny": [
      "Bash(git push*)", "Bash(git -C * push*)", "Bash(git commit*--no-verify*)", "Bash(git commit* -n *)",
      "Bash(git -c core.hooksPath*)", "Bash(git add -f *)", "Bash(git add --force *)",
      "Bash(gh api * -X *)", "Bash(gh api * --method *)", "Bash(gh pr *)", "Bash(gh repo create *)",
      "Bash(gh gist *)",
      "Edit(/snapshot/**)", "Write(/snapshot/**)",           // Fastwork original: local, read-only, never committed
      "Edit(/.cache/upstream/**)", "Write(/.cache/upstream/**)",
      // Timing traces go through the locked runner (`pnpm fw run`), never ad hoc (v1 deny list).
      "mcp__chrome-devtools__performance_start_trace", "mcp__chrome-devtools__performance_stop_trace",
      "mcp__serena__replace_symbol_body", "mcp__serena__insert_after_symbol", "mcp__serena__insert_before_symbol",
      "mcp__serena__replace_content", "mcp__serena__replace_in_files", "mcp__serena__rename_symbol",
      "mcp__serena__safe_delete_symbol", "mcp__serena__write_memory", "mcp__serena__edit_memory",
      "mcp__serena__delete_memory"
    ]
  },
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "node",
      "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/session-brief.mjs"], "timeout": 10 }] }],
    "PreToolUse": [{ "matcher": "Bash|Edit|Write|WebFetch|EnterWorktree|Agent", "hooks": [{ "type": "command",
      "command": "node", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/guard.mjs"], "timeout": 10 }] }],
    "SubagentStart": [{ "hooks": [{ "type": "command", "command": "node",
      "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/role-brief.mjs"], "timeout": 10 }] }],
    "SubagentStop": [{ "hooks": [{ "type": "command", "command": "node",
      "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/usage-record.mjs"], "async": true, "timeout": 30 }] }],
    "TeammateIdle": [{ "hooks": [{ "type": "command", "command": "node",
      "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/teammate-idle.mjs"], "timeout": 60 }] }],
    "TaskCompleted": [{ "hooks": [{ "type": "command", "command": "node",
      "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/task-gate.mjs"], "timeout": 600 }] }]
  }
}
```

The real file must be plain JSON: strip the comments.

**Uncommitted `.claude/settings.local.json`:**
- Read access to the v1 repo for agents: `"permissions": {"additionalDirectories": ["~/source/fastwork-com-web-optimize"]}`.
- A deny on `Edit(~/source/fastwork-com-web-optimize/**)` and `Write(~/source/fastwork-com-web-optimize/**)`, so v1
  stays read-only.
- These are machine-specific paths, so they stay out of the committed file.
- INFERRED: confirm that `additionalDirectories` accepts `~/`.

### 6.1 Hook scripts (each a small pure-core module with unit tests, per note 06's testability goal)

| Script | Event | What it does | Blocks? |
|---|---|---|---|
| `guard.mjs` | PreToolUse | Maps `agent_type` to the role's write globs (§3.2) and refuses writes outside them (exit 2 + reason). Refuses `EnterWorktree` when `agent_id` is set, i.e. inside a teammate or subagent (v1 I-272). Refuses `Agent` calls once the alive-teammates count ≥ 3, read from `~/.claude/teams/<team>/config.json`, which the docs say teammates may read. Refuses Bash that runs a Fastwork-copying command into the repo (port of v1 `git-guard.mjs`) | yes |
| `role-brief.mjs` | SubagentStart | Returns `additionalContext`: the peer directory (live names from the team config), the role's budget (maxTurns, cW) and the one-line lane rules. It is injected once per agent, so the cache is kept (CONFIRMED hooks) | no |
| `usage-record.mjs` | SubagentStop (async) | Sums `message.usage` from `agent_transcript_path` (dedupe by `message.id`, as in v1 `usage.mjs`), prices it with the table in §4, and appends `{agent_id, agent_type, name, model, effort, in, out, cacheRead, cacheWrite, usd}` to `<git-common-dir>/fw/usage/usage.jsonl` and to console-api `POST /usage` | no |
| `teammate-idle.mjs` | TeammateIdle | (a) Same usage record, keyed by `teammate_name`. (b) Gate: if the teammate's worktree has uncommitted changes in its lanes, exit 2 "commit or hand back first". (c) If it has no open task and no assignment in console-api, return `{"continue": false, "stopReason": "parked: no work"}`, the v1 "no work, no listener" rule; a later message brings it back | yes / stop |
| `task-gate.mjs` | TaskCompleted | Runs `pnpm fw gate --task <id>` for the task's worktree: affected tests, plus parity for parts, `lake build` for `lean/`, `kb lint` for `refs/`. Exit 2 with the first failing lines | yes |
| `session-brief.mjs` | SessionStart | Prints the roster, today's spend by role from `usage.jsonl`, and open tasks from console-api: ≤ 15 lines | no |

---

## 7. Example agent definitions (drafts)

### 7.1 `.claude/agents/engine-researcher.md`

```markdown
---
name: engine-researcher
description: Derives the rendering-cost mathematics for one question from Chromium (Blink, cc, viz) or WebKit (WebCore rendering, RemoteLayerTree, CoreAnimation glue) source and specs. Writes a cited research note and test vectors for packages/cost-model. Spawn as a named teammate per engine (eng-chromium, eng-webkit) so the two cross-check each other. Read-heavy; never measures; never edits app code.
model: claude-opus-5-5
effort: high
maxTurns: 200
autoCompactWindow: 400000
color: purple
tools: Read, Grep, Glob, Bash, Write, Edit, WebFetch, WebSearch, Agent, SendMessage, Skill, mcp__serena__get_symbols_overview, mcp__serena__find_symbol, mcp__serena__find_referencing_symbols, mcp__serena__find_declaration
---

You research how one rendering engine turns a web page's scroll animation into frame cost, for a
study that optimizes a React rewrite of a public homepage. First invoke the `kb-add` skill.

Scope: the question in your spawn prompt, for your engine only. Your peer researches the other engine:
message it when a claim is cross-engine or when you disagree with its note.

Method:
1. Pin sources with `pnpm fw src:fetch <repo> <paths>`; read only under `.cache/upstream/<repo>@<sha7>/`.
   For "where is X computed" lookups spawn a `source-locator` subagent (Sonnet) or use Explore (Haiku);
   do not grep the whole tree yourself.
2. Every claim gets file:line@sha or a spec/bug URL and CONFIRMED or INFERRED. Excerpts go in
   `refs/upstream/excerpts/<repo>/<path>@<sha7>#L<a>-L<b>.md`, at most 40 lines each, with the license noted.
3. Turn the mechanism into a formula with units and the conditions under which it holds (e.g. tile size,
   layer promotion, raster budget). Write 3 or more test vectors to
   `packages/cost-model/<engine>/fixtures/<topic>.json`, each with the source line that justifies it.
4. Note what a measurement must show to refute the formula (the measure lane runs it, not you).

Write only `research/notes/**`, `refs/upstream/excerpts/**` and the fixtures path above (enforced by a hook).
You are a teammate: never call EnterWorktree. Never copy Fastwork code or assets; cite `snapshot/` paths only.
Final message to the lead: the note path, the formula, the fixtures, open questions. 10 lines or fewer.
```

### 7.2 `.claude/agents/part-builder.md`

```markdown
---
name: part-builder
description: Rebuilds one homepage part as a React + MUI component that is visually identical to the original, behind a feature flag in packages/parts, with a harness route, unit tests, and a passing parity gate. Spawn as a named worktree subagent (name part-<slug>, isolation worktree on the call). One part per agent.
model: claude-sonnet-5-5
effort: medium
maxTurns: 150
autoCompactWindow: 200000
isolation: worktree
color: blue
skills:
  - part-contract
tools: Read, Grep, Glob, Edit, Write, Bash, SendMessage, mcp__serena__get_symbols_overview, mcp__serena__find_symbol, mcp__serena__find_referencing_symbols, mcp__serena__get_diagnostics_for_file
---

You rebuild exactly one part of the homepage (named in your prompt) in `apps/site/src/parts/<slug>/`.
The preloaded `part-contract` skill defines the part interface, the flag registration and the harness
route; follow it.

Rules:
- Look at the original only through `pnpm fw snapshot show <part>` (screenshots, computed styles,
  DOM outline). Never copy its code, class names, CSS or assets into the repo: write it fresh with MUI.
- Each motion variant the original has becomes a flag value (e.g. `hero.motion = original | css-sdt | none`)
  so measurements can pick it.
- Done when `pnpm fw gate --part <slug>` passes (typecheck, unit tests, parity diff within the
  part's tolerance). Run it yourself; when it fails twice on the same diff, stop and report the diff
  path instead of guessing.
- Touch only your part's directory and its one registry entry in `packages/parts`.
- Commit on your worktree branch with message `part(<slug>): …`; the lead lands it.

Final report: branch, gate result, flag values added, known gaps. 8 lines or fewer.
```

When a part is hard (scroll-driven hero, sticky stacks), the lead re-spawns it with `model: "opus"` and/or
`effort: "high"` on the call. No second definition is needed (per-invocation `effort` exists since v2.1.292,
CONFIRMED).

### 7.3 `.claude/agents/ref-librarian.md`

```markdown
---
name: ref-librarian
description: Mechanical reference work - pins an upstream repo path, writes a refs/external or refs/upstream card with frontmatter, regenerates the index, fixes kb lint errors. Cheap and fast; returns paths only.
model: claude-haiku-5-5
effort: low
maxTurns: 60
autoCompactWindow: 100000
omitClaudeMd: true
color: cyan
tools: Read, Grep, Glob, Write, Edit, Bash, WebFetch
---

You maintain the reference store of this repo. Everything you need is here and in your prompt.

Hard rules (restated because you start without CLAUDE.md):
1. Never copy code, text or assets from the Fastwork site or from `snapshot/` into the repo.
2. Never edit outside `refs/**` and `research/INDEX.md`.
3. No personal data: no e-mails, LAN IPs, device ids, home paths.
4. Upstream excerpts are 40 lines or fewer, with a permalink and the license.

Steps: `pnpm fw src:fetch` to pin; write the card from `refs/_template/<kind>.md`; `pnpm kb lint`;
`pnpm kb index`. Report the created paths and the lint result, one line each.
```

### 7.4 `.claude/agents/Explore.md` (cheap search for everyone)

```markdown
---
name: Explore
description: Fast read-only codebase and reference search. Returns file:line answers.
model: claude-haiku-5-5
effort: low
autoCompactWindow: 100000
tools: Read, Grep, Glob, Bash
---
Answer the search question with 1-based file:line references and one line each. Read only; change nothing.
```

The remaining definitions follow the roster table, each with a body of ≤ 400 words:
- `source-locator`;
- `console-builder`;
- `measure-engineer`;
- `lean-prover`, which adds `mcp__lean-lsp` to `tools`;
- `experiment-owner`;
- `reviewer`, with `tools: Read, Grep, Glob, Bash` only and no `Agent`, so it stays a leaf.

---

## 8. Measuring token usage per role (so the loop reports it)

| Method | What you get | Setup | Status |
|---|---|---|---|
| **`/usage`** | Session block: tokens and $ per model at list price. Plan breakdown attributes recent usage to subagents, skills and MCP; flags long context and cache misses over 10 %; `d`/`w` toggles 24 h / 7 d. `Prompt cache (main)` line, main conversation only | none | CONFIRMED (costs "Using the /usage command") |
| **`/tasks`** | Each running subagent's model and effort | none | CONFIRMED (sub-agents "Choose a model") |
| **Local transcript meter `pnpm fw usage`** | Per agent, per role (name prefix), per model: input, output, cacheRead, cacheWrite, $ at list price, cold-wake count (requests whose cacheWrite > 50 % of prompt) | Port v1 `research/management/tools/usage.mjs`: reads `~/.claude/projects/<proj>/<session>.jsonl` and `<session>/subagents/**/agent-*.jsonl` (CONFIRMED path); names from `agent-*.meta.json` (OBSERVED in v1, INFERRED still true); dedupe by `message.id`. Pure pricing function plus tests in `packages/cost-model` or a small `packages/usage` | works offline, no settings; the recommended primary |
| **Hooks** | A cost card per finished subagent (`SubagentStop` + `agent_transcript_path`) and per idle teammate (`TeammateIdle` + `teammate_name`/`agent_id`), pushed to console-api | §6.1 | CONFIRMED inputs; mapping teammate transcripts to `agent_id` INFERRED |
| **OpenTelemetry** | `claude_code.token.usage` (type `input/output/cacheRead/cacheCreation`) and `claude_code.cost.usage`, with `model`, `effort`, `query_source` (`main/subagent/auxiliary`) and `agent.name`. Event `claude_code.api_request`: per-request tokens, `cost_usd`, `duration_ms`. Traces add `agent_id` / `parent_agent_id` | **User** settings or shell: `CLAUDE_CODE_ENABLE_TELEMETRY=1`, `OTEL_METRICS_EXPORTER=otlp`, `OTEL_LOGS_EXPORTER=otlp`, `OTEL_EXPORTER_OTLP_PROTOCOL=http/json`, `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:<console-api port>`, `OTEL_LOG_TOOL_DETAILS=1` (otherwise custom agent names show as `"custom"`). Console-api implements `/v1/metrics` + `/v1/logs` (OTLP/HTTP JSON) into SQLite | CONFIRMED attributes (monitoring-usage "Cost counter", "Token counter", "API request event"). `agent.name` is the definition *type*, not the instance; that it is set for teammates is INFERRED |

**What the loop reports, every experiment card and every daily summary (INFERRED design):**
- `tokens_by_role`: role → {model, effort, requests, in, out, cacheRead, cacheWrite, usd, coldWakes, maxContext}.
- `share`: lead vs. teammates vs. subagents. v1 had 81 % from subagents.
- `cacheReadShare` and `coldWakeShare`: these test the `1h` TTL and `autoCompactWindow` choices against v1's 96 %
  cache-read baseline.
- **Dollar figures are list-price estimates, not a bill.** On a subscription the plan's own weighting is not public,
  as v1 also noted (`loop-distillation` L274-275).

**Exit metric for the cost design (proposal):**
- Opus share of $ ≤ 70 %. It was ~97 % in v1.
- Lead share ≤ 25 %.
- Cold-wake share of cacheWrite tokens trending down after the switch to `1h`.
- Review these at each daily check-in. If a role's tokens per accepted deliverable rise for two days, the lead changes
  its model, effort or window and records the change in `research/decisions/`.

---

## 9. Risks

1. **The feature is experimental.** Limits and fields have changed in every month of v1. Pin the Claude Code version
   in `research/decisions/` and re-verify this note's field list on upgrade; `claude --debug` flags unknown fields.
2. **Task tools might not turn on from project env.** Without them there is no shared task list and no
   `TaskCompleted` on `TaskUpdate`. The fallback is a shell alias, or console-api as the task board (v1 used its own
   store for the same reason: `AGENT_ROLES.md` L199-205).
3. **A named worktree subagent may behave differently than expected.** If `name` + `isolation` on the call does not
   give an addressable subagent, the fallback is v1's pattern: the lead creates the worktree, spawns a teammate, and
   the teammate works by absolute paths.
4. **Haiku quality.** If the librarian's or Explore's answers need rework more than about 1 time in 5, move them to
   Sonnet `low`. The meter shows the true cost of rework.
5. **Over-tight `autoCompactWindow`.** Frequent compaction loses detail and each compaction is a large request. Watch
   the `compact_boundary` count per role in the transcripts (CONFIRMED event shape in sub-agents "Auto-compaction").
6. **`ask` rules in a team.** Teammate permission prompts surface in the lead, so Fable spawns and measurement-code
   edits will interrupt the user. That is intended, but it can stall a teammate until the user answers.
7. **`guard.mjs` relies on `agent_type` being present for teammates.** It is documented for subagents. For teammates
   only `agent_id` is documented, so it needs a spike. The fallback maps `agent_id` to the role via the team config.

---

## 10. Open questions for the user

1. Permission mode for the lead (and so all teammates): `default` with the allow-list, `acceptEdits`, or `auto`?
   `auto` adds classifier requests.
2. Lead effort: keep Opus 5.5 `medium` as the default and use `/effort high` on planning days? Or run `high` all the
   time? `high` gives more verification but more output tokens on every lead turn.
3. Fable: allowed at all, and on what budget? On a subscription it may bill usage credits with a consent prompt.
4. Is a project-wide `autoCompactWindow` of 400000 acceptable for the lead? Or do you prefer 1M with fewer
   compactions and a higher per-turn cost?
5. Enable OpenTelemetry in your user settings and point it at the local console-api, or rely only on the local
   transcript meter?
6. Teammates visible in-process (per-role effort works) vs. tmux split panes (everyone visible, but split-pane
   teammates lose per-role effort and context caps)?
7. Turn on `CLAUDE_CODE_ENABLE_TODO_TOOLS` for a shared task list? Its tool definitions and reminders cost context on
   every agent, and the docs say newer models track work without it.
8. Drop the git status snapshot from every agent (`includeGitInstructions: false`) and rely on the `land` skill plus
   lefthook?

---

## Sources

Claude Code docs, fetched 2026-10-17 as Markdown:
- Agent teams: https://code.claude.com/docs/en/agent-teams (enable; display modes; model order; definition parts
  applied to teammates; permissions; token usage; limitations)
- Subagents: https://code.claude.com/docs/en/sub-agents (frontmatter reference; choose a model / effort; available
  tools; permission modes; nesting depth; concurrency; what loads at startup; resume; auto-compaction; names)
- Model config: https://code.claude.com/docs/en/model-config (aliases; Fable and usage credits; effort levels and
  defaults; Haiku 5.5 context and pricing; auto-compact)
- Costs: https://code.claude.com/docs/en/costs (`/usage`; agent team token costs; reduce token usage; why usage
  climbs)
- Monitoring: https://code.claude.com/docs/en/monitoring-usage (metrics, attributes, `api_request`,
  `subagent_completed`)
- Hooks: https://code.claude.com/docs/en/hooks (TeammateIdle, TaskCreated, TaskCompleted, SubagentStart,
  SubagentStop, common input, exec form)
- Settings reference: https://code.claude.com/docs/en/settings-reference (`env` handling and ignored variables,
  `teammateMode`, `subagentPromptCacheTtl`, `worktree.*`, `autoCompactWindow`, `effortLevel`, `modelSettings`,
  `includeGitInstructions`, `enabledPlugins`, `outputStyle`)
- Env vars: https://code.claude.com/docs/en/env-vars
- Permissions: https://code.claude.com/docs/en/permissions (path syntax, Agent parameter rules, trust)
- Tools reference: https://code.claude.com/docs/en/tools-reference ("Task tool availability")
- Prompt caching: https://code.claude.com/docs/en/prompt-caching (TTL buckets, subagents and the cache)
- Worktrees: https://code.claude.com/docs/en/worktrees ("Isolate subagents with worktrees", `.worktreeinclude`)
- Skills: https://code.claude.com/docs/en/skills (frontmatter reference)

Claude platform docs:
- Pricing: https://platform.claude.com/docs/en/about-claude/pricing (model prices, cache multipliers, Haiku 5.5
  >100K tier)
- Models overview: https://platform.claude.com/docs/en/about-claude/models/overview (context windows, positioning)

Tools:
- Serena language list: https://github.com/oraios/serena/blob/d9e4c796fae0207ba6848d1df4b331122a5567b5/src/solidlsp/ls_config.py
  (L130 `TYPESCRIPT`, L172 `LEAN4`)
- lean-lsp-mcp: https://github.com/oOo0oOo/lean-lsp-mcp (repo metadata via `gh api`); README mirror at
  https://mcpservers.org/en/servers/oOo0oOo/lean-lsp-mcp

v1 repo (read-only, commit `eae1bb99`, 2026-10-14), path `../fastwork-com-web-optimize`:
- `.claude/settings.json`; `.claude/agents/{bundle-mapper,fix-owner,fix-reviewer,toolsmith,wave-integrator}.md`
- `fixes/AGENT_ROLES.md` L7-17 (roster), L187-205 (why the lead coordinates; task store), L207-305 (spawning
  mechanics as of v2.1.286), L317-339 (model and effort per task)
- `research/loop-distillation/README.md` L240-275 (cost), L335-348 (rulebook cost), L400-437 (orchestration and cost
  discipline), L445-465 (what to do differently)
- `memory/agent-teams-not-workflows.md`, `memory/agent-spawn-names.md`, `memory/lead-delegates-research.md`,
  `memory/lead-delegates-areas-measures.md`, `memory/usage-meter-every-30-min.md`
- `research/management/tools/usage.mjs` (header: transcript sources, dedupe, weighting)

Sibling note: `research/kickoff/06-architecture-and-tooling.md` (layout §2.2, knowledge store §4, worktrees §6.3,
rulebook §6.4).
