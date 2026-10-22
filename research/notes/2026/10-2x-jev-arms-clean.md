---
id: 2026-10-22-jev-arms-clean
kind: note
title: "Clean Haiku and Sonnet arms for the Jev comparison: the isolated re-run keeps the first run's verdict"
status: review
created: 2026-10-22
topics: [jev, oracle, claude-p, isolation, haiku, sonnet, evaluation]
---

# Clean Haiku and Sonnet arms for the Jev comparison

**Answer.** Re-run with one isolated `claude -p` call per row, the Haiku and Sonnet arms keep the first run's verdict
(MEASURED, `results/jev-arms-clean/table.md`):

- D1 (incident class, 116 rows): Sonnet leads with 75 right (64.7 %); Jev has 65 (56.0 %) and Haiku 64 (55.2 %).
- D2 (finding severity): Sonnet 44 of 89 (49.4 %), Jev 40 of 83 (48.2 %) and Haiku 43 of 90 (47.8 %) are level.
- Lean certifies no option for any arm on either set, as in the first run.

The clean calls saw no tool, MCP server, CLAUDE.md or memory; the probe passed for both models (MEASURED,
`results/jev-arms-clean/probe.json`). Per arm, accuracy moved 2.5 to 6.1 points between runs: down on D1, up on
D2. One run per row cannot tell whether the context removal or sampling variance moved it. Between the runs,
14 to 36 choices changed per arm and set.

## How the calls were isolated

Each row is one call, `claude -p --model <haiku|sonnet> --tools "" --system-prompt <ARM_PREAMBLE> --setting-sources ""
--strict-mcp-config --no-session-persistence --output-format json`, prompt on stdin (`claudeArgs`,
`scripts/jev-arms-clean.mjs:13@8cbc0616`, CONFIRMED). The cwd is a fresh `mkdtemp` dir under the session scratchpad,
never the repo (`callClaude`, `:89`). The child environment keeps only `ENV_KEEP` (`:20`): HOME, PATH, USER, LOGNAME,
SHELL, TMPDIR, LANG, LC_ALL, TERM. That drops the parent's `CLAUDECODE` and `CLAUDE_*` variables. The prompts come
from `pnpm fw oracle arm-input`; they are byte-identical (`cmp`) to the first run's prompt files (MEASURED).
Concurrency was 4, with up to 2 retries per failed call; no call failed.

`--system-prompt` is the closest Claude Code offers to "no system prompt": the harness still prepends its own blocks
(accepted limit, listed below). `ARM_PREAMBLE` (`apps/runner/src/oracle-score.ts:49@8cbc0616`) therefore appears
twice, as the system prompt and at the start of the user prompt.

## Probe verdict: PASS for both models (MEASURED)

`node scripts/jev-arms-clean.mjs probe` makes four calls per model, and `probeVerdict` (`:210`) fails on any one leak.

| check | haiku | sonnet | pass rule |
|---|---|---|---|
| init event tools / MCP servers | [] / [] | [] / [] | both empty |
| minimal call prompt tokens | 629 | 608 | at most 1000 (`HARNESS_MAX`, `:184`) |
| arm row call prompt tokens | 1898 | 1876 | at most minimal + 1563 (row bytes / 2.5 + 40) |
| introspection turns | 1 | 1 | 1, no permission denial |
| introspection lists tools / files | NONE / CANNOT | NONE / CANNOT | both words present |
| leak markers in the quoted text | none | none | none of 12 (CLAUDE.md, MEMORY.md, fwcore, ...) |

The 1000-token cap sits below the smallest file the probe must keep out. CLAUDE.md is 6402 bytes, about 1600 tokens
at 4 bytes per token. MEMORY.md is 8520 bytes, about 2100 tokens (INFERRED from byte counts). The introspection call
asks the model to quote every text it received. Both models quote exactly three harness blocks besides the question
(MEASURED, redacted text in `probe.json`):

