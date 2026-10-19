# morph.mount:shift adds 9 layers per frame: attribution and the `shift-dormant` fix

Task morph-layers (discovery R3, round 2). `morph.mount:shift` mounts the start-selling panel early (Lean
`Fw.Parts.MorphMountOpt.mountV`). It saves the mount's style recalc in the trigger frame, but in Chromium it adds 9
drawing layers per frame until the original trigger. That is +1053 on swipe-v1 and +1134 on swipe-touch-v1 (MEASURED,
below).

## Answer

- The 9 layers come from one cause: the three marquee tracks run a transform animation while the panel is mounted
  and invisible. Each other extra layer is a consequence of those three (overlap, or a composited descendant).
- `shift-dormant` keeps `shift`'s early mount but keeps the panel's timed state asleep while
  `dormant = mountV ∧ ¬mountO`: the tracks get `animation-name: none` and the morph countdown starts no driver (no
  1 s interval, no spring, no observer). Both wake on the original's trigger.
- The layers are then the faithful page's at every frame (MEASURED: equal layer lists in frames 0-116 of a real dump,
  equal census on both profiles).
- `shift` has a second problem: the morph countdown's 1 s interval starts at the early mount, so its tick phase is
  not the original's (MEASURED below; Lean `clock_not_phaseFree`). `shift`'s visual proof needs `PhaseFree` and that
  premise is false for this panel. `shift-dormant` does not need it.

Trade-off at commit f59fdbf0, median of 3 runs, sums over the run (MEASURED; runs in Measurements):

| profile | arm | drawingLayers | RecalcStyleCount | LayoutCount | UpdateLayoutTree.elementCount |
|---|---|---|---|---|---|
| swipe-v1 | faithful | 24903 | 1832 | 318 | 44181 |
| swipe-v1 | shift | 25956 (+1053) | 1831 (-1) | 314 (-4) | 44387 (+206) |
| swipe-v1 | shift-dormant | 24904 (+1) | 1832 (0) | 315 (-3) | 44397 (+216) |
| swipe-touch-v1 | faithful | 26100 | 1864 | 377 | 48525 |
| swipe-touch-v1 | shift | 27234 (+1134) | 1862 (-2) | 372 (-5) | 48741 (+216) |
| swipe-touch-v1 | shift-dormant | 26098 (-2) | 1863 (-1) | 373 (-4) | 48727 (+202) |

- `shift-dormant` drops all of `shift`'s extra layers (the +1 / -2 are within the 1-3 layer spread between runs of
  one arm). It keeps 3 of `shift`'s 4 saved layout passes on swipe (4 of 5 on touch) and none of its saved recalc on
  swipe (1 of 2 on touch).
- Both early-mount arms restyle about 200 more elements than faithful (+0.5 %). Swipe r1, against faithful:
  frames 0-9 equal; frames 10-116 +379 (shift) and +380 (shift-dormant), not attributed; from the trigger frame on
  -183 and -178. The trigger frame restyles 210 elements in faithful and 45 / 48 in shift / shift-dormant.

