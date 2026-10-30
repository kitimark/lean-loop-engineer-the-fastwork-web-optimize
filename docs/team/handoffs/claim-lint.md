# Claim lint

- Branch `worktree-wf_fa4e4bfe-ec3-1`, worktree `.claude/worktrees/wf_fa4e4bfe-ec3-1`, round 2 (round 1 refused: no
  wiring, doctored golden rows named as refusals, note and ledger overstated). No CI runs.

## Rule (lean/Fw/Plan/Claims.lean)
- Status tags: `claimOk` with `claim_ok_iff`, `confirmed_ok_iff`, `measured_ok_iff`, `measured_scratch_refused`,
  `inferred_ok_iff`. Cites come from the tag's scope (block plus section heading; a heading's whole section; a table
  row's caption block); scratch paths and the bound word come from the unit's own tokens.
- Key references: `numOk` (half away from zero at the written places, `numOk_iff`, `roundQ_half`, `roundQ_exact`),
  `rangeOk` (`rangeOk_iff`), table captions `under T in F: Head = key`, `.txt` quotes, `a op b = c` arithmetic.
- `handle` serves `claims.reads` and `claims.lint`; `lean/scripts/ClaimsGolden.lean` prints, checks (`--check`) or
  serves (`--serve`) it.

## Wiring
- `landLint` (packages/plan-lint/src/land-lint.ts) runs `node packages/plan-lint/src/cli.ts <changed notes/handoffs>`;
  the CLI builds `+Fw.Plan.Claims` first. `apps/runner/src/land.ts` calls it once per land (dry after the merge check,
  real in the pre-lock slot, the locked merge or the card path) and pushes its lines; verdict and exit code unchanged.

## Verified
- Golden `packages/contracts/golden/plan/claims.jsonl`, 42 rows: 7 real refused fragments (names carry the commit that
  holds them verbatim), labelled variants, corpus rows. Caught: end-floor-writes r2 "70 to 83" (`rangeEnds`),
  watch-memory r2 MEASURED with no source (`measuredNoSource`). Unchecked, no artifact key: nav-cta r2 "within 10 px
  ... at 1280", watch-memory r2 "1.7 x" and "150 to 860 MB", end-floor-writes r2 frame counts and Lesson.
- plan-lint node tests 49/49 (3 new for `landLint`); apps/runner tests 3749/3749; ci-paths 56/56; check.sh green.
- Dry land prints `claims lint: 1 warnings in 1 of 2 files` at dbbb22043 (a quoted tag in this task's note, since
  fixed), then `VERDICT dry claim-lint`.

## Open
- `fw claims lint` dispatch (apps/runner/src/fw-main.ts) and a fwcore op (lean/Fw/Wire/Plan.lean): outside writes.
- plan-lint has no package.json, so land checks run apps/runner tests (they read packages/plan-lint/**), not its node
  tests. A land-dry fixture test belongs in apps/runner/test (outside writes).
- The bound word fires on timeouts and thresholds; CSV/YAML formats are unchecked.
- Read first: `lintCases` near the end of Claims.lean, then `landLint` and `lintNote`.
