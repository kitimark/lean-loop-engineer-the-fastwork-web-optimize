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
  `Fw.Parts.PlatformScene` is the original's `lE` test with `cE`'s two values). Branches: `near_false_iff`,
  `paused_of_above`, `paused_of_below`, `active_of_near`, `paused_iff`. `#guard`s at vh 775: y 2325 active, y 2326 paused,
  y 3000 / 4500 / 5267 paused.
- Stale frames, generic: `stale_off`, `stale_hidden`, `paused_frame_same` (a box that moved at most k since the
  last callback and overflows the track by at most m, with k + m <= vh, does not meet the viewport). Against the
  original, class E: `visSame_original` (via `faithful_eq_original`).
- Clocks: `phase_gap` (faithful local time = variant local time + total paused time), `faithful_eq_of_active` (no
  pause, same clock), `cue_phase_differs` (the 2.2 s cue loop shows another phase after a pause than the faithful
  arm). The variant's phase equals the original's, since the original pauses the same way.
- Layers: `layers_le` (paused never adds a layer, on any host), `layers_paused`, `layers_unowned`, `hero_paused_drop`
  (85 will-change-only boxes, 85 to 0 on an owning host), `wk_normal_owns`. The 85 is a modelled count
  (`heroWcFamilies`: 80 countdown faces, 4 deck cards, the copy, at <= 600 px) matched to the MEASURED will-change
  reason count 91 to 6 (run 39548856639, y 3000 and 4500, a drop of 85). The cue keeps its layers: a paused animation
  still has the animation reason (`RenderLayerCompositor.cpp:3842-3867@862f17d`).
- Golden: `packages/contracts/golden/parts/hero-scene-pause.jsonl`, checked by `scene.golden.test.ts`.
- Axioms: `propext`, `Classical.choice`, `Quot.sound`.

## The hero's boxes while paused (Lean section 6)

`hero_paused_hidden`: at every probe of `Fw.Site.Breakpoints.matrix` (the 124 loads of `breakpoints.gen.json`), a
paused hero box whose frame scrolled at most `kMax` since the observer's callback does not meet the viewport.
`hero_paused_hidden_fresh` is the case without a stale frame, and `kMax_pos` proves `kMax > 0` at all 124 probes.