Recommendation (the decision is the lead's): replace `morph.mount:shift` in the preset with
`morph.mount:shift-dormant`. It costs about 1050 (swipe) / 1130 (touch) drawing layers less per run than `shift`, gives
back 1 recalc and 1 layout pass, and restyles about the same number of elements (+10 / -14). Its visual proof holds
on the measured premise; `shift`'s does not (`clock_not_phaseFree`, countdown phase measured). If the lead wants a
whole-run gate pass first, keep both off the preset: the only non-pass cell is the pre-existing WebKit phone-rotation
`matchMedia =Lean` cell (gate section).

## Attribution (step 1)

Chromium probe of `shift` (commit 1f7ef2d6 pushed as ci/morph-layers-probe; never landed): run 39309340297 (shift)
and run 39309334426 (faithful), artifact `chromium-counts-rewrite-r1`, file `layers.json`, frame 30 of swipe-v1
(430 px wide). Reduction: in each file take the last cc layer-tree snapshot of frame 30; key each layer as
`debug name | compositing reasons | width x height | draws content`; subtract the two key multisets. Faithful has 19
layers (14 drawing), shift 28 (23 drawing). The 9 keys only in shift (MEASURED):

| layers | element | Chromium compositing reason |
|---|---|---|
| 1 | panel, 398x52 | FixedPosition |
| 1 | panel backdrop, 422x52 | none (separate layer: no merge candidate) |
| 3 | `.track` x 3 (135x1348, 136x1340, 135x1612) | ActiveTransformAnimation |
| 2 | column content above the tracks (136x52, 135x52) | Overlap |
| 1 | panel center block, 398x280 | Overlap |
| 1 | nav bar, 398x52 (visible, has text) | Overlap |

`kActiveTransformAnimation` comes from `HasCurrentTransformAnimation`
(compositing_reason_finder.cc:563-572@f842f52). Blink sets that flag only for an effect that exists and is current or
in effect: the test is at css_animations.cc:2276 and the flag is set at :2280 (css_animations.cc:2270-2280@f842f52).
A paused animation in its active phase is still in effect, so the paused scene rule (`will-change: auto`,
`animation-play-state: paused`) keeps the layer. The layer goes away only when the animation is removed. The Overlap
layers follow from the layerization walk: a chunk that may overlap a newer layer it cannot merge with gets its own
layer (paint_artifact_compositor.cc:945-974@f842f52).

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
- Visual. `Panel` models the panel's state from two inputs: the history its timed state starts from, and whether it
  is mounted now. `single p` feeds one mount history to both (the `MorphMountOpt` view). `armD` mounts with the
  variant's bit and wakes the timed state with the original's history. `visSame_dormant` proves
  `VisSame E vp armO armD` from `Hidden`: the panel draws nothing in the viewport before the original mounts,
  whatever its inputs (`hiddenBefore_of_hidden` turns it into `MorphMountOpt.HiddenBefore`). It needs no `PhaseFree`.
- `clock_not_phaseFree`: a panel holding a clock that refreshes every `P` frames from its start (`clockPanel`,
  `lastRefresh`) is not `PhaseFree`. So `shift`, which starts the morph countdown at the early mount, does not meet
  the premise of its own visual proof. `phaseFree_of_untimed`: a panel that reads only the mount bit is `PhaseFree`.
- Premise of `armD`, tested against the page (MEASURED, probe below): the panel's timed state starts at the original's
  trigger. Timed parts: the tracks' CSS animations and the countdown driver. The rest of the panel reads only the
  mount bit (panel writer, the columns scene clock, paused before the trigger, and the CTA border transition, which
  fires only on a change). The countdown's digit shape is set at the early mount; it is not timed, and the driver
  checks it again when it starts.
- Layers: `layerize` models the Chromium walk (`place` follows :927-938, `walk` follows :945-974). Premise
  `Absorbed`: the dormant panel's chunks have no direct reason and lie inside the newest layer's rect, so they
  merge. From it, `layerize_absorbed`, `layers_dormant_eq` (equal layers at every frame) and `census_dormant_eq`
  (equal run totals). `#guard`s check `layerize` and `absorbedB` on small chunk lists; `absorbed_nil` covers a panel
  that paints nothing.
- Site: `.stage[data-fw-dormant] .track { animation-name: none }`; `HeroCountdown` gets `hold` and starts no driver
  while it is true. App wakes on MorphMount's `onWake`, which fires on the original trigger (`mountNext`). TS `dormant`
  and the replay are checked against `packages/contracts/golden/parts/morph.mount.dormant.jsonl`
  (`dormant.golden.test.ts`), so there is no TS stand-in.

## Real-dump checks (probe of round 2)

Probe build: commit 7f0c0340 plus two probe commits, pushed as ci/morph-layers-probe2 (e2f4c38f, never landed).
swipe-v1 (430x932), runs=2. Runs: 39322953386 (faithful), 39322959537 (shift), 39322964853 (shift-dormant); arms
checked through `meta.search`. Artifact `chromium-counts-rewrite-r1`, files `layers.json` and `phase.json`.

- `Absorbed` (MEASURED): with the reduction above, shift-dormant and faithful have equal layer multisets in each of
  frames 0-116 (frame 30: 19 layers, 14 drawing, in both; frame 100: 49 and 44 in both). shift still has the 9 extra
  keys at frames 30 and 100. Source for why the dormant panel adds no layer: at morph 0 its opacity is 0 with no
  opacity animation or `will-change: opacity`, so `PaintedOutputInvisible` holds (paint_layer_painter.cc:168-190@f842f52)
  and its chunks draw nothing; with no transform animation (tracks asleep) none of them has a direct reason (INFERRED
  link, the equal dumps are the evidence).
- Timed state (MEASURED, `phase.json`: setInterval / clearInterval calls recorded in the page and binned by virtual
  time into frames). The morph countdown's `setInterval(1000)` is installed in frame 116 (virtual time 22933 ms) in
  faithful and shift-dormant, and at load (virtual time 167 ms) in shift. The hero countdown's interval (load,
  17 ms) is the same in all three.
