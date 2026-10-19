# compose-check handoff (branch worktree-wf_c01d6050-edd-1)

State: round 2 done; the commit is the branch head (`git log -1`), on top of main 575e3087.

Verified:
- `lean/Fw/Measure/Compose.lean`: `verdict` per (stage, type, zone or whole run) with a theorem per branch;
  `refusal` (unclean, fewer than 2 flags) with `refusal_eq_none_iff`, `refusal_unclean`, `refusal_fewFlags`;
  `armFor` requires another run id (`armFor_spec`, `armFor_ne_self`); `Cell.informative` and `Cell.beyond`
  (`informative_iff`, `informative_iff_beyond`, `vacuous_of_zero`, `informative_exact_iff`). `#guard` on each.
- Op `measure.compose` (`lean/Fw/Measure/Wire.lean`) emits `baseFlags`, per row `informative` and `beyond`, and
  `tally.informative`. Golden: `packages/contracts/golden/measure/measure.compose.jsonl` (5 cases, both refusals,
  a base with a shell part), from `lean/Fw/Measure/Golden.lean` via `scripts/MeasureGolden.lean --check`.
- `packages/engine-check/src/compose.mjs`: `loadRun` throws without `meta.rewrite.config.variants`.
- wave2.mjs `f6`, `f6cmd` and `PASS_TYPES` are deleted; no TS stand-in is left on the F6 path.
- Result (`research/notes/2026/10-20-compose-check.md`): coherent set ci/f6-set (11 runs at 575e3087). v2-proved
  composes on 5 of 5 decided cells, all informative, but only `morph.mount:shift` acts in them. The round 1 triple
  composes only vacuously, and its base has commission, pain and people set to shell.
- `lean/scripts/check.sh` green; engine-check 21 pass, apps/runner 1135 pass with tsc, ci-paths 40 pass.

Open:
- No unit type is frame exact in `classes.frozen.json`, so zone cells never decide.
- Multi-flag add-ups (FireAnimationFrame, FunctionCall, Layout.dirtyObjects) are quarantined. A verdict needs a
  class for them (more runs).
- Flag independence is not checked. The verdict does not reference `lego_swap_units`.
- `docs/team/handoffs/integrate-wave-2.md` still names the retired `wave2.mjs f6` command (not my file).

Conventions: rows are keyed by (stage, count type, zone or whole run). A part is a row's `parts` entry (its single
delta) and is named in `beyond` and in `coupled`. Downloads: `gh run download <id> -p 'chromium-counts-*' -D <dir>/<id>`,
then `cli.mjs --compose results/compose-check/plan.json --runs <dir> --out results/compose-check`.

Read first: the note's Result and Answer, then `pre`, `verdict` and `refusal` in Compose.lean.
