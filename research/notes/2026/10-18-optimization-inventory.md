---
id: 2026-10-18-optimization-inventory
kind: note
title: "Inventory: what we would prove (original vs optimized) for every animated part, and what Lean and CI already give us"
status: review
created: 2026-10-18
topics: [lean, rendering, chromium, webkit, parity, work-dominance, inventory]
---

# Optimization inventory: visual equivalence + work dominance, per part

Question (user direction 2026-10-18): for each animation or rendering optimization of the homepage rewrite, what would
we prove in Lean, original part vs optimized part, so that (1) the picture is the same and (2) the engine does less
work? The engine behaviour comes from engine source. CI counts check the model, and the phone is only a spot check.
This note is the inventory. It proves nothing new.

Labels: **CONFIRMED** means a cited source (engine file:line@sha7, repo file:line@efde437, or a doc). **MEASURED**
means a number from a repo file, and the note says whether it came from CI or a local run. **INFERRED** means my
reasoning. Lean and repo cites are at `efde437`. Engine cites are the pinned sparse clones `chromium@f842f52` and
`WebKit@862f17d`.

## 0. Answer first

- **The page has 14 animated mechanisms.** Five are already parts with a Lean spec: `engine.scroll`, `nav.hitTest`,
  `hero.countdown`, `hero.exit` and `morph.mount`. The other nine are only described in `02-site-anatomy` §2, and four
  of them are the remaining `morph.*` ports. CONFIRMED `apps/site/src/parts/*/part.json`, `docs/team/work-graph.json`.
- **About 25 optimization candidates exist.** They fall into four proof classes:
  - **E, exact:** the observed values are equal at every state.
  - **E-s, exact per sample:** values are equal at every scroll offset or time t, but are produced by another thread
    or clock.
  - **Q, equal after quantisation:** values differ by less than one 8-bit step or the PL tolerances.
  - **L, look change:** a user decision, never a parity proof.

  Three E proofs exist today:
  - `NavHitTest.hitSkip_morph` and `allowHit_eq_faithful`;
  - `HeroCountdown.strip_shows_same`;
  - `NavHitTest.changed_write`.

  One work proof exists: `EngineScroll.batched_le_faithful` and `batched_le_one`, a forced-layout model.
- **Missing piece: an engine model in Lean.** We need a map from "property p changed on element x" to "the pipeline
  stages it dirties" (style, layout, paint, composite-only) for each engine. Each clause would cite engine source. The
  facts it needs are CONFIRMED in source (§3), and they differ by engine: blur is accelerated in WebKit and
  main-thread in Chromium. Opacity crossing 1 relayouts in WebKit only.
- **The theorem shape reuses what exists.** The visual side is a per-state equality of observations, with tolerances
  from `Fw.Gate.Compare` (PL1 ½ px, PL2 1e-3). The work side is a per-frame count vector `≤` from the engine model.
  `Fw.Screen.screen_sound` then gives "no frame costs more under any non-negative coefficients", and
  `Fw.Measure.noMoreWork_sound` says which CI count types may confirm it.
- **CI can validate today in Chromium only.** The `chromium-counts` lane gates 60 of 70 types on the original. It has
  `trace.Animation.compositeFailedBits` (deterministic) as a direct check of "is this animation on the compositor".
  The WebKit Simulator lane serves the original only. On WKTR every page-work count is quarantined. The one WebKit
  dominance result, hit-skip `RecalculateStyles` 164 → 19, is a **local** run, so it is not a result yet.

## 1. Parts and how the original animates them

The faithful part must reproduce these drivers, including the bad ones (PLAN.md:666, the `faithful` kind). Line
numbers in the "source" column point into `research/kickoff/02-site-anatomy-and-rewrite.md` (written A:<line>). That
file describes the original's JS and CSS by line; no Fastwork code is copied here.

### 1.1 The nine end-of-page parts (rev 9 scope, PLAN.md:642-647)

