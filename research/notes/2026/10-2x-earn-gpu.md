---
id: 2026-10-22-earn-gpu-variant
kind: note
title: "Can the GPU keep the earn button's faithful collapse animation and make it cheaper? Engine source, candidates, bound-arm measurement"
status: review
created: 2026-10-22
topics: [nav, earn, transitions, compositing, gpu, webkit, chromium, clip-path, at-property, look-change, measurement]
---

# Earn button: GPU variants that keep the faithful look

Question (user, console review comment on `nav:earn-no-transition`, 2026-10-22): keep the animation's look; can GPU
rendering make it cheaper; how big is the difference? Sources: WebKit@862f17d and Chromium@f842f52 (sparse clones;
"(raw)" = fetched from raw.githubusercontent at the same sha). Site CSS: `apps/site/src/parts/nav/nav.module.css`.
The user rejected `nav:earn-no-transition` as the answer and wants the faithful animation kept; task earn-bound-arm
measured the first gate of the plan below (the `bound` arm).

## Answer

- **The earn transitions are not where the main-thread lag is (the mask and sheen animations stayed on).** With every earn transition switched off, main-thread work in the finish zone is
  the same as the faithful page and the same as the A/A control, on macOS and on the iOS Simulator (section "Result of
  the bound arm"). By the plan's own gate candidate B is not built.
  MEASURED, see the result section for run ids. The CI hosts have no real GPU, so a saving on the compositor or the
  GPU process could not show; this result bounds main-thread work only.
- **Two of the three animated properties cannot run on the GPU in either engine.** `max-width` and `padding-inline`
  are layout properties. `opacity` already runs composited. Its transition restarts on every frame while `--morph`
  changes, so it gives no main-thread saving during the morph. CONFIRMED (table Q1).
- **No GPU variant is pixel-identical.** The faithful arm lays out each frame and snaps the pill background to device
  pixels. Any transform or clip variant moves an already rasterized layer by fractional pixels, so edge anti-aliasing
  and text sampling differ. A variant that scales the button also distorts the text glyphs and the 24 px corners. At best
  a variant is class Q (equal geometry per Lean, pixels within the gate's PL1/PL2), never class E. INFERRED, reasons below.
- **Best same-look candidate (B), not built:** a registered `@property --earn-s` transition plus translate-only
  geometry. The engine's own restart rule produces the shown scalar, so the creep is exact. The kink of the box width
  is computed per frame with `min()`. Layout is kept at full width and changes 2 times per push instead of 43 (open) or
  65 (close). It is not GPU-*animated*: the scalar is interpolated on the main thread every frame, in both engines. It
  removes per-frame layout and repaint, not the per-frame style pass.
- **The only GPU-animated candidate (A)** (WAAPI transform/opacity, started once when the computed value stops
  changing) matches the faithful look only after the last computed change. Matching the box-width kink needs
  two-segment keyframes with a subdivided Bezier, so it is equal only up to float precision. It needs 4 or more new
  layers. Not recommended.

**Recommendation:** keep the faithful animation (the default arm is already the faithful one). Do not build a GPU
variant: the lower bound of any variant of the earn transitions is no better than A/A on the CI hosts. If the user still wants a cheaper
look-change instead, the closest option is A with affine (one-segment) transitions, class L (text path off by up to about
15 px mid-collapse at desktop). Whether a real iPhone feels the earn animation stays open: it needs the phone replay
(plan step 4), which the VMs cannot replace.

## What the button does (restated)

`.btn.earn` (`nav.module.css:167-185`): `max-width = 176·s` px (phone 152·s), `padding-inline = 24·s` (phone 16·s),
`opacity = (1 − earnOut)·expand`, with `s = expand·(1 − earnOut)` and `earnOut = clamp(m/0.2)`. It also sets
`filter: blur(10·earnOut px)` and `transform: translateY(−8·earnOut px)`, which are not transitioned. It has `overflow:
hidden`, `white-space: nowrap` (`:149`), `justify-content: center` (`:155`). Its `mask-image` is `none` in the hero-pill
state (`:195-196`) and `var(--nav-earn-mask)` in every other state under `prefers-reduced-motion: no-preference`
(`:224-225`), where the `earn-unmask` animation (0.98 s, 0.52 s delay) also runs. The button is the last item of
`.actions`, which is `position: absolute; right: 8px` (`:128-140`). So the button's box width `w` moves the language
menu, and its label stays centred in the box and is clipped on both sides once the box is narrower than the label.
The hero-pill state has its own earn transitions (opacity 0.2 s, `:189-197`) and the phone block has more
(about `:284-300`); `earn-unmask` and the sheen are CSS animations, not transitions.

Box width (flex item, border-box, nowrap, `min-width: 0`): `w(s) = min(T + 2·pad·s, maxW·s)`, where T is the label
width. It has a kink at `s* = T / (maxW − 2·pad)` (desktop T/128). The label centre is at `R − w/2`, the language menu at
`R − w − gap − L`. INFERRED from the CSS flex rules; Lean `Nav.lean` has `earnMaxW` (`:269`), `earnPad` (`:272`) and
`earnOpacity` (`:275`) (`lean/Fw/Parts/Nav.lean:263-285`) but no box-width function yet.

Where the faithful arm's visible change happens (golden `packages/contracts/golden/parts/nav-earn.jsonl`, desktop):

| push | frames with per-frame restarts | visible there | after the last computed change |
|---|---|---|---|
| open | 1-3 (max-width shown 176 → 175.3) | yes, opacity 1, ≤ 0.7 px | one 680 ms transition, frames 3-43; opacity one 120 + 320 ms transition |
| close | 18-~41 (shown 0 → 5.6 px) | button at opacity 0; language menu moves ≤ 5.6 px | one 680 ms transition, ~41-81 (1.35 s after the push) |

So the "creep" the user sees is mostly one ordinary transition, started from the shown value at the last computed
change. The restarts matter only in the first 3 open frames and for the language menu on close. MEASURED in the
Lean model (golden rows); 60 Hz frame times.

The existing flag `nav:earn-no-transition` (class `is-earn-still`, `nav/index.tsx:104`, `logic.ts:88-95`) switches the
earn transitions off only while the nav is morphing (`nav.module.css:200-202`), and changes the look. The bound arm
below switches them off at all times; it is a probe, not a flag.

## Q1. Which animated properties composite today

| property (transitioned) | WebKit (iOS/macOS) | Chromium | Status, source |
|---|---|---|---|
| `max-width` | no: not accelerated, a change needs layout | no | CONFIRMED. WebKit accelerated set = properties with `animation-wrapper-acceleration` in `Source/WebCore/css/CSSProperties.json`: opacity (:7114), filter (:10263), backdrop-filter (:10639), transform (:12112), translate (:12260), scale (:12281), rotate (:12306), offset-* threaded-only (:7004-7077); generated by `css/scripts/process-css-properties.py:3823-3825, 4093-4096`. Layout: `Source/WebCore/style/StyleDifference.cpp:406`. Chromium `kCompositableProperties`, `third_party/blink/renderer/core/animation/compositor_animations.cc:78-84` |
| `padding-inline` | no: needs layout | no | CONFIRMED, `StyleDifference.cpp:426`; same lists |
| `opacity` | yes: Core Animation animation via `RenderLayerBacking::startAnimation` | yes, cc animation | CONFIRMED, `Source/WebCore/rendering/RenderLayerBacking.cpp:4768-4786`; `compositor_animations.cc:80, 201` |
| opacity, restarted every frame | each restart cancels and recreates the animation from style, so the main thread still runs style on every frame and sends a new animation | same | restart rule CONFIRMED (`Source/WebCore/style/Styleable.cpp:743-756`; `css_animations.cc:2703-2732`); that it costs a new compositor animation per frame is INFERRED |

- WebKit's threaded time-based animations are off by default (`ThreadedTimeBasedAnimationsEnabled`, default false,
  `Source/WTF/Scripts/Preferences/UnifiedWebPreferences.yaml:8557-8571`). On WebKit, "composited" therefore means a Core
  Animation animation in the UI process / render server. CONFIRMED.
- Not transitioned but changed per frame while `earnOut` moves (open frames 1-3, close frames ~18-40): `transform`
  on a composited layer is RecompositeLayer, and `filter` is RecompositeLayer unless painted
  (`Source/WebCore/rendering/RenderElement.cpp:300-311, 334-340`). CONFIRMED.

## Q2. Candidates

**Scene equality used below.** Two arms draw the same geometry when, at every frame, the pill rectangle (left edge, right
edge, corner radius), the label centre, the language-menu x, opacity, blur and translateY are equal. Pixels may still
differ by snapping and resampling (class Q).

| # | variant | composited in WebKit | composited in Chromium | text pixels | geometry equal at every frame? |
|---|---|---|---|---|---|
| S | `transform: scaleX` on the button or an inner pill | yes (transform) | yes | no: the bitmap is scaled, glyphs stretch and resample; 24 px corners become elliptical | no |
| F | FLIP: scaled wrapper plus counter-scaled label | yes | yes | no: two resampled bitmaps; `lerp(a,b,e)·lerp(1/a,1/b,e) ≠ 1` mid-transition, so the label wobbles unless densely keyframed | no |
| C | translate + `clip-path: inset(0 0 0 x round 999px)` transition | no: clip-path is not in the accelerated set; on a composited layer **without a mask** the change is RecompositeLayer through a shape layer, **with a mask** (the earn has one outside the hero pill) it repaints | yes, through the native clip-path paint worklet (`CompositeClipPathAnimation` stable); the compositor rasterizes an interpolated SkPath each frame | translated label: resampled at fractional offsets | not with one transition: x is piecewise in s (kink) |
| M | `mask-position`/`mask-size` animation | no; mask change is RepaintLayer | no | label repainted | possible, but on the main thread |
| P | `@property --earn-s` (number) transition on `.actions` plus translate-only geometry (candidate B) | no: custom properties are never accelerated | no: only custom properties used by a paint worklet | translated layers: resampled | **yes**: same transition rule produces the shown s; `min()` gives the kink per frame |
| W | WAAPI transform/opacity, started once at the last computed change (candidate A) | yes | yes | resampled | only after the last change, and only with two-segment keyframes (float precision) |

Sources for the table:

- clip-path, WebKit: not in the accelerated set (above). `adjustStyleDifference` gives RecompositeLayer only if
  `willCompositeClipPath()` (`RenderElement.cpp:321-326`), which is false when `hasMask()`
  (`Source/WebCore/rendering/RenderLayer.cpp:779-791`). The shape-layer path carries "FIXME: Avoid repaints when clip
  path changes" (`RenderLayerBacking.cpp:1933-1958`). CONFIRMED. So on the earn button itself (it has a mask-image
  whenever the nav is not the hero pill, `nav.module.css:224-225`) a clip-path transition repaints every frame. The
  clip would have to sit on a separate child without a mask.
