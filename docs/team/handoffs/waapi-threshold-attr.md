# waapi-threshold-attr handoff

State: branch `worktree-wf_be3f7e90-9a2-2` (round 2 commit on top of 4abe6e5c); `ci/waapi-threshold-attr` = merge c05acefd. `sh lean/scripts/check.sh` green.

Verified:
- Lean `lean/Fw/Parts/MorphTweenOpt.lean`: `attrReaders` (9 readers), `AttrScene`, `stepAttr`/`runAttr`, `oldW`/`fixW`; proved `fixW_ok`, `attr_band`, `dlLo_sound`, `waapi_vis` over `AttrScene` (both arms share `fixW` and `attrReaders`); counterexample `old_attr_stale`.
- `stepAttr` premise, not proved: marker finish events and frame callbacks run before the frame's style and layout (`page_animator.cc:292-311,335`@f842f52; WebKit `Page.cpp:2308,2330,2337`@862f17d).
- Golden `packages/contracts/golden/parts/morph-tween-waapi.attr.jsonl`; `waapi.golden.test.ts` replays it for both arms.
- Driver `waapi.driver.ts`: writes `data-fw-morph` at push, via a marker per threshold ahead (`onMarker` :133, poll :124 until strictly past), at finish.
- Cost, INFERRED from the fake replay (holds only under the premise above): script runs on 7 of 42 frames (open), 13 of 64 (reverse at 300 ms).
- CI, MEASURED (A/A 39466378530): bug B's 205 Chromium nav/logo units (39412301221) drop to 0 class or logo units.
  - waapi: 39449092483, 39453458295, 39471466367. waapi-scoped: 39457767229, 39462241403, 39472304195.
  - Chromium and macOS WebKit, but macOS waapi-scoped covers only 390/641.
- Lean outcomes: chromium hero pass, chromium morph fail; linux-webkit hero pass, linux-webkit morph no verdict: coverage. 39471466367: mac-webkit hero pass, mac-webkit morph fail. 39472304195: mac-webkit no verdict: widths.
- The morph fails come only from nav.background-color repeats plus earn row F, which are reported, not counted.
  - nav.background-color: the original's oklab transition is read raw by kit.mjs `colour()` against rgb. In sRGB it is in band at most widths; residual ≤ 7.2/255 (INFERRED: no post-morph background ease).

Open:
- macOS waapi-scoped 640/1280 cell: `pnpm -s fw run --trajectory --ref ci/waapi-threshold-attr --fw morph.tween:waapi-scoped --engines both`.
- kit.mjs `colour()` must parse oklab and compare in sRGB, then re-run the morph outcome. Also judge the missing background ease.
- Re-admission is owned by trajectory-admission (fResult stays model-bug).

Conventions:
- Regenerate the attr golden via `attrJsonl ()` with the `include_str` guard off.
- The lead regenerates the footprint goldens at land.
- Scratch outcome script: storedOf + outcome over downloaded artifact dirs.

Read first: MorphTweenOpt.lean from `attrReaders` to `waapi_vis`, then the ledger row morph.tween.waapi.falsified.
