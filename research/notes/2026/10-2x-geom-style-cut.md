# geom-style-cut: the flip's per-frame style writes, which have a reader and which do not

Status: PARKED, not landed (lead 2026-10-28). Negative result: a Lean-proved removal of the tween's dead per-frame writes; Chromium elements per recalc -1.7 %, recalc count unchanged, WebKit not shown. Review: it adds tween-to-geom coupling and a leave-order invariant that broke once (run 40589409628), and its WebKit A4 1440x900 failure (run 40595877403, covered=false) is not reproduced without the cut. Code stays on branch worktree-wf_2ebef0df-5ee-1 (a8962c52e).

Question: phone-flip-p95 found 99 % of the flip arms' main-busy long frames are `RecalculateStyles` (36 and 45 ms per long frame against 10 ms
in the base) behind a native `setProperty`. Which per-frame writes of the tween run in geom mode, who reads them, and can the dead ones go with the
same look? Branch ci/geom-style-cut, Lean `lean/Fw/Parts/MorphStyle.lean`, golden `packages/contracts/golden/parts/morph-style.jsonl`.

## The writes per frame (MEASURED, deterministic jsdom probe of the real MorphTween; results/geom-style-cut/writes.json)
`apps/site/src/parts/morph.tween/style.probe.test.ts` renders `MorphTween`, wraps `CSSStyleDeclaration.setProperty`, records attribute
mutations, pushes once with a wheel event and steps 48 frames at 60 Hz. It is a test (jsdom, no layout), not a CI measurement.

| mode | writes per frame | writer, property, element |
|---|---|---|
| base | 3 (124 in 48 frames) | `publish`: `--morph` and `data-fw-morph` on the nav; `updateFade`: `--morph-fade` on the platform |
| flip, tween as on main | 3 (124) | the same three |
| flip, after the cut | 1 (42) | `data-fw-morph` on the nav only |

Not per frame (checked in source): `morph.columns` writes `--cs-cf/--cs-a/--cs-d` on resize only (index.tsx:112-114); the panel writer writes
`data-start-selling-scene`, `aria-hidden`, `data-expanded` and `tabindex` only at the 0.001, 0.35, 0.55 and 0.92 crossings
(morph.panel/driver.ts:19-34); `classList.toggle` with an unchanged value in nav and nav.hitTest changes nothing; `morph.stage` publishes
only in the scroll-driven stage variant. In `geom-timed` the tween has no frame loop after the take: it publishes at the start, at each crossing and at the end
(geom-timed.driver.test.ts), so the per-frame writes are an `faithful`-tween-with-geom cost; geom-timed's style cost has another source (below).

## Consumers per mode (CONFIRMED in source, Lean `consumers`)
- `--morph` inline on the nav: read by `var(--morph)` in nav.module.css, box.module.css, morph.panel/morph.module.css and morph.columns/morph.module.css
  (all inside the nav). In flip mode `.is-flip [data-fw='nav'] { --morph: 1 !important }` (morph.geom/geom.css:22-23) wins over the inline value:
  no reader. Skipped while the flip is on and m > 0.
- `--morph-fade` inline on the platform: read only by `opacity` and `filter` of platform.module.css:12-13. The `platform` tracks (morph.geom/tracks.ts:177-178)
  animate exactly those two properties (fill both; the goal stylesheet after a timed settle): no reader. Skipped under the same rule.
- `data-fw-morph` on the nav: read by the three observers (nav/index.tsx:113, nav.hitTest/index.tsx:32, morph.geom/index.tsx:89) and by
  `panel.closest` at mount; no CSS selector names it. Kept (the geom driver is driven by it). It costs script, not style: Blink only schedules a recalc for an
  attribute when a rule set names it (style_engine.cc:1903-1944@f842f52, `CollectInvalidationSetsForAttribute`, then `HasAttributeDependentStyle`).

`@property` with `inherits: false` for `--morph-fade` was considered and rejected: in flip mode the write has no reader, so skipping it narrows more than
registration would, and in base mode the look must not change. `--morph` has many descendant readers in base mode, so it cannot become non-inherited.