- clip-path, Chromium: `CompositeClipPathAnimation` status stable
  (`third_party/blink/renderer/platform/runtime_enabled_features.json5:1342-1345` (raw)). The animation composites only
  if the paint image generator accepts it (`compositor_animations.cc:365-378`;
  `third_party/blink/renderer/modules/csspaint/nativepaint/clip_path_paint_definition.cc:425-453` (raw)). The
  compositor interpolates the keyframe SkPaths and redraws them anti-aliased every frame (`:470-530` (raw)), and
  refuses rounded insets whose paths cannot be interpolated (`:747-750` (raw)). CONFIRMED. That SkPath point
  interpolation equals CSS `inset() round` interpolation only while both ends have the same corner radius (w ≥ 48 px
  desktop) is INFERRED.
- mask: not in either list (above); WebKit `a.mask != b.mask` returns RepaintLayer (`StyleDifference.cpp:582-583`).
  CONFIRMED.
- custom properties: WebKit `isAccelerated` returns false for custom properties
  (`Source/WebCore/style/StyleInterpolation.cpp:256-266`). They take the same restart path as standard properties
  (`Styleable.cpp:859-860` → `:743-756`). Chromium composites a custom property only when a CSS paint image uses it
  (`compositor_animations.cc:426-440`); its transitions take the same handle path
  (`third_party/blink/renderer/core/animation/css/css_animations.cc:2947-2966`, `:2694-2732`). CONFIRMED.
