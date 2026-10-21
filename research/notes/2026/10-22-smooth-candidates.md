---
id: 2026-10-22-smooth-candidates
kind: note
title: "Ranked smoothness candidates for iPhone Safari: hero exit (toolbar-collapse scroll throttle) and end of page (5 resized layers per morph frame)"
status: review
created: 2026-10-22
topics: [lag, webkit, ios-toolbar, scroll-driven, hero.exit, hero.cue, engine.scroll, morph.tween, morph.mount, morph.panel, morph.columns, morph.countdown, nav, iosurface, look-change, phone]
---

# Smoothness candidates for the hero exit and the end of page

Two surveys merged, with all 16 adversarial-check findings applied ("Check findings"). No new measurement; the
2026-10-21 phone records were recounted. WebKit cites `@862f17d`; `WK/` = Source/WebKit/, `Prefs` =
Source/WTF/Scripts/Preferences/UnifiedWebPreferences.yaml. Repo lines from the surveys at `e49111a`; lines the check
named rechecked at `ecdc078`. LS = [10-20-webkit-lag-source](10-20-webkit-lag-source.md), RC =
[10-22-webkit-render-cost](10-22-webkit-render-cost.md), COV = [10-22-lag-coverage](10-22-lag-coverage.md).

## Answer

- **Hero exit.** The cause is Safari's scroll throttle while the toolbar collapses. When the obscured insets change
  interactively, WKWebView sends the web process one visible-rect update per 100 ms "to save power", so `scrollY` and
  the JS-driven exit step at about 10 Hz (`WK/UIProcess/API/ios/WKWebViewIOS.mm:142, 3256-3268`). The mechanism is
  CONFIRMED. That this is the lag the user feels is INFERRED. In the rewrite pass, 51 of the 83 short still runs inside
  the exit range last exactly 5 or 6 frames, which is 100 ms at 17 ms per frame (MEASURED).
- The only candidate that removes the stepping without lifting the power throttle is the threaded scroll-driven CSS
  exit. It is proved in Lean, has no TS variant and no measurement.
- **End of page.** On the phone every morph frame resizes 5 backed layers: nav, panel and 3 tracks. Each resize
  allocates a new IOSurface and repaints the whole layer (RC F3; path CONFIRMED, cost INFERRED). No same-look
  candidate removes all 5. Keeping the panel at its final size (C1) is refuted on the visual, and the nav clip pill
  (C8) removes 1 of the 5.
- Measure before code in both zones ("Measurement needed before code").

## Phone viewport and its confound

All four passes in `results/phone/2026-10-21/summary.json` ran 430 wide at dpr 3, but at different heights (MEASURED).

| pass | arm | viewport | frames | hero stalls |
| --- | --- | --- | --- | --- |
| 1 | original | 430 x 815 | 3734 | 174 |
| 2 | rewrite | 430 x 775 | 5026 | 94 |
| 3 | look | 430 x 775 | 5161 | 94 |
| 4 | original | 430 x 815 | 4304 | 108 |

- **Confound.** The 40 px height gap most likely reflects a different toolbar state at the start of each arm
  (INFERRED). The throttle acts only while the toolbar collapses, so an arm comparison of stalls or still runs mixes
  the arm with the toolbar state.
- **Nav geometry at 430 wide** (`apps/site/src/parts/nav/nav.module.css:254-261`). The width goes from 398 px
  (`100vw - 32px`) to 406 px (`100vw - 24px`), the height from 52 px to `100vh - 24px`, the top from 16 px to 12 px.
- **End-state nav or panel surface.** With 100vh = 815 px (INFERRED: the taller recorded height), the layer is
  406 x 791 CSS px, or 1218 x 2373 device px. That is 14.5 MB at 5 B/px, the real-iPhone format from RC F3b, and
  11.6 MB at 4 B/px, the Simulator format. RC's 13.5 MB and 10.8 MB are for the 390 x 844 CI viewport.

## Hero exit

