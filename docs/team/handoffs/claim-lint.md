# Claim lint

- Branch `worktree-wf_fa4e4bfe-ec3-1`, round 1. Rules, golden and plan-lint I/O in aed97053b; note, ledger row and
  handoff in the next commit. No CI runs.

## Rule (lean/Fw/Plan/Claims.lean)
- Status tags: `claimOk` with `claim_ok_iff`, `confirmed_ok_iff`, `measured_ok_iff`, `measured_scratch_refused`,
  `inferred_ok_iff`. Cites come from the tag's scope (block plus section heading; a heading's whole section; a table
  row's caption block); scratch paths and the bound word come from the unit's own tokens.
- Key references: `numOk` (half away from zero at the written places, `numOk_iff`, `roundQ_half`, `roundQ_exact`),
  `rangeOk` (`rangeOk_iff`), table captions `under T in F: Head = key`, `.txt` quotes, `a op b = c` arithmetic.
- `handle` serves `claims.reads` and `claims.lint`; `lean/scripts/ClaimsGolden.lean` prints, checks (`--check`) or
  serves (`--serve`) it.

## Verified
- Golden `packages/contracts/golden/plan/claims.jsonl`, 40 rows from the refused fragments (nav-cta-webkit-match r2,
  watch-memory r2/r3, end-floor-writes r1/r2); check.sh job "claims golden check"; lean.yml trigger row lists it.
- `node --test packages/plan-lint/test/claims-lint.test.ts` 33/33; tsc on packages/plan-lint clean.
- Corpus: 1432 warnings in 354 of 1177 files, listed in research/notes/2026/10-30-claim-lint.md. CLI exits 0.
- `#print axioms`: `claim_ok_iff` none, the rest propext/Classical.choice/Quot.sound.

## Open
- `fw claims lint` dispatch in apps/runner/src/fw-main.ts and a fwcore op in lean/Fw/Wire/Plan.lean (outside writes).
- plan-lint has no package.json, so land checks do not run its test; tsc borrows gh-budget's typeRoots.
- The bound word fires on timeouts and thresholds (67 warnings); CSV/YAML formats are unchecked.
- Read first: the `lintCases` table near the end of Claims.lean, then `lintNote` in packages/plan-lint/src/claims-lint.ts.