| part | port state (CONFIRMED) | original driver | what it writes per frame | engine path today | source |
|---|---|---|---|---|---|
| `engine.scroll` | part + Lean; variants `faithful`, `batched` | one passive `scroll`/`resize` listener → one rAF `iE` → every registered callback in Set order; IO `rootMargin:100% 0px` toggles `active` | nothing itself; it sets the frame structure (reads and writes interleave across callbacks) | main thread; forced style or layout whenever a read follows a write | A:79; `lean/Fw/Parts/EngineScroll.lean:1-22` |
| `nav.hitTest` | part + Lean; `faithful`, `hit-skip`, `elements-skip` | per frame, never IO-gated: `getComputedStyle`, 3-4 rects, `pointer-events='none'` write, `elementFromPoint`, restore write | `pointer-events` inline (style write, inherited); class `is-on-dark` | forced style recalc and a hit test every frame, in both engines | A:119-125; `NavHitTest.lean:1-24` |
| `hero.exit` | part + Lean; `faithful` only | rAF body: `.hero-track` rect → `--exit-opacity` on `.hero`, `pointer-events` | an inherited custom property, read by `calc()` in opacity, translate and `blur(scatter·18px)` of about 230 descendants | main-thread restyle of the subtree every scroll frame; custom properties are never accelerated (§3) | A:137, A:142; `HeroExit.lean:1-21` |
| `hero.countdown` | part + Lean; `faithful`, `strip` | 1 s `setInterval` + a rAF spring per digit (k 280, c 18, m 0.3, 16 ms slices) | `translateY` on 10 `.face` spans per digit, each `will-change: transform` (about 80 layers) | the transform itself is compositable, but the JS writes it from rAF (main-thread style per frame); WebKit drops a face's backing store when it leaves the clip (v1) | A:139; `HeroCountdown.lean:1-20` |
| `morph.mount` | part + Lean; `faithful` landed, no delta (gate run 39053169745, git log `ce9692e`) | IO `dN` mounts the whole panel within 200 % of `#platform`; non-passive capture `wheel`/`touchmove` listeners | DOM insertion of about 105 images and 5 columns in one scroll frame | one 42-75 ms (Chrome 6x) or about 106 ms (phone) frame | A:259-266; `MorphMount.lean` |
| `morph.tween` | not ported | push at the end → **680 ms rAF tween**, ease-out cubic $1-(1-t)^3$, reversible from the current value; `preventDefault` + `scrollTo(instant)` pin | inline `--morph` on the header; readers: nav `top/width/height` (layout), `color-mix` background, `border-radius`, `backdrop-filter` blur (paint), logo `left`, actions `gap`, Join `max-width/padding/opacity`, panel opacity/blur/scale | layout + paint every frame; WebKit repaints a resized composited layer completely (v1, `RemoteLayerBackingStore.mm`) | A:267-286 |
| `morph.panel` | not ported | derived flags from `--morph`: `is-morphing`, `is-on-dark` > 0.2, `is-expanded` > 0.92, aria/tabindex; `--morph-fade` blurs `#platform` out | classes + `filter: blur(calc((1-fade)·12px))` on the whole platform section (`blur(0)` at rest) | class flips restyle; the blur is main-thread in Chromium | A:270-278, A:234 |
| `morph.countdown` | not ported | the second countdown in the panel, same spring and faces as `hero.countdown` | as `hero.countdown`, plus about 80 more layers in the hidden menu | as `hero.countdown` | A:139, A:263 |
| `morph.columns` | not ported | 5 columns of about 21 eager images with 16 s up/down marquees | `transform` keyframes (CSS) | compositor-eligible, but large backing stores (five 1282² PNGs) | A:261; `01-prior-loop-lessons.md:136` |

### 1.2 The other sections (shells first, then faithful ports behind the swap check, PLAN.md:1042)