Hero zone per pass, MEASURED (`summary.json`; original passes 1 and 4, rewrite and look 1 pass each):

| metric | original | rewrite | look |
| --- | --- | --- | --- |
| frames > 50 ms per 100 moving | 30.4 / 20.1 | 0.00 | 0.00 |
| frames > 34 ms per 100 moving | 49.3 / 36.4 | 1.20 | 1.67 |
| median interval ms | 34 / 29 | 17 | 17 |
| longest ms | 152 / 117 | 45 | 50 |

Simulator region A per step: Layout 179,323 us and FunctionCall 152,789 us in the original, 6,472 us and 26,438 us in
the rewrite (`10-21-lag-windows.md`, run 39511908073, MEASURED). Main-thread cost no longer limits the hero.

**Stalls, recounted** from the local raw records `rec-1..4.json` (not committed), MEASURED. A pair is
`partSeries` (`ys[i]`, `vs[i+1]`) and a stall is `stallAt` (`lean/Fw/Device/Session.lean:277-282, 333`). A "moving
exit pair" has a page move and a value in (0, 1000). "After still" means `scrollY` did not change the frame before.
A still run is a maximal run of k frames with unchanged `scrollY` that ends in a move, where the value during the run
is in (0, 1000). The jump is the `scrollY` change that ends a 5- or 6-frame run.

| pass | arm | stalls / moving exit pairs | stalls after still | still runs, k = 1-9 | still runs, k = 5-6 | jump after k = 5-6, px (min, median, max) |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | original | 174 / 271 (64%) | 56 | 62 | 19 | 21, 86, 193 |
| 2 | rewrite | 94 / 430 (22%) | 85 | 83 | 51 | 10, 100, 226 |
| 3 | look | 94 / 388 (24%) | 77 | 72 | 59 | 2, 102, 233 |
| 4 | original | 108 / 180 (60%) | 67 | 72 | 36 | 59, 152, 526 |

- Most rewrite frames in the exit move every frame (430 moving exit pairs). While the toolbar collapses (INFERRED: the
  recorder does not log toolbar state), `scrollY` sits for 5 to 6 frames and then jumps, by a median of 100 px.
- The stall count is the wrong exit metric. The faithful exit body runs in its own rAF requested by the engine
  callback (`apps/site/src/parts/hero.exit/driver.ts:87`), so the first value after a still run arrives one frame
  late and `stallAt` counts about one stall per still run (85 after still against 83 runs). `engine.scroll:batched`
  reads in the same frame (`driver.ts:86`) and would remove those stalls while the 10 Hz steps stay.
- Throttle path (CONFIRMED): fixed and sticky layers are moved out of band while the throttle holds
  (`WKWebViewIOS.mm:3265-3267`), so the sticky stage stays smooth and its JS-driven contents step. The bypass is
  `hasMainThreadScrollDrivenAnimations`, true only for a progress-based animation that is not fully accelerated
  (`WK/WebProcess/WebPage/Cocoa/WebPageCocoa.mm:2356-2357`, `Source/WebCore/animation/AnimationTimelinesController.cpp:267-279`).

### Hero exit candidates, ranked

