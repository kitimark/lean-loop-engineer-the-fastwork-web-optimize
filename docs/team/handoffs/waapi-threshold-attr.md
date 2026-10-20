# waapi-threshold-attr handoff

State: branch `worktree-wf_be3f7e90-9a2-2`, round 3 (doc-only) on top of cf26bbc0 plus a merge of main; `sh lean/scripts/check.sh` green.

Verified:
- Lean `lean/Fw/Parts/MorphTweenOpt.lean`: `attrReaders`, `AttrScene`, `stepAttr`/`runAttr`, `oldW`/`fixW`; proved `fixW_ok`, `attr_band`, `dlLo_sound`, `waapi_vis` (both arms share `fixW` and `attrReaders`); counterexample `old_attr_stale`.
- `stepAttr` premise, not proved: marker finish events and frame callbacks run before style and layout (`page_animator.cc:292-311,335`@f842f52; WebKit `Page.cpp:2308,2330,2337`@862f17d).
- Golden `packages/contracts/golden/parts/morph-tween-waapi.attr.jsonl`, replayed for both arms by `waapi.golden.test.ts`. Cost INFERRED from the fake replay: script on 7 of 42 frames (open), 13 of 64 (reverse at 300 ms).
- CI, MEASURED (A/A 39466378530): bug B (205 Chromium nav/logo units, 39412301221) is gone on Chromium and macOS WebKit, cell by cell:
  - Chromium waapi (39449092483, 39453458295, 39471466367) and waapi-scoped (39457767229, 39462241403, 39472304195), all widths.
  - macOS WebKit waapi 390/640/641/1280 (39471466367); waapi-scoped 390/641 (39472304195).
  - macOS waapi-scoped 640/1280 not measured (hosted runner cancelled, 39472304195); INFERRED from the shared nav path (`waapi.driver.ts:177` navKeyframes takes no arm); MEASURED at trajectory-admission (required dispatch).
- nav.background-color units: pre-existing waapi difference, also before the fix (39412301221: 4 close@0 units), not bug B; partly the kit.mjs oklab artefact; residual ≤ 7.2/255 OPEN under kit-colour-space.
- Linux WebKit (not in the unit, no verdict); each run's `summary-playwright-webkit.md` as run :line:
  - (a) settled-sample artefact, in 1 of 2 runs per variant (each 3 reps): 39449092483 at 640 (nav.cls.is-morphing :62, logo.position :75, logo.transform-origin :76, panel.attr.data-start-selling-scene :93); 39457767229 at 390 (nav.cls.is-morphing :20, nav.rect :25, nav.backdrop-filter.num :30, logo.position :33, logo.transform-origin :34, logo.rect-in-nav :35, panel.attr.data-start-selling-scene :51), all close@0. Orig close never reaches m = 0 there (frame gap 173/411 ms p50/p90, 39449092483 :191); the reducer judges the settled candidate sample against it (`reduce.mjs:34,108`; `Trajectory.lean:231` windowOne, `:282` bucketVerdict). Follow-up trajectory-settled-sample.
  - (b) width tail, OPEN, not bug B: 1280 nav.rect :151, nav.transform.shift :158 close@0 in 39457767229 and 39462241403; the driver skips orig's post-flip nav width ease (orig/base up to 53 px wide at settled frames, candidate final, also before the fix 39412301221). Follow-up waapi-nav-width-tail.
  - (c) colour, pre-existing: nav.background-color and logo.color close@0 (:27, :36; also 39412301221 :26, :35). OPEN under kit-colour-space.
  - Not split: earn.* (row F, also in the A/A); actions.gap (39453458295 :167, 39462241403 :41, :83), OPEN.
- Lean outcomes: chromium hero pass, morph fail (nav.background-color, earn row F); linux-webkit morph no verdict: coverage; 39471466367 mac-webkit hero pass, morph fail; 39472304195 mac-webkit no verdict: widths.

Open: kit.mjs `colour()` must parse oklab and compare in sRGB (kit-colour-space); re-admission and the macOS waapi-scoped 640/1280 cell belong to trajectory-admission (fResult stays model-bug); trajectory-settled-sample; waapi-nav-width-tail.

Conventions: regenerate the attr golden via `attrJsonl ()` with the `include_str` guard off; the lead regenerates the footprint goldens at land.

Read first: MorphTweenOpt.lean from `attrReaders` to `waapi_vis`, then the ledger rows morph.tween.waapi.falsified and morph.tween.waapiScoped.falsified.
