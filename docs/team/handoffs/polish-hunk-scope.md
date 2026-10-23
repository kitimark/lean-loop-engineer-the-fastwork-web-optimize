branch: worktree-wf_f7e61c92-f16-1
worktree: .claude/worktrees/wf_f7e61c92-f16-1 (under the main checkout)
last commit: `git log -1` on the branch (round 2 work)
CI runs: none (no CI push; local lanes through fw slot)

State (round 2)
- Lean `Fw.Plan.Polish`: `admitted` is containment (`h.start - margin <= e.start /\ e.hi <= h.hi + margin`); `admitted_iff`, `editKept_near`, `restored_far_*` follow; guard `!admitted [<60,2>] <62,59>`; golden case in `packages/contracts/golden/plan/polish.jsonl`.
- `apps/runner/src/polish.ts`: git runs with `-c core.quotePath=false`; `parseDiff` takes the path from the `---`/`+++` lines (unquoting if git quoted); a kept code/shell file with no edit record is restored; an edit hunk running past the margin is restored whole and named.
- Tests: apps/runner/test/polish.test.ts (fixtures: 50-line run past the margin, paths with a space and a non-ASCII character).
- `docs/team/tools/polish.md` describes the plan output, containment rule and main-checkout refusal.
- Accepted limits: prose files are kept whole (Lean cutSafe); relOk checks path text, not symlinks.
- TS stand-ins: `parseDiff`/`headerPath` and the reverse-apply glue (git text, no decision).
Open: final check.sh, runner test, ci-paths test, land-inputs test, dry land and review-ready results are in the report.
Read first: docs/team/tools/polish.md, lean/Fw/Plan/Polish.lean (section Hunks).