| # | candidate | what exists | look | expected WebKit effect | work to land |
| --- | --- | --- | --- | --- | --- |
| 1 | Threaded scroll-driven exit | `Fw.Parts.HeroExitOpt`: `consumer_eq_s` (`lean/Fw/Parts/HeroExitOpt.lean:181`), `wk_all_comp` (`:589`), `wk_var_exact`, `wk_trade` (`:723, 793`), `wk_trade_not_general`; proof `f6544e3`, hero-exit-restate landed in `3dbed91c` (merge `acf7eb7e`). No `animation-timeline` in `apps/site/src` (grep, CONFIRMED). `ThreadedScrollDrivenAnimationsEnabled` is stable and on by default for WebKit (`Prefs:8518-8530`, CONFIRMED) | same under premise RG11 | Consumers follow UI-process scrolling on every UI scroll callback: `WK/UIProcess/WebPageProxy.cpp:18557-18562`, `ScrollingTreeScrollingNode.cpp:517-528`, `RemoteScrollingTreeIOS.cpp:56-62` (CONFIRMED). Removes the 10 Hz steps and the extra frame (INFERRED). Trade: one main style pass with N+3 units stays, the UI process gains the animations | TS/CSS variant plus a Lean golden for keyframes and ranges; open RG11, C3 (which offset the compositor shows), the opacity-1 crossing, resident layers, the `pointer-events` sentinel |
| 2 | Throttle-lift probe: one non-accelerated progress-based animation on the page | nothing | same if it animates nothing visible | Per-frame visible-rect updates during the collapse, for the whole page (`WKWebViewIOS.mm:3256-3268`, CONFIRMED) | One phone pass. A diagnostic, not a ship candidate: it lifts a throttle WebKit keeps "to save power" on every toolbar collapse, and that power cost is unmeasured (INFERRED) |
| 3 | `engine.scroll:batched` | `Fw.Parts.EngineScroll`; TS variant exists; ledger: no win on style passes | same value per offset | One frame earlier after each still run; the 10 Hz steps stay | Lean "frames behind" statement to count as a win |
| 4 | `hero.exit:scoped` inline | `inline_visSame`, `wk_units` 123 to 9; Chromium 136 to 45 style elements per frame (runs 39461009752, 39462188464) | same | Small: no hero frame over 50 ms is left | Blocked on the mac-webkit morph cell |
| 5 | Promote the cue (`will-change: filter`) | nothing; cue blur at `hero.cue/cue.module.css:13` has no `will-change`. Copy is not a target: no blur on the phone (`hero.exit/logic.ts:63-64`), already promoted (`hero/hero.module.css:26`) | pixel check needed (CA blur against CG blur) | Removes the per-frame painted filter rebuild (`RenderLayerFilters.cpp:207-261`, INFERRED); candidate 1 supersedes it on Safari 26.4+ | Pixel check, then a TS variant |
| 6 | `hero-relayout-boundary` (`contain: size layout` on `.hero`) | UNPROVEN; Chromium bound 0 to 37% of totalObjects | not proved | Stops the outset layout walk at `.hero` (INFERRED) | Lean proof first |
| 7 | Constant blur radius, or no blur on the phone | nothing | class L | Removes the cue blur cost | User review |
| 8 | `hero-pause-rule` (`hero:scene-pause`) | `HeroScenePause` `visSame_original` (`8f8d5787`); Simulator census run 39548856639: 51 to 65 layers at y 3000 and 4500, against 136 to 145 in the `morph.mount:shift` arm (run 39309416016), not the faithful arm (`10-20-hero-pause-rule.md:141-142`) | same as the original | None in the exit zone: with `rootMargin` 100% the hero stays active; helps the rest and finish zones | Its own gate |

## End of page

- The panel is `inset: 0` in the nav (`morph.panel/morph.module.css:15-17`); the tracks follow its width
  (`morph.columns/morph.module.css:17-26`). At morph start the countdown faces become about 80 to 160 new UIViews in
  one commit (RC, INFERRED count). C1: `Fw.Parts.MorphPanelOpt` `not_Q`, `footer_shift`.
- C4 is not installed under `(hover: none)` (`engage_touch`, `MorphTweenOpt.lean:2230`; `morph.tween/index.tsx:70-73`,
  CONFIRMED). If the look pass ran scroll-lock plus earn, it measured earn alone. That composition is INFERRED: no
  committed file records the look search (`packages/measure-webkit/src/device-arms.mjs:46` takes it from the CLI).

### End-of-page candidates, ranked (keys: RA resize realloc and repaint, UV new UIViews, TW touch wait, BL blur, DC decode)

