# hero:scene-pause: the original's paused-scene rule on the hero track

Task hero-pause-rule (webkit W2a, split from W2 = R5). The original pauses every registered scene while it is far
off-screen: `will-change: auto` and `animation-play-state: paused` on the scene and all its descendants. The faithful
rewrite has no such rule on the hero, so the hero's 80 face spans and 4 deck cards keep their `will-change` layers
at every scroll position. `hero:scene-pause` ports the rule to the hero track (`[data-fw="hero-exit"]`).

## The original's rule (CONFIRMED, snapshot)

- CSS: `.start-selling [data-start-selling-scene=paused]` and the same selector followed by `:where(*)` set
  `will-change: auto !important` and `animation-play-state: paused !important`
  (`snapshot/site/_app/immutable/assets/2.gBuqKVzi.css` byte 227279). `.start-selling` wraps the whole page
  (`snapshot/site/index.html`), so the rule reaches every registered scene.
- JS, `snapshot/site/_app/immutable/nodes/2.DyWL8TcE.js`:
  - `lE` (byte 90888) is the initial "near" test: bottom ≥ -vh and top ≤ 2vh.
  - `cE` (90704) writes `active` / `paused` on each observer change.
  - `uE` (91001) shares one IntersectionObserver per `rootMargin`.
  - `dE` (91483) registers a scene. The defaults are `rootMargin` `100% 0px` and `manageAnimations` on when an element
    is given.
  - The hero section is registered at byte 152358: `dE(c, {deferRendering: !0, element: b})`.
- The port uses its own attribute `data-fw-hero-scene` and the site's existing `watchActive` observer
  (`apps/site/src/parts/people/shared.ts`, `rootMargin` `100% 0px`). Values are restated, no code is copied.

## Lean (`lean/Fw/Parts/HeroScenePause.lean`)

- Rule identical to the original: `heroScene_eq_original : heroScene = sceneOf` (rfl; `sceneOf` in
  `Fw.Parts.PlatformScene` is the original's `lE` test with `cE`'s two values). Branches: `near_false_iff`, `paused_of_above`, `paused_of_below`,
  `active_of_near`, `paused_iff`. `#guard`s at vh 775: y 2325 active, y 2326 paused, y 3000 / 4500 / 5267 paused.
- Visible output unchanged while paused: `stale_off` (a paused box that moved at most k since the last callback, with
  k + m ≤ vh, does not meet the viewport), `stale_hidden`, `paused_frame_same`. Against the original:
  `visSame_original` (via `faithful_eq_original`).
- Clocks: `phase_gap` (faithful local time = variant local time + total paused time), `faithful_eq_of_active` (no
  pause, same clock), `cue_phase_differs` (the 2.2 s cue loop shows another phase after a pause than the faithful
  arm). The variant's phase equals the original's, since the original pauses the same way.
- Stacking: `establishes hasTransform wc = hasTransform || wc` and `establishes_wc_irrelevant`: on a box with a
  transform, dropping `will-change` changes no stacking context, so no paint order changes.
- Layers: `layers_le` (paused never adds a layer, on any host), `layers_paused` (owning host: only boxes with another
  reason keep a layer), `layers_unowned`, `hero_paused_drop` (85 will-change-only boxes, 80 faces + 4 deck cards +
  copy: 85 → 0 on an owning host), `wk_normal_owns` (WebKit Normal owns `will-change` layers).
- Golden: `packages/contracts/golden/parts/hero-scene-pause.jsonl` (vh 667 / 775 / 844 / 900 x 8 cases, plus the
  constants). The site's `heroSceneOf`, the CSS rule values and the observer's `rootMargin` are checked against it
  (`apps/site/src/parts/hero/scene.golden.test.ts`).
- Axioms: `propext`, `Classical.choice`, `Quot.sound`.

## Engine source (CONFIRMED)

- WebKit@862f17d: `will-change` gives a layer through `RenderLayerCompositor.cpp:3996-4018`; the conservative non-Mac
  policy returns false at 4008-4012, the normal policy keeps it. Animation reason: 3842-3867 (the keyframe stack must
  currently affect the property or run accelerated; a paused animation still affects it, so the cue keeps its
  layers). Stacking: `RenderLayer.cpp:627`, `RenderElementStyleInlines.h:86,93`, `RenderElement.cpp:328-331`,
  `StyleAdjuster.cpp:395`. Play state: `CSSAnimation.cpp:162-185`, `WebAnimation.cpp:1349-1379`.
- Chromium@f842f52: `will-change` is a direct reason (`compositing_reason_finder.cc:76-122`, will-change at
  116-119), so Chromium drops these layers too. Stacking: `computed_style.cc:2986`, `computed_style.h:2185-2201`,
  `2262-2273`. Play state: `css_animations.cc:2021-2046`, current-animation flag `2270-2280`.

## Limits

- Stale frame: the observer reports once per callback. A scroll larger than vh - m between two callbacks can show
  one frame with the stale state. The original has the same bound (same observer, same margin).
- Look change against the faithful arm only: after a pause the hero's loops (cue `scrollFloat` 2.2 s, accent idle
  0.6 s) resume at the original's phase, not the faithful arm's. **Marked for the user's visual review.**
- Not ported: the original's `deferRendering` (`content-visibility`) on the hero. Follow-up.
- Safari lag effect INFERRED; no iPhone run.
- Bridge: the hero now reads the hero.exit rect. Edges hero → hero.orbit, morph.mount → hero, people.deck → hero;
  318 chain pairs (was 322); `lean/Fw/Parts/Bridge.lean` regenerated.

## CI (MEASURED)

WebKit census, webkit-sim run 39548856639 (sha 26b881fa, `?fw=hero:scene-pause`, iOS Simulator 430x775 DPR 3, 2
fresh-load passes). Baseline and original are the earlier runs 39309416016 and 39318078000.

| y | flag (pass 1 / 2) | faithful rewrite | original | will-change layers (flag) |
|---|---|---|---|---|
| 0 | 122 / 112 | - | - | 92 / 92 |
| 3000 | 58 / 51 | 136-145 | 42-47 | 6 / 6 |
| 4500 | 65 / 56 | 136-145 | 42-47 | 6 / 6 |
| max (5231 / 5267) | 45 / 39 | 124-128 | 30 | 5 / 5 |

- Off-screen the count drops by about 80-87 layers. Lean predicts 85 (`hero_paused_drop`). The remaining gap to the
  original (about 9-18 layers) comes from reasons other than `will-change` (animation, overlap, composited
  descendants). At y 0 the hero is active and still has its 92 will-change layers, as in the faithful arm.
- Breakpoint gate, run 39549161028: pass on chromium and on playwright-webkit. Every cell is pass, NC, or UNREACHABLE
  under the Lean reach rule.
- Trajectory probe, run 39548822269:
  - playwright-webkit is CLEAN: 2000 of 2000 units pass (path hero).
  - chromium is RED with 43 new units, all in one rep at width 390, path morph, and none on a hero node. 42 are coverage
    on nav nodes (open@1). One is content: nav logo color, close@0, apart.
  - INFERRED unrelated, because the nav is outside the hero-exit subtree that the rule touches.
