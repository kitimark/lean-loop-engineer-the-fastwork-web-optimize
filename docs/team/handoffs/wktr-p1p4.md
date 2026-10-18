# Handoff: wktr-p1p4 (do goldens P1/P4 "scrollDriven style = 0" hold on WebKit?)
**Answer: no.** WebKit restyles once per rendering update when a transform animation runs on `scroll()`; goldens were wrong.
MEASURED (WKTR iOS 26.5 Simulator, macos-26, CI run 39075991405, 3 jobs x 3 passes, fwcore classes kMax 4 / tMax 24):
| fixture | styleRecalcs per rendering update | class |
|---|---|---|
| control (scroll only) | 0 (0 of 53; 0 of 159) | deterministic |
| scroll-timeline (`animation-timeline: scroll(root)`, transform) | 1 (53 of 53; 159 of 159 with 2 idle updates) | deterministic |
| time-accel (document timeline, transform, accelerated) | 0 (0 of 53; 0 of 159); ev_animActive 53 | deterministic |
| scroll-js-transform / -bg (rAF-free scroll handler writes) | 0.74 to 0.93 | quarantined |
**State:** branch `ci/wktr-p1p4` (commit sha in the report). Done: fixtures + `.github/workflows/wktr-fixtures.yml`
(`pnpm fw ci wait --workflow wktr-fixtures`); `lean/Fw/Engine/WebKit.lean` golden block rebased on `webkitX`
(`withAnim`, `scrollStepX`, `lift_scrollStep`), premise `WktrStyleRate.Holds`, theorems `style_rate_model` and
`style_rate_old_refuted`; `packages/contracts/golden/engine/webkit.jsonl` regenerated (only 2 rows: P1 RecalculateStyles and
P4 styleRecalcs of `scrollDriven`, `=0` to `=o`); `research/findings/ledger.json` (n=10, hero.exit n=6, cd-roll-ca n=8, n=23).
check.sh green. Regenerate: `import Fw.Engine.WebKit` + `IO.FS.writeFile "../packages/contracts/golden/engine/webkit.jsonl"
Fw.Engine.WebKit.goldenJsonl`, `lake env lean --run` from `lean/`.
**Parts impact (not edited; why-parts owns `lean/Fw/Parts/**`):** only `HeroExitOpt` uses a scroll timeline on WebKit.
- False as stated: `wkVar_eq`, `wk_var_exact` (style passes 1, units N+3, not 0), `wk_trade` for every `cs` (holds at `cs = wkOrigChanges`).
- Still true: `wk_anim_comp`, `wk_all_comp`, `wk_legacy_main`, `wkAnims_*`. `goldenRows` guards `RecalculateStyles`/`styleRecalcs` `<o` fail once rebuilt on `webkitX`.
- Expected verdict change (scratch computation, gN=4 phone band): `hero-exit.jsonl` webkit RecalculateStyles and styleRecalcs `<o` become `<=o`
  (scroll frame 1 vs 1 passes, units 7 vs 12; idle frame has no update); all other WebKit rows and the claim (trade) unchanged.
- `HiddenPause`/`MorphTweenOpt` (`compFrame_zero`, `anim_comp_zero`): time timelines, CONFIRMED by the time-accel arm. Not affected.
**Open:** (1) premise registry: `Fw/Ops/Premise.lean` is on main (not in this branch, not in my writes). Add id `wktr_scroll_timeline_restyle`, theorems
`Fw.Engine.WebKit.style_rate_model`, `style_rate_old_refuted`, engine webkit. Its test cannot be a Playwright page (no `internals.styleRecalcCount`):
the test is the WKTR lane `wktr-fixtures.yml`; the lead decides how the registry names a non-Playwright test.
(2) why-parts rebuilds `wkVar`/`wkFrames` on `webkitX` and regenerates `hero-exit.jsonl`. (3) Optional: JS arms at `--frames 3` (not run).
**Outside the listed writes (needed to run CI):** `.github/workflows/wktr-fixtures.yml`, one `paths` line in `wktr.yml` (`!packages/measure-wktr/fixtures/**`).
**Read first:** `Fw.Engine.WebKit` section "The WKTR fixtures", `packages/measure-wktr/fixtures/run.sh`, ledger n=10.