| # | candidate | what exists | look | expected WebKit effect | work to land |
| --- | --- | --- | --- | --- | --- |
| 1 | Measure first, no site code | task `webkit-cost-counters` | none | Decides C8, C4t and C9b | See "Measurement needed before code" |
| 2 | C10 `morph.countdown:strip` | `HeroCountdownOpt` `strip_visSame`, `wk_normal_layers` (80 face layers to 8), `strip_backing_gt`; proof `d5cca095`, land `92c7aa9c`. MEASURED more pipeline work in the strip arm: `UpdateLayoutTree.elementCount` 11264 to 22445, commits 1064 to 1085 (runs 39257533380, 39259074927, `10-19-c3-decision.md:27`); engine-check run 39131314391: `census.layers` 17972 to 17970. Excluded by the C3 decision (`packages/contracts/golden/preset/v2-proved.decisions.jsonl` row 5, `why.verdict` "excluded"; curated in `lean/Fw/Preset/Gen.lean:65-72`). `part.json:13` requires `hero.countdown:strip` | E at scene level (`strip_visSame`); pixel E open under fractional ancestor opacity (ledger n 13); label trade on both engines | UV: about 90% fewer face views at morph start (INFERRED); trade: 12 instead of 10 backed cells per digit | Reverse both curated exclusions in `Gen.lean` (adds `hero.countdown:strip` too); remove the TS strip's shared-loop subscriber (`sub_still_not_le`, `HeroCountdownOpt.lean:716`); pixel check; 4 trajectory cells; a new-layers-per-commit count. Gain small-medium, effort medium |
| 3 | DL one listener plus TB touch band | `App.tsx:50-51` mounts both; both attach capture `touchmove`/`wheel` with `passive: false` in the 200% band (`morph.mount/index.tsx:85-91`, `morph.tween/driver.ts:101-107`), each with a `getBoundingClientRect` per forward move | E if the Lean equivalence holds; TB under the INFERRED premise that one touch sequence moves the page at most about 1 vh | TW: one handler and one rect read fewer per touchmove; none outside the band (INFERRED, small) | Lean equivalence over `takes` against `taken`, the two `armed` definitions (`lean/Fw/Parts/MorphMount.lean:31`, `lean/Fw/Parts/MorphTween.lean:220`) and the two active flags; Lean `armTouch(y)`; golden vector; phone touchstart-to-scroll check; wheel keeps 200% |
| 4 | D `img.decode()` at idle | images are `loading="eager" decoding="async"` (`morph.columns/index.tsx:75`) | E against the decoded model | DC removed at morph start; trade: about 30 MB of decoded images held from the 200% mount | Lean decode rule beside `Fw.Engine.WebKitImage`; memory-pressure check |
| 5 | C8 nav at final size, pill by composited `clip-path: inset(... round r)` | nothing | E only if the bar sits in an inner box sized to the pill, the panel keeps the current rect, `backdrop-filter` follows the clip (open), and mask anti-aliasing stays within Q | RA: 1 of 5 resized backings (the nav); cost: a 14.5 MB surface held always | WebKit read for `backdrop-filter`; Lean `Fw.Parts.Nav` restated; IOSurface counter; gate at all breakpoints |
| 6 | C2 panel and platform `filter`/`opacity` as real-property animations | `MorphPanelOpt` `fade_visSame_Q`, `wk_fade_trade`; tasks `variant-morph-panel-rest`, `panel-rest-n11` | Q at sampled frames; class L only if the CA animation rate differs from the 60 Hz nav geometry. COV L4: the display link rises only for threaded time-based animations, off by default (`Prefs:8557-8568`), so a mismatch is INFERRED, not shown | BL and the platform repaint move to CA (`--morph-fade` repaints 83% of the close-push paint area, MEASURED, `10-21-lag-windows.md`) | Keyframes from Lean `tween`/`fade` with an error bound; retarget on reverse push |
| 7 | C9a create morph layers before the take | the opposite exists: `morph.mount:shift-dormant` (`MorphMountDormant` `visSame_dormant`) | E | UV at the take near 0; trade: resident backings, Chromium layers rise again | Waits for C10; weighed against `morph-preset-dormant` |
| 8 | C4t, CB, C1b, constant track width | nothing | class L | Possibly large if the pin fight is real | Pin-fight measure, then user review |
| 9 | C1r panel backing at final size, children at the current rect | C1 refuted (`MorphPanelOpt` `end_E`, `footer_shift`, `not_Q`; ev `80c210e`) | E only with restated veil, centre, footer and `transform-origin`; high risk | RA: 1 more backing | Only after C8 shows a measured realloc win |
| - | `morph.mount:shift-dormant`, `morph-idle-none` | `visSame_dormant`; morph-idle-none 1910 of 28107 Chromium layer-frames (run 39309334426) | E | Little on WebKit (INFERRED) | The blocker is the shared mac-webkit morph cell (39453181962 fail, 39455284967 no verdict: coverage); 39442517769 has no mac-webkit morph cell. All three ran the 8-flag preset with `morph.mount:shift`; no shift-dormant run exists |
| - | `morph.tween:waapi`, `waapi-scoped`, `morph-nav-scope` | waapi falsified (`10-20-preset-drop-waapi.md`); nav-scope unmeasured | E | None: WebKit never runs a custom property in the UI process (LS line 16, region A) | Drop for iPhone lag |
| - | C4 `morph.tween:scroll-lock` | MT-L `lock_vis`, `forced_lt`, `engage_touch`; land `e1eb917d`; runs 39496271199, 39498373119; 39505188144 fails mac-webkit morph (A/A 39505203727 fails too) | class L | Mac only; 0 on the iPhone | Look-change row, user decision pending |

