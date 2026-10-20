# latex-teardown (docs and skills step of lean-latex-removal)

- **State:** branch `worktree-wf_1de700b0-a77-1`; edits `be4ee02b`, this handoff in the next commit. No Lean code changed.
- **Verified:** `sh lean/scripts/check.sh` green; ci-paths 41/41; runner land-inputs 55/55; `node --check` build-review.js.
- **Classes:** (a) live text saying Lean holds/needs/avoids LaTeX, or naming the retired lint: rewritten; (b) artifact
  math tooling: kept, positive; (c) unrelated (`$$` PID, `translateX`, serena language list, role names): left. `.claude/skills/**` had no hits.

| File | Hits before | Class | Action |
|---|---|---|---|
| `.claude/workflows/build-review.js` | 2 | a | "unless the mathview lint refuses them" and "mathview lint included" replaced (lint no longer reads docstrings; check.sh runs the axiom check) |
| `.claude/agents/math-reviewer.md` | 3 | a+b | dropped "ignore any math left in docstrings"; `mathview --decl`, corrected LaTeX for the artifact kept |
| `docs/team/tools/lean-first.md` | 3 | a | step 2 `$$` docstring rule now points to comment-sicko; worked-example `$$` line removed; `lfg-mathview-facts` kept |
| `docs/team/tools/prompt-rules.md` | 1 | a | R4 now: comments and docstrings per comment-sicko, `#guard` per decision function |
| `docs/team/tools/visual-diff.md` | 1 | a | "(LaTeX statements in the docstrings)" removed |
| `docs/team/tools/premises.md` | 1 | a | "LaTeX statement" became "statement" (see open 1) |
| `docs/team/parallel-plan.md` | 4 | a+b | 2 "LaTeX in docstrings" phrases removed; 2 `$$` design blocks in the doc kept |
| `docs/team/tools/math-artifact.md` | 6 | a+b | "Lean docstrings hold no math" became "Lean source holds specs, proofs and code"; KaTeX/mathview steps kept |
| `docs/team/tools/disk-cleanup.md` | 2 | b | mathview-cache row says it is a leftover nothing reads |
| `CLAUDE.md`, `token-policy.md`, `page-writer.md` | 1, 1, 2 | b | kept |
| `lean/MathView*.lean`, `lean/README.md`, `lean/lakefile.toml`, `lean/scripts/*` | 36, 22, 7, 5, 14 | b | kept (autoTex renderer, export CLI, `standardAxioms`) |
| `scripts/math-pending.mjs`, `docs/plan/tools/check-lean-lessons.mjs` | 7, 9 | b | kept (reads signed rows; KaTeX parse of a page) |
| `scripts/test-wt-prep.sh`, `wait-guard.md`, `.serena` x2 | 3, 1, 2 | c | left |
| `packages/contracts/golden/**` | 74 | b/c/hist | generated; left (`present.mathview`, `translateX`, `$$` deny case, graph titles) |

## Open
1. `lean/Fw/Ops/Premise.lean`: `Premise.statement` holds LaTeX strings and its module doc says "statement (LaTeX)".
   It is data emitted on premise rows, not a docstring. Lead decides whether it counts as artifact math or gets converted.
2. `lean/Fw/Site/README.md:17` names `lake exe mathview --lint` (still exists: sorry/axioms only); outside these writes.
3. The `mathview-cache` row can go once no checkout holds that directory.
