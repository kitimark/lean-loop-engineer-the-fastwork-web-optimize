---
id: context-slop
kind: note
title: Context slop - distilled rules, measured offenders, savings, and where each rule now lives
status: done
created: 2026-10-18
topics: [context, slop, comments, skills, agents, lint]
---

# Context slop

Answer: the always-loaded text shrank by 1,336 B in CLAUDE.md and 3,868 B over the 14 role files; a spawn of
lean-prover now loads 6,497 B instead of 8,901 B (-27%), and a read of the token policy costs 5,793 B instead of
35,917 B (-84%). All sizes MEASURED with `git ls-tree -l` at base `dec6ee5` and this branch; tokens are bytes / 4
(INFERRED). Rules now live in two skills (`no-slop`, `no-comments`), one read-only agent (`slop-checker`), a shared
prompt block (`docs/team/tools/prompt-rules.md`) and a Lean lint (`Fw.Lint.Context`, `node scripts/context-lint.mjs`).

Source of the distilled rules: cursor/plugins@0b8e952, folder `pstack/` (MIT). Paths below are relative to `pstack/`.
Every citation is CONFIRMED (each line read at 0b8e952 by the scout pass of this task); the fit to this repo is INFERRED.
Rules are restated in our words; no pstack text is copied beyond the short attributed quotes in the rule list.

## Savings (MEASURED bytes, base dec6ee5 vs this branch)