- pixel identity: the faithful background is drawn on a device-pixel-snapped rect
  (`Source/WebCore/rendering/BackgroundPainter.cpp:285`), and the label is re-rasterized at each new layout position.
  A translated or clipped layer is rasterized once and placed at fractional offsets by Core Animation or cc. That this
  gives different edge and glyph pixels is INFERRED (Core Animation is closed source). On an iPhone (DPR 3) the
  difference is at most about 1/3 CSS px of anti-aliasing, so the class is Q, decided by the gate's PL1/PL2.

### Candidate B in detail (best, not built)

- `.actions` registers `--earn-s` (`syntax: "<number>"`, `inherits: true`) and lists `transition: --earn-s 0.68s`
  (same curve). It keeps `opacity` on the button as today (composited, same restart behaviour).
- During a push the button keeps its full rest width W0 = w(1) in layout. A child pill (overflow hidden, background,
  no mask) is translated right by `W0 − w(s)`, with `w(s) = min(T + 2·pad·s, maxW·s)` and T set once from the rest
  layout. Its content is counter-translated so that the label sits at `R − w(s)/2`. The language menu gets
  `translate: W0 − w(s)`. The button's static `overflow: hidden` with `border-radius: 999px` clips the right side.
- At the end of the collapse (shown s = 0, `transitionend` on `--earn-s`) the layout switches to max-width 0 in the
  same frame as the translates reset. On a close push it switches to W0 at the first frame with s > 0. That makes 2
  layout frames per push instead of 43 (open) / 65 (close) style-changing frames.
