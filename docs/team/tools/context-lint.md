# context-lint

Checks the files agents load or read on most tasks against a size budget and a few mechanical slop patterns. Lean decides
every verdict (`Fw.Lint.Context`, fwcore op `lint.context`); `scripts/context-lint.mjs` only lists files and sends their
path, byte size and lines. Writing rules behind it: skills `no-slop` and `no-comments`.

## Use

```
node scripts/context-lint.mjs [--all] [--json] [--strict] [paths..]
```

No paths: `CLAUDE.md`, `.claude/agents/*.md`, `.claude/skills/*/SKILL.md`, `docs/team/token-policy.md`,
`docs/team/tools/*.md`, `docs/team/handoffs/*.md`. `--all` prints every finding (default the first 12), `--json` the raw
reply. fwcore comes from `FW_CORE_BIN`, else `lean/.lake/build/bin/fwcore`.

## Verdicts

Per file, first match wins: `overBudget` (bytes, then lines, then frontmatter description bytes), else `slop` (first hit
by line), else `ok`.

| Kind | Bytes | Lines | Description | Slop checked |
|---|---|---|---|---|
| `CLAUDE.md` | 5000 | | | dated note, task heading, AI tell |
| agent | 2000 | | 300 | SHA, dated note, task heading, AI tell |
| skill | 4000 | | 300 | SHA, dated note, task heading, AI tell |
| team doc (tools, token-policy) | 6000 | | | task heading, AI tell |
| handoff | | 30 | | AI tell |
| other | | | | none |

Slop kinds: `sha` (7-40 lowercase hex with a digit and a letter), `datedNote` (a `dddd-dd-dd` date), `historyHeading` (a
heading with `(task ` or ending in a kebab-case id in parentheses), `aiTell` (an em dash, a word in `aiWords` or a phrase in
`fillers`).

## Output

One line per non-ok file, `context-lint: <verdict> <path> (<measure> <value> > <budget>)` or `(<slop> at line <n>)`, then
`context-lint: N files: a ok, b over budget, c slop (warn-only)`. A missing fwcore prints one `WARN` line.

## Gate

Warn-only and standalone: it exits 0 on findings and no gate runs it yet. It is not a `lean/scripts/check.sh` job,
because it reads `CLAUDE.md`, `.claude/**` and `docs/**`, outside `CHECK_SH_READS` (`apps/runner/src/land.ts`), so
the dry land refuses it as `reads`; a separate land check with those reads is a lead decision, like `--strict` (exit
1) once the handoffs over 30 lines are trimmed. Proofs: `verdict_cases`, `over_mono`, `overBudget_mono`, `rank_mono`,
`verdict_of_facts`; golden `packages/contracts/golden/lint/lint.context.jsonl` (`Fw.Ops.Golden`, checked by `fwtest`).