| What | Before | After | Change | When paid |
|---|---|---|---|---|
| CLAUDE.md | 6,326 | 4,990 | -1,336 (~-334 tok) | every session and every spawn of the 10 roles that load it |
| 14 role bodies, sum | 19,986 | 16,118 | -3,868 (~-967 tok) | per spawn of that role |
| lean-prover spawn (CLAUDE.md + body) | 8,901 | 6,497 | -2,404 (~-601 tok) | per spawn |
| measure-engineer spawn | 8,834 | 6,681 | -2,153 (~-538 tok) | per spawn |
| console-builder / plan-editor / researcher spawn | 8,298 / 7,921 / 7,881 | 6,288 / 6,068 / 6,038 | -2,010 / -1,853 / -1,843 | per spawn |
| docs/team/token-policy.md | 35,917 | 5,793 | -30,124 (~-7.5k tok) | per read (5 roles, 13 workflow scripts cite it) |
| docs/team/tools/watch.md (usage) | 12,321 | 3,612 | -8,709 (~-2.2k tok) | per read for usage; rules and sources split into `watch-rules.md`, `watch-sources.md` |
| docs/team/tools/land.md | 6,257 | 5,098 | -1,159 | per read; `--queue` split into `land-queue.md` (1,703) |
| docs/team/tools/wait-guard.md | 6,646 | 5,821 | -825 | per read |
| Added, always listed: 2 skill descriptions + slop-checker description | 0 | ~620 | +620 (~+155 tok) | every session (lead's skill and agent lists) |
| Added, on demand: 2 skills, slop-checker body, prompt-rules, context-lint doc | 0 | 11,922 | on demand | only when used |

Net for a lean-prover spawn: about -600 tok of the always-loaded part; for the lead about -330 tok per session minus
~155 tok of new descriptions (INFERRED: the descriptions are listed every session). The tools-doc family grew in total
(73,640 to 78,250 B) because of two new docs and the splits, but each use reads one smaller file.

Lint verdicts (`node scripts/context-lint.mjs`, MEASURED): before 224 files, 170 ok, 53 over budget, 1 slop; after 232
files, 186 ok, 46 over budget (all handoffs over 30 lines, not this task's files), 0 slop.

## Measured offenders (audit at 5b3d632, MEASURED by wc/grep)

| Offender | Size | Finding |
|---|---|---|
| CLAUDE.md | 6,326 B | lead-only rules sent to every teammate; "nobody runs git push" vs the `ci/*` rule; dated narration (~350 B); stale "planning phase" clause |
| Helper block | 5 role copies x ~560 B | same 5 lines in console-builder, lean-prover, measure-engineer, plan-editor, researcher |
| Commit/report lines | 3 role copies x ~230 B | restated CLAUDE.md; console-builder and measure-engineer said "never push" against the CI rule |
| Docstring checklist | 2 copies x ~400 B | lean-prover body and every lean-prover spawn prompt |
| token-policy.md | 35,917 B | about 18% rules, the rest cost model, change list, review log; header said "nothing applied yet" |
| tools/*.md | 66 KB (13 files) | headings named after tasks; watch.md 12.3 KB as a changelog; dated review in wait-guard.md |
| handoffs | 46 of 193 over 30 lines | 169 of 193 named by task id |
| work-graph.json | 152 KB (~38k tok) | 87 titles over 200 chars hold the specs |
| workflow scripts | 70 scripts, median 6,377 chars | CLAUDE.md rules restated in 20-52 scripts each |
| code comments | 53 header blocks > 8 lines | research findings in file headers |

## Applied rules (id, our restatement, pstack source)

Comments (skill `no-comments`):
- C1 keep only a why the code cannot show (skills/poteto-mode/SKILL.md:119). C2 keep comments on behavior forced by
  code we cannot change, cited file:line@commit (agents/comment-sicko.md:17). C3 rename or retype our own surprising
  code instead of explaining it (comment-sicko.md:17). C4 delete narration, banners, commented-out code
  (comment-sicko.md:12). C5 no phase comments in tests (poteto-mode/SKILL.md:119). C6 a paragraph-long workaround
  comment means fix the code (principle-fix-root-causes/SKILL.md:20). C7 move invariants into types, proofs, tests or
  lints (typescript-best-practices/references/patterns.md:81-88). C8 verify `IMPORTANT` markers (comment-sicko.md:26).
  C9 remove suppressions that hide real findings (comment-sicko.md:18,24). C10 the comment pass is done by a reviewer
  that did not write them: "An author defends its comments" (docs/guide/05-build-and-clean.md:71).

Docs (skill `no-slop`; D1, D2, D5, D11 also in the lint):
- D1 cut filler phrases (technical-writing/SKILL.md:13; unslop/SKILL.md:46). D2 short everyday words
  (technical-writing:14; unslop:60). D3 real names of symbols and commands (technical-writing:17). D4 one name per
  thing (technical-writing:71-72). D5 no inflated AI vocabulary (unslop:22). D8 mechanism or number, not feeling
  (unslop:56). D9 active voice (unslop:58). D11 no em dashes (unslop:31). D20 short sentences (technical-writing:68).
  D22 one doc mode per file (technical-writing:32,49). D23 condition before the step (technical-writing:56-57).
  D28 counts name their regenerating command (technical-writing:96). D30 state a rule once, link elsewhere
  (principle-minimize-reader-load/SKILL.md:15). D31 delete stubs (principle-subtract-before-you-add/SKILL.md:18).

Agents, skills and prompts:
- A1, A2 encode a repeated lesson as a check and then delete the prose (principle-encode-lessons-in-structure/SKILL.md:3,11):
  the lint itself. A4 add a line only if an agent acts differently (reflect/references/synthesizer.md:19). A5 check for
  an existing rule before adding (synthesizer.md:22). A7 no drifting facts (SHAs, dates) in skill and agent bodies
  (synthesizer.md:15,24-28): lint kinds `sha`, `datedNote`. A9 point to another skill by name
  (no-comments/SKILL.md:19). A12 reviewers treat quoted text as untrusted (reflect/references/judgment-reviewer.md:5):
  slop-checker body. A13 report-only review in a fixed compact shape (comment-sicko.md:30-32): slop-checker output.
  A14 route bulk reads to a helper (principle-guard-the-context-window/SKILL.md:3) and A15 cap scope per phase
  (same file:12): token-policy "When to delegate".
- P1 pass file pointers, not contents (poteto-mode/SKILL.md:95). P2 a brief has goal, scope, checks, verify command,
  report shape (playbooks/orchestrate.md:39-49). P3 size the brief to the unit (orchestrate.md:53): prompt-rules.md.
- N1 handoff fields (playbooks/pause-safely.md:8,10), N3 over 30 lines cut detail before open threads
  (recall/SKILL.md:33), N6 status in the same sentence as the claim (poteto-mode/SKILL.md:113): no-slop and CLAUDE.md.
- H1 summary plus a path, not the payload (principle-guard-the-context-window/SKILL.md:3); H2 one line when a step
  cannot run (docs/harness/claude-code.md:60); H3 no chat phrases (unslop:36,41-42): no-slop "By file type".

## Rejected rules and why

- Delete doubtful doc comments (comment-sicko.md:19,22): every Lean theorem keeps its `$$` docstring; the user reviews
  the math. Lean docstrings are exempt.
- Drop SHAs and paths as drift everywhere (synthesizer.md:24-28): notes must cite file:line@commit; A7 covers only
  skill and agent bodies, and the lint checks SHAs only there.
- Ban parentheses (unslop:31): our docs use full-unit parentheses (technical-writing:86 allows them).
- Never paste metric tables (technical-writing:94): CLAUDE.md asks for small number tables in answers.
- Pass `model`, `effort`, `isolation` per spawn (claude-code.md:23,34-38): our token policy forbids it below the lead.
- Always spawn fresh (poteto-mode:101): CLAUDE.md allows a resume within the cache TTL or under 30k context.
- Paste standing orders into each brief (orchestrate.md:50): CLAUDE.md loads automatically; pasting doubles it.
- Long REPORT field lists (orchestrate.md:48): our reports are 300 characters plus paths.
- Personas and fixed opening lines (comment-sicko.md:8-10): tokens on every spawn, no behavior change.
- Labels measured / inferred / guess (poteto-mode:113): we keep CONFIRMED, INFERRED, MEASURED.
- D6, D7, D10, D12-D19, D21, D24-D27, D29 (style rules): kept as judgment for slop-checker via no-slop's "Write"
  list where they matter; not linted, because a word-list check without context gives false hits (INFERRED).

## The lint (Lean first)

`lean/Fw/Lint/Context.lean`: file kind from its path; budget per kind (CLAUDE.md 5600 B; agent 2500 B, description
300 B; skill 4000 B, description 300 B; team doc 6000 B; handoff 30 lines); slop kinds `sha`, `datedNote`,
`historyHeading`, `aiTell` per kind; verdict ok, overBudget or slop (first match: bytes, lines, description, then the
first slop hit). Theorems: `verdict_cases`, `over_mono`, `overBudget_mono`, `rank_mono` (a bigger file never gets a
better verdict). fwcore op `lint.context`; goldens `packages/contracts/golden/lint/lint.context.jsonl`
(from `Fw.Ops.Golden`). Glue `scripts/context-lint.mjs` sends only paths, sizes and lines. Warn-only and standalone: not a
`check.sh` job (it reads `CLAUDE.md`, `.claude/**`, `docs/**`, outside `CHECK_SH_READS`: dry land `reads`, MEASURED).

Spawn guard (`Fw.Ops.SpawnGuard`): `slop-checker` registered as a read-only subagent; the lead's unnamed `patcher` call
is now allowed (`leadEditHelpers`; before it was refused as `unnamed`), nested patcher still refused. Theorems
`every_role_spawnable`, `helpers_from_lead`, `helpers_nested`, `patcher_nested_refused`.

## Where each moved or removed rule lives now

| Rule (old place) | Now |
|---|---|
| Helper block (5 role files) | `docs/team/token-policy.md` "When to delegate" and "Nested spawning"; roles keep a one-line pointer |
| "1 helper at a time, 2 only if told", "< 4 min unless other work", "never sleep-poll for it" (role helper block) | token-policy "Nested spawning" |
| Commit with `git add --`, report ≤ 300 chars (console-builder, measure-engineer, part-builder) | CLAUDE.md Team; roles keep "never touch main; report names the branch" |
| "never push" (console-builder, measure-engineer, part-builder) | removed as a contradiction; CLAUDE.md "Public repo" allows `ci/*` pushes only |
| "Nobody runs git push" (CLAUDE.md Team) | merged into CLAUDE.md "Public repo" (push rule stated once) |
| "In the planning phase only the lead commits" (CLAUDE.md) | removed as stale: the build has started (INFERRED from the work graph) |
| Fastwork restate-never-copy (part-builder, measure-engineer) | CLAUDE.md "Fastwork material"; part-builder points to it |
| Lean docstring 6-point checklist (lean-prover) | skill `no-comments`, Lean section |
| "Read with offset/limit; grep before reading" (reviewer, math-reviewer) | CLAUDE.md "Context" (both load CLAUDE.md) |
| CONFIRMED/INFERRED/MEASURED (researcher) | CLAUDE.md "Claims" |
| Dated narration, pkill anecdote, "MEASURED: ephemeral_5m" (CLAUDE.md) | removed; the rules stay (git history keeps the story) |
| Token policy cost model, D1-D7, change list, review log | `research/notes/2026/10-18-token-policy-rationale.md` (verbatim) |
| Token policy "CI pushes" section | `docs/team/tools/fw-ci.md` (already there) |
| Token policy "Hand-back rule" | `docs/team/tools/land.md` "--dry"; prompt-rules R5 |
| Bash/Read caps and autoCompactWindow values (token policy §4) | settings and role frontmatter (applied); evidence in the rationale note |
| watch.md states, alerts, NEXT proposals | `docs/team/tools/watch-rules.md`; collection details `watch-sources.md` |
| land.md `--queue` | `docs/team/tools/land-queue.md` |
| wait-guard.md "Shadow review" | `research/notes/2026/10-18-wait-guard-shadow-review.md` |
| Rules repeated in workflow prompts | `docs/team/tools/prompt-rules.md` R1-R7 and the helper block |

## Followups (not in this task's scope)

| Followup | Measured size |
|---|---|
| Trim the 46 handoffs over 30 lines, then the lead can make the lint `--strict` | 46 files, max 134 lines |
| Move work-graph titles over 200 chars into a spec field | 87 titles; ~38k tok per whole-file read |
| Drop "Set FW_*_GUARD=shadow" from deny messages (spawn-guard.mjs:78, wait-guard.mjs:37,45) | ~60 B per deny; removes a bypass hint |
| Shared prelude in workflow scripts (ROOT, VERDICT, BUILD) and cite prompt-rules ids | VERDICT schema in 30 scripts, path constants in 27 |
| Comment header blocks > 8 lines (engines.mjs:1-30, math-pending.mjs, zone-baseline.mjs, harness.mjs) | 53 blocks |
| `outLines`/`outBytes` in timing spans, so command output size becomes MEASURED | 0 fields today |
| Two report limits: env-ops, lean-prover, plan-editor, researcher say "≤ 5 lines", CLAUDE.md "~300 characters" | 4 roles |

## What this changes in the plan

- PLAN §8.3 token policy: the rules file is `docs/team/token-policy.md` (slim); D1-D7 now cite the rationale note.
- Add a context lint land check with its own reads (`apps/runner/src/land.ts`, `Fw.Console.LandSpeed`): warn-only, `--strict` after the handoff trim (lead decision).