| part (work-graph id) | original driver | properties | engine path | source |
|---|---|---|---|---|
| `nav` / `nav.langMenu` (`port-nav`) | CSS transitions and keyframes | `backdrop-filter: blur(calc(20px·(1-morph)))`, background .7 s, width .68 s; load-time `mask-position` unmask and sheen | width is layout; mask is paint | A:113-118 |
| `hero.orbit` (`port-hero`) | load-only CSS keyframes, desktop, with inline vars per card | transform, translate, scale, opacity, `preserve-3d` | compositor | A:136 |
| `hero.accent` | CSS: `stroke-dashoffset` on 3 SVG paths, inline `width` transition (0.9 s), `step-end` opacity "boil" | dashoffset, width, opacity | WebKit: dashoffset change ⇒ layout (§3); width ⇒ layout in both engines | A:138 |
| `hero.cue` | CSS float loop + `filter: blur(scatter·18px)` | transform; blur | blur repaints while scattering | A:142 |
| `people.card` (`port-people`) | at the 0.72 threshold: CSS transitions (opacity 0.7 s, blur 14 px → 0 over 1.6 s, lift 0.9 s) + a JS lerp of `--future-shrink` at 22 % per frame | visibility, opacity, filter blur, transform, border-radius | Chromium cannot composite blur (§3); a triple flip at one threshold | A:149-160 |
| `people.o` | CSS layout transitions on re-entry | `grid-template-columns` 0.6042em → 5.25em, height, max-width, width, margin, border-width | layout every frame (57 layouts, Chrome 6x) | A:161 |
| `people.deck` | x-mandatory scroll-snap; `--profile-scale` JS lerp; per-role widgets (vinyl spin, feed panel-in) | aspect-ratio boxes; transform | WebKit relays out on every toolbar step (finger only) | A:162 |
| `people.carousel` | `{#if}` swap about every 1 s, mounting fresh `<img>`; `avatars-exit` keyframes | width, flex-basis, margin-right, border-width; pop ends at `opacity:1` | layout in both engines; WebKit adds a presence-flip layout (§3) | A:163 |
| `pain.notes` (`port-pain`) | 3 s `setInterval` with `Math.random()` positions and colours; per-frame read of `.commission-card` rect | DOM insertion, transform | still runs at ≤ 860 px where the notes are `display:none` | A:165-181 |
| `commission.typing` (`port-commission`) | per frame: two rects → `setProperty('--commission-*')` → `style.height` → `Range.getClientRects()`; typing 28 ms per character, caret `step-end`, rAF width count-up | custom props, height, text nodes, width | forced layout after style writes every frame; WebKit runs interleaved layout inside style recalc under size containers | A:183-202 |
| `platform.sweep` (`port-platform`) | CSS 4 s infinite | `background-position` on `background-clip:text` | main-thread style + paint every frame | A:231 |
| `platform.glint` | SMIL | `x1/x2` on a `linearGradient` | main thread | A:232 |
| `platform.entries` | CSS keyframes | `filter: blur(8px)` + opacity + transform | blur on main in Chromium | A:233 |
| `platform.stageBg`, `platform.marquee` | static blur + grain blend; 90 s / 56 s transform loops | blur(16px), `mix-blend-mode`; transform | paint of large stores; compositor | A:235-236 |
| `engine.scene` (cross-cutting) | section IO toggles `data-start-selling-scene` → `animation-play-state: paused !important` on `:where(*)`, `content-visibility:auto` | subtree-wide style | 29-32 ms style records; the gate flapped 800 times in 10 s | A:303 |

At rest, the sweeps and the glint cost ULT 120, PrePaint 120 and Paint 240-602 per 2 s. Pausing both drops PrePaint
from 120 to 5 (A:238-243, v1, OBSERVED).

## 2. Optimization candidates and their claimed equivalence