- Tracks (MEASURED, `layers.json` `animations`: Blink `Animation` trace events). The 3 track animations begin in
  frame 116 in faithful and shift-dormant; in shift they began before frame 0. Begin events: 143 / 140 / 143.
- Round 3 (the hold keeps the digit shape): probe ci/morph-layers-probe3 (c95a4779 = f59fdbf0 plus the two probe
  commits), runs 39325816743 (faithful) and 39325823271 (shift-dormant), same artifact and files. Equal layer
  multisets in each of frames 0-116 (frame 30: 19 / 14 in both; frame 100: 49 / 44 in both). The 1 s interval is
  installed in frame 116 (22933 ms) in both; the 3 track animations begin in frame 116 in both (143 begins each).

## Measurements (step 3)

chromium-counts, arm rewrite, 3 runs each, image sha256:8f0e17f5 (image_run 39049264131). Each arm was checked
through `meta.search`. Reduction: per run, the sum over `frames[]` of `counts['census.drawingLayers']`,
`counts['census.layers']`, `counts['metric.RecalcStyleCount']`, `counts['metric.LayoutCount']` and
`counts['trace.UpdateLayoutTree.elementCount']`. Values are r1 / r2 / r3, or one value when all three agree.

Commit d5a219cc (round 1: tracks asleep, countdown not held):

| profile | arm | run id | drawingLayers | layers | RecalcStyleCount | LayoutCount | elementCount |
|---|---|---|---|---|---|---|---|
| swipe-v1 | faithful | 39312237130 | 24903 / 24905 / 24902 | 28105 / 28107 / 28105 | 1832 | 318 | 44185 / 44178 / 44179 |
| swipe-v1 | shift | 39312232132 | 25956 / 25954 / 25955 | 29159 / 29157 / 29158 | 1831 | 314 | 44376 / 44381 / 44370 |
| swipe-v1 | shift-dormant | 39312226632 | 24905 / 24903 / 24901 | 28108 / 28107 / 28105 | 1832 | 315 | 44401 / 44387 / 44397 |
| swipe-touch-v1 | faithful | 39312270019 | 26096 / 26100 / 26095 | 29438 / 29441 / 29436 | 1864 | 377 / 377 / 378 | 48523 / 48529 / 48528 |
| swipe-touch-v1 | shift | 39312263301 | 27234 / 27230 / 27233 | 30575 / 30571 / 30574 | 1862 | 372 / 373 / 372 | 48748 / 48714 / 48721 |
| swipe-touch-v1 | shift-dormant | 39312256022 | 26097 / 26098 / 26095 | 29438 / 29439 / 29436 | 1863 | 373 | 48746 / 48748 / 48745 |

Commit 7f0c0340 (round 2: countdown held without its digit shape):

| profile | arm | run id | drawingLayers | layers | RecalcStyleCount | LayoutCount | elementCount |
|---|---|---|---|---|---|---|---|
| swipe-v1 | faithful | 39322631016 | 24903 / 24904 / 24902 | 28105 / 28108 / 28104 | 1832 | 318 | 44175 / 44178 / 44174 |
| swipe-v1 | shift | 39322636707 | 25956 / 25954 / 25955 | 29160 / 29157 / 29158 | 1831 | 314 | 44382 / 44385 / 44383 |
| swipe-v1 | shift-dormant | 39322642131 | 24903 / 24903 / 24902 | 28106 / 28105 / 28105 | 1832 | 315 | 44401 / 44394 / 44398 |
| swipe-touch-v1 | faithful | 39322647575 | 26096 / 26097 / 26100 | 29437 / 29439 / 29441 | 1864 | 378 / 377 / 377 | 48524 / 48525 / 48503 |
| swipe-touch-v1 | shift | 39322653548 | 27230 / 27231 / 27231 | 30572 / 30572 / 30573 | 1862 | 372 / 373 / 373 | 48741 / 48752 / 48738 |
| swipe-touch-v1 | shift-dormant | 39322659999 | 26098 / 26099 / 26096 | 29440 / 29440 / 29437 | 1864 | 374 / 376 / 374 | 48749 / 48749 / 48748 |