## Why a skipped write is cheaper (engine source, CONFIRMED/INFERRED)
- Blink: an inherited custom property that differs between old and new style, on an element whose style uses variables, makes the difference `kInherited` and
  the children are recomputed (style/computed_style.cc:468-475@f842f52). When the computed value does not change (the nav under the `!important` override) the
  element recalculates alone. CONFIRMED.
- WebKit: `determineChanges` adds `Change::Inherited` when `nonFastPathInheritedEqual` is false (style/StyleChange.cpp:39-43@862f17d), and that compares
  `m_inheritedRareData` (style/computed/StyleComputedStyle.cpp:285-297), which holds the custom properties. So a changed inherited `--morph-fade` on the platform section
  re-resolves its whole subtree every frame. CONFIRMED for the change flag, INFERRED for the custom-property map being part of the equality.

## Lean (CONFIRMED, proved)
`seen_same`: for every flip state, every m and every previously stored value, a reader of a skippable write sees the same value with the skip as with a
write at every frame. `base_writes`: flip off writes every frame (base unchanged). `leave_writes`, `skip_iff`: the skip is exactly flip and m > 0.
`skippable_navMorph/platFade`, `not_skippable_navAttr`: the consumer table. `leave_flush`, `leave_flush_stale`: the flush inside `leave` reads the stored value, so it must
be current (below). `saved_le`, `saved_base`: the saving is bounded and zero in the base. TS twin `style.logic.ts`, golden test `style.golden.test.ts` (also reads
the CSS files and checks the Lean reader table against them).

## A bug the first CI run found, and the leave fix (MEASURED)
Run 40589409628 (sha 295c32121, the cut without a leave write): flip cell `morph.geom:on` passes on both engines, but flip verify A4 (quiet leave) fails on 9 of 12 bands on
Chromium (WebKit also fails the step). The comparable run before the change, 40566917070 (sha fa1a0d8a1, morph.tween untouched), passes every flip step. Cause (INFERRED from
tree.ts:137-156): in the timed path `mark` calls `timed.settle(0)` (which runs `leave`: class off, `getBoundingClientRect` flush) before `publish(0)`; with the writes skipped the
inline `--morph` is stale at that flush and the nav transitions to 0 afterwards (A4 reads background-color and width moving for 49 frames). Fix (commit a8962c52e): `settleTimed` in
driver.ts writes `--morph` and `--morph-fade` for m = 0 before the settle when the flip class is on; test style.driver.test.ts.

Run 40595877403 (breakpoint-gate dispatched on ci/geom-style-cut, sha a8962c52e, checked with git ls-remote), flip-cell job:
- Chromium: flip cell, flip verify A3a, A4, A5 pass on all 12 bands, and the two repeat passes (3 bands each) pass. The leave fix cures the A4 failure on Chromium.
- WebKit (Playwright, Linux): flip cell, A3a and A5 pass on 12 of 12 bands. A4 fails on one band, 1440x900: the second leave's window holds 1 frame (`covered: false`, the
  recorder needs 800 ms) while the readings in it are quiet (`moving 0`, `maxDev 0`, `maxBgDist 0`). The repeats on 390x844, 1280x800 and 1920x1080 pass. This is a missing window,
  not a moving nav (INFERRED: a capture that ended early); with the dispatch limit there is no second run to tell a flake from a pattern. The pinned unit asks A4 on both engines, so
  WebKit A4 is 11 of 12 bands here and the unit is not met on that engine.

## CI numbers
### Chromium counts (MEASURED, swipe-touch-v1, `target=rewrite`, `fw=morph.geom:on`, 3 runs on separate VMs, 771 frames per run; results/geom-style-cut/chromium-{before,after}-run.json, reducer reduce.mjs)
Before = run 40595881712 on ci/land-phone-flip-p95-8ddad95 (sha 05f588951, no file differs from main 8ddad950b). After = run 40595886260 on ci/geom-style-cut (a8962c52e).