- Engine work per frame while s moves: style recalc of the dependents, then `translate` changes on composited layers
  (RecompositeLayer, `RenderElement.cpp:300-311`). No layout, and no repaint of the bar. The layer bounds stay constant,
  so the per-frame IOSurface reallocation of a resized composited layer (`10-22-webkit-render-cost.md` F3) is gone for
  the earn. INFERRED.
- Cost of B: 2 to 3 new composited layers (pill, label, language menu). On iOS each new layer means UIView creation
  and an IOSurface (render-cost F7, F3), and it counts against PLAN §6.2 `layerBudget`.
- Where B is not equal in geometry: below w = 48 px the faithful corner radius is w/2, while the clipped pill keeps
  24 px corners. Lean must show this happens only where the shown opacity is small, or clip with an `inset()` (main
  thread, RecompositeLayer on a mask-free child) instead. Open frame 22 (desktop) has max-width 43.9 at opacity 0.108,
  so it is not opacity 0; it is under a 10 px blur.

### What Lean must prove for "same look" (B), if it is ever built

1. `shown_scale`: for one `Tr`, `shown tr time (fun k => c * g k) on k = c * shown tr time g on k` (induction on `run`;
   `value` is linear in the start and end values). This gives max-width = maxW·shown s and padding = pad·shown s, so the
   two layout properties of the faithful arm are one scalar, the one `--earn-s` shows. Add to
   `lean/Fw/Parts/NavEarnOpt.lean`.
2. `boxW` (new, `Nav.lean`): `w(s) = min(T + 2·pad·s, maxW·s)`, label centre `R − w/2`, menu x `R − w − gap − L`, as
   the faithful draw function. This is an engine-model statement; flex rules cited, not proved from engine code.
3. `geom_same`: for every frame k and both viewports, the variant's pill edges, label centre and menu x, computed
   from `shown --earn-s`, equal the faithful ones computed from shown max-width/padding (from 1 and 2). This is equality
   on every frame, not only on settled frames, and covers corners only where w ≥ 2·radius (or a stated opacity bound).
4. `handoff_same`: at the two layout-switch frames, laid-out geometry plus translate = faithful geometry.
5. Opacity, blur, translateY: unchanged functions (identity).
6. Work: per engine (`Fw.Engine`), the frames on which the earn subtree needs layout drop from `work` to 2 per
   push; style-changing frames stay equal to `work_le`'s faithful count.

Candidate A additionally needs `single_after_last_change` (for k ≥ k0, the shown value is one transition from the
shown value at k0) and a Bezier subdivision lemma: the timing curve restricted to [x0, 1] and renormalised is a
`cubic-bezier` with control x in [0, 1]. The kink time solves a cubic, so the keyframe offset is a float, and the
result is equal only within float precision.