- Track and stage: the track is 200vh (reduced motion: the stage's height), the sticky stage is `heroHeightPx`
  (100svh, min 680 px above 600 px). `stage_fits` proves stage <= 2vh at every probe, so the stage stays in the track.
- Overflow `m` is the largest reach of a box family beyond the stage, at any exit scatter in [0, 1]:
  - orbit cards (above 600 px): the 779 px canvas is centred on the stage. A card's centre lies between its ring slot
    (radius at most 248 px, `radius_le`) and its resting centre. Its ink is within half its width plus height of the
    centre at any rotation and scale <= 1, plus the motion blur outset (`blurOutset`, 3 sigma + 3, from both
    engines' kernel code), the 0 2px 4px shadow and the exit scatter `scatterY` vh.
  - deck cards (600 px and below): top at 69.25 % or 83.33 % of the stage, half width plus height, shadow, scatter
    -12 vh or 22 vh.
  - copy column (title, accent, countdown, text, buttons, cue): inside the stage plus `copyOutset` 260 px (a face
    moves at most 5 cells of 52 px; the copy's and the cue's blur and translate stay below it,
    `copy_outset_dominates`).
- `kMax = vh - m`. After the splash only the copy column animates (cards have `animation: none` at `data-done`, deck
  cards always), so a stale frame would need only `kCopy = vh - 260`. INFERRED: Lean defines `kCopy` and proves
  `kCopy_ge` (at least 170 px), but no theorem applies `stale_hidden` to the copy family with a shift up to `kCopy`, and
  the premise "after the splash only the copy column animates" is read from the CSS, not modelled.

| probes | vh | m (px) | kMax (px) | kCopy (px, INFERRED) |
|---|---|---|---|---|
| 932x430 phone landscape | 430 | 412.8 | 17.2 | 170 |
| 1024x768 | 768 | 477.0 | 291.0 | 508 |
| 1440x822 / 823 | 822 | 467.2 | 354.8 | 562 |
| above 600 px at 900 / 901 | 900 | 453.2 | 446.8 | 640 |
| 430x775 | 775 | 327.8 | 447.2 | 515 |
| 430x815 | 815 | 329.9 | 485.1 | 555 |
| 600 px and below at 900 | 900 | 334.5 | 565.5 | 640 |
| 430x932 | 932 | 336.2 | 595.8 | 672 |

Stacking and paint order (`hero_wc_paint_same`): dropping `will-change` changes no paint order for the 85 boxes. The
copy (`translate`, hero.module.css:208) and the deck cards (`rotate`, deck.module.css:25) always have a transform
(`establishes_wc_irrelevant`). The 80 faces have no transform until the countdown driver's first write
(driver.ts:67); they are absolute boxes with only text inside, so they paint as one unit with or without a
stacking context (`atomic_leaf`, CSS 2.1 Appendix E step 8).

## Every CSS animation in the hero subtree (CONFIRMED, CSS read)

| part | animation | selector | kind | neutralised by the splash end |
|---|---|---|---|---|
| hero | copyFromRing 0.7 s after 1.14 s | `.copy`, above 600 px | one-shot | yes: `[data-splash=done] .copy` sets `animation: none` (hero.module.css:38-41) |
| hero.orbit | ringAppear 0.12 s, cardFromRing 1.7 s | `.card` | one-shot | yes: `[data-orbit][data-done] .card` (card.module.css:160-168), set with `data-splash=done` (orbit driver.ts:69-70) |
| hero.cue | copyFromRing 0.7 s after 1.14 s | `.cue`, above 600 px | one-shot | yes: `[data-splash=done] .cue` (cue.module.css:89-94) |
| hero.cue | copyIn 0.7 s after 0.2 s | `.cue`, 600 px and below | one-shot | no: the done rule is above 600 px only |
| hero.cue | scrollFloat 2.2 s | `.float` | loop | no |
| hero.accent | strokeIn, strokeOut 0.9 s | `.drawingIn .path`, `.drawingOut .path` | one-shot per JS state | no |
| hero.accent | idle0, idle1, idle2 0.6 s step-end | `.idle .frameN` | loop | no (`steps` variant: none) |
| hero.deck | none | `.deck > article` (deck.module.css:26) | - | - |
| hero.countdown, hero.exit | none (the countdown moves by driver transforms) | - | - | - |

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

- Look class E against the original, the PLAN's look reference: the flag restores the original's own paused-scene
  rule, so both pause on the same test and every animation has the same local time (`visSame_original`). The flag is
  registered `optimized`, tier T0, `visClass` E; it is not a look change.
- It differs from the faithful arm, which lacks the original's pause rule: while paused every hero CSS animation stops
  and resumes on return at the original's time, not the faithful arm's. The list: cue scrollFloat (2.2 s loop), accent
  idle0 to idle2 (0.6 s loops), accent strokeIn and strokeOut, cue copyIn at 600 px and below, and until the splash
  ends (1.82 s after load) the copy and cue copyFromRing and the card ringAppear and cardFromRing. A page that loads
  already paused (scroll restoration, anchor, back navigation) holds these at their start until the user scrolls back,
  as the original does. The countdown has no CSS animation; its faces only lose `will-change`.
- No-claim zones (the same list as part.json `limit` and summary.json `lean.limits`):
  - a paused box is hidden within `kMax` during the splash (proved, `hero_paused_hidden`) and after the splash within
    `kCopy` (170 px at 932x430, INFERRED); a stale frame that scrolled further has no claim;
  - a copy column laid out taller than the stage: text layout is not modelled, the proof assumes the column fits;
  - `svh` below `vh` (Safari with its toolbars): the proof assumes svh = vh and sets the stage to `heroHeightPx vh`;
  - `hero.countdown:strip` is not covered: a strip reaches up to 11 cells above its digit, outside `copyOutset`.
- Not ported: the original's `deferRendering` (`content-visibility`) on the hero. Follow-up.
- Safari frame time INFERRED, no device run.
- Bridge: the hero now reads the hero.exit rect. Edges hero to hero.orbit, morph.mount to hero, people.deck to hero;
  318 chain pairs (was 322); `lean/Fw/Parts/Bridge.lean`, `FootprintRows.lean`, `FootprintData.lean` and the
  footprint goldens regenerated (outside the task's graph writes, accepted).

## CI (MEASURED)

WebKit census, webkit-sim run 39548856639 (sha 26b881fa, `?fw=hero:scene-pause`, configHash 3cab45fdb721e6b0, iOS
Simulator 430x775 DPR 3, 2 fresh-load passes). Baseline: run 39309416016, the `morph.mount:shift` arm (task baseline,
search `?fw=morph.mount:shift`, configHash 3bf7fec1fdffb72d), not the plain faithful rewrite. Original: run 39318078000.

| y | flag (pass 1 / 2) | morph.mount:shift arm | original | will-change reason (flag) |
|---|---|---|---|---|
| 0 | 122 / 112 | - | - | 92 / 92 |
| 3000 | 58 / 51 | 136-145 | 42-47 | 6 / 6 |
| 4500 | 65 / 56 | 136-145 | 42-47 | 6 / 6 |
| max (5231 / 5267) | 45 / 39 | 124-128 | 30 | 5 / 5 |

- Attribution: the two arms differ in config, so the drop is attributed by reason, not by total. The will-change
  reason count is 91 at y 3000 and 4500 in the baseline and 6 with the flag, in both passes (MEASURED). Lean predicts
  85 (`hero_paused_drop`). The rest of the gap to the original (about 9-18 layers) has other reasons (animation,
  overlap, composited descendants).
- y 5267 has n = 1 (run 39548856639). In pass 1 the document was 6006 px tall at the first read (max y 5231)
  and 6042 px in the same pass's scroll phase; pass 2 read 6042 from the start, with the same configHash (MEASURED).
  The 36 px arrived after the first read of the cold load (INFERRED: a late font or image size); the census was not
  re-run.
- Breakpoint gate, run 39549161028: pass on chromium and on playwright-webkit. Every cell is pass, NC, or UNREACHABLE
  under the Lean reach rule.
- Trajectory probe, Chromium, width 390, path morph (MEASURED; open@1 is bucket 1 of the open push, m in [0.05, 0.15)):

| run | sha | rewrite search | lane | open@1 coverage units | reps with an open@1 sample: original / faithful / candidate | nav logo color close@0 |
|---|---|---|---|---|---|---|
| 39548822269 | 26b881fa | `?fw=hero:scene-pause` | RED | 42 new | 0/5, 2/5, 0/5 | fail in one rep (the 1 content unit) |
| 39553952680 | 1f437e75 | `?fw=hero:scene-pause` | RED | 42 new | 0/5, 1/5, 0/5 | pass |
| 39556935431 | 4e378931 | `?fw=hero:scene-pause` | CLEAN | 42 both (faithful arm 0/5 too) | 0/5, 0/5, 0/5 | pass |
| 39557718020 (control) | 2e463b39 | default (no flag) | CLEAN | 0 | 0/5, 3/5, 3/5 | pass |

  Inputs read back from artifact `trajectory-inputs` of each run (engines=chromium, widths=390; fw empty for the
  control). 39548822269 also ran 1280 and WebKit: playwright-webkit CLEAN, 2000 of 2000 units (path hero); Chromium 1280
  candidate had an open@1 sample in 5/5 reps. No run has a hero unit failing.
- Verdict: the control is clean, so the open@1 coverage red is not the probe's row E sampling event at this sha
  (row E of `research/notes/2026/10-21-faithful-hero-baseline.md` needs the no-flag arm to show it). It is a flag effect
  on the open push's first frame (MEASURED): the first nonzero `m` of a rep is either about 0.066 or about 0.2. The
  default rewrite lands at 0.066 in 9 of 25 reps over the four runs; the flag arm never does (0 of 15) and the original
  never does (0 of 20). A one-sided Fisher test on 0/15 against 9/25 gives p about 0.0075 (INFERRED: reps of different
  runs treated as independent). The candidate's first-frame timing equals the original's; the coverage rule fails it
  because it judges the rewrite against its own bucket grid, not against the original's. 39556935431 is CLEAN only
  because its faithful arm also missed. No content unit differs (the nav logo close@0 unit failed once, in 39548822269,
  and passed in the other three).
- Mechanism of the timing change: not determined. CONFIRMED only that the rule and the IO touch only the hero track
  subtree (`hero.module.css:42-45`, `index.tsx:38-39`); the frame-pacing effect of removing about 85 layers is INFERRED.
- Per the lead's rule (control clean, flag arm red in 2 of 3 runs), this is a flag effect and the flag does not enter
  `v2-proved` on this evidence. Not fixed here; the open@1 coverage rule against the original's own first frame is a
  probe follow-up.