1. The line "You are a Claude agent, built on Anthropic's Claude Agent SDK." in front of our system prompt.
2. An "# Environment" block: the scratch cwd path (it holds the project directory's name), platform, model id,
   date and the harness's downloaded-files rule.
3. A `<system-reminder>` with the account's email address as user context.

Sonnet once refused to quote its context, so the probe retries the introspection up to 3 times and keeps the refused
texts. The init event still lists 55 slash commands, 19 skills, 5 agents and 3 built-in plugins. With no tool, the
model cannot call any of them (MEASURED: `tools` is empty and the introspection took one turn).

Resolved model ids: `claude-haiku-5-5` and `claude-sonnet-5-5` (MEASURED, `modelUsage` of every call).

## First run and clean run, per arm (MEASURED)

Scores come from `pnpm fw oracle score` (Lean `oracle.score`) on the same labels and held-out split. The first-run
copies are in `results/jev-arms-clean/first-run/`; Jev is re-scored from its recorded answer log, with no sends.

| set | arm | run | right / rows | accuracy | held-out | held-out accuracy | certify |
|---|---|---|---|---|---|---|---|
| d1 | jev | recorded | 65 / 116 | 56.0 % | 18 / 33 | 54.5 % | none |
| d1 | haiku | first | 69 / 116 | 59.5 % | 20 / 33 | 60.6 % | none |
| d1 | haiku | clean | 64 / 116 | 55.2 % | 17 / 33 | 51.5 % | none |
| d1 | sonnet | first | 78 / 116 | 67.2 % | 19 / 33 | 57.6 % | none |
| d1 | sonnet | clean | 75 / 116 | 64.7 % | 20 / 33 | 60.6 % | none |
| d2 | jev | recorded | 40 / 83 | 48.2 % | 34 / 73 | 46.6 % | none |
| d2 | haiku | first | 38 / 90 | 42.2 % | 32 / 75 | 42.7 % | none |
| d2 | haiku | clean | 43 / 90 | 47.8 % | 36 / 75 | 48.0 % | none |
| d2 | sonnet | first | 39 / 90 | 43.3 % | 34 / 75 | 45.3 % | none |
| d2 | sonnet | clean | 44 / 89 | 49.4 % | 39 / 74 | 52.7 % | none |

Choices that differ from the first run's, per row (MEASURED, last column of `table.md`): Haiku 36 of 116 on D1 and 14
of 90 on D2; Sonnet 31 of 116 and, on D2, 17 of 89 answered rows plus 1 unparsed row. The Jev rows' invalid column in `table.md` shows '-'; the recorded run had 10 invalid Jev replies on D1 and 0 on D2 (first run `summary.json`). One D1 row names its answer in its text (incident
`inc-orphan-wait-loop`, label `c-orphan-wait`). Both models picked that label in both runs, so that row cannot show
a context effect either way.

At 116 rows the standard error of an accuracy near 60 % is about 4.5 points; at 90 rows near 48 % it is about 5.3
points (INFERRED, binomial). Every between-run change above lies within 1.3 standard errors. Sonnet's 10-row lead
over Jev on D1 is about 2 standard errors of one arm; a paired test per row was not run.

Lean's `oracle.validate` (read through `invalidOf`, `:303`) rejects some probability vectors. These answers are
scored by their choice but cannot be certified:

| set | arm | first run | clean run |
|---|---|---|---|
| d1 | haiku | 15 sums off | 78 sums off, 1 key set differs |
| d1 | sonnet | 76 key sets differ, 10 sums off, 1 pick not the argmax | 16 sums off, 13 key sets differ |
| d2 | both | 0 | 0 |

Jev had 10 invalid replies on D1 and 0 on D2 (`10-2x-jev-replay.md`, D1 and D2 sections). One clean Sonnet D2 reply put prose
before its JSON object. `answerOf` (`:56`) follows the arm protocol in `10-2x-jev-replay.md` step 3 and keeps only
bare JSON, one fenced block or a bare option name, so that row is missing.

## Cost and wall time (MEASURED)

| arm | calls | prompt tokens | output tokens | $ estimate (Claude Code) | wall time, D1 + D2 | median / max call |
|---|---|---|---|---|---|---|
| haiku clean | 206 | 379,173 | 88,493 | 0.12 | 140 s + 105 s | 2.8 s / 7.0 s (D1) |
| sonnet clean | 206 | 374,866 | 61,138 | 2.10 | 157 s + 108 s | 3.6 s / 7.6 s (D1) |
| haiku first | 63 agent turns | about 2.9 M (cache) | 93,750 | not recorded | 102 s | - |
| sonnet first | 67 agent turns | about 3.1 M (cache) | 36,202 | not recorded | 89 s | - |

The dollar column is Claude Code's `total_cost_usd`, summed per call; the real cost is the user's plan quota
(accepted limit). A clean call carries about 1.8 k prompt tokens per row. The first run carried about 14 k to 15 k per
row, since its 42 agents read the Claude Code system prompt, CLAUDE.md and MEMORY.md (first-run token sums from the
workflow's usage log, MEASURED). The first run was faster in wall time because it ran 21 agents per model at once;
the clean run ran 4 calls at a time.

## Limits

- Harness blocks remain (accepted): the SDK line, the Environment block and the userEmail reminder, about 600
  tokens. They carry no project instruction or memory, but the cwd path names the project directory.
- Effort differs. The first run used effort `low` with a structured-output schema. The clean run uses the CLI
  default, so its output tokens include thinking and its replies are free text parsed by `answerOf`.
- One run per row per model. Context removal and sampling variance are confounded in every between-run delta.
- Jev's arm is the recorded run (accepted): D2 has 7 rows that Jev never answered, so its D2 denominator is 83.
- `answerOf`, `probeVerdict` and `costOf` are TS stand-ins with unit tests (`scripts/jev-arms-clean.test.mjs`, 11
  pass) and no Lean spec. That test file runs in no CI workflow yet.

## What this changes in the plan

- `research/notes/2026/10-2x-jev-replay.md`, section "The Haiku and Sonnet arms": cite the clean numbers above in
  place of the first run's, and name `scripts/jev-arms-clean.mjs run` as the arm runner. Its step 2 ("without tools
  or a system prompt") becomes the `claude -p` flags above, with the three harness blocks stated as the residue.
- Jev trial decision: unchanged. Jev is level with Haiku on both sets, trails Sonnet on D1 and certifies nothing.
- Next measurement, if the lead wants the context effect itself: 3 clean runs per row and model, then a paired
  per-row test. One run per row cannot separate context from sampling variance.
