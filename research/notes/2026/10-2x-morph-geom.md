# morph.geom:on: the site half (task morph-geom)

Design: `10-27-morph-compositor-geometry.md`. Lean: `10-2x-morph-geom-lean.md`. Results: round 3.

## Finding: the veil fold premise is refuted (task geom-veil-restore)
Round 2 folded the veil into D on the premise "at m = 1 D is opaque, so the end state is unchanged". CONFIRMED false: the veil
paints above the backdrop pictures (apps/site/src/parts/morph.panel/index.tsx paint order: backdrop, then veil, line 54 for the
veil) while D paints below them (nav layers K0..U, D), so an opaque D never darkens the pictures and they look brighter
(the user saw it on the iPhone). MEASURED local (cols probe A2): m = 1 differs from base on 8.8-11.7 % of pixels, 0.04-0.13 % with
the veil back. The veil track, its Lean layer and animation, the counts and the golden rows are restored; the fold stays in
`MorphGeomCounts.lean` only as a memory bound (`net_lvl0_fold_bytes`). Details: `10-2x-geom-veil-restore.md`.
The section below records the refuted round-2 decision; its bytes are the memory the restored veil layer costs back.

## Memory decision (round 2: veil folded, REFUTED)
The veil is folded into the solid fill D: no veil layer, no veil track, the panel's veil element is `display: none` under
`.is-flip`. A solid fill paints nothing and has no backing, so the veil's W x H backing bytes are gone. The cost is a look
change of class L: the veil's radial shape (123% x 74%, #131922 to transparent) is dropped; at m = 1 D is opaque #131922
so the end state is unchanged, mid-morph the box edge region is uniformly filled instead of shaped. (A gradient on D would
make D paint and take the veil's bytes back, a zero saving.)

Net bytes = flip bytes minus what the faithful page backs at morph frames (dpr 3 below 641 px, 2 above). Level 0 is the
nav only (certain); level 2 adds the panel and the platform (INFERRED from the CSS). The Simulator census of the faithful
layers was not built this round (no lane exists that dumps layer backings of the faithful page at morph frames), so the
level is still undecided and the decision is stated per level.

| faithful backs | flip with the veil folded | plus the platform without its own layer |
|---|---|---|
| nav only (level 0) | fits 10 of 12 bands (not 1440x900, 1920x1080) | fits 12 of 12 |
| nav, panel, platform (level 2) | fits 12 of 12 | fits 12 of 12 |
| level 2 net bytes, flip (bands in `bandVps` order) | -1806336, -3905280, -9704448, -13428864, 4561920, -23823360, -6243200, -11384832, -12649472, -17327104, -18424832, -18424832 | |

Proved by `decide +kernel` in `MorphGeomCounts.lean`: `net_lvl0_flip` (exact bytes per band), `net_lvl0_flip_fits`,
`net_lvl0_platform`, `net_lvl0_platform_fits`, `net_phone_fold` (every phone band fits at level 0), `net_lvl2_flip`, `net_lvl2_flip_bytes` (exact net bytes per band at level 2).
Decision: ship the folded veil; the two big desktop bands may stay named over at level 0 (accepted limit, the iPhone bands
fit). The platform step is taken only if the census shows the faithful page has no platform layer.

## Lean lookup lemma
`MorphGeomLook.lean`: `lookFn` finds the function at an index of the animation with a given element, property and key;
`look_bar`, `look_actions`, `look_centre`, `look_footer_x/y`, `look_footerGrad`, `look_footerEnd`, `look_bc_x/y`,
`look_Kb`, `look_Kb_y` are `rfl`-level (after the two `if`s of `anims`), `look_column` and `look_image` give membership.
So every function `composed` (rect_eq) evaluates is the function of an animation in `anims`; the image lemma holds for the
zero row gap the animation uses.

## Premises (registry rows, pages in packages/premise-tests)
`anim.keytimes` (piecewise linear across key times), `anim.individual-transform` (translate, scale, transform compose in
order), `clip.nested-radius` (two nested rounded clips, inner composited and translated), `backdrop.masked-ancestor`
(backdrop blur under a rounded overflow clip equals the unmasked one). The accelerated set itself is CONFIRMED by source
(GraphicsLayerCA.cpp:1183-1215@862f17d) and by `accelerable_bands`; no page can observe CA acceleration. A debug run on
Chromium (local, not a result) passed all four.

## Site part
* `apps/site/src/parts/morph.geom/` (registered, variant `on`, class L). `tracks.ts` is the track builder (floats restating
  the Lean definitions: box, doors, counter, logo, bar, actions, panel, columns, images, veil, centre, footer, platform, and
  the earn/lang 60 Hz time tracks with the retargeted-transition run model; the engine table is picked by a feature probe).
  `tracks.golden.test.ts` replays the 12 knot tables and all 653 `sample` lines of `morph-geom.jsonl` within 1e-6 (passes),
  and checks one function-list shape, sorted offsets 0..1 and unique (selector, property) per effect.
* `driver.ts` follows today's tween: the first `--morph` above 0 enters the flip, later values only write `currentTime`
  (1000 m on m tracks; the tween time that shows m on time tracks), m back at 0 cancels and leaves. Guards: nav not
  `is-on-dark`, reduced motion. `tree.ts` tags elements with `data-mg`, wraps the nav children in K0..K3, U, with G and D, and
  unwraps. `geom.css` holds the clipper geometry, `transform-origin`, the transition-none list (the Lean `flip` line) and
  the base-rule resets (`--morph: 1`, actions and logo `translate`). `.is-flip` sits on the root element.
* Round 2 built the earnClip/earnLabel wrappers (`tree.ts wrapEarn`), backdropClip/Kb/Ub (`wrapBackdrop`), the lang width
  (measured) and the earn width (11 rem desktop, 9.5 rem phone). Not built: the reversal-correct time tracks (morph-timed).
  geom.css of these wrappers has never been looked at in a browser.

## TS stand-ins
`tracks.ts` (floats, 40-step bisection), `driver.ts`'s `timeOf` (inverse tween for the time tracks), `tree.ts` (DOM glue).
The `composed` to `anims` lookup lemma in Lean is not written.

## Results (round 3)
| item | run | reading |
|---|---|---|
| premise-tests, push 2 (backdrop.masked-ancestor narrowed to Chromium) | 40430312224 | success |
| breakpoint gate, `morph.geom:on`, both engines | 40428166855 | chromium pass (504 cells, 0 fail, 7 excused); playwright-webkit pass (504 cells, 0 fail, 291 excused) |
| Chromium counts, base vs flag, 3 runs each | 40428218497 vs 40428270226 | profile push-cycle-d1000; counts equal to the unit except raster.invalidatedLayers (base 4111/4113/4107, flag 4112/4107/4111) and Layer.deleted (base 29/41/29, flag 29/29/29). No Animation.* count differs |
| WebKit Simulator counts, base 40428422068 vs flag 40428440889, 3 VMs each (offscreen-webkit-cli.mjs, minVms 3) | both complete | all four zones decided, verdict noGain (z4500 10 steps, z5000 5, finish 15, whole 105); the flag's Paint/Layout/RecalculateStyles ranges overlap or exceed the base (whole: Paint 1310-1359 base, 1254-1338 flag; Layout 601-635, 609-653); Composite and FireAnimationFrame equal |

Chromium counts: the Lean window reader (`OffscreenWindows`, minFrames 34/20/40/60/20/174) defines windows for swipe-touch-v1
only and refuses these counts.json (profile push-cycle-d1000), so no window verdict exists for this flag. The equal counts
say (INFERRED) the push-cycle profile does not exercise the morph frames (or the flag did not enter the flip there); they are not
evidence of a saving. A swipe-touch-v1 run of both arms is the follow-up that makes the reader apply.

Look report (LOCAL debug run on this Mac, Chrome stable, not a CI result; script `packages/premise-tests/src/look.mjs`,
numbers `results/morph-geom/look-chromium-local.json`). The faithful arm writes `--morph = m` by hand; the flag arm gets the
same writes and its driver pauses the effects at 1000 m (time tracks at the tween time that shows m). Region nav: max
channel delta / share of pixels over 12 (percent), nav rect union of both arms.

| band | 0 | .01 | .05 | .08 | .15 | .2 | .32 | .5 | .55 | .8 | 1 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 320x568 | 0/0 | 110/0 | 214/3.4 | 48/5.9 | 15/0.8 | 45/0 | 15/0.4 | 7/0 | 11/0 | 88/0.1 | 7/0 |
| 360x640 | 206/0.4 | 205/0.3 | 201/0.3 | 234/0.2 | 185/0.8 | 178/0.9 | 16/0.1 | 6/0 | 11/0 | 89/0 | 18/0 |
| 390x844 | 51/0.1 | 0/0 | 0/0 | 0/0 | 1/0 | 1/0 | 3/0 | 7/0 | 14/0 | 89/0.1 | 39/0.8 |
| 430x932 | 0/0 | 0/0 | 0/0 | 0/0 | 1/0 | 2/0 | 2/0 | 15/0 | 10/0 | 92/0.4 | 43/0.8 |
| 640x360 | 0/0 | 0/0 | 0/0 | 0/0 | 2/0 | 1/0 | 2/0 | 6/0 | 7/0 | 83/0 | 6/0 |
| 640x1000 | 7/0 | 0/0 | 0/0 | 9/0 | 2/0 | 4/0 | 13/0 | 8/0 | 23/0.1 | 101/1.7 | 40/2.3 |
| 641x700 | 0/0 | 0/0 | 0/0 | 0/0 | 1/0 | 2/0 | 6/0 | 8/0 | 6/0 | 67/0.1 | 11/0 |
| 768x1024 | 1/0 | 7/0 | 8/0 | 197/5.4 | 85/6.9 | 5/0 | 66/4.3 | 35/1.8 | 10/0 | 75/0.1 | 13/0 |
| 1024x768 | 3/0 | 23/4.8 | 15/0.5 | 26/1.7 | 23/1.5 | 13/0 | 21/0.4 | 14/0 | 10/0 | 89/0.1 | 13/0 |
| 1280x800 | 0/0 | 0/0 | 0/0 | 0/0 | 2/0 | 2/0 | 3/0 | 6/0 | 5/0 | 66/0.1 | 13/0 |
| 1440x900 | 3/0 | 8/0 | 6/0 | 6/0 | 135/0 | 35/0 | 11/0 | 11/0 | 13/0 | 79/0.2 | 15/0 |
| 1920x1080 | 0/0 | 0/0 | 0/0 | 0/0 | 14/0 | 22/0.5 | 16/0.1 | 7/0 | 9/0 | 80/0.1 | 2/0 |

Reading: E at m = 0 is not pixel-exact in 360x640 and 390x844 (206 and 51 at m = 0, where the flag has no effects: page
animation drift between two loads, not the flag; INFERRED, untested), at m = 1 the nav differs by at most 43 (430x932) with 0.8 percent over 12 in the
three narrow bands 390, 430 and 640x1000. Mid-morph deltas are large only in a few cells (320x568 .05/.08, 768x1024 .08-.5,
1024x768 .01): the class L look change. The region outside the nav is dominated by page animation drift between the two
loads (INFERRED) and is not reported as a look reading. Accepted limits: one engine (Chromium), one local run, no WebKit look.

## Memory decision, final statement
Per level, proved in `MorphGeomCounts.lean`: level 0 (faithful backs the nav only): flip fits 10 of 12 bands, 12 of 12 with the
platform dropped; level 2 (nav, panel, platform): 12 of 12. The faithful level stays undecided (no census lane exists), an
accepted limit; the follow-up task is the faithful morph-frame layer census.

WebKit reading: the flag is no gain on the engine-computation counts of the swipe scroll (the morph is a small part of the 105 steps and, INFERRED, the tracks add Layout in the flip-on frames); the saving the design claims is memory and compositor work, which these counts do not show. Not a failure of the pinned unit.