## Q3. Verdict

- No pixel-identical GPU variant exists (class E impossible). INFERRED from snapping and resampling.
- Equal geometry (class Q candidate): B, the main-thread `@property` scalar with composited translates. It is not
  GPU-animated, but it moves the earn's per-frame layout and repaint to compositing. Not built: the bound arm shows
  no main-thread headroom to win.
- GPU-animated with the faithful creep: none. A matches the faithful look only after the last computed change, and
  needs two-segment keyframes plus float-precision offsets.
- Closest look-change option for the look-change class (L): A with one affine transition per layer, started at the last
  computed change. The label path differs where s < s*: at s = 0.5 desktop the label is about (T − 64)/2 px off, about
  15 px for T ≈ 95. That T is INFERRED; the real T must be measured. It runs fully on the compositor in both engines.

## The bound arm (what was measured)

Arm `bound`: the faithful page of `base` (same configuration hash, so the arm-identity check passes) plus one injected
stylesheet that sets `transition: none !important` on `[data-fw="nav-earn"]` and its two pseudo-elements, added after the
load and before the recorder starts (`packages/gate-breakpoints/src/smooth/bound.mjs`). The arm checks that the
button's computed `transition-duration` is `0s` and refuses the window otherwise. The button then shows the computed
value on every frame, which is the least main-thread work any variant of the earn transitions can leave (the earn-unmask and sheen
animations stay on): a lower bound
for the earn's layout and style work, never a candidate. It never enters a preset or the shipped site (a test pins
that the nav part has no `bound` variant).

Limits, all stated:

- The `.actions` `gap` transition (0.68 s, `nav.module.css` about `:134`) stays on; it is not an earn transition. The
  `earn-unmask` and sheen CSS animations stay on.
- Whether the bound is "lower" for the whole page rests on one INFERRED step: removing a transition removes work, it
  never adds any other than the final-value jump.
- The macOS runner VM (Playwright WebKit) and the iOS Simulator VM have no real GPU. They measure main-thread work
  (Layout, Paint, style, FunctionCall per zone) and not GPU or UI-process work, which is where a compositor-run
  animation would pay.
- Each end-push half is held 1400 ms (`END_PUSH.holdMs` 1000 before), so the close collapse (1.35 s after the push)
  is no longer cut off. Windows from earlier notes used 1000 ms and do not compare exactly with these.
- Why this arm was asked for first: the closest earlier data, the `look` arm (`morph.tween:scroll-lock` plus
  `nav:earn-no-transition`) in run 39634194664 (`10-2x-smoothness-webkit.md`), differed from base by about the A/A
  spread. Finish-zone render work per 2 s window, macOS: base 600.67 ms, aa 564.92, look 551.87; iOS Simulator: base
  225.84, aa 234.78, look 168.84. Layout covered ms, macOS: 72.92, 66.70, 59.68; iOS: 35.61, 27.59, 25.63. MEASURED
  there; that the earn's own gain sits below CI noise was INFERRED, and the bound arm now confirms it for main-thread
  work.

## Result of the bound arm

Go/no-go (plan step 1): build candidate B only if `bound` beats `aa` in Lean `across` (pair `base|bound`, verdict
`second`) in the finish zone, in at least 2 of 3 jobs of a leg with none disagreeing. MEASURED outcome: **no-go**. In
every decisive job of both WebKit legs the verdict is `same`; no job says `second`.

| leg | run | jobs | finish-zone verdict per job (`first` / `second` / `same` / insufficient) | verdict over jobs |
|---|---|---|---|---|
| macOS Playwright WebKit, 390 px | 39729682403 (`smoothness-webkit-mac-1..3`, 8 reps per arm, 48 windows each, none refused) | 3 | 0 / 0 / 3 / 0 | same |
| iOS Simulator, Mobile Safari, 430 px | 39754568950 (`smoothness-webkit-sim-1..3`, 6 reps, 36 windows each, none refused) | 3 | 0 / 0 / 3 / 0 | same |

The Lean zone verdict (`zoneVerdict`, twin `report.mjs`) compares the per-window render work per frame of the two arms
against the A/A pair, per job.

