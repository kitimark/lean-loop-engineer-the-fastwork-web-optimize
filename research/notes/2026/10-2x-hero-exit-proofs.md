# hero.exit:threaded: the R2 style saving, the WebKit edge-frame cost, and RG11 from engine source

Tags: CONFIRMED (Lean theorem or source cited), INFERRED (reasoned, not seen). No CI or phone runs in this task.

## Answer

* Both missingWhy items of ledger row n 6 are closed by theorems in `lean/Fw/Parts/HeroExitWork.lean`, linked in the
  row's leanFor and leanAgainst. The row is `proved`. `Fw.Preset.Gen.run` regenerated the preset, and
  `hero.exit:threaded` changed from `not yet` (blocker `proofs`) to `enter`. CONFIRMED by
  `packages/contracts/golden/preset/v2-proved.decisions.jsonl` and `v2-proved.json`.
* RG11 stays a hypothesis of `consumer_eq_s`. The engine source confirms it when the track is at least 1 px taller
  than the scrollport and the scrollport keeps its height. Outside that it stays INFERRED (see RG11 below), so the
  premise row is partly CONFIRMED, not CONFIRMED.

## Item 1: the style saving with the R2 fan-out (CONFIRMED, Lean)

* The consumers are counted from the golden-linked `heroTree` (`Fw.Engine.Restyle`, golden
  `packages/contracts/golden/parts/hero.exit.scoped.json`), not by hand. `shown_consumers`: the nodes that read the
  exit values and have a box are the shown cards plus the copy and the cue, with 4 cards in the phone band and 10 above.
* `fanOut_add`: hero + consumers + fan-out = `crFull (heroTree ℓ)`, which is 99 in the phone band and 172 above.
  `crOrigR2` adds one style-only change for each fan-out element to `crOrig`.
* `cr_orig_r2`: the original keeps `crOrigPasses`, and its style units become `crFull (heroTree ℓ)`.
* `cr_style_saving`: whenever the threaded animation is on, both arms run the same number of style passes. The
  variant's style units are at most `animCount ℓ N` (`N + 3` in the phone band, `N + 4` above), which is less than
  the original's 99 or 172.
* `cr_lane_style_saving`: in the lane, the variant's units are exactly `animCount ℓ N`.
* `Fw.Measure.quarantined_unsound`, linked in leanAgainst, says the lane cannot read the saving, because only
  elementCount maps to units and it is quarantined.

## Item 2: the WebKit edge frames, a proved cost (CONFIRMED, Lean)

* `rest_iff_before`: under RG11 the consumers sit at their rest values exactly when the scroll offset is at or above
  the track top. `rest_values` gives the rest values: opacity 1 and blur radius 0.
* `opacity_edge`: the copy's, the cue's and the cards' opacity takes the `opacityCross1` row exactly when one of the two frames
  rests and the other does not. `isOpaque` flips at 1, `StyleOpacity.h:66`; the flip is Layout at
  `StyleDifference.cpp:208-214`@862f17d.
* `filter_edge` is the filter-presence clause. The variant's `exitBlur` runs `blur(0px)` to `blur(18px)`
  (`apps/site/src/parts/hero.exit/threaded.module.css:136-141`). `blur(0px)` counts for `hasFilters`
  (`StyleNonInheritedMiscData.cpp:161-164`, `StyleFilter.h:94`@862f17d), so the start and park frames never flip
  filter presence (`StyleDifference.cpp:217`). What they do flip is the zero outsets of the blur: the kernel is empty
  only at radius 0 (`FEGaussianBlur.cpp:107,112-120`), outsets are compared at `StyleDifference.cpp:68-83`, and an
  outset change is Layout at `:452-453`@862f17d.
* The phone-band copy has no blur in either arm. Its base is `filter: none` (`hero.module.css:207`), and the narrow
  variant rule has no `exitBlur` (`threaded.module.css:46-48`).
* `wk_var_no_layout`: the variant's scrolled frame does no layout.
* `wk_edge_work` and `wk_edge_layout`: the edge frame adds exactly one pass of layout, compositing update and paint.
  That pass carries `edgeCount ℓ N` units: `N + 3` in the phone band and `N + 4` above.
* `edgeFrames_eq`: along a run of frames, the edge frames are the starts plus the parks.
* `edgeFrames_le_starts`: starts ≤ edge frames ≤ 2 · starts + 1, and ≤ 2 · starts when the run begins at rest. So each
  rest-to-live switch costs at most two layout frames, its start and its park.