Sources: v1 backlog rows `01-prior-loop-lessons.md:121-142` (written KD#n), anatomy A:*, PLAN presets PLAN.md:678-679.
The column "visual" gives the proof class from §0. The column "Lean today" names an existing theorem, or "—".

### 2.1 The pre-registered end-of-page decision (PLAN.md:1046, Q6 at PLAN.md:1237)

| arm | what changes | visual | work claim | evidence |
|---|---|---|---|---|
| `original` | the 680 ms scroll-jacked tween (faithful) | reference | — | — |
| `v1-best` (g0.0m as flags) | finger-following menu (PR-040), constant 20 px glass (g0.0k), pre-painted People card (+22 MB), compositor morph | **L**: PR-040 and the constant glass are look changes the user accepted in v1; parity is not claimed | phone longest frame 584 → 42 ms, 80 → 4 slow frames | A:284-288, KD#11 (v1, OBSERVED) |
| ablation arm | generated `frozen`/`static`/`nopaint`/`box` | not equal by design; fairness rule: boxes equal, script and layout counts equal, only paint and raster lower | attribution only | PLAN.md:673 |

### 2.2 Per-part candidates

| # | part | candidate (v1 name) | change | visual | work claim (engine reason) | Lean today |
|---|---|---|---|---|---|---|
| 1 | engine.scroll | `batched` | reads before writes, one pass per frame | **open**: each read may now see pre-write values (`batched_le_faithful` docstring says so) | forced style and layout ≤ faithful, and ≤ 1 per kind | `batched_le_faithful`, `batched_le_one` (`EngineScroll.lean:313,324`) |
| 2 | engine.scroll | `observers` (KD#1) | scroll listener → IO/RO; no per-frame rect reads | E, if every threshold is an IO threshold | 0 forced layouts in steady scroll | — |
| 3 | nav.hitTest | `hit-skip` | skip the probe while morph > 0.2 | **E**: `is-on-dark` is forced true | −1 forced style, −1 hit test per frame in that range | `hitSkip_morph`, `expanded_masks` (`NavHitTest.lean:211,220`) |
| 4 | nav.hitTest | `elements-skip` (nav-hit-test) | `elementsFromPoint` skipping the nav subtree except re-enabled boxes; no `pointer-events` write | **E** under the allow-list premise | removes 2 style writes, hence the forced recalc | `allowHit_eq_faithful`; `firstOutside_ne_faithful` shows the premise is needed (`:165-187`) |
| 5 | nav.hitTest | write-on-change | set `is-on-dark` only when it changes | **E** | fewer style invalidations | `changed_write` (`:235`) |
| 6 | hero.exit | `hero-exit-threaded` (v6, KD#2) | JS var → CSS scroll-driven animation of opacity/translate on the consumers | **E-s**: `exitOpacity_linear` + `_before`/`_after` show the fade is a clamped linear map of the scroll offset, which is what a linear keyframe on a scroll timeline computes (INFERRED; the timeline's progress formula still needs an engine cite) | 0 inherited-var writes per frame; compositor-only if all consumers are compositable. The `blur(scatter·18px)` on the cue and copy is **not** compositable in Chromium (§3) and `pointer-events` is not animatable on the compositor | `exitOpacity_*`, `consumers_*` (`HeroExit.lean:120-185,417-450`) |
| 7 | hero.countdown | `strip` (cd-strip, KD#12) | 10 faces per digit → one 12-entry strip | **E** inside the clip window | layers 80 → 16 (`layerBudget`, part.json); paint on re-entry lower in WebKit | `strip_shows_same` (`HeroCountdown.lean:378`) |
| 8 | hero.countdown | `cd-roll-ca` (WAAPI roll), hidden-skip, clock-aligned timer (KD#19) | spring → WAAPI transform; pause off-screen; derive digits from the clock | WAAPI: **E-s** only if the spring trajectory is restated as keyframes (T2 in v1); hidden-skip: E when not visible; clock-aligned: E at every second boundary | 0 rAF per frame while rolling; 0 work off-screen | spring and `remainingSeconds_*` exist, no equivalence yet |
| 9 | morph.tween | g0.0b: one WAAPI `cubic-bezier` | rAF tween → a WAAPI animation with the same curve | **E-s**: $1-(1-t)^3$ is exactly `cubic-bezier(1/3, 1, 2/3, 1)` (the x-polynomial is the identity when $x_1 = 1/3, x_2 = 2/3$; the y-polynomial expands to $3t-3t^2+t^3$). INFERRED algebra, provable by `ring`. Reversal from the current value needs its own lemma | if the animated properties stay `top/width/height/gap`, layout remains: the curve change alone saves only script | — |
| 10 | morph.tween | CM / compositor-morph (PR-030) | transforms on a scroll timeline; rounded box from 4 corner clippers | **Q at best**: scaling a box is not resizing it (radius and text do not scale), so equality holds only for the clip outline. v1 tiered it, it did not prove it | paint per morph frame 0.28-0.29× on the phone (v1) | — |
| 11 | morph.panel | g0.0f flat GPU fills + clip; constant glass (g0.0k) | animated backdrop blur → a constant one | g0.0f: Q, to be shown; constant glass: **L** | no backing-store resize (WebKit) | — |
| 12 | morph.mount | lazy or near-end layer warm-up (v14, D1 always-built card) | mount at a still moment, not in a scroll frame | **E** after mount; the first open must match | moves the 42-106 ms mount out of motion | `mountNext_mono`, `armed_*` (`MorphMount.lean`) give the trigger, not the cost |
| 13 | morph.countdown | strip + own clock layer (KD#12) | as #7, plus isolate the clock from the big menu layer | E (as #7) | menu-centre redraws per open 196 → 11 (v1) | reuse `strip_shows_same` |
| 14 | morph.columns | g0.0h columns as a still picture; `dprSized` images (KD#16) | marquee → still image while closed | E only while hidden or covered | v1: smaller files did **not** buy frames; backgrounds off: 16 → 3 slow frames (ablation) | — |
| 15 | hero.accent | boil-ca: `step-end` → keyword `linear` ramp with byte-identical frames; accent-wipe | timing function swap | E per sample, if every sample lands on a plateau (v1 says "byte-identical frames"); a proof needs the sample grid | 240 style + 481 paints / 4 s → 8 + 33 at the page bottom (all of KD#6, v1) | — |
| 16 | people.card | MQ-gated shrink (KD#3) | stop the JS lerp where CSS forces scale 1 and radius 0 | **E** (CSS overrides the written value) | Chrome 6x 66.5 → 71.6 fps (v1) | — |
| 17 | people.card | blur tail cut 1.6 → 0.9 s; PR-041 instant reveal; g0.0m pre-painted | shorter blur, skip fade after a flick, keep layers | tail cut: **Q** (claims the tail is below visibility, to be shown); PR-041 and pre-paint: **L** and E respectively | reveal frame 50 → 30.5 ms (v1) | — |
| 18 | people.o | FLIP (people-gpu, PR-031) | layout animation → set the final size, slide with transform | **not E**: v1 classed it as a proposal because sub-pixel frames differ | Chrome layouts 56 → 4 (v1) | — |
| 19 | people.carousel | st6 (clip-path/translate) + keep slots mounted + rest at 0.999 (KD#8) | width/margin animation → clip + translate; never let opacity reach 1 | st6: **not E** (different intermediate geometry); 0.999: **Q**. With $\alpha = 0.999$ the 8-bit composite moves by at most $0.001 \cdot 255 = 0.255 < \tfrac12$ step under round-to-nearest. INFERRED; it depends on how Skia and CoreAnimation quantise alpha (open) | WebKit: no layout from the presence flip (§3); slow frames at rest 19-27 → 0 (v1) | — |
| 20 | people.deck | `cqiFormula` sizing (g0.0j) | `aspect-ratio` + `height:auto` → `calc(100cqi·764/353)` | **E** when the container's inline size equals the shell width (algebra) | largest layout 25.7 → 0.4 ms per toolbar step (v1, finger only) | — |
| 21 | pain.notes | arm the interval only when visible; solid-colour layers for the dark flip | — | E (notes `display:none` ≤ 860 px) | 33 Hz idle engine → 0 | — |
| 22 | commission.typing | commission-forced-layout (reads first, line count via RO); typing-chunks; no `container-type` above per-frame text | reorder; 2 characters per step | reorder: as #1; chunks: **L/Q** (every other intermediate frame is skipped) | Chrome 1x layouts 226 → 97 (chunks, v1) | `batched_le_faithful` applies to the reorder |
| 23 | platform.sweep | sweep-exact G3 / illusion-sweep / translateBand (PR-009) | `background-position` → a gradient band on `::after` moved by `translateX` | **E-s** if band position = background offset at each t (to prove) | compositor-only motion | — |
| 24 | platform.glint | glint-ca G1 | SMIL `x1/x2` → transform | E-s (to prove) | as #23 | — |
| 25 | engine.scene / idle | pause per element, hysteresis (KD#10, KD#18) | per-element `getAnimations().pause()` with covered and faded owners | **E** while the element is not visible (premise: covered or opacity 0) | 1,816 restyles/s mid-page → about 0; Simulator 65 → 2 layouts, 74 → 0 paints, "pixels identical" (v1) | — |

## 3. Engine facts that decide the work side (CONFIRMED in pinned source)

| fact | Chromium @f842f52 | WebKit @862f17d |
|---|---|---|
| properties that may animate off the main thread | opacity, rotate, scale, translate, transform, filter, backdrop-filter; background-color and clip-path only with a native paint worklet: `third_party/blink/renderer/core/animation/compositor_animations.cc:344-372, 400-424` | opacity, filter, backdrop-filter, transform, translate, scale, rotate (`always`); offset-* only with threaded animations: `Source/WebCore/css/CSSProperties.json:7114, 10263, 10639, 12112, 12260, 12281, 12306` (and 7004-7077); flag consumed by `css/scripts/process-css-properties.py:731-735, 3823-3825` |
| pixel-moving filter (blur) | **not** composited: `kFilterRelatedPropertyMayMovePixels` (`compositor_animations.cc:408-416`); backdrop-filter stays composited (`:417-420`) | `filter` is accelerated `always` (`CSSProperties.json:10263`) |
| custom property (`--morph`, `--exit-opacity`) | compositor only if a CSS Paint worklet reads it, else unsupported (`compositor_animations.cc:426-440`) | never accelerated (`Source/WebCore/style/StyleInterpolation.cpp:256-265`, custom → `false`) |
| scroll-driven animation on the compositor | needs a `UserScrollable()` scroll node on the source (`compositor_animations.cc:1136-1158`) | needs the `threadedScrollDrivenAnimationsEnabled` setting and a scrollable area (`Source/WebCore/animation/ScrollTimeline.cpp:417-425`; updater `AcceleratedTimelinesUpdater.cpp:75-82`) |
| `stroke-dashoffset` change | — (not read) | forces layout: `svgDataChangeRequiresLayout` (`Source/WebCore/style/StyleDifference.cpp:136-163`, line 161) |
| opacity crossing 1 | — (not read; v1 says Blink does not relayout, KD#8) | forces layout when `isOpaque()` flips (`StyleDifference.cpp:208-215`, inside `miscDataChangeRequiresLayout` at 173) |

MEASURED in CI fixtures (`packages/measure-chromium/README.md:147-151`): a compositor animation of transform/opacity
gives Paint 0, Layout 0 and cc.Commit/Activate 0, but UpdateLayoutTree is still 120 (one main-thread style update per
BeginFrame). A main-thread animation (width, background-color) gives Paint 240 and Layout 162. So the model's
"compositor-only" class must be "0 paint, 0 layout, 0 commit". It must **not** be "0 style".

## 4. Lean we already have, and how a part theorem would reuse it

| module | what it states (from the docstring math) | role in "visual equivalence + work dominance" |
|---|---|---|
| `Fw/Spec/Screen.lean` | a run is per-frame count vectors; `screen_sound` (`:142`): if $V \le B$ componentwise in every aligned frame, then $T_{\kappa,c}(v) \le T_{\kappa,c}(b)$ for every $\kappa$ and every $c \ge 0$ | the final step: componentwise work dominance ⇒ no frame costs more under any linear engine model |
| `Fw/Spec/Cost.lean` | $w = (s, e, \ell, k)$ = script µs, restyled elements, laid-out objects, painted kpx; `mainUs_mono` (`:59`), `compositorOnly_same_main` (`:80`), `onTime_of_le` (`:99`) | the per-frame work vector the engine model produces; "compositor-only" variants keep main cost |
| `Fw/Spec/Frames.lean` | `tick(dt)` = 120 Hz ticks by exact integer rounding; `countAbove` and `tick5_eq_countAbove` | turns frame times into the slow-frame count of the phone spot check |
| `Fw/Spec/Verdict.lean` | v1 A/B rule: better iff the ranges are disjoint with n ≥ 3 (`better_sound`, `:80`) | validating timing on the phone or CI timing lanes, not counts |
| `Fw/Spec/Stage.lean` | topic lifecycle R → I → D → F → V → L with gates (`advance_one`, `enter_F`) | where a proved candidate moves (D → F needs the proof, V needs the CI confirmation) |
| `Fw/Parts/EngineScroll.lean` | `forced_ρ(d, as)` counts forced style or layout updates over an access list; `batched_le_faithful`, `batched_le_one` | the template for the work side: an **operational** model over accesses. Extend `Access` with the property class from §3 |
| `Fw/Parts/NavHitTest.lean` | hit stacks, `faithfulHit`, `allowHit`, `isOnDark`; skip theorems | the template for the visual side: an observation (`isOnDark`) is equal whatever the skipped input is |
| `Fw/Parts/HeroCountdown.lean` | exact spring, faces and strip; `strip_shows_same` | the template for "different DOM, same visible picture inside a clip" |
| `Fw/Parts/HeroExit.lean` | `exitOpacity` clamp, linear, monotone, Lipschitz; CSS consumers restated; `pill_threshold` (single owner of 0.72) | gives the value function f(scroll) that a scroll-timeline variant must equal |
| `Fw/Parts/MorphMount.lean` | arming geometry, push take rule, listener actions, `mountNext_mono` | the trigger side of morph variants; no cost model yet |
| `Fw/Gate/Compare.lean` | PL2: strings equal or same skeleton with numbers within $10^{-3}$; PL1: boxes within $\tfrac12$ px, exact decimals | the **equivalence relation** for the visual side (Q class) |
| `Fw/Gate/{Items,State,Rule,Scope,Reach}.lean` | per-part item pairing, per-state verdicts, pass/fail rollup, the probe scope (hypothesis H), cells an engine port cannot reach | the states over which "∀ states" ranges: breakpoints × sampled scroll/time stops |
| `Fw/Site/Breakpoints*.lean` | 30 media conditions as decidable predicates; the 124-load matrix sees every edge | equivalence must hold in every band; variants gated on an MQ (#16) use these predicates directly |
| `Fw/Measure/Classes.lean`, `Tolerance.lean` | determinism classes; `det_frames_sound`, `margin_sound` (margin $2t$), `quarantined_unsound`, `noMoreWork_sound`/`_cost` | which CI count types may confirm a predicted dominance, and with what margin |
| `Fw/Measure/{Zones,ZoneBaseline,WebKit,Arms,Splits,Neutral}.lean` | zone sums, cross-run baselines, WebKit reductions, by-design quarantine, containment splits, N0/N1 | the reduction from raw CI counts to the vectors `screen` compares |

**Proposed shape (INFERRED).** For a part $P$ with variants $o$ (faithful) and $v$ (optimized), states $s \in S$
(breakpoint env × scroll offset × time × input), and an engine $\epsilon \in \{\mathrm{cr}, \mathrm{wk}\}$:

$$\textbf{(vis)}\quad \forall s \in S:\ \mathrm{obs}(v, s) \approx_{\mathrm{PL}} \mathrm{obs}(o, s)$$

$$\textbf{(work)}\quad \forall s \in S:\ W_\epsilon\big(\Delta_v(s)\big) \le W_\epsilon\big(\Delta_o(s)\big)\ \text{componentwise}$$

Here:

- $\mathrm{obs}$ is the restated computed values that reach paint (or the visible part of them, as in
  `strip_shows_same`).
- $\approx_{\mathrm{PL}}$ is `Fw.Gate.Compare`'s relation, or equality for class E.
- $\Delta(s)$ is the list of DOM/style accesses and property changes in the frame.
- $W_\epsilon$ is the new engine model: it maps a change list to `(forced style, forced layout, style elements,
  layout objects, paint kpx, layers, compositor-only animations)`. Each clause cites §3.

`screen_sound` then gives "never more costly under any non-negative coefficients". `noMoreWork_sound` says which CI
types (deterministic per frame, stable by totals with margin $2t$) can confirm the prediction on a run.

## 5. CI count types that can validate predicted work

| lane (workflow) | engine / target | count types | classes | can it judge a variant today? |
|---|---|---|---|---|
| `chromium-counts.yml` (`packages/measure-chromium`) | headless Chromium, `HeadlessExperimental.beginFrame` stepping, 430×932 DPR 3, linux-arm64; original **and** rewrite | 70 types on the original arm (`classes.frozen.json`, profiles `swipe-v1`, `swipe-touch-v1`): `trace.*` (UpdateLayoutTree, Layout + dirtyObjects/totalObjects/partial, PrePaint, Paint, RasterTask, HitTest, FireAnimationFrame, FunctionCall, EventDispatch, IntersectionObserverCompute, ResizeObserverNotify, ScheduleStyleRecalculation, InvalidateLayout, Layerize, Layer.created/deleted, cc.Commit/Activate/Draw, `Animation.begin/instant/compositeFailedBits`, N1 sheet events), `metric.*` (LayoutCount, RecalcStyleCount, Nodes, …), `census.*` (layers, tiles, drawing area px), `raster.*` (invalidation rects/area/layers), `n0.*`, `hasDamage` | swipe-v1 original: 32 deterministic, 28 stable, 10 quarantined; rewrite arm 52 types (44 det). Quarantined: Paint, RasterTask, DisplayItemListRaster, LayoutObjects, Nodes, MajorGC, … (MEASURED, CI runs 39049264131, 39049466889, 39049469621, `classes.frozen.json`) | **yes**, for the det/stable types. Paint itself is quarantined, so paint predictions must use `raster.invalidationAreaPx` (stable) or `census.*`. `trace.Animation.compositeFailedBits` (det) checks the compositor-eligibility clause of the model directly |
| `webkit-sim.yml` (`packages/measure-webkit`) | Mobile Safari in the iOS Simulator, Web Inspector Timeline, 430×775 DPR 3 | Timeline records per scroll step: RecalculateStyles, Layout, InvalidateLayout, Paint (+ quad area), Composite, FireAnimationFrame, FunctionCall, EventDispatch, ObserverCallback, TimerFire; `RenderingFrame` absent on iOS 27.0; LayerTree census (29 reason flags, layer counts) | per step: Composite, FireAnimationFrame, ObserverCallback, EventDispatch det; RecalculateStyles stable (tol 1); Layout/Paint/InvalidateLayout quarantined per step, stable at total (README:45-70, 260-265) | **original only**: the lane stops for any other preset or flag (`.github/workflows/webkit-sim.yml:33-42`). The rewrite numbers (hit-skip 164 → 19, batched 164 → 145, strip +74 rAF) are a **local** Simulator run (`packages/measure-webkit/README.md:267-290`; `10-17-plan-evidence.md:168` says "MEASURED locally (debug)"), so they are not a result |
| `wktr.yml` (`packages/measure-wktr`) | WebKitTestRunner, iOS 26.5 Simulator, `window.internals` | styleRecalcs, styleUpdateSizeSum, lastStyleUpdateSize, layoutUpdates, compositingUpdates, styleInvalidations, renderingUpdates, layerFlushes | only renderingUpdates and layerFlushes are deterministic (driven by the harness); every page-work type is quarantined (MEASURED, CI runs 39036983052, 39042087508, `packages/measure-wktr/README.md:92-112`) | **no** for dominance (`quarantined_unsound`); useful only for direction and to cross-check the WebKit model's layout clauses once timers are frozen |
| phone (spot check) | iPhone, finger or scripted | frames > 50 ms per 100 | — | spot check only: original finger 2.6 vs scripted 22.9 per 100 (MEASURED, `10-18-phone-session-1b.md`) |

## 6. Gaps

1. **No engine model in Lean.** §3 lists the facts. Nothing yet maps a property change to dirtied stages, so no
   candidate except the access-order ones (#1, #22) has a work proof. INFERRED priority: build it first.
2. **WebKit validation is local-only.** `webkit-sim` does not serve the rewrite, and the WKTR page counts are
   quarantined. Until the lane serves `?fw=`, WebKit dominance stays a model prediction.
3. **`batched` parity is open.** The cost is proved, but the reads may see different values
   (`EngineScroll.lean:309-312`).
4. **Q-class premises need source.** How Skia and CoreAnimation quantise alpha (for 0.999), and how the
   scroll-timeline progress is computed (for hero.exit), are not yet cited in engine source.
5. **Several v1 fixes are not visual-equal.** FLIP (#18), st6 (#19), typing chunks (#22) and CM (#10) are L or Q at
   best. They need a user decision or a tolerance, not a parity theorem.

## What this changes in the plan

- **PLAN §6.2 (variants), the `optimized` kind row:** add the requirement "an `optimized` variant lands with a Lean
  pair: a visual theorem of class E, E-s or Q (Q needs its tolerance from `Fw.Gate.Compare`), and a work theorem
  over the engine model; class L goes to `proposal`".
- **PLAN §6.6 (parity levels), the V-h work parity row:** add a predicted-vs-counted check. The model predicts the
  dominance per count family. `chromium-counts` confirms it on det/stable types through `noMoreWork`, and a
  disagreement is a model bug to fix from engine source, not a tolerance to widen.
- **Work graph:** new tasks:
  - `engine-model-lean`: `Fw/Engine/{Chromium,WebKit}.lean` from §3, every clause with a file:line@sha7;
  - `webkit-sim-rewrite`: let `webkit-sim.yml` serve `?fw=` so the WebKit predictions get CI counts;
  - `morph-tween-curve`: prove `cubic-bezier(1/3,1,2/3,1)` = $1-(1-t)^3$ before porting g0.0b.
