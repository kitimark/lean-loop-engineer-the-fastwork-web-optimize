# writes-closure-followups

- Branch: worktree-wf_39a630d6-e70-1 (worktree .claude/worktrees/wf_39a630d6-e70-1)
- Last code commit: 9a09d8066, then a merge of main (642babc15, main at 17cb8b6dc)
- CI runs: none (all checks are local Lean, vitest and node tests)
- Verified: check.sh green (writes-closure golden 21 cases, axioms ok); apps/runner 3006/3006 tests and tsc ok;
  ci-paths + build-review node tests 69/69; live `fw plan lint`: 0 writesClosure errors
- Open: the live lint's 1 error (`timing-slot-width trailerNoEvidence`) comes from main's graph

## What landed
- `lean/Fw/Plan/WritesClosure.lean` section "Gaps from the scripts and the row globs": `readsOf`, `normRead`,
  `ghMatches` (GitHub glob twin), `inputGaps`, `gapsOf`; theorems tie an unmatched read to `required`.
  Section "Plan sync": `newErrors`, `new_error_refused`, `old_error_passes`, `warning_passes`.
- Golden `packages/contracts/golden/plan/writes-closure.jsonl` adds rows `glob`, `gaps`, `sync`; cases carry
  `scripts` and `globs`, and their gaps are derived by `gapsOf`.
- `scripts/ci-paths.mjs` `leanInputGaps` is the one gap function; `leanInputProblems` and
  `apps/runner/src/plan-closure.ts` `gapsOf` both call it.
- `apps/runner/src/plan.ts` `syncClosureRefusal` compares with the previous committed graph (`previousGraph`);
  `fw plan sync` throws on a new writesClosure error.
- `.claude/workflows/build-review.js`: the builder runs `fw plan lint` after merging main, before the dry land.

## Conventions
- Golden regen: `cd lean && lake env lean --run scripts/WritesClosureGolden.lean`.
- TS glue without proof: `previousGraph` (git I/O); JS regex `matches` agrees with `ghMatches` only for globs
  without `?`, `+`, `[`.

## Read first
`lean/Fw/Plan/WritesClosure.lean` (sections above), then `apps/runner/test/plan-closure.test.ts`.