## RG11 from engine source

The model: `prog y = clamp01 ((y − T) / max(1, h − v))`, with T the track top, h the track height and v the viewport
height (`Fw.Parts.HeroExit.exitRange`). The variant uses `view-timeline: --hero-exit block` on the track with
`animation-range: contain` (`threaded.module.css:14,29`).

* WebKit @862f17d, CONFIRMED.
  * `ViewTimeline.cpp:322-325` reads the offset and the container size as floats (`visibleHeight()`).
  * `computeTimelineData` (`:509-511`): rangeStart = subjectOffset − containerSize, range = subjectSize +
    containerSize.
  * Contain start is rangeStart + subjectSize (`:535`), and contain end is rangeEnd − subjectSize (`:564`). The two are
    swapped when end < start (`:578-579`), which gives [T, T + h − v] for h ≥ v.
  * Progress is distance over range as a float (`ScrollTimeline.cpp:383-397`), so there is no quantum beyond float
    rounding.
* Chromium @f842f52, CONFIRMED.
  * The viewport is the scroller's `LayoutContentRect` height (`view_timeline.cc:335-341`).
  * `kContain` is the min/max of "subject start at view start" and "subject end at view end"
    (`timeline_range.cc:73-89`), the same [T, T + h − v].
  * On the compositor the offset becomes time at 16 µs per px with `ClampRound`
    (`cc/animation/scroll_timeline.cc:128-130`), a quantum of 1/16 px of offset.
* Where it matches: for h − v ≥ 1 both engines compute the model's `(y − T)/(h − v)`, within 1/16 px of offset on
  Chromium's compositor and within float rounding on WebKit. CONFIRMED.
* Where it does not, INFERRED:
  * For h − v < 1 the engines divide by h − v, while the model uses 1. At h = v WebKit has no current time
    (`ScrollTimeline.cpp:389-391`).
  * v is the scrollport (`LayoutContentRect`, `visibleHeight`), not `innerHeight`. When a dynamic toolbar changes the
    scrollport height, v moves within a gesture, and neither engine's timeline nor the model was checked for that.
* Verdict: the premise row now reads "CONFIRMED for h − v ≥ 1 with v the scrollport height; INFERRED for h − v < 1
  and a scrollport that changes height". It is not CONFIRMED as a whole.

## Gaps found, not closed here (follow-ups)

* Interior blur frames: the kernel size is an integer step of the radius (`FEGaussianBlur.cpp:107`), so its outsets
  change on many interior frames, and WebKit then lays out in both arms. INFERRED. Not modelled.
* The handover frames (`threaded.ts:132-156`, toggling `data-exit-live`) restyle once. Not modelled.

## Model fix: the cue's `exitFade` (CONFIRMED from source)

* The original's cue reads the exit opacity: its rule is `opacity: calc(var(--copy-in) * var(--exit-opacity))`, and
  the settled rule is `opacity: var(--exit-opacity)` (`snapshot/site/_app/immutable/assets/2.gBuqKVzi.css`, selector
  `.scroll-cue`). The variant's cue runs `exitFade` in both bands (`threaded.module.css:33,60`). The model had left
  the cue's opacity out of both arms.
* Fixed: `HeroExit.cueOpacity` and `Consumer.cueOpacity`, which are covered by `consumer_eq_s`. The cue's
  `cueReaders` now include opacity. `wkOrigChanges` has `2N + 5` changes. The cue's animations are opacity +
  transform in the phone band, and opacity alone above 600 px.
* Counts that changed:

  | count | phone band | above 600 px |
  |---|---|---|
  | `animCount` (was `N + 3` in both) | `N + 3` | `N + 4` |
  | Chromium compositor animations | `N + 2` (was `N + 2`) | `N + 2` (was `N + 1`) |
  | `edgeCount` | `N + 3` (was `N + 2`) | `N + 4` (was `N + 3`) |

* `cr_lane_mixed` now reads: props units `+1` in the phone band and `+2` above, style units `+0` and `+1`. Above
  600 px the CI lane's ride-along adds one style unit over the original. `cr_real_trade`, `wk_trade` and the R2 style
  saving hold as before. The golden rows use the phone band, and they are unchanged.
* The golden `settled` list (`hero-exit.threaded.jsonl`) does not include `cueOpacity`. Adding it would require
  changing the site's `threaded.ts` and `threaded.test.ts`, which are outside this task: a follow-up.