Finish zone (macOS: end windows, 2.8 s; Simulator: end windows plus the hero windows that ran at the page end), median over the kept windows of three jobs (MEASURED, the same runs; the Lean verdict is
over per-job medians, these are pooled medians):

| metric | mac base | mac aa | mac bound | sim base | sim aa | sim bound |
|---|---|---|---|---|---|---|
| render work ms per window | 725.77 | 714.48 | 733.64 | 225.73 | 204.04 | 200.90 |
| render work us per frame | 7382 | 7302 | 7252 | 5887 | 6257 | 5637 |
| RecalculateStyles ms | 505.20 | 494.74 | 498.68 | 147.63 | 143.94 | 127.40 |
| Layout ms (covered) | 89.56 | 87.60 | 85.25 | 32.83 | 30.28 | 28.94 |
| Layout records | 188 | 188 | 176 | 81 | 78 | 82 |
| Paint ms | 179.20 | 178.18 | 184.06 | 61.47 | 60.43 | 59.39 |

- The A/A spread (base − aa) is as large as the effect of removing every earn transition (base − bound), in both
  legs. macOS render work: base − aa 11.3 ms, base − bound −7.9 ms (bound is the slower one). iOS Simulator render work:
  base − aa 21.7 ms, base − bound 24.8 ms, bound − aa −3.1 ms. The iOS point estimate for bound is 11 % under base, but
  aa is 10 % under base too, so that gap is revisit noise.
- Class counts of the finish zone (deterministic / stable / quarantined; kMax 4, tMax 24, three jobs per leg): mac base
  2 / 5 / 4, aa 2 / 7 / 2, bound 2 / 8 / 1; sim base 3 / 5 / 3, aa 2 / 5 / 4, bound 2 / 5 / 4. The bound arm has no
  more deterministic counts than A/A. MEASURED.
- The hero and rest zones agree on macOS (`same` in 3 of 3 jobs for both). On the iOS Simulator they cannot decide: most
  hero windows have fewer than 5 kept frames in the hero zone (some windows put all their frames into the finish zone;
  the cause was not investigated), so those zones read `insufficient` and only the finish zone carries the sim verdict.
  In the sim leg most hero windows ran at the page end, so all their frames count in the finish zone: 12 of 18 hero
  windows for base, 13 for aa and 17 for bound (MEASURED, run 39754568950). This mix favours bound, because those
  windows cost about half the per-frame work of an end window. With end windows only, bound still does not beat A/A:
  render work per window base 239.49, aa 240.49, bound 233.32 ms (MEASURED, same run, reviewer re-reduction). Why hero
  windows start at the page end was not investigated.

How the three runs got there (all free runners, 3 of 6 dispatches):

| run | what | outcome |
|---|---|---|
| 39729682403 | all of `[earn-bound]`: mac 8 reps and sim 7 reps, 3 jobs each | mac complete. Sim jobs 1 and 2 stopped after 31 and 38 windows (the Simulator shut down, `Timeline.stop` timeouts), sim job 3 hit the 45 min limit with no artifact |
| 39744983394 | `[sim-only]`: 4 reps per sim job | jobs complete but each arm had only 4 to 6 kept finish windows, and the verdict needs at least 5 per arm (`MIN_REPS`); base had 4 in all three jobs. 4 reps cannot reach 5 |
| 39754568950 | `[sim-only]`: 6 reps per sim job | 36 windows per job, none refused, all three jobs decisive |

Pooling all eleven jobs of the three runs gives the same answer (macOS: 3 of 3 `same`; sim finish: 5 `same`, 3
insufficient, none `second`).

What the result does not say:

- No GPU or UI-process time is visible on either host (no real GPU). A compositor-run animation could still lower felt
  jank on a phone; the bound arm shows only that the main thread has nothing to gain from the earn animation. The
  phone replay (plan step 4) stays the open check.
- `bound` keeps the `.actions` gap transition and the earn mask and sheen animations (see above); a variant that also
  removed those could save more, but that would change the look further.
- The sim legs are scripted in-page scroll (no wheel device), so the iOS numbers say nothing about touch input.

