# Handoff: hero-exit-restate (WebKit hero-exit frames after wktr-p1p4)
**State:** branch `worktree-agent-a2f67222eaa42a51a`, main merged; `lean/scripts/check.sh` green, runner tests 432/432, site golden tests green.
- `lean/Fw/Parts/HeroExitOpt.lean`: `wkVar m l N` = fold of `withAnim` (`wkStep`) over `zip (wkTargets l N) (wkAnims l N)` on
  `scrollStepX emptyX` (`webkitX`); `wkIdle` the same on `emptyX`. `wkVar_eq` (no premise: scrollPos + one `restyle` per target,
  N+3 comp anims), `wkIdle_eq` (= lifted `compFrame (N+3)`), `wk_var_exact` (premise `WktrStyleRate.Holds`: style passes
  μ.timeline = 1, units N+3), `wk_trade` / `wk_tradeE` (premise, at `wkOrigChanges l N lo` with `lo ≠ none`: a filter
  change on a box without a layer is `equal`, so the original's style units fall to 2N+2 and the trade fails at N = 0),
  `wk_trade_not_general` (against `jsFrame []` the variant is not `mainLe`). Kept: `wk_anim_comp`, `wk_all_comp`,
  `wk_legacy_main`, `wkAnims_*`. Golden `packages/contracts/golden/engine/hero-exit.jsonl`: only WebKit RecalculateStyles and
  styleRecalcs changed, `<o` → `≤o` (7 vs 12 units). `webkit.jsonl` unchanged.
- `lean/Fw/Ops/Premise.lean`: `TestKind` page|lane (field `kind`, default page); `covered`: lane premise iff its `testId`
  (a workflow path) is in the caller's file list; `registered`/`flagged` only page premises (`not_flagged_of_lane`,
  `untested_of_lane_missing`). New premise `wktr_scroll_timeline_restyle` (webkit, lane `.github/workflows/wktr-fixtures.yml`).
  TS port `apps/runner/src/premises.ts` (`workflowFiles(root)`), golden `ops/premise.jsonl` regenerated.
- Ledgers: findings n=6 (mechanism, leanFor/leanAgainst, resolved missingWhy removed); mistakes m175.
**Regenerate:** from `lean/`: `import Fw.Parts.HeroExitOpt`, write `Fw.Parts.HeroExitOpt.goldenJsonl` to
`../packages/contracts/golden/engine/hero-exit.jsonl` via `lake env lean --run`; premise: `scripts/PremiseGolden.lean [--check]`.
**Open items (lead):**
- Hardening of m175 is not built: every row of `golden/engine/*.jsonl` should carry a `premise` id that the registry covers,
  enforced in `fw premises`. Needs a work-graph task id (the incidents ledger requires one for `partly`).
- `wktr-fixtures.yml` only summarizes; it does not fail when styleRecalcs per update ≠ (0, 1, 0). A lane premise's workflow should assert.
- Stale prose (WebKit accelerated / scroll-driven = zero web-process or style work), for the lead:
  research/notes/2026/10-18-engine-webkit-pipeline.md:42, :314, :509 (`accelerated_zero_main`, not a Lean name);
  research/notes/2026/10-18-engine-proof-design.md:198, :438; research/notes/2026/10-18-engine-gaps.md:411;
  docs/plan/PLAN.md:1178; docs/team/work-graph.json:2190 (proof-hero-exit text); maybe: optimization-inventory.md:118,
  research/kickoff/04-webkit-rendering-math.md:53, work-graph.json:2620, docs/plan/loop-plan.html:1242;
  docs/team/handoffs/proof-hero-exit.md:9,18 (names old `wk_var_exact`/`wk_trade`).
- No Lean downstream of the old theorems besides `wk_tradeE` (fixed). Math view entries for the restated theorems need re-signing.
**Read first:** HeroExitOpt module header bullet "Work, WebKit", then `wk_var_exact`, `wk_trade`, `wk_trade_not_general`.
