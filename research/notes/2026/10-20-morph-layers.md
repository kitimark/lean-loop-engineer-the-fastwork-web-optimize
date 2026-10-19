# morph.mount:shift adds 9 layers per frame: attribution and the `shift-dormant` fix

Task morph-layers (discovery R3). `morph.mount:shift` mounts the start-selling panel early (Lean
`Fw.Parts.MorphMountOpt.mountV`). It saves the mount's style recalc in the trigger frame, but in Chromium it adds 9
drawing layers per frame until the original trigger. That is +1053 on swipe-v1 and +1134 on swipe-touch-v1 (MEASURED,
below).

## Answer

- The 9 layers come from one cause: the three marquee tracks run a transform animation while the panel is mounted
  and invisible. Each other extra layer is a consequence of those three (overlap, or a composited descendant).
- `shift-dormant` keeps `shift`'s early mount, but sets `animation-name: none` on the tracks while
  `dormant = mountV ∧ ¬mountO`. The layers are then the faithful page's at every frame (MEASURED, both profiles).
- Trade-off: the trigger frame needs a style recalc again, because the tracks' animation starts there
  (`animStart_eq_mountStart`). Of `shift`'s wins, `shift-dormant` keeps the layout passes before the trigger. It gives
  back the trigger frame's recalc (swipe: all of the 1-recalc win; touch: 1 of 2).

## Attribution (step 1)

Chromium, probe build of `shift` (commit 1f7ef2d6 on ci/morph-layers-probe), frame 30 of swipe-v1, layer dump
diffed against faithful (MEASURED):

| layer | element | Chromium compositing reason |
|---|---|---|
| 1 | panel | FixedPosition |
| 1 | panel backdrop | none (separate layer: no merge candidate) |
| 3 | `.track` × 3 | ActiveTransformAnimation |
| 2 | column content above the tracks | Overlap |
| 1 | panel center block | Overlap |
| 1 | nav bar (visible, has text) | Overlap |

`kActiveTransformAnimation` comes from `HasCurrentTransformAnimation`
(compositing_reason_finder.cc:563-572@f842f52). Blink sets that flag only from an effect that exists and is current
or in effect (css_animations.cc:2224-2230@f842f52). A paused animation in its active phase is still in effect, so the
paused scene rule (`will-change: auto`, `animation-play-state: paused`) keeps the layer. The layer goes away only when
the animation is removed. The Overlap layers follow from the layerization walk: a chunk that may overlap a newer
layer it cannot merge with gets its own layer (paint_artifact_compositor.cc:945-974@f842f52).

WebKit Simulator, same `shift` build, y=0 (run 39309416016, MEASURED, `shift` only). 11 panel layers: 3 tracks
[animation], 3 columns [transformWithCompositedDescendants], the panel [filter/opacity/transformWithCompositedDescendants],
the backdrop [opacityWithCompositedDescendants], veil, center and footer [overlap]. The nav bar adds 1 [overlap].
All of them hang on the 3 animated tracks. WebKit gives the animation reason only when the keyframe effect stack
currently affects the property or an accelerated animation runs (RenderLayerCompositor.cpp:3842-3867@862f17d).
`animation-name: none` meets neither condition. The WebKit count for `shift-dormant` is source-only (accepted
limit).

## Rejected: idle-none on the paused scene

R3 proposed `animation-name: none` while the scene is paused. In the faithful page the scene is paused in frames
where the panel is mounted and the nav bar's text is visible. There, idle-none removes the nav bar's Overlap layer,
which is a layer change under visible text. There is no proof that the text paint is unchanged, so this variant was
dropped (task limit: no layer change under text without a visual proof).

## The fix (step 2): Lean `Fw.Parts.MorphMountDormant`

- `dormant x t := mountV x t && !mountO x t`, with `#guard`s, `dormant_iff`, `not_dormant_of_mountO` and
  `not_dormant_of_not_mountV`.
- `animated_eq_mountO`: the tracks animate exactly when the original has mounted. `animStart_eq_mountStart`: the
  animation starts at the original's mount frame.
