# glint-compositor

Question: can the glint on the two `[data-fw-dash]` svgs run with no SMIL timeline and no per-frame attribute or style write, the look kept?
Background: geom-recalc-bisect (10-2x-geom-recalc-bisect.md) found about 1 style recalc per idle frame in WebKit from the SMIL timeline of the 4
`<animate>` on x1/x2; glint-hold-wktr (10-2x-glint-hold-wktr.md, run 40823517468) cut it only 26 percent. Task glint-compositor; flag
`platform.glint:compositor` (registry, class L, never in a preset).

## Design (CONFIRMED by proof and by the unit tests)
- x2 - x1 is 120 at every time (Lean `glint_translate`), so the animated gradient is one fixed gradient shifted by x1 + 200. The variant draws the
  dash as an HTML clip of the stadium shape (`clip-path: path(...)` on the 94 x 3.2 box, opacity as the original's highlight) holding one fixed
  120 px layer with the six CSS stops, moved by `translateX` over the original's 5 s, linear, six keyframes.
- Lean `Fw.Parts.PlatformGlintCompositor`: `shiftAt_eq` (keyframe value = x1 + 200), `stops_eq` / `stops_eq_all` (each of the six stop positions in dash
  coordinates equal the original's at every elapsed time), `variant_no_smil`, `variant_no_writes`, `faithful_writes` (4 SMIL animations write per tick in the
  original, 0 in the variant; the premise that a linear-easing transform animation on an HTML box is compositor-run is INFERRED from source, below).
- Keyframes are generated: `lean/Fw/Parts/PlatformGlintCompositorGolden.lean` writes `packages/contracts/golden/parts/platform-glint-compositor.jsonl`
  and `apps/site/src/parts/platform.glint/compositor.gen.ts`; `compositor.test.ts` replays the golden (stop positions at 36 samples, keyframes, set facts).
- Why an HTML box and not an SVG child: WebKit `LayerBasedSVGEngineEnabled` defaults to false (Source/WTF/Scripts/Preferences/UnifiedWebPreferences.yaml:4592-4604
  @862f17d), so an SVG child transform is not accelerated there; `KeyframeEffect::canBeAccelerated` (Source/WebCore/animation/KeyframeEffect.cpp:1970-2022)
  needs replace composite and no steps or linear() timing, hence `easing: linear`. Chromium starts a transform animation on a non-SVG box on the compositor
  (third_party/blink/renderer/core/animation/compositor_animations.cc:315-335 @f842f52). INFERRED.

## Look (MEASURED, CI premise glint.compositor-pixels, run 40833327444 at 090b513b4)
Bound decided before the data: 12 of 255 per channel (the bound of glint.hold-pixels), 27 times across the 5 s cycles, both engines, device ratio 1 and 2.
Result: not inside the bound at the dash ends.

| engine | dpr | worst channel difference | where |
|---|---|---|---|
| Chromium 156 | 1 | 41 | left/right round-cap column of the dash end, only while the band is bright at that end |
| Chromium 156 | 2 | 94 | same |
| WebKit 27.2 | 1 | 35 | same |
| WebKit 27.2 | 2 | 79 | same |

Class L (look change, for the user's review). A local debug run (not a result) located it: with `clip-path: inset(0 round 1.6px)` the first cap column differs by up
to 44; `path()` leaves about 3 pixels per dash end. The variant equals the analytic coverage of the stadium (col 0 coverage 0.50, 0.97, 0.67 for the three rows
of the cap; the variant's pixel values give 0.51, 0.97, 0.68); the original's stroked cap paints 0.34, 0.79, 0.49 in both engines. So the difference is the
engines' stroke-cap coverage, not the gradient. Tried and not better: border-radius with overflow hidden, will-change, CSS mask from a data URI (did not
render), mask from an SVG `<mask>` reference (the clip was not applied in WebKit).
The premise test was changed after this run (same bound): it asserts the bound inside the dash (x from 2 px after each end) and records the cap-column worst and the
class, so the lane is not red for a recorded class L; the rerun is in the follow-up run below.

## WKTR pref OFF accel lane (MEASURED, run 40833327416, 3 jobs, results/glint-compositor/r1; WKTR is not iOS Safari)
Rule decided before the data (Lean `Fw.Device.GlintHoldCompositor.judgeC`, golden `packages/contracts/golden/device/glint-compositor.jsonl`, stand-in
`packages/measure-wktr/src/glint-compositor.mjs`): unread (a cell under 40 idle / 12 flip frames), no-contrast (base under floor + 50), uninformative (span within
twice the band), within the floor band (h <= f + band, the target), no cut (b <= h + band), else cuts partly; band = max(span/16, spread of the base arms);
overall: at least 2 judged jobs, all alike.

Recalcs per 100 frames (base = mean of its arms, floor = every svg timeline paused):

| job | cell | base | floor | compositor | band | verdict |
|---|---|---|---|---|---|---|
| j1 | idle | 102 | 0 | 0 | 6 | within the floor band |
| j2 | idle | 100 | 0 | 0 | 6 | within the floor band |
| j3 | idle | 100 | 0 | 0 | 6 | within the floor band |
| j1 | flip | 193 | 92 | 94 | 13 | within the floor band |
| j2 | flip | 232 | 81 | 85 | 9 | within the floor band |
| j3 | flip | 185 | 74 | 90 | 6 | cuts partly |

Overall idle: within the floor band (3 of 3). Overall flip: mixed (the Lean rule does not merge a different verdict). INFERRED reading: the idle recalcs of 100 per 100
frames, the glint's SMIL timeline, are gone (0 = the paused-timeline floor, where the hold-freeze reached 74); in the flip the compositor arm sits within 3 to 16
of the floor, flip frames of the compositor arm are 58 to 71 per job (few). internals.acceleratedAnimationsForElement was not read for the glint layers, so
"runs on the compositor" is INFERRED from the source and the 0 recalcs.

## Not done / limits
- Chromium counts lane (task item 5) not run: the only Chromium counts profile with arms (offscreen-v1) counts hidden frames, where neither arm mounts the glint;
  no lane counts the playing glint on-screen in Chromium. Follow-up.
- No phone run; WKTR is not iOS Safari; the phase of the compositor start is the effect's first frame, not the original's beginElement (at most one frame).
- The flag is not in a preset; class L needs the user's look review of the dash end caps.
