# skills-reframe

State: branch `worktree-wf_40d66781-cd1-1`, one commit on top of main (see `git log -1`).

## Done
- `.claude/skills/no-comments/SKILL.md`: orchestrator in the pstack pattern (scope, spawn `comment-sicko`, accept or
  reject, root-cause fixes, encoding offers, counts). 38 lines.
- `.claude/agents/comment-sicko.md`: new. Keep list, doubt means delete, `MUST KILL`, suppressions by rule, Lean rules
  (no LaTeX, one-line contract docstring only, module doc at most 2 lines, no proof narration). Edits comments only.
- `.claude/skills/no-slop/SKILL.md`: unslop + technical-writing + minimize-reader-load, plus our budgets and file-type
  rules. 59 lines.
- `slop-checker` reviews prose against no-slop only. `math-reviewer` reviews artifact math, not docstrings.
  `lean-prover` points at the comment-sicko Lean rules. `token-policy.md` rows. CLAUDE.md "No LaTeX in Lean" line.
- `checker.md` unchanged: it holds no reference to the comment, slop or LaTeX rules.

## Verified
- `apps/runner` `pnpm test` (tsc + vitest) green with `FW_CORE_BIN` at the main checkout's fwcore: 1004 passed.
- `node --test scripts/ci-paths.test.mjs`: 32 passed.
- MEASURED: fwcore `ops.spawn` denies a named `comment-sicko` spawn with `unknownRole`.

## Open (lead)
- Register comment-sicko (task comment-sicko-spawn): a (subagent, edits) row in SpawnGuard.prodRoles and hook ROLES,
  and add it to SpawnGuard.leadEditHelpers.
- token-policy: dropped the lake build log line (the generic Long output line covers it) and the handoff 30-line line
  (in CLAUDE.md), to stay under 6000 B.
- context-lint warns `sha` on the three attribution lines; an exemption belongs in `Fw.Lint.Context`.
- CLAUDE.md was already over its 5600 B budget (6266 B, now 6295 B).
- `docs/team/tools/prompt-rules.md` R4 and `docs/team/tools/lean-first.md` still ask for `$$` docstrings:
  lean-latex-removal.
