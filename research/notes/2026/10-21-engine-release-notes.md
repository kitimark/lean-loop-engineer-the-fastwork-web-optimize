---
id: 2026-10-21-engine-release-notes
kind: note
title: "engine-release-notes: no Safari 26.0-27.2 note or Chrome 156 entry fixes the hero.exit:scoped freeze; it is open WebKit bug 325900 (with 321094), unfixed on main through 318999, so the redesign must not wait for an engine fix"
status: draft
created: 2026-10-21
topics: [webkit, chromium, release-notes, waapi, custom-properties, matched-declarations-cache, hero.exit, morph.tween, nav, premises]
---

# Engine release notes, mapped to flags and premises

## Answer

- **hero.exit:scoped.** The WebKit freeze we hit is filed upstream as bug 325900, "Explicit `inherit` of a non-inherited registered custom property resolves to a stale or sibling value". It is NEW and has no fix (CONFIRMED, https://bugs.webkit.org/show_bug.cgi?id=325900). The report's matrix has Chromium 150 and 154 and Firefox 156 passing the same case (CONFIRMED, 325900 comment 0). Our Chromium pin 156 was not tested there; it should pass because Blink's cache guard refuses the hit (INFERRED, `matched_properties_cache.cc:200-216@f842f52`). Bug 321094 is the `var()` reader half and is also NEW (CONFIRMED, https://bugs.webkit.org/show_bug.cgi?id=321094). None of the Safari 26.0, 26.1, 26.2, 26.3, 26.4, 26.5, 26.6, 27.0 or 27.2 beta notes mentions either bug (MEASURED: 0 hits in the nine DocC JSON files listed below). The search keys were the bug ids and their radars: 189482288 (325900), 184130578 (321094) and 184017733 (320984), from the `rdar://` lines in each bug. A positive control, radar 158919736 from W10, gets 1 hit. The redesign therefore cannot rely on an engine fix.
- **Partial fix.** The only fix is bug 320984 at 318999@main. It re-applies the custom property itself but not its `var()` readers (CONFIRMED, 321094 comment 2). 318999 is above the 27.0.x branch point 316606@main, so it is in neither our WebKit pin nor Safari 27.0.1 unless it was cherry-picked, and no branch commit is listed (INFERRED).
- **The 13.1 post, three questions.** The post names no accelerated properties. It does not mention custom properties. It says animations are processed "at the next most opportune moment with no need to force a style invalidation", with CSS animations, CSS transitions and WAAPI "in sync" on one shared engine (CONFIRMED, https://webkit.org/blog/10266/web-animations-in-safari-13-1/). The concrete answers come from source at 862f17d, in the Q&A section below.
- **Nav bug.** On the update path, WAAPI writes only the target's computed style. `KeyframeEffect::apply` and `setAnimatedPropertiesInStyle` take a `Style::ComputedStyle&` and write nothing else (CONFIRMED, `Source/WebCore/animation/KeyframeEffect.cpp:1644-1668,1842-1934@862f17d`). The only attribute write in `Source/WebCore/animation/` is the `style` attribute in `commitStyles()` (CONFIRMED, `WebAnimation.cpp:1793-1915`, write at :1912, the single `setAttribute` hit in that directory). `apps/site/src` never calls `commitStyles` (CONFIRMED, grep). So the stale `data-fw-morph`, `is-morphing` and `is-on-dark` state is a fault in our code, and no engine release changes that (INFERRED from the above).
- **Chrome 156.** Chrome Status lists 11 entries at milestone 156, and none touches animation, custom properties or style caching (CONFIRMED, https://chromestatus.com/api/v0/features?q=browsers.chrome.desktop=156). Blink's matched properties cache refuses a hit under explicit inheritance when the parents' non-inherited data differ (CONFIRMED, `third_party/blink/renderer/core/css/resolver/matched_properties_cache.cc:200-216@f842f52`). That data includes `NonInheritedVariables`, a field with no `inherited` flag (INFERRED, `third_party/blink/renderer/core/style/computed_style_extra_fields.json5:730-740@f842f52`). The Chromium tracker has no open issue matching either mechanism (INFERRED from titles, queries in §4).

Version rule used below: every Safari 27.0.x build is cut from 316606@main. Our pin 862f17d is 316606.322@safari-7625.1.29.10-branch, and the newest tags 7625.1.29.11.27 and 7625.1.29.18.27 are 316606.369 and 316606.373 (CONFIRMED, https://commits.webkit.org/316606@main and the tag identifiers). A main fix at or below 316606 is in the pin and in 27.0.1. A main fix above it is in neither unless it was cherry-picked (INFERRED).

## 1. Index

| # | URL | Engine | Version | Date | Feature (status) |
|---|---|---|---|---|---|
| W1 | https://webkit.org/blog/10266/web-animations-in-safari-13-1/ | WebKit | Safari 13.1 | 2020-04-08 | WAAPI ships; one shared engine for CSS animations, CSS transitions and WAAPI (CONFIRMED) |
| W2 | https://webkit.org/blog/8343/ | WebKit | STP | 2018-06-20 | "Web Animations in WebKit": WAAPI avoids forced style invalidation (CONFIRMED) |
| W3 | https://webkit.org/blog/12445/new-webkit-features-in-safari-15-4/ | WebKit | 15.4 | 2022-03-14 | `contain`, all four types (CONFIRMED) |
| W4 | https://webkit.org/blog/13152/webkit-features-in-safari-16-0/ | WebKit | 16.0 | 2022-09-12 | size container queries (CONFIRMED) |
| W5 | https://webkit.org/blog/13966/webkit-features-in-safari-16-4/ | WebKit | 16.4 | 2023-03-27 | `@property`, Properties and Values API (CONFIRMED) |
| W6 | https://webkit.org/blog/15865/webkit-features-in-safari-18-0/ | WebKit | 18.0 | 2024-09-16 | `content-visibility`; unprefixed `backdrop-filter` (CONFIRMED) |
| W7 | https://webkit.org/blog/17101/a-guide-to-scroll-driven-animations-with-just-css/ | WebKit | 26 beta | 2025-06-20 | scroll-driven animations guide (CONFIRMED) |
| W8 | https://webkit.org/blog/17333/webkit-features-in-safari-26-0/ and https://developer.apple.com/documentation/safari-release-notes/safari-26-release-notes | WebKit | 26.0 (20622.1.22) | 2025-09-15 | scroll-driven animations (144887859); "inherit" as a var() fallback (136463977); content-visibility fixes (141237620, 148273903, 148553259, 148663896); will-change fixes (146281670, 146292698); accelerated-action time offset (142604875) (CONFIRMED) |
| W9 | https://webkit.org/blog/17541/ and .../safari-26_1-release-notes | WebKit | 26.1 (20622.2.11) | 2025-11-03 | container query with position-try (158880410) (CONFIRMED) |
| W10 | https://webkit.org/blog/17640/ and .../safari-26_2-release-notes | WebKit | 26.2 (20623.1.14) | 2025-12-12 | commitStyles commits custom properties (158919736); commitStyles on finished animations (158684709); `contain: layout` baseline (159007878); tree-scoped container-name (160696378) (CONFIRMED) |
| W11 | https://webkit.org/blog/17798/ and .../safari-26_3-release-notes | WebKit | 26.3 (20623.2.7) | 2026-02-11 | style resolution loop with position-try (163691885) (CONFIRMED) |
| W12 | https://webkit.org/blog/17862/ and .../safari-26_4-release-notes | WebKit | 26.4 (20624.1.16) | 2026-03-24 | threaded scroll-driven animations (168027635); `@property` initial-value optional (131288198); name-only `@container` (164648718) (CONFIRMED) |
| W13 | https://webkit.org/blog/17938/ and .../safari-26_5-release-notes | WebKit | 26.5 (20624.2.5) | 2026-05-11 | scroll-driven fixes (171630023, 171630127) (CONFIRMED) |
| W14 | https://webkit.org/blog/18178/ and .../safari-26_6-release-notes | WebKit | 26.6 (20624.4.5) | 2026-07-27 | nothing on our features (CONFIRMED) |
| W15 | https://webkit.org/blog/18325/ and .../safari-27-release-notes | WebKit | 27.0 (20625.1.29) | blog 2026-09-17, notes 2026-09-14 | `.animation` on AnimationEvent (176527591); fill-mode viewport units (80075191); !important vs animation (174367827); perspective-origin var() (131288246); var() fallback only on guaranteed-invalid (181114298); `contain: layout` forced-layout cost (171545381); style query default custom value (165627262); will-change serialization (175482352); view-transition stale accelerated transform (173323193); :has() invalidation fixes (CONFIRMED) |
| W16 | (no notes page) | WebKit | 27.0.1 | n/a | Apple's index lists no 27.0.1 notes (CONFIRMED, index JSON); the macOS build is 22625.1.29.11.28 per the bug 327925 report (CONFIRMED) |
| W17 | https://developer.apple.com/documentation/safari-release-notes/safari-27_2-release-notes | WebKit | 27.2 beta (20625.2.8) | 2026-10-13 | animation-range with zoom (185760120); nothing on custom properties (CONFIRMED) |
| C1 | https://chromestatus.com/feature/5640265926705152 | Blink | M78 | n/a | Properties and Values API, `registerProperty` (CONFIRMED) |
| C2 | https://chromestatus.com/feature/5193698449031168 | Blink | M85 | n/a | `@property` (CONFIRMED) |
| C3 | https://chromestatus.com/feature/5126405660606464 | Blink | M84 | n/a | Web Animations API (commitStyles and related) (CONFIRMED) |
| C4 | https://chromestatus.com/feature/4613920211861504 | Blink | M85 | n/a | `content-visibility` (CONFIRMED) |
| C5 | https://chromestatus.com/feature/6522186978295808 | Blink | M52 | n/a | CSS Containment (CONFIRMED) |
| C6 | https://chromestatus.com/feature/6525308435955712 and /5076875399921664 | Blink | M105, M111 | n/a | container queries; style queries on custom properties (CONFIRMED) |
| C7 | https://chromestatus.com/feature/5679432723333120 | Blink | M76 | n/a | `backdrop-filter` (CONFIRMED) |
| C8 | https://chromestatus.com/feature/6752840701706240 | Blink | M115 | n/a | scroll-driven animations (CONFIRMED) |
| C9 | https://chromestatus.com/feature/5083257285378048 and /6046278267043840 | Blink | M133; M151 proposed | n/a | `Animation.overallProgress` (shipped M133); `.animation` on events, the twin of W15, status Proposed at M151, so not shipped (CONFIRMED) |
| C10 | https://chromestatus.com/feature/5168674259468288 | Blink | M159, proposed | n/a | optional `@property` descriptors, the twin of W12 131288198 (CONFIRMED) |
| C11 | https://developer.chrome.com/blog/chrome-156-beta | Blink | 156 beta; pin 156.0.8078.4 = f842f52 | 2026-09-30 | a stub post that points to Chrome Status, where none of the 11 milestone-156 entries touches our features (CONFIRMED) |

Search gaps:
- I found no WebKit post on `will-change` and no post on style invalidation or the matched declarations cache (OPEN; queries "webkit.org blog will-change", "webkit.org blog style invalidation").
- I did not resolve the `will-change` chromestatus entry because the search timed out (OPEN).
- The blog posts W9 through W15 are cited by post number only.

## 2. Mapping (flag, Lean premise or theorem, verdict)

| Source item | Flag (`apps/site/src/parts/*/part.json`) | Lean | Verdict and reason |
|---|---|---|---|
| bug 325900, bug 321094 | hero.exit:scoped | `HeroExitOpt.consumer_eq_scoped` (:1289), `wk_units` (:1321) | **contradicts.** The theorem assumes `inherit` hands each reader the parent's current value. WebKit's matched declarations cache keys on inherited custom properties only (`Source/WebCore/style/MatchedDeclarationsCache.cpp:123-163@862f17d`) and does not re-apply `var()` readers (`StyleResolver.cpp:693-728@862f17d`) (CONFIRMED) |
| bug 325900 | hero.exit:scoped | none: `consumer_eq_scoped` (`HeroExitOpt.lean:1289`) has no engine premise | **new risk.** No premise is attached to `consumer_eq_scoped`. `css.inherits-false` (`lean/Fw/Ops/Premise.lean:419-423`) lists only `MorphTweenOpt.waapi_vis` and `registrationsScoped_see`, and it covers the initial value on children, not an explicit `inherit` when the parent value changes (CONFIRMED, its `theorems` list and statement). The proposed `wk.mdc-explicit-inherit` premise in §5 would be the first one on this theorem |
| bug 320984 (318999@main) | hero.exit:scoped | same | **unrelated to the pin.** It is a partial fix above 316606 (INFERRED) |
| W1 shared engine, rAF-time sync | morph.tween:waapi, waapi-scoped | `clock.raf-timeline` (:409), `WaapiPremises` R5 (`MorphTweenOpt.lean:275`) | **confirms.** The timeline time is frozen to the rAF timestamp (`AnimationTimelinesController.cpp:125-129@862f17d`) (CONFIRMED) |
| W1, plus the source showing no attribute writes | morph.tween:waapi (nav reads `data-fw-morph`) | `waapi_vis` (:921), `view_eq` (:899) | **new risk.** The engine updates styles only. Our driver writes `data-fw-morph` at start and finish only (`waapi.driver.ts:110,140`), so `view_eq` holds only for style readers (CONFIRMED) |
| acceleration list (source) | morph.tween:waapi | `waapi_work_le_webkit` (:1057, `custom_main`) | **confirms.** Custom properties are never accelerated (`StyleInterpolation.cpp:256-266@862f17d`), and the theorem already puts them on the main thread (CONFIRMED) |
| registered syntax interpolation (source) | morph.tween:waapi | `css.number-linear` (:414), `discrete_not_linear` (:264) | **confirms.** Numeric, Color and TransformFunction interpolate (`StyleInterpolation.cpp:215-240@862f17d`) (CONFIRMED) |
| W12 threaded scroll-driven (26.4) | hero-exit-threaded (not shipped) | `wk_all_comp`, `WktrStyleRate.Holds` (HeroExitOpt) | **confirms** the 26.4+ precondition. The site uses no `animation-timeline` today (CONFIRMED, grep `apps/site/src`) |
| W10 commitStyles with custom properties (26.2) | hero.accent:steps, engine.scene:hidden-pause | `anim.list` (:379) | **confirms.** The fix is below 27.0, so it is in the pin (INFERRED) |
| W8 and W6 content-visibility fixes | pain.notes:visible, visible-idem | `cv.read-forces-lock` (:389), cv.* | **confirms.** The fixes are in 26.0, before the pin; none changes skip semantics (INFERRED) |
| W15 `contain: layout` forced-layout cost (171545381) | people.deck (`contain`) | none | **new risk (small).** Forced-layout cost differs between 26.x and 27.0, so WebKit counts are per-version (INFERRED) |
| W8 136463977, W15 181114298 (var/inherit fallback) | hero.exit (scope.ts) | `consumer_eq_scoped` | **unrelated.** Both concern a fallback; our readers have no `inherit` fallback (INFERRED) |
| W15 `.animation` on events, C9 | none | none | **unrelated** |
| C1 to C8 baselines | every flag | lane rules cr.* | **confirms.** Every feature ships long before M156 (CONFIRMED) |

## 3. Questions on the 13.1 post (W1), answered from source at 862f17d

- **Which properties are accelerated?** The post says only "allowing browsers to use hardware acceleration when available" (CONFIRMED, W1). The source answers it (all paths under `Source/WebCore/` at 862f17d):
  - Always accelerated: opacity, filter, backdrop-filter, transform, translate, scale and rotate (CONFIRMED, `css/CSSProperties.json:7114,10263,10639,12112,12260,12281,12306`).
  - Accelerated only with the threaded flags: the offset-* properties (CONFIRMED, `CSSProperties.json:7004-7077` and `css/scripts/process-css-properties.py:4093-4096`).
  - An effect that mixes accelerated and other properties runs partly accelerated (CONFIRMED, `animation/KeyframeEffect.cpp:1737-1769`).
- **How are custom properties in keyframes handled?** The post does not mention them (CONFIRMED, W1). In the source:
  - `--x` keys become CSSPropertyCustom (CONFIRMED, `KeyframeEffect.cpp:174-175,590-593`).
  - `canInterpolate` returns true for every custom property, with a FIXME that it should apply only to registered ones (CONFIRMED, `style/StyleInterpolation.cpp:268-279`).
  - Keyframes are recomputed when a registration changes (CONFIRMED, `KeyframeEffect.cpp:1126`).
  - After animation, `var()` users on the animated element are re-resolved (CONFIRMED, `style/PropertyCascade.cpp:370-377`, `style/StyleTreeResolver.cpp:899-919,1076-1097`).
- **When does JS-visible state update?**
  - The post says animations update in sync without forcing a style invalidation, that `finished` is a promise and that events are dispatched together (CONFIRMED, W1).
  - In the source, Animations is a rendering-update step after Resize, Scroll and MediaQueryEvaluation (CONFIRMED, `page/Page.cpp:2290-2309`). It updates the timelines, removes replaced animations, runs a microtask checkpoint and then dispatches events (CONFIRMED, `animation/AnimationTimelinesController.cpp:104-143,209-230`).
  - `getComputedStyle` forces a style update (premise `read.forced-update`). The update path writes only the computed style, so DOM attributes and classes do not change; only an explicit `commitStyles()` writes the `style` attribute (CONFIRMED, `KeyframeEffect.cpp:1644-1668,1842-1934` and `WebAnimation.cpp:1912`, both @862f17d).

## 4. Bug search

Queries on bugs.webkit.org via the REST quicksearch, with hit counts:
- Mechanism A: "MatchedDeclarationsCache" 5, "ALL MatchedDeclarationsCache" 21, "ALL matched declarations cache" 65, "ALL inherits false custom property" 50, "ALL non-inherited custom property" 10, "ALL explicitly inherited cache" 47, "ALL registered custom property inherit" 39, "ALL custom property stale" 44.
- Mechanism B: "ALL animate custom property" 114, "ALL animating custom properties" 20, "ALL web-animations custom property" 23, "ALL CSS variable animation not updated" 87, "ALL accelerated custom property" 29.

| Bug | Title (short) | Status | Fix commit | In pin 862f17d / 27.0.1 |
|---|---|---|---|---|
| A 325900 | explicit `inherit` of a non-inherited registered property is stale | NEW | none | no / no (CONFIRMED) |
| A 321094 | `var(--unknown, inherit)` stale when the parent's non-inherited style changes | NEW | none | no / no (CONFIRMED) |
| A 320984 | `inherit()` function, partial fix for 321094 | FIXED | 318999@main (ae3c47183d32) | no / no (INFERRED) |
| A 258914, 259112 | allow variable references in the cache, then a regression fix | FIXED | 265827@main, 265985@main | yes / yes; these introduced the cached path (INFERRED) |
| A 260199, 260340 | allow explicit `inherit` in the cache | FIXED | 266986@main (b733d192e11b), 267001@main (8b9264f72639) | yes / yes (CONFIRMED) |
| A 273874 | partial style application after a cache hit | FIXED | 278648@main (0a38622f9803) | yes / yes (CONFIRMED) |
| A 251590 | `inherit` of a non-inherited custom property | FIXED | 259809@main (06e3540a49d0) | yes / yes (CONFIRMED) |
| A 315656 | cache overloaded when a variable animates indirectly | NEW | none | performance only (CONFIRMED) |
| B 210963 (dupes 249397, 249641, 251022) | CSS animations participate in the cascade; non-inherited animated property used by a standard one | FIXED | 258514@main (eb9e694c2fc9) | yes / yes (CONFIRMED) |
| B 250448 | `var()` users not updated when the referenced property animates | FIXED | 258786@main (fee955ee6904) | yes / yes (CONFIRMED) |
| B 192334, 291568 | registered custom property animation edge cases | REOPENED, NEW | none | not our path (INFERRED) |
| B 327925 | `<integer>` animated value not rounded, reproduced in 27.0.1 | NEW | none | our `--morph` is `<number>`, so unrelated (INFERRED) |
| B 293727 (rdar 152630876) | WAAPI on an unregistered custom property; an inline `transform: rotateZ(var(--x))` set after a `getComputedStyle` read does not update until a reflow (reported on Safari 18.2 and 18.5) | NEW | none | not known: untriaged, no comment after the radar, not in any 26.0-27.2 note (0 hits for 293727 or 152630876). The report animates an unregistered property; our `--morph` is a registered `<number>`. Whether our reader writes match its trigger was not checked (OPEN; the §5 trajectory probe would show it) |

- Mechanism B. The five queries return 235 unique bugs, 26 of them open (MEASURED, re-run 2026-10-20 with `include_fields=id,summary,status`). I reviewed all 26 open titles and read 293727 in full; I did not review the 209 resolved titles one by one. Only 293727 matches the shape "a `var()` reader of an animated custom property is not updated", and its relevance to our path is OPEN (row above). The fixes 210963 and 250448 are in the pin. No open title asks WAAPI to update attributes. So no open bug is known to hit our Mechanism B path (INFERRED from the title review).
- Chromium: searched through the tracker's JSON endpoint, `POST https://issues.chromium.org/action/issues/list` with body `[null,null,null,null,null,["157"],["<query>",null,<n>]]`. The reply starts with `)]}'`, then an `IssueSearchResponse`: per issue the id, then `[componentId, type, status, priority, severity, title, …]`, and the total at `[6][2]`. The status codes are 1 NEW, 2 ASSIGNED, 3 ACCEPTED, 4 FIXED, 5 VERIFIED, 6 NOT_REPRODUCIBLE, 7 INTENDED_BEHAVIOR, 8 OBSOLETE, 10 DUPLICATE (MEASURED: each `status:<name>` query returned only that code). Plain words match comment text too, so the two long queries pull in WPT import trackers. The `title:` and `status:open` variants are the precise ones. Reporter and owner fields were not copied. Run 2026-10-20:

| Query (exact) | Total | Titles reviewed | Matching issue |
|---|---|---|---|
| `MatchedPropertiesCache inherit custom property` | 24 | all 24 | none open. Closest are fixed: 40677204 "Cache styles with explicit inheritance and var() references" (FIXED) and 40396113 "CSS Properties which depend on animation-affected properties are not properly computed" (FIXED). The only open hit is 40676722, custom property set on a parent is slow (NEW, performance) |
| `animated custom property dependent style` | 155 | first 25 | no match found |
| `animated custom property dependent style status:open` | 42 | all 42 | no match found (scroll timeline, WPT import trackers, unrelated features) |
| `MatchedPropertiesCache inherit custom property status:open` | 1 | 1 | 40676722 only (above) |
| `explicit inherit non-inherited registered custom property` | 4 | all 4 | none open; all 4 FIXED (40708479, 40677204, 40496688, 40482531) |
| `title:MatchedPropertiesCache` | 6 | all 6 | none open; all FIXED or VERIFIED (for example 40928440, 40414080) |
| `title:inherit title:registered` | 3 | all 3 | 386853940 "Registered custom properties applied through animations are tainted when inherited" (NEW) is about the `attr()` security taint, not stale values; 428116090 (OBSOLETE); 40275587 (FIXED, flaky test) |
| `title:inherit title:custom status:open` | 3 | all 3 | 386853940 (above); 460742361 `inherit()` in custom functions (NEW, feature) |
| `title:animated title:custom title:property status:open` | 4 | all 4 | 485271330 `:visited` color with an animated custom property (NEW); 359904330 custom properties in `Animation.range*` throw (NEW); 40697525 CPU cost (NEW). None is a stale dependent style |
| `title:"custom property" title:stale` | 0 | n/a | no match found |

  Two more open `:visited` issues came up under `registered custom property inherit status:open` (136 total, first 50 reviewed): 569257985 and 562569551. Both are about `:visited` link colour with an animated or transitioning custom property. `apps/site/src` styles no `:visited` state; the one hit is a test filter in `hero.exit/scoped.test.ts:274` (CONFIRMED, grep). So they are not our path (INFERRED). Result: no open Chromium issue matches Mechanism A or B (INFERRED from the titles; bodies not read). This fits the Blink cache guard (`matched_properties_cache.cc:200-216@f842f52`) and the Chromium 150/154 pass in 325900.
- The pinned clones are depth 1, so `git log --grep` could not be used. Commit placement comes from commits.webkit.org identifiers (CONFIRMED, `refs/upstream/PINS.md`).
- `refs/upstream/PINS.md` holds no wrong version fact, so it is unchanged.

## 5. What this changes for the fix tasks

- **hero.exit:scoped redesign.** Write the scoped variables inline on each reader, or register them `inherits: true`, so no reader depends on an `inherit` of a non-inherited property. Mutable inline style bypasses the cache (`style/ElementRuleCollector.cpp:970@862f17d`) (INFERRED). In Lean, add a WebKit premise such as `wk.mdc-explicit-inherit` that cites 325900 and 321094, and make `consumer_eq_scoped` require it to be absent or the reader to be inline-written.
- **waapi crossing writes.** WAAPI cannot carry `data-fw-morph`, so the driver must write it at each threshold crossing that the Lean thresholds (`MorphTweenOpt.lean:770`) give. `--morph` already runs on the main thread, so a per-frame crossing check takes away no compositor offload (INFERRED).
- **is-on-dark.** Recompute it on every morph state write, not only in the scroll callback (`nav.hitTest/index.tsx:36-46`). No engine release changes this (CONFIRMED, sections 2 and 4).
- **Trajectory probe.** Sample `getComputedStyle` on the hero copy and the nav logo per scroll step in WebKit and Chromium. A forced update still reads cached values, so it detects the 325900 freeze without screenshots. The same probe would also show a 293727-style missed update (INFERRED). Re-check bugs 325900 and 321094 and the 27.2 branch point at each Safari release, because the 20625.2.8 base is unknown (OPEN).

## What this changes in the plan

- **§4.7 evidence model.** Add "an open engine bug that matches a theorem's model refutes that theorem's premise". hero.exit:scoped then carries a refuted premise (325900) until the inline-write redesign lands. Its cut is dropped under premise as in §10.7, not left CONFIRMED.
- **§10.7 lanes.** Add a release-notes check (Apple notes JSON plus Chrome Status milestone entries) at each new Safari or Chrome pin, so that this index stays current.
