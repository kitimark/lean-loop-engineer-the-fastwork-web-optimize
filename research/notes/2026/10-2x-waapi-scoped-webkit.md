# waapi-scoped-webkit: is `morph.tween:waapi-scoped` worth a fixed driver on WebKit?

End-of-page GPU candidate 3. The flag `morph.tween:waapi-scoped` (Lean `MorphTweenOpt`) restyles 6.8 % fewer elements in
Chromium. Real devices refuted it because it shares the waapi driver, which left the nav classes stale. This note decides
whether a fixed driver is worth building. No CI run was made; the two Simulator items are closed as premises (Items) and the
verdict rests on source (CONFIRMED lines, INFERRED consequences) and a Lean model.

## Items

| Item | Status | Evidence |
|---|---|---|
| WebKit Simulator RecalculateStyles/Layout per finish zone, scoped vs base | premise closed as finding | A Simulator touch window records no Timeline (`research/notes/2026/10-2x-sim-touch-reliable.md:46-47`, Lean `timelinePlan` `lean/Fw/Measure/TouchPush.lean:77`), so it has no record counts to compare; the record claim is the Lean model below |
| Stale nav class reproduces in the Simulator | premise closed as finding | The class bug is fixed in source: `waapi.driver.ts` writes `data-fw-morph` at push, threshold crossings and settle; Lean `MorphTweenOpt.attr_band` (`lean/Fw/Parts/MorphTweenOpt.lean:774`), old failure `old_attr_stale` :813 |
| Verdict | closed negative finding for the iPhone lag, with fix requirements | below |

Lead decision: no CI dispatch. The two Simulator items are closed as premises with the reasons above, not measured. The
recorder patch and `results/waapi-scoped-webkit/lead-commands.md` stay as the re-admission path.

## Premise check (CONFIRMED from source at HEAD)

The stale-class failure is fixed in source: `waapi.driver.ts` writes `data-fw-morph` at push, at every threshold crossing
(`MARKER_THETAS`, `waapi.logic.ts:149`) and at settle (`settleFlight`), and the nav derives `is-morphing` / `is-expanded`
from it with a MutationObserver (`nav/index.tsx:112-135`, `nav/logic.ts:55-64`). The Lean side proves the hint covers the
band (`MorphTweenOpt.lean` `fixW_ok` :695, `attr_band` :774; the old failure is `old_attr_stale` :813). What is pending is
re-admission by a trajectory probe on WebKit, not a driver rewrite. So the class bug is not a reason to close the flag.

## Why scoped cannot help the phone's felt lag (CONFIRMED source, INFERRED consequence)

1. WebKit does not accelerate a custom-property animation: `Style::Interpolation::isAccelerated` returns false for an
   `AtomString` (custom) property (`StyleInterpolation.cpp:256-265@862f17d`), and `KeyframeEffect.cpp:1740-1768` sets the
   accelerated state from it. The `--morph` tween therefore runs on the main thread in both arms; scoped keeps that.
2. What scoped changes is which elements inherit the changing property. A registered inherited custom property that
   changes marks descendants `Change::Inherited` (`StyleInheritedRareData.cpp:352`, `StyleComputedStyle.cpp:285-296`,
   `StyleChange.cpp:36-88`); the non-inherited `--platform-morph` removes the platform subtree from that walk
   (`10-20-tween-platform-scope.md`). That saves element visits inside one RecalculateStyles record. The number of records
   per frame is unchanged (INFERRED; the Chromium -6.8 % is elements, not records).
3. The WebKit lag is main-thread work per frame plus compositor stalls (`10-20-webkit-lag-source.md:16`); an element-count
   cut inside an unchanged record count is the smallest lever of the set, and the pill and nav need the same driver
   frames in both arms.
4. The shared driver has a separate WebKit defect: on macOS WebKit 1280 the nav `width` transition at the `is-morphing`
   flip is lost in 15 of 15 cand reps (`10-21-waapi-tail-webkit.md` phase 2, run 39573516482). The lead decision
   `waapi-tail-drop` owns it. A scoped driver inherits it.

## Verdict

Not worth a dedicated fixed driver for the iPhone lag. Close the candidate as a negative finding: a change that trims elements per style recalc does not change the main-thread tween cost on WebKit when the
property is not accelerated and the record count per frame stays. General lesson: a Chromium restyled-element count is
a Chromium result; on WebKit, rank a flag by records and compositor work, which a count of elements does not show.

Requirements if the lead still wants scoped re-admitted (each with its reason):

| Requirement | Reason |
|---|---|
| Class publishing stays as in `waapi.driver.ts` (push, threshold crossings, settle) | `fixW_ok`, `attr_band`; no change needed |
| A WebKit decision on the width tail first (`waapi-tail-drop`) | 15 of 15 reps lost the transition on macOS 1280 |
| One trajectory-probe re-admission run on WebKit for the arm `morph.tween:waapi-scoped` | a flag needs its class sequence per engine before it joins a preset |
| A mid-morph class sampler in the Simulator recorder (patch provided) | an end-of-window read cannot show a stale class |
| macOS WebKit RecalculateStyles/Layout per zone, scoped vs base, 3 runs on separate jobs | only lane with counts and a morph push |

## Limits

- No Simulator or CI number was produced; the Simulator is not the phone.
- Point 2 and 3 are INFERRED from source; no WebKit timeline record count for scoped vs base exists yet.

## Lean (why-module `lean/Fw/Measure/WaapiScopedWebkit.lean`)

A model of one WebKit frame of the `--morph` tween over `StyleInterpolation.cpp:256-265` and `KeyframeEffect.cpp:1740-1768`
(both @862f17d). `records accelerated visit` is one record when the property is not accelerated, none when it is.

| Theorem | Says |
|---|---|
| `records_len_eq`, `records_len_one` | not accelerated: both arms have the same record count per frame (one) |
| `records_accelerated` | accelerated: no main-thread record in either arm (the other branch; not the `--morph` case) |
| `scoped_subset`, `scoped_avoids` | scoped visits a subset of base's elements and no platform element: the only change |
| `visited_le` | scoped visits no more elements than base in a frame |
| `fewer_visits_equal_records` | witness: fewer visits with equal records, so element count and record count are separate |

The record-per-frame claim is a model over WebKit source, not a measurement. The ledger row is `morph.tween.waapiScoped` (notes of task `waapi-scoped-webkit`).
