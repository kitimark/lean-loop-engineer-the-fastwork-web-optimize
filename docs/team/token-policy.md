# Token policy: helpers and context hygiene

The rules agents follow. Evidence and decisions: `research/notes/2026/10-18-token-policy-rationale.md`. Writing
rules: `.claude/skills/no-slop/SKILL.md`, `.claude/agents/comment-sicko.md`. Shared prompt rules:
`docs/team/tools/prompt-rules.md`. Gate: `node scripts/context-lint.mjs` (`docs/team/tools/context-lint.md`).
About 4 chars per token (INFERRED).

## When to delegate

| Situation | Do |
|---|---|
| Output < 2k tokens (~8 KB, ~100 lines) | inline, filtered |
| Search/read sweep over > 3 files or > 8 KB, answer ≤ 1k tokens of facts, done in < 4 min | `scout` |
| Sweep over > 100k tokens | split over several scouts, else one `scout` |
| One build/test run | inline: log to a file, then `grep`/`tail` |
| Several runs, or a diagnosis over many log lines | `runner` |
| Waiting > 1 min | one bounded foreground wait (blocking command with timeout, or Monitor with an until-condition); never a sleep-poll loop; a wait longer than your cache TTL ends with a handoff note |
| Waiting for CI | `pnpm fw ci wait <runId>` (or `--branch ci/<x>`) in the background; never `gh run watch` or a gh loop (`docs/team/tools/fw-ci.md`) |
| Verbatim text you will edit | inline `Read` with offset/limit; never delegate |
| Checklist judgement over > 20 KB (failure diagnosis, number cross-check, diff hunk) | `checker`; adversarial math, number or privacy review stays with Opus reviewers |
| Prose of a diff or file set against `no-slop` | `slop-checker` |
| Code comments of a diff or file set | build-review Polish; lead: `fw polish --staged` (`tools/polish.md`) |
| Mechanical edits to many named files | lead spawns `patcher` at depth 1 with absolute paths; nobody touches those files until it returns |
| Same-model helper | only if the task passes ~10k tokens and no cheaper tier can do it |

## Helpers

| Helper | Model / effort | Spawned by | Does | Tools |
|---|---|---|---|---|
| `scout` | haiku / low | lead or a role with `Agent` | grep, find, read-and-extract, git log/show, `gh search code`, `.cache/upstream` lookups | Read, Grep, Glob, Bash, Serena symbols |
| `runner` | haiku / low | lead or a role with `Agent` | one named build/test/measure command, logged to the given scratchpad path; returns exit code and first errors | Bash, Read, Grep, Glob |
| `checker` | sonnet / medium | lead or a role with `Agent` | one checklist question over a log, hunk or file set | Read, Grep, Glob, Bash |
| `slop-checker` | sonnet / medium | lead or a role with `Agent` | review prose against `no-slop`; returns file:line and the cut | Read, Grep, Glob, Bash |
| `comment-sicko` | sonnet / medium | lead or build-review, unnamed | delete comments that fail its keep list, flag `MUST KILL` code | Read, Grep, Glob, Bash, Edit |
| `patcher` | sonnet / low | lead only (depth 1) | edits exactly specified in the prompt, on absolute paths | Read, Edit, Grep, Glob (no Bash) |

All helpers but `patcher` and `comment-sicko` (comments only) are read-only. Lean `Fw.Ops.SpawnGuard` decides every
spawn (`every_role_spawnable`, `helpers_from_lead`, `helpers_nested`, `patcher_nested_refused`); the hook is
`apps/runner/hooks/spawn-guard.mjs`.

## Nested spawning

- Roles with `Agent`: lean-prover, researcher, measure-engineer, console-builder, plan-editor (part-builder later). Reviewer,
  math-reviewer, page-writer, env-ops and all helpers have none.
- A role may spawn only `scout`, `runner`, `checker`, `slop-checker`; `patcher` and `comment-sicko` are depth 1 only.
- A role passes `subagent_type` only, never `model` or `isolation`; the lead may pass `model`/`effort` per call.
- Depth stays 2 (lead, role, helper); helpers cannot spawn.
- Session cap 10, shared across depths; the over-limit error says "Do not retry". Each parent runs ≤ 1 helper at a time,
  ≤ 2 only when told so and while the lead has ≤ 3 direct agents. The lead runs ≤ 5 direct agents when they use helpers.
  RAM (16 GB) also limits parallel builds.
- Delegate only work a helper finishes in < 4 min, unless you have other work meanwhile; never sleep-poll for a helper.
- Helper return ≤ 1,000 tokens: line 1 the answer or `pass`/`fail`; then `path:line - fact` bullets with a status; then
  `Not checked:`. Longer output goes to a scratchpad file and only its path is returned.
- Helpers never commit, never message the lead and write no handoff; the final message is the return value.
- Helper prompt ≤ 15 lines: question, paths, output format, size cap. Helpers skip CLAUDE.md, so the prompt repeats the
  rules they need (`docs/team/tools/prompt-rules.md`).

## Context hygiene

- Never print > ~150 lines: `grep -n`, `head`, `tail -40`, `wc -l` first; quiet flags.
- Long output: `cmd > "$LOG" 2>&1; echo "exit=$?"; grep -nE 'error' "$LOG" | head -40`.
- Analysis scripts write their table to a file and print ≤ 30 lines.
- Read: locate with `grep -n`, then `Read` with offset/limit ≤ 150 lines; a whole file only to edit it.
- Do not re-read an unchanged file; list read files in the handoff. Prefer Serena `find_symbol` over whole source files.
- Handoff by size: after ~45 tool rounds (~150k context), at the next milestone write the handoff and finish.
- Handoff by idle: idle longer than the agent's TTL with context > 30k means `TaskStop` and a fresh agent; never resume > 250k.
- Cache TTL 5m for helpers and fresh reviewers.

## Lead

- Delegate fact lookups in notes and the plan (`scout`), profiler runs (`runner`), diff review (`reviewer` or `checker`),
  several runs (`runner`/`checker`), repo-wide searches (`scout`).
- Inline: notes the lead must judge, `git status/log/diff --stat`, commits and `fw land`, one build/test run, small edits to
  CLAUDE.md and role files, reports and handoffs.
- Spawn named roles, never general-purpose; pass `model: sonnet` for a mechanical task given to an Opus role; respawn rather
  than resume idle agents.
