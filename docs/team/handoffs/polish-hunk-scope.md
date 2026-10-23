branch: worktree-wf_f7e61c92-f16-1
worktree: .claude/worktrees/wf_f7e61c92-f16-1 (under the main checkout)
last commit: see `git log -1` on the branch (WIP commit before checks)
CI runs: none (no CI push; local lanes only, through fw slot)

State
- Lean `Fw.Plan.Polish`: `Span`, `margin` (3), `admitted` (hunk rule), `Span.reach` (lines named to comment-sicko), `relOk` (path rule), `editKept`, `blocked` (main-checkout rule); theorems `admitted_iff`, `admitted_nil`, `admitted_hunk`, `admitted_inside`, `restored_far_above`, `restored_far_below`, `reach_admits`, `relOk_empty`, `relOk_abs`, `relOk_up`, `relOk_plain`, `editKept_rel`, `editKept_near`, `blocked_mem`, `blocked_ne_nil`; `#guard` goldens at the end of the file (no separate PolishGolden.lean).
- fwcore op `plan.polishHunks` in `lean/Fw/Wire/Plan.lean` (outside the task writes, needed to expose the rule); JSON goldens in `packages/contracts/golden/plan/polish.jsonl` (7 hunks cases).
- `apps/runner/src/polish.ts`: `plan` prints `comments <mark> <rel path> lines <lo-hi,...>` and `prose <rel path>`; `commit` refuses (exit 1, `VERDICT polish-commit <id> refused`) when the main checkout is dirty in the plan's files, reverts each out-of-hunk edit hunk of code and shell files (one `git apply -R --unidiff-zero` per hunk, later first) and names it.
- `.claude/workflows/build-review.js`: comment-sicko prompt carries the line ranges per file; the lead's interim guard stays (worktree line, strays).
- `docs/team/tools/polish.md` still describes the old plan output (outside the task writes; follow-up).
- Final checks: check.sh green, apps/runner test 2860 passed, ci-paths test 54 passed, build-review test 12 passed, `VERDICT dry polish-hunk-scope`, `VERDICT review-ready polish-hunk-scope review`.

Accepted limit (prose): prose cuts (slop-checker) are exact-substring and unique, and Lean `judge` plus `cutSafe` decide each cut (`judge_apply_unique`, `judge_apply_safe`), so the hunk rule applies to comment edits (code and shell) only; prose files are kept whole.
TS stand-ins: `parseDiff` and the reverse-apply glue (reading git text, no decision); a kept file with no edit-hunk record is kept.

Verified: `plan` and `commit` against a real git fixture (apps/runner/test/polish.test.ts: in-hunk edit kept, edit 50 lines away restored, several hunks, main-checkout refusal, plan output); node --test scripts/build-review.test.mjs.
Open: results of check.sh, runner test, ci-paths test, land-inputs test and the dry land are in the report.
Read first: docs/team/tools/polish.md, lean/Fw/Plan/Polish.lean (section Hunks).
