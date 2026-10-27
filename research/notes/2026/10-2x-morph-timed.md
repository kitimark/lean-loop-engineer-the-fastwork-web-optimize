# morph.tween:geom-timed (MEASURED on CI, PROVED in Lean, class L with morph.geom:on)

Question: with the geometry as compositor layers (morph.geom:on), can the push itself run as Web Animations on the compositor
clock, so no per-frame JS writes the morph value between push and end?

## Design (CONFIRMED in code, proofs in lean/Fw/Parts/MorphGeomTimed.lean)
- Per push one Web Animation per track on a shared `startTime` (the event time), 680 ms, easing `cubic-bezier(1/3,1,2/3,1)`,
  which is the tween's ease `1-(1-x)^3` (Lean `bezier_eq_ease`). Time tracks (earn, lang) are linear over the push.
- A reversal cancels the set and starts a new one from the ideal value at the event time. The keyframes are the track cut to
  the part the push still travels (`rebase`, up or down by mirroring). Proved: `rebase_eval`, `timed_eq_ideal` (any push
  sequence), `reverse_continuous`, `faithful_gap` (the faithful restart from the last frame is at most 3 frames of value away),
  `solver_gap`, `rebase_end`, `commit_eq` (last keyframe = the goal style of every non-time track), `crossMs_some`.
- The goal style is one root-attribute rule installed at a push up (base = last keyframe, so the animations may end); a push
  down holds its last keyframe (`fill: both`) until the end timer leaves the geometry.
- No rAF between push and end: the thresholds the page reads from `data-fw-morph` (0.001, 0.2, 0.4, 0.5225 pointer cut,
  0.55, 0.72, 0.92) and the end are `clock.interval` timers at the Lean `crossMs` times; each publishes the ideal value once.
- `MorphGeom` (morph.geom/index.tsx) owns the DOM side under this variant and skips its observer; it hands the timed geometry to
  the tween through `morph.tween/geom-timed.bus.ts`. Where geom is not allowed (nav not on dark, reduced motion) the faithful tween runs.

## TS stand-ins
- Time tracks of every push except the exact one from rest up are sampled at 60 Hz (`timeKnots`); no Lean spec for them.
- Timer firing times (`setInterval` granularity) are not modelled; a threshold is published at or after its `crossMs`.

## Evidence (run ids)
| item | run | reading |
|---|---|---|
| golden replay | apps/site geom-timed.golden.test.ts | 6 scenarios, 7 rebase, 12 cross cases equal the Lean golden |
| premises anim.shared-start, anim.reversal-jump | premise-tests 40454239481 | success on both engines |
| breakpoint gate, both engines, morph.geom:on,morph.tween:geom-timed | 40454266249 | pass |
| Chromium swipe-touch-v1 x3, base vs flag | 40454388920 vs 40454426552 | all windows noGain (results/morph-timed/chromium-windows.md) |
| WebKit Simulator, 3 VMs each, base vs flag | 40454309560 (one VM rerun) vs 40454356842 | z4500, z5000, finish, whole all noGain, counts equal (results/morph-timed/webkit-zones.md) |

Chromium windows: Paint, RasterTask and FireAnimationFrame fall (end 0-19: Paint 243 to 177, RasterTask 319 to 124,
FireAnimationFrame 43 to 23) but RecalcStyleCount, LayoutCount and PaintImage rise a little, so no window is a gain (the Lean rule
requires every counter not above).

## Not delivered
- The WebKit key check (no morph style, layout, paint or rAF between push and end on the Simulator timeline): the webkit-sim
  profile scrolls through y steps and dispatches no wheel or touch event (no such call in packages/measure-webkit/src), so no
  push runs and the arms are equal by construction (INFERRED). WebKit cells stay undecided.
- Faithful memory level (no census lane), the pin fight, nav.hitTest and the toolbar throttle (out of scope).
- Look: class L, user review pending; no phone run.
