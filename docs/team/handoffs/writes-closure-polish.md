# writes-closure-polish

- Branch: worktree-wf_f0a48602-5d2-1 (worktree .claude/worktrees/wf_f0a48602-5d2-1)
- Last code commit: 186f02b15 (main 7e4722c7d merged, no new main commits)
- CI runs: none (all checks are local Lean, vitest and node tests)
- Verified: check.sh green (writes-closure golden 21 cases, axioms ok); apps/runner 3019/3019 and tsc ok;
  contracts 11/11; ci-paths 56/56, build-review 15/15; `node scripts/ci-paths.mjs --check` ok; live `fw plan lint`:
  0 errors
- Open: none in the unit. Follow-up: `normRead` keeps `..`, so a `**` row glob over the prefix (`lean/**`) also
  matches `lean/../x`; no script reads such a path today.

## What changed
- `lean/Fw/Plan/WritesClosure.lean`: `jsSpace` written with `\u` escapes (same code points); `rowGlob`
  (closed allowlist: one optional leading `!`, then ASCII letters, digits, `._-/*`) with `rowGlob_iff`,
  `rowGlob_empty_refused`, `rowGlob_char_refused`, `rowGlob_meta_refused` (`?`, `+`, `[` refused); `leanRow.all rowGlob`.
- Golden `writes-closure.jsonl` adds `rowGlob` rows (`glob`, `ok`).
- `scripts/ci-paths.mjs`: `rowGlob` twin, `leanRowGlobs`; `leanInputProblems` refuses a row glob outside the subset
  before any gap is computed. `normRead` doc says it keeps `..`.
- `scripts/ci-paths.test.mjs`: golden replay of `rowGlob`, live row inside the subset, refusal of `?`, `+`, `[`.
- `docs/team/tools/plan.md`: plan sync's fwcore dependency and its time (180 ms p50 before, 642 ms after; closure
  check alone 374-404 ms).
- `docs/team/handoffs/writes-closure-followups.md`: merge sha line and Open line fixed.

## Read first
`lean/Fw/Plan/WritesClosure.lean` `rowGlob`, then `scripts/ci-paths.mjs` `leanInputProblems`.