| | RecalcStyleCount | UpdateLayoutTree events | ScheduleStyleRecalculation | elementCount sum | peak elementCount |
|---|---|---|---|---|---|
| before (3 runs) | 2381, 2385, 2381 | 2398, 2402, 2398 | 2414, 2418, 2414 | 61475, 61556, 61470 | 1195-1279 |
| after (3 runs) | 2381, 2381, 2385 | 2398, 2398, 2402 | 2414, 2414, 2418 | 60491, 60447, 60539 | 1195-1279 |

- The number of style recalculations does not change (identical in total; the per-frame class of RecalcStyleCount is stable at 4 in both arms, classes.txt of each run). The cut does not remove a recalculation per frame.
  Cause (INFERRED, not measured): the per-frame recalcs come from the morph.geom WAAPI tracks that Chromium samples on the main thread (for example the platform filter, platform/part.json limit), not from the data-fw-morph attribute, which no selector names (lines 30-31).
- The elements the recalculations walk fall by about 1000 of 61500 (-1.7 %), from 61470-61556 to 60447-60539; the spread inside an arm is at most 92, so the step is real on these counts.
  The per-frame class of elementCount is quarantined in both arms (k 36 before, 61 after; policy kMax 4), so the sum is a total over frames, not a per-frame claim.
- The counts lane counts calls and elements, not time, and does not throttle (no 6x lane exists). A time claim for the phone is not made here.
- geom-timed: chromium-counts takes one fw string, so no geom-timed arm was dispatched; the CI 2 run 40589409521 (sha 295c32121, cut build only) has it: RecalcStyleCount 2383-2388, elementCount sum 58544-58643 (results/geom-style-cut/chromium-after.json).

### WebKit Simulator (MEASURED, scroll sweep of the webkit-sim lane; results/geom-style-cut/reduce-webkit.mjs)
After = run 40595890762 (webkit-sim dispatched on ci/geom-style-cut, a8962c52e, `target=rewrite`, `fw=morph.geom:on`). The run was cancelled in its VM 1 job, so two VMs (2 passes each) exist.
Before = run 40454309560 (ci/morph-timed, sha 7fe3e525e, fw=morph.geom:on, 3 VMs, 2 passes each). Its site code differs from main 8ddad95 on the geom:on path: morph.geom adds the veil track, the quiet leave flush and 20 lines of geom.css (git diff 7fe3e525e 8ddad950b). The comparison therefore mixes the cut with those changes and shows nothing about the cut alone (MEASURED counts, confounded).

| | RecalculateStyles per sweep (passes) | ScheduleStyleRecalculation | steps |
|---|---|---|---|
| before | 678, 699, 678, 681, 651, 652 (mean 673) | 636, 654, 638, 643, 613, 618 | 106-107 |
| after | 649, 649, 662, 659 (mean 655) | 619, 619, 622, 624 | 106-107 |

- The mean is 18 lower (-2.7 %) but the passes of the before arm span 651-699 and the after arm 649-662: the ranges overlap and the difference is not larger than the spread, so WebKit shows no
  change that this data can tell from noise. Per step the mean difference is under 1.6 calls in every step; nothing concentrates at one scroll position. The sweep scrolls the page and
  does not push the morph, so the flip frames are a small part of what it counts (INFERRED); a push profile on the Simulator does not exist yet.

## Does the cut lower per-frame style work?
- Chromium: it lowers the elements per recalculation total by 1.7 % and does not lower the number of recalculations. MEASURED, 3 runs per side.
- WebKit: not shown; the before run is on other geom code and the difference is within the spread.
- Time: not measured (no throttled lane, no phone run). The main-thread cost on the phone that phone-flip-p95 found stays attributed to the geom WAAPI tracks sampled each frame (INFERRED), not to the dead writes this cut removed.

## What this leaves open
- geom-timed's style cost (348 of 396 long frames, 364 with no script stack): after the take the tween writes nothing per frame, so the cost is probably (INFERRED) the WAAPI tracks the geom driver
  creates (animation ticks on non-compositable properties), in morph.geom/** (task geom-image-model is parked there). Follow-up task.
- WebKit flip verify A4 at 1440x900 (window of 1 frame): rerun the breakpoint-gate on ci/geom-style-cut to tell a flake from a pattern.
- A WebKit before run on main's code and a flip-push profile on the Simulator.