## Class L: for the user's visual review

| zone | candidate | why it changes the look |
| --- | --- | --- |
| hero | constant or no cue blur on the phone; cue promotion if its pixel check fails | the blur differs mid-exit; CA blur may differ from CG blur |
| end | C4t pin-free touch take | the morph no longer pins the scroll |
| end | CB constant blur radius (crossfade) | blur(r) is not a mix of blur(0) and blur(12) |
| end | C1b nav by `transform: scale` | radius and content distort |
| end | constant track width | tracks stop following the panel |
| end | C2, only if its rate mismatch shows | CA and the nav geometry may run at different rates |
| end | C9b freezing a width-driven image | the drawn image stops tracking the width |
| end | C4 `morph.tween:scroll-lock` (Mac) and `nav:earn-no-transition` | already in the look-change rows; earn "kept", review pending (runs 39473950464, 39530106935) |

## Measurement needed before code

1. **Hero exit check.** Count `scrollY` still runs of 5 to 6 frames inside the exit range, or the rAF `scrollY` step
   size, to find the throttle windows. Then sample one consumer on every frame inside those windows: a pixel sample
   of the cue or copy, or `getComputedStyle` of a consumer. The candidate passes when the consumer changes on frames
   where `scrollY` is still. `getComputedStyle` reads the web-process timeline, which the throttle also holds, so for
   the threaded port only a pixel sample shows the compositor's value (INFERRED). Do not use the stall count. The
   recorder reads only the inline `--exit-opacity` (`packages/measure-webkit/src/device-record.mjs:19, 29-33`), so a
   CSS exit leaves it nothing to read.
2. **Throttle-lift probe:** one phone pass with candidate 2; if the throttle is the cause, the 5- to 6-frame still runs
   disappear. Run all arms of that session at one viewport height, or log the toolbar state per frame.
3. **IOSurface creations and new layers per morph commit**, by nav, panel and tracks (`webkit-cost-counters`). This
   sizes C8's 1-of-5 share and C10's UV gain.
4. **The pin fight on the phone:** `scrollend` per gesture and rAF `scrollY` oscillation while pinned. This decides C4t.
5. **The image count:** a Lean count of width-driven column images per breakpoint from the `sips` sizes. Height-driven
   covers keep a constant drawn rect (RC F4), so C9b likely closes as a finding at 0.

## Proposed tasks