- Visual: `visSame_dormant` proves `VisSame E vp armO armD` from `HiddenBefore` (the panel is invisible before the
  original mounts). It needs no phase-freedom premise, because the animation's start time is the original's.
- Layers: `layerize` models the Chromium walk (`place` follows :927-938, `walk` follows :945-974). Premise
  `Absorbed`: the dormant panel's chunks have no direct reason and lie inside the newest layer's rect, so they
  merge (INFERRED: the panel has no will-change or transition while dormant). From it, `layerize_absorbed`,
  `layers_dormant_eq` (equal layers at every frame) and `census_dormant_eq` (equal run totals). A modelled
  ≤ 640 px frame `#guard`s 2 / 2 / 8 layers (no panel / dormant / animated) and the reason list.
- Site: `.stage[data-fw-dormant] .track { animation-name: none }`. App wakes on MorphMount's `onWake`, which fires
  on the original trigger (`mountNext`). TS `dormant` and the replay are checked against
  `packages/contracts/golden/parts/morph.mount.dormant.jsonl` (`dormant.golden.test.ts`), so there is no TS stand-in.

## Measurements (step 3)

chromium-counts, arm rewrite, 3 runs each, commit d5a219cc, image sha256:8f0e17f5 (image_run 39049264131). Each
arm was checked through `meta.search`. Sums over the run (r1 / r2 / r3):

| profile | arm | run id | census.drawingLayers | census.layers | RecalcStyleCount | LayoutCount |
|---|---|---|---|---|---|---|
| swipe-v1 | faithful | 39312237130 | 24903 / 24905 / 24902 | 28105 / 28107 / 28105 | 1832 | 318 |
| swipe-v1 | shift | 39312232132 | 25956 / 25954 / 25955 | 29159 / 29157 / 29158 | 1831 | 314 |
| swipe-v1 | shift-dormant | 39312226632 | 24905 / 24903 / 24901 | 28108 / 28107 / 28105 | 1832 | 315 |
| swipe-touch-v1 | faithful | 39312270019 | 26096 / 26100 / 26095 | 29438 / 29441 / 29436 | 1864 | 377 / 377 / 378 |
| swipe-touch-v1 | shift | 39312263301 | 27234 / 27230 / 27233 | 30575 / 30571 / 30574 | 1862 | 372 / 373 / 372 |
| swipe-touch-v1 | shift-dormant | 39312256022 | 26097 / 26098 / 26095 | 29438 / 29439 / 29436 | 1863 | 373 |

Per frame, r1, dormant minus shift: drawingLayers -9 in frames 0-116 (swipe) and 0-125 (touch). Against faithful
the difference is 0 except for single-frame noise of 1-2 layers (swipe frame 477; touch frames 134 and 350). The
same kind of single-frame noise also appears between faithful and shift. Recalc: dormant equals faithful on swipe; on touch it is -1 at frame 126.
`shift` instead saves 1 at frame 117 (swipe) and 2 at frames 125-126 (touch). Layout: dormant keeps `shift`'s -1 at
swipe frames 18, 39 and 46 (touch 21, 42 and 49). It gives back the -1 at the trigger frame.

Breakpoint gate, `fw=morph.mount:shift-dormant`, run 39312308450 attempt 1 (MEASURED). Every morph.* part passes in
every sweep on Chromium. Its only 2 failing cells are `commission` margin-inline at desktop-1512 and pain-1440
(orig 132px / 8px, rewrite 0px): the known commission flake (10-19-integrate-wave-2.md, "Commission probe flake";
default arm failed 2 of 3 runs). This change does not touch that part. WebKit: 0 fail. The verdict is incomplete
(UNREACHABLE envs, phone-rotation matchMedia not comparable). Attempt 2 was started to read the flake again.

## Accepted limits

- `Absorbed` is a premise from the layer dump and the CSS, not from a dump of the dormant build (INFERRED). The
  census equality is MEASURED.
- WebKit `shift-dormant` layer counts are source-only.
- The early mount's recalc win at the trigger frame cannot coexist with zero extra layers. With no layer before the
  trigger, there is no animation before it, so the animation must start at the trigger, which is a style change.
