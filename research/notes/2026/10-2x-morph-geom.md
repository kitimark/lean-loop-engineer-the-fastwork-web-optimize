# morph.geom:on: the site half (task morph-geom)

Design: `10-27-morph-compositor-geometry.md`. Lean: `10-2x-morph-geom-lean.md`. This round built the part and the memory
decision; the premises, the look report, the gate and the counts were not run (state partial, see Open).

## Memory decision (step 0)
The Lean census (`mem_bands`) counted every flip backing as new and freed nothing. `MorphGeomCounts.lean` restates it as net
bytes: flip bytes minus what the faithful page already backs at morph frames, dpr 3 below 641 px and 2 above, the layout of
`Ctx.sample`. The faithful side is a level: 0 is the nav only (certain: colour-mix fill under a backdrop blur, `will-change`);
1 adds the panel; 2 adds the platform. Levels 1 and 2 are INFERRED from the CSS. The Simulator census measurement that would
settle the level was not run (no CI push spent), so no run id exists.

| faithful backs | flip as designed | veil folded into D/G | veil folded and platform layer dropped |
|---|---|---|---|
| nav only (level 0) | fits 5 of 12 bands | fits 10 of 12 (not 1440x900, 1920x1080) | fits 12 of 12 |
| nav, panel, platform (level 2) | fits 12 of 12 | fits 12 of 12 | fits 12 of 12 |

Proved by `decide +kernel`: `net_lvl0_flip`, `net_lvl0_fold`, `net_lvl0_fold_platform`, `net_lvl2_flip`, `net_phone_fold`.
Decision: shrink in the stated order. Step 1 (fold the veil gradient into the fill layer) makes every phone band fit
(`net_phone_fold`, the accepted limit allows the two big desktop bands to stay named over at level 0). Step 2 (the platform
fade without its own layer) is taken only if the Simulator shows the faithful page has no platform layer; if it has one the
flip adds nothing there and step 2 is moot. The Lean `layers`/`anims` still contain the veil as a layer with its own track:
removing it (gradient on D, D tracks unchanged) is an open Lean change, not done here.

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
* Not built: earnClip and earnLabel wrappers, backdropClip/Kb/Ub, the reversal-correct time tracks (morph-timed),
  measured layout sizes (label and earn widths use the Lean sample values; logo width is measured). Those effects are skipped
  when their element is absent.

## TS stand-ins
`tracks.ts` (floats, 40-step bisection), `driver.ts`'s `timeOf` (inverse tween for the time tracks), `tree.ts` (DOM glue).
The `composed` to `anims` lookup lemma in Lean is not written.
