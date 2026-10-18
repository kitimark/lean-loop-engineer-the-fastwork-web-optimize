# engine-golden-premise-lint (lean-prover, m175 hardening)

## State
- Branch `worktree-agent-a7812b8342c61c3ae`, main merged; `lean/scripts/check.sh` green (about 7 s warm, 16 s cold).
- `lean/Fw/Ops/Premise.lean`, section "Engine golden citations": `Cite` rules, `cites`, `citeLint` (uncited, bad,
  untested), `untestedPremises` (17), `engineCites`. Theorems: `uncited_row_flagged`, `bad_of_unknown`,
  `untested_of_cited`, `citeLint_ok_iff`, `citeLint_ok_of_annotated`, `engineCites_ids`, `untested_ids_fresh`,
  `engineCites_valid`, `engineCite_ok_iff`, `covered_mono`.
- Section "The WKTR lane assertion": `wktrExpected` (control 0, scroll-timeline 1, time-accel 0 per update),
  `passOk`, `laneFailures`, `laneFailures_nil_iff`, `lane_old_claim_fails`. The golden is
  `packages/contracts/golden/ops/wktr-lane.jsonl`, written by `scripts/PremiseGolden.lean`.
- `scripts/EngineCiteLint.lean` runs in check.sh: 253 rows in 12 files are all cited. It warns that 17 untested
  premises are cited by 253/253 rows; only 4 rows also cite the measured p18 (webkit P1/P4 scrollDriven style, and
  hero-exit webkit style).
- `packages/measure-wktr/fixtures/summarize.mjs --assert` ports `laneFailures` and exits 1 on any failure.
  `test/summarize.test.mjs` checks it against the Lean golden.

## Conventions
- A row is the string fields of its JSON line plus `file`, the path below `golden/engine/`. A row cites the union of
  all rules whose pattern matches it. A new golden file cites nothing until it is listed in `engineFiles`.
- No page premise is cited: no golden value is computed under one (scout sweep, 2026-10-18).

## Open items
- The lead must add one workflow line, in the `classes` job, step "Classes and summary":
  `node "$GITHUB_WORKSPACE/packages/measure-wktr/fixtures/summarize.mjs" wktr-fix-j* --assert | tee -a "$GITHUB_STEP_SUMMARY"`
- The TS `fw premises` does not run the cite lint yet.
- The webkitX/WKTR dependency of the other WebKit variant rows is INFERRED, not cited.
- To measure an untested premise: add a lane, move the premise into `registry`, and drop it from `untestedPremises`.

## Read first
- The `Fw/Ops/Premise.lean` module header, then the `engineCites` docstring.