Commit f59fdbf0 (round 3, final: countdown driver held, digit shape set at mount):

| profile | arm | run id | drawingLayers | layers | RecalcStyleCount | LayoutCount | elementCount |
|---|---|---|---|---|---|---|---|
| swipe-v1 | faithful | 39325709978 | 24902 / 24905 / 24903 | 28105 / 28108 / 28106 | 1832 | 318 | 44191 / 44181 / 44177 |
| swipe-v1 | shift | 39325715862 | 25956 / 25957 / 25956 | 29158 / 29160 / 29160 | 1831 | 314 | 44387 / 44387 / 44389 |
| swipe-v1 | shift-dormant | 39325721909 | 24902 / 24905 / 24904 | 28106 / 28108 / 28107 | 1832 | 315 | 44393 / 44400 / 44397 |
| swipe-touch-v1 | faithful | 39325727288 | 26100 / 26097 / 26100 | 29441 / 29439 / 29441 | 1864 | 377 / 377 / 378 | 48502 / 48525 / 48527 |
| swipe-touch-v1 | shift | 39325735139 | 27232 / 27234 / 27234 | 30573 / 30575 / 30575 | 1862 | 372 | 48741 / 48724 / 48743 |
| swipe-touch-v1 | shift-dormant | 39325741608 | 26098 / 26098 / 26097 | 29439 / 29438 / 29438 | 1863 | 373 / 374 / 373 | 48743 / 48727 / 48724 |

Per frame (d5a219cc, r1), dormant minus shift: drawingLayers -9 in frames 0-116 (swipe) and 0-125 (touch). Against faithful
the difference is 0 except for single-frame noise of 1-2 layers, which also appears between faithful and shift.
Layout: dormant keeps `shift`'s -1 at swipe frames 18, 39 and 46 (touch 21, 42 and 49) and gives back the -1 at the
trigger frame. Recalc: `shift` saves 1 at frame 117 (swipe) and 2 at frames 125-126 (touch); dormant saves none.

## Breakpoint gate, `fw=morph.mount:shift-dormant`

The unit of decision is each morph.* cell. The known commission flake (10-19-integrate-wave-2.md:80-84) is at
desktop-1512 only.

- Run 39312308450 (d5a219cc). Attempt 1: every morph.* cell passes on both engines; Chromium fails `commission`
  margin-inline at desktop-1512 (the known flake) and at pain-1440 (not covered by that record; this change does not
  touch `commission`). Attempt 2: Chromium pass (504 cells, 7049 readings pass, 0 fail, 7 excused). WebKit
  incomplete: `matchMedia =Lean` not comparable at phone-rotation; every morph.* cell passes or is UNREACHABLE.
- Run 39322625340 (7f0c0340). Chromium pass (7049 pass, 0 fail, 7 excused). WebKit fail: morph.countdown FAIL 9/10
  at touch-rm (touch-rm-600 to touch-rm-1200). The digit, face, number and spacer counts were 0 in the rewrite and
  8 / 64 / 4 / 8 in the original. The gate's scroll excursion does not wake the panel there, and the round-2 hold
  also held the digit shape, so the clock kept its placeholders. Round 3 sets the shape at mount and holds only the
  driver. The gate compares no face transform (anchors.json, role `face`).
- Run 39325704868 (f59fdbf0, final). Chromium pass (504 cells, 7049 readings pass, 0 fail, 7 excused). WebKit
  incomplete: 6763 pass, 0 fail, 291 excused, 1 cell not ok, `matchMedia =Lean` at sweep:phone-rotation (stops #1 and
  #3 not comparable). That cell is not a morph.* cell and is pre-existing on main (10-19-integrate-wave-1.md:31). Every
  morph.* cell (morph.mount, morph.countdown, morph.columns, morph.tween, morph.panel) passes on both engines or is
  UNREACHABLE under an existing exemption. No commission cell fails. Verdict per morph.* cell: pass.

## Accepted limits

- `Absorbed` and the timed-state premise are checked by a probe dump of swipe-v1 in Chromium (MEASURED), not by a
  committed test; the probe code stays on ci/morph-layers-probe2.
- WebKit `shift-dormant` layer counts are source-only.
- The early mount's recalc win at the trigger frame cannot coexist with zero extra layers. With no layer before the
  trigger, there is no animation before it, so the animation must start at the trigger, which is a style change.
- The extra restyled elements in frames 10-116 of both early-mount arms (about +380 on swipe) are not attributed.