TS stand-ins (no new Lean was written for this task): the `base|bound` pair in `PAIRS`
(`packages/measure-webkit/src/profile/report.mjs`) reuses the existing Lean-twin verdict functions; the go/no-go rule
(at least 2 of 3 jobs, none disagreeing) was applied by the builder from the Lean `across` table, not computed by code.

## Why the bound arm reads `same` (negative result: mechanism, Lean why, lesson)

Pinned unit: the NO-GO for candidate B, runs 39729682403 (macOS), 39754568950 (iOS Simulator), 39744983394 (too few
windows, insufficient), with the Lean `across` verdict `same` for the pair `base|bound` in the finish zone.

- **Mechanism (MEASURED numbers, INFERRED cause).** Removing every earn transition removes only the work of the earn
  button's own restarted transitions. The finish-zone medians above move by less than the A/A spread (macOS render work:
  base − aa 11.3 ms against base − bound −7.9 ms; Simulator: 21.7 against 24.8 ms), and the layout and style counts fall
  only a few percent (macOS Layout records 188 to 176, RecalculateStyles 505 to 499 ms). The main thread's per-frame
  style and layout work while `--morph` moves is spent mostly on what else changes in those frames (nav width, actions
  gap, hero and platform parts); the earn button is one box with two pseudo-elements among them. That the earn share is
  small is INFERRED from the table; the measured fact is only that it sits inside the repeat-to-repeat spread.
- **Lean why (CONFIRMED, `lean/Fw/Gate/Smooth.lean`, `Fw.Measure.WebKitProfile.zoneVerdict` = `hitchVerdict`).** A job
  says `second` only when every repeat of base has more render work per frame than every repeat of bound
  (`hitchJudge_second` :597, `above`), and only if the A/A pair is not itself told apart; otherwise it says `same`
  (`hitchJudge_same` :602 when the two ranges overlap, `hitchVerdict_noisy` :652 when the A/A pair separates). The jobs
  then go through `across k` with `k = agreeNeeded 3 = 2` (:697): a verdict over 3 jobs needs 2 of them to say
  `second` and none `first`; with 0 `second` the branch is `across_same` (:735). The median shift of bound against base
  (macOS −1 %, Simulator 11 %) is no larger than the A/A gap against base (2 % and 10 %), so the repeat ranges are not
  disjoint and the premise of `second` is absent in every job. Which of the two `same` branches (overlap or noisy A/A) fired in each job is not recorded in the report
  (INFERRED: overlap, from the pooled table). The theorems say why a `second` needs separated ranges, not why the earn
  work is small; that is the mechanism above.
- **Lesson.** Measure the bound of a candidate (all of its work removed) before building it: a candidate cannot win
  more than its bound. A bound that stays inside the A/A spread ends the candidate on that metric and host, and the
  A/A spread sets the smallest effect a CI job can show. A candidate whose gain would sit on the compositor or GPU
  needs an instrument that sees that thread (the phone), because a VM without a GPU reads `same` for it by
  construction.

Report: `results/earn-bound/report.json` is valid. `fwcore` `console.report` answers `"invalid":[]` (an empty
`invalid` list is the accepted case, not a refusal) and one item "Review the report earn-bound-webkit" with state
`unposted`; it is not posted. Ledger: `research/findings/ledger.json` tracks this candidate (`nav.earn.noTransition`, n 39) but is outside the
task's writes, so the lead adds one `notes` row (entry = that finding's `candidate` text, task `earn-bound-arm`, field
`mechanism`) carrying the three bullets above: runs 39729682403, 39754568950, 39744983394; `across` `same` in 3 of 3
jobs per leg; `hitchJudge_second`, `hitchVerdict_noisy`, `across_same`; the lesson.

## What this changes in the plan

- PLAN §6.2 / look-change rows (`nav:earn-no-transition`): add "GPU variants: no class E variant exists. B
  (`@property` scalar plus translates) is the class Q candidate and is not built: the bound arm shows no
  main-thread headroom on CI. A (WAAPI) is an L option." Keep the default faithful.
- Work graph: `earn-gpu-b` (Lean `shown_scale`, `boxW`, `geom_same`, `handoff_same` first) stays unstarted; reopen it
  only if the phone replay (plan step 4, `base` against `bound` with device frame intervals) shows a gap that the VMs
  could not.
