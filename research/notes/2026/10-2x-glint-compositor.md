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
Result: not inside the bound at the dash edges (table next).

First run 40833327444 (all pixels counted):

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
The premise test was changed twice after seeing these numbers (the bound 12 did not change): run 40837035170 (push 2) showed that in Chromium at device ratio 2 the
partly covered top and bottom rows of the dash also differ (59), so the final premise asserts the bound only in the interior of the dash (x from 2 px after each end,
y from one device pixel inside the top edge to one inside the bottom edge) and records the all-pixel worst and the class. Final run 40837548139 (at ced74ee8c), both
engines, holds:

| engine | dpr | worst, all pixels (edges included) | worst, interior |
|---|---|---|---|
| Chromium 156 | 1 | 41 | 2 |
| Chromium 156 | 2 | 94 | 3 |
| WebKit 27.2 | 1 | 35 | 2 |
| WebKit 27.2 | 2 | 79 | 2 |

So the gradient, its position and the dash interior match (interior at most 3 of 255); only the edge pixels differ: the cap columns at the dash ends and the partly covered
top and bottom rows. The class is L because the all-pixel worst is above the bound.

## WKTR pref OFF accel lane: INVALID for the variant (runs 40833327416 and 40837547847, 3 jobs each, results/glint-compositor/r1 and r2)
Rule decided before the data (Lean `Fw.Device.GlintHoldCompositor.judgeC`, golden `packages/contracts/golden/device/glint-compositor.jsonl`, JS stand-in
`packages/measure-wktr/src/glint-compositor.mjs`): unread, no-contrast, uninformative, within the floor band (h <= f + band, the target), no cut, cuts partly;
band = max(span/16, spread of the base arms); overall needs at least 2 judged jobs, all alike.

What the runs read (MEASURED), recalcs per 100 frames, base = mean of its arms, floor = every svg timeline paused:

| run | job | idle base / floor / compositor | flip base / floor / compositor |
|---|---|---|---|
| r1 | j1 | 102 / 0 / 0 | 193 / 92 / 94 |
| r1 | j2 | 100 / 0 / 0 | 232 / 81 / 85 |
| r1 | j3 | 100 / 0 / 0 | 185 / 74 / 90 |
| r2 | j1 | 97 / 0 / 0 | 172 / 77 / 89 |
| r2 | j2 | 99 / 0 / 0 | 190 / 96 / 77 |
| r2 | j3 | 104 / 0 / 100 | 168 / 68 / 177 |

Why these are not a result: the accel probe (`packages/measure-wktr/src/mid-page.mjs`, `rsArm`) pauses every running Web Animation before it counts, to isolate the
SMIL timeline of the original (SMIL is not a Web Animation, so the base arm keeps it). The variant's glint is a Web Animation, so the probe paused it too:
`pausedN` is 7 to 10 in the compositor arms against 5 to 8 in the base arms, and no compositor arm had a glint animation running. The zeros in 5 of 6 idle cells measure a
page whose glint is stopped, which is what the floor measures. Only r2 j3 differs (20 animations still running after the pause, idle 100, flip 177), and the cause of
those 20 is not known, so it cannot be read as the variant's cost either. The first read of these numbers ("idle 100 to 0, within the floor band") was wrong and is retracted.
Question asked of the mistake (never-skip rule): why was it not seen before the push? The arm was never run against a variant that is itself a Web Animation (the hold
arm is SMIL). Lean-provable? The decision "a reading needs the variant's animations running" is: `judgeLive` (theorems `judgeLive_notRunning`, `judgeLive_of_live`) refuses a
reading with `glintLive = 0`; with it the stand-in re-judges r1 and r2 as "variant animation not running" in every cell (`results/glint-compositor/*/verdict.txt`).

Fix committed, not run (the 3 pushes are used): the probe keeps the glint animations when the arm option `gk` is set (the glint modes set it) and records `rs.glintLive`.
To measure: push `ci/glint-compositor` once more with `[ci:wktr] [accel]` and the temporary wktr.yml build/mode edit of commit 5eaad3bb4 (build `--config
"?fw=morph.geom:on,morph.tween:geom-timed,platform.glint:compositor"`, accel `--modes glint-base-thr-off,glint-comp-thr-off`), 3 jobs, then
`node packages/measure-wktr/src/glint-compositor-cli.mjs <job dirs>`.

## WKTR pref OFF accel lane, valid reading (MEASURED, run 40845872049 at 79077612d, 3 jobs, results/glint-compositor/r4)
The corrected probe keeps the variant's animations (`rs.glintLive` = 2 in every cell of both arms), so Lean `judgeLive` accepts all six cells. The rule `judgeC` was
fixed before the data (band = max(span/16, base spread)). Recalcs per 100 frames, base / all-paused floor / compositor:

| job | idle | flip |
|---|---|---|
| j1 | 100 / 0 / 0 | 176 / 75 / 88 |
| j2 | 100 / 0 / 0 | 171 / 72 / 80 |
| j3 | 98 / 0 / 0 | 171 / 68 / 87 |

Idle: within the floor band in 3 of 3 jobs, so with threaded animations OFF the compositor-run glint costs no per-frame style recalc while the original's SMIL costs 100 per
100 frames. Flip (scroll/interaction arm): cuts partly in 3 of 3 (compositor 80 to 88 against base 171 to 176 and floor 68 to 75; it stays above the floor band). Overall: idle
within the floor band, flip cuts partly. WKTR is not iOS Safari; no phone run.

## Edge cause (INFERRED, follow-up for an edge-exact variant)
The original draws the dash as an SVG stroked line with round caps, rasterized by the SVG renderer's stroke path with its own antialiasing of the cap arcs. The variant
clips an HTML box with `clip-path: path(...)` of the stadium outline, which both engines apply as an antialiased coverage mask over a composited layer (a separate raster of the
gradient layer, then masked). The two paths cover the partly covered cap columns and the top and bottom rows with different coverage (up to 94 of 255), while the fully covered
interior is the same gradient (at most 3). Not traced to file:line in the time box; to confirm, diff the coverage of a solid-color stadium drawn both ways. An edge-exact variant
would draw the mask as the same stroke (an SVG `mask` with the original line, or an inline SVG `foreignObject`-free layer) and keep the transform on an HTML wrapper.

## Not done / limits
- Flip arm: the compositor glint still recalcs above the floor band (80 to 88 against floor 68 to 75); why is not known.
- Chromium counts lane (task item 5) not run: the only Chromium counts profile with arms (offscreen-v1) counts hidden frames, where neither arm mounts the glint;
  no lane counts the playing glint on-screen in Chromium. Follow-up.
- No phone run; WKTR is not iOS Safari; the phase of the compositor start is the effect's first frame, not the original's beginElement (at most one frame).
- The flag is not in a preset; class L needs the user's look review of the dash edge pixels.
