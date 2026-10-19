# compose-check handoff (branch worktree-wf_c01d6050-edd-1)

State: F6 check built and run on existing artifacts. Commit: `git log -1` on the branch.

Verified:
- `lean/Fw/Measure/Compose.lean`: `verdict` per (stage, type, zone), with a theorem per branch
  (`verdict_composes_iff`, `verdict_coupled_iff`, `verdict_reported_iff`, `verdict_missing`, `missing_not_composes`,
  `missing_not_coupled`, `verdict_quarantined`, `verdict_noZoneMargin`, `verdict_drift`), plus `coupled_cell_sound`,
  `composes_exact`, `armFor_spec`, `cellAt_missing`. `#guard` on every decision function.
- Op `measure.compose` in `lean/Fw/Measure/Wire.lean`; golden `packages/contracts/golden/measure/measure.compose.jsonl`
  from the `measure.compose` cases of `lean/Fw/Measure/Golden.lean` (`scripts/MeasureGolden.lean`, `--check`).
- `packages/engine-check` is in `FWCORE_USERS` and declares `packages/contracts/golden/measure/**` (land.ts).
- `packages/engine-check/src/compose.mjs` and `cli.mjs --compose`: glue only. `test/compose.test.mjs` replays the
  golden through fwcore and rebuilds a golden request from run dirs.
- Result (`research/notes/2026/10-20-compose-check.md`): the hidden-pause triple composes on 5 of 5 judged cells.
  v2-proved is not comparable because no single-flag arm shares its base 39253166643.

Open:
- v2-proved needs one base, the v2-proved arm and 10 single-flag arms on one commit (not dispatched).
- No unit type is frame exact in `classes.frozen.json`, so zone cells never decide. A per-zone F6 needs a
  frame-exact unit class or a sound per-zone margin for stable(k at least 1).
- The pairing uses base run id and zone shape. Counts files carry no site commit.

Conventions: the plan names runs (`results/compose-check/plan.json`); runs are downloaded with
`gh run download <id> -p 'chromium-counts-*' -D <dir>/<id>`; the CLI takes `--runs <dir>`.

Read first: the note's Answer, then `pre`/`verdict` in Compose.lean.