| task | what | exit check |
| --- | --- | --- |
| `toolbar-throttle-probe` | one phone pass with candidate 2 | still runs of 5 to 6 frames gone in the probe arm |
| `phone-consumer-sample` | recorder: per-frame pixel or computed-style sample of a hero consumer; still-run counter | runs on the 2026-10-21 records and reproduces the table above |
| `session-stall-split` | `Fw.Device.Session`: stalls after a still frame and other stalls, plus still runs | Lean theorems; golden vector from rec-2 |
| `hero-exit-threaded-port` | TS/CSS variant from `HeroExitOpt` plus a Lean golden for keyframes and ranges | measurement 1 passes on the phone; ranks above `hero.exit:scoped` admission |
| `webkit-cost-counters` (extend) | add IOSurface creations per morph frame by layer, new layers per commit, `scrollend` per gesture, pinned `scrollY` oscillation | counts on the CI Simulator |
| `countdown-strip-readmit` | C10: reverse the C3 exclusions, remove the shared-loop subscriber, pixel check, trajectory cells | the four cells and the pixel check |
| `morph-double-listener` (merge TB) | Lean equivalence over `takes`/`taken`, both `armed`, both active flags; `armTouch` | golden vectors; phone latency check |
| `decode-at-idle` | Lean decode rule, memory trade | memory-pressure check |
| `column-image-width-count` | lean-prover count for C9b | count per breakpoint |

## Check findings

All 16 were applied. Three were applied with a stated difference.

| # | finding | applied |
| --- | --- | --- |
| 1 | C10 status | yes: scene-level E, pixel E open (ledger n 13), label trade; look risk "pixel check needed" |
| 2 | C10 is MEASURED and excluded | yes: runs, C3 exclusion, `Gen.lean`, `requires`, `sub_still_not_le`; gain/effort lowered, rank 2 after measurement |
| 3 | 390-wide geometry | yes, restated for 430 wide, cite `254-261`. Difference: the check's 11.6 MB uses 4 B/px; the real iPhone uses 5 B/px (RC F3b), so both 14.5 MB and 11.6 MB are given |
| 4 | stall count as exit check | yes: `scrollY` still runs plus a consumer sample. Added: `getComputedStyle` is likely throttled too, so the port needs pixels |
| 5 | "only candidate" | yes: "without lifting the power throttle"; candidate 2 is a diagnostic, and the "save power" reason is in the source |
| 6 | "every 6 to 7 frames" | yes, narrowed to toolbar collapse. Difference: the recount gives jumps of 10 to 226 px, median 100, not 56 to 192 |
| 7 | viewport confound | yes |
| 8 | still-run counts | yes: the stated rule reproduces 19/51/59/36. The "expected per-mille changed" column was dropped: its definition is not recoverable from the survey |
| 9-16 | look arm, dormant runs, C4 A/A, pause-rule range, `384fe8a`, waapi cite, CA rate, DL premise | yes, each as the check asked: look arm INFERRED; runs recast; A/A added; 51 to 65 against the `morph.mount:shift` arm; `3dbed91c`; LS line 16; rate INFERRED with the preference default; all three equalities |

## What this changes in the plan

- **§4.6 (phone limits):** add the toolbar-collapse throttle as a lag kind that the phone sees as 5- to 6-frame
  `scrollY` still runs. Require one viewport height for all arms of a session, or log the toolbar state.
- **§4.2 Step 1:** extend `webkit-cost-counters` with per-layer IOSurface creations, new layers per commit, `scrollend`
  per gesture and pinned `scrollY` oscillation.
- **§6.1 (hero.exit, morph.*):** rank the threaded scroll-driven exit first for the hero, with the consumer-sample exit
  check, not the stall count. For the end of page, rank measurement first and C10 second with its C3 conditions. Mark
  C4 "no iPhone effect" and C1 refuted.
- **§10.4 (work graph):** add the tasks in "Proposed tasks"; merge the touch band into `morph-double-listener`. COV
  gains the toolbar throttle as a lag kind.
