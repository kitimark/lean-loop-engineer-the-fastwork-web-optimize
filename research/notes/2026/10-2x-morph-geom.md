# morph.geom:on: the site half (task morph-geom)

Design: `10-27-morph-compositor-geometry.md`. Lean: `10-2x-morph-geom-lean.md`. This round built the part and the memory
decision; the premises, the look report, the gate and the counts were not run (state partial, see Open).

## Memory decision (round 2: veil folded)
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

Proved by `decide +kernel` in `MorphGeomCounts.lean`: `net_lvl0_flip` (exact bytes per band), `net_lvl0_flip_fits`,
`net_lvl0_platform`, `net_lvl0_platform_fits`, `net_phone_fold` (every phone band fits at level 0), `net_lvl2_flip`.
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
