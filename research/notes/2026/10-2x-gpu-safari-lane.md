---
id: 2026-10-2x-gpu-safari-lane
kind: note
title: "GPU arms on the Simulator and macOS Safari: a same-session pixel, census and memory lane, and why timing is refused"
status: draft
created: 2026-10-23
authors: [agent:measure-engineer]
topics: [measurement, webkit, simulator, safari, gpu, nav, morph, pain, iosurface, noise-floor]
---

# GPU arms: the Simulator lane (local, paired with CI)

Every number below is a local Simulator reading, taken in one session per zone on one Mac, and is paired
evidence, not a gate. Each reading sits next to the CI rows of the same arm (run ids in
`results/gpu-safari/lane/ci-pairs.mjs`). Code lives under `results/gpu-safari/lane/`; results are JSON
(stats and hashes, never PNGs) in `results/gpu-safari/<arm>.json`.

Session (MEASURED): iPhone 27 Simulator `fw-iphone-27`, iOS 27.0 runtime, DPR 3, viewport 430x775, UA
`Version/27.0 Mobile Safari`. Shot runs (UTC ids; PNGs stay in `$TMPDIR`, never committed):
nav `gpu-safari-sim-2026-10-23T00-46-14-744Z`, morph `gpu-safari-sim-2026-10-23T01-50-53-878Z` (round 3, driven
by a real push), pain
`gpu-safari-sim-2026-10-23T01-08-55-113Z`.

## Method

Per zone one capture: warm-up load, faithful (base), A/A control (faithful again), flag arms, faithful
once more (order probe, base3). Pixel cells use the existing Lean-backed `grade` (Fw.Gate.PathPix); the
rest is TS (stand-ins below). The noise floor is the later-load A/A floor: the changed px between the second
faithful load (A/A control, base2) and the third (order probe, base3), pairs i=1, j=2, because the first load
is the outlier (finding 1). An arm is "within" the floor when its nearest later load (base2 or base3) differs
by no more than that floor.

## Finding 1: the first faithful load is an outlier (MEASURED)

The first measured faithful load differs from later loads. base2 and base3 are pixel-identical at nav
m0.25/0.5/0.75, but base vs base2 changes 19,437 / 9,121 / 8,717 px (m0.1 59,857; m0.9 13-17). On pain it
is 337k-355k changed px with maxDelta up to 255 (cause not identified; the dark class matches at y-16 and
y-1, so it is not the flag state), while base2 vs base3 is 3.1k-6.8k. So the control must be the later loads and the arm is compared to the nearest faithful load
(`againstLoads`). Memory and IOSurface drift down with load order by about 10-20 MB the same way
(base 107, base2 102, arm 100 MB at nav m0.1), so an arm below faithful by that much is order drift.

## Nav arms (nav-clip-box, nav-bar-fixed, nav-logo-3d), states m0.1/0.25/0.5/0.75/0.9

| state | later-load floor (px) | clip-box changed vs nearest later load | max delta |
|---|---|---|---|
| m0.1 | 45,635 | 365,743 | 51 |
| m0.25 | 0 | 716,119 | 31 |
| m0.5 | 0 | 1,012,015 | 72 |
| m0.75 | 0 | 842,541 | 92 |
| m0.9 | 4 | 1,453,153 | 220 |

- All three arms sit above the later-load floor at every state (grades L at m0.5 and m0.9, "invalid" where
  the arm's two shots or the A/A control were not stable). The earlier floor (first load against the second,
  59,857 / 19,437 / 9,121 / 8,717 / 13-17 px) was the outlier pair and is not used. bar-fixed and logo-3d differ from clip-box by about 2k px
  at the logo/bar; all three share the fixed 406x791 box, which explains the common diff (MEASURED; cause
  INFERRED).
- Histogram at clip-box m0.5: 84% differ by 1 level, 12% by 2-3, 3.5% by 4-15, 1,457 px by 16 or more. At
  m0.9: 90% by 1, 18,061 px by 16 or more. The large deltas are subpixel text shifts (box 406 wide vs
  405.19, content centred, about 0.4 CSS px; INFERRED from the shot comparison, images look identical).
- Glass (backdrop blur area) median colour delta: 0 on the pill rect, [-1,0,0] on the union mask at
  m0.25/0.5 against A/A [0,0,0] (MEASURED). No colour shift of the glass beyond one level.
- Edge ring (3 device px around the faithful pill): clip-box 5,143 / 6,211 / 8,617 / 8,742 / 9,178 changed
  px against the A/A ring 12 / 2 / 0 / 2 / 0, so the pill edge moved clearly more than noise (MEASURED;
  this is the look change of the fixed box). Out-of-mask changed px: 74-179 (tiny).
- Census: 208 layers in faithful, clip-box and bar-fixed; logo-3d 209 (transform3D 0 to 1, one more layer);
  bar-fixed and logo-3d: overlap 5 to 4, stacking 169 to 170, willChange 173 to 174 (MEASURED).
- Not a lane artifact (MEASURED): stateSeen shows equal --morph and scrollY 5267 for faithful, arm and control
  at every state, and the arm shots are stable. The CI breakpoint gate covers rest states and the trajectory
  covers rects, so neither sees these mid-morph pixels. The three nav flags change the look mid-animation
  (pill edge ring, subpixel content shift up to maxDelta 220 at m0.9) and go to the user look-review class.
- Memory 100-117 MB arm vs 107-132 MB faithful, but the control and base3 drift the same way (order drift).
  IOSurface (vmmap proxy, not Instruments) e.g. m0.5 gpu region/MB: faithful 220/303, arm 213/290,
  control 213/287: no difference beyond drift.
- CI pairing: breakpoint-gate nav-clip-box 39842609609, bar-fixed 39846092556, logo-3d 39848853982;
  trajectory 39842561544 / 39842569267 / 39842581192. webkit-sim rows dispatched (39872562267 clip-box,
  39872566438 bar-fixed, 39872570182 logo-3d); task nav-fixed-followups reduces them.

## Morph panel (morph-panel-threaded, bundled morph-panel-threaded-fade), states m0.25/0.5/0.75

Driven through a real push (round 3, MEASURED). `sim-capture.mjs` `PUSH_EXPR` dispatches a wheel event (deltaY 120) at the page end, so the
page's own tween driver takes the push and starts its own effects: the panel WAAPI effects (`createPanelEffects`) in the threaded arms and the
platform fade (`createThreadedFade`) in the bundled one. While the handler runs, requestAnimationFrame parks the driver's frame loop, and the
effects the push started are paused. `STEP_EXPR` then sets `currentTime` of each effect to the elapsed time at which the tween value is m
(`elapsedAt`: 1 - (1 - x)^3 = m, the same curve as the panel bezier cubic-bezier(1/3, 1, 2/3, 1), 62 / 140 / 252 ms at 0.25 / 0.5 / 0.75), runs
the driver's frame at the time whose published value equals m (start lag 0 to 1 ms), and pins `--morph` to m exactly. Faithful goes through
the same push and starts no effect. Read back per state (`pushSeen` in the result JSON): faithful 0 effects, threaded 2 (morph-panel
transform+opacity, filter), bundled 3 (plus platform filter+opacity), all `paused` at progress 0.25 / 0.5 / 0.75; `--morph` and scrollY 5267
equal in faithful, arm and control. Run `gpu-safari-sim-2026-10-23T01-50-53-878Z`.

Round 2 compared static states (`SET_MORPH` skips the driver, so no effect ever started): 77,355 / 128,885 / 157,829 px for the threaded arm. Those
rows were the const-bounds class only and are replaced by these.

| state | later-load floor (px) | threaded changed (nearest later load) | bundled changed (nearest later load) | max delta |
|---|---|---|---|---|
| m0.25 | 8,620 | 29,272 (20,664) | 29,272 (20,664) | 2 |
| m0.5 | 1,567 | 121,715 (120,148) | 121,843 (120,276) | 3 |
| m0.75 | 5,315 | 146,134 (146,128) | 146,135 (146,129) | 3 |

- All six rows are above the later-load floor (2.4x at m0.25, 77x at m0.5, 27x at m0.75), outside the mask 0. Grades L, invalid, L; m0.5 is
  invalid because the A/A control's two shots differ (and the bundled arm's too), not because of the arm. The first two faithful loads are
  pixel-identical here (pair 0,1: 0 px) and the third differs from both (8,620 / 1,567 / 5,315), so the floor is the later-load pair 1,2 as
  defined. Differences are almost all 1 level (m0.5: 102,739 px at 1, 18,976 at 2-3, none at 4 or more). The GPU effects (CA opacity, blur
  and scale) render the panel within 3 levels of the main-thread raster; the cause of the 1-3-level difference is INFERRED (CA compositing
  against software raster), not isolated.
- Layer census (MEASURED): total 209 layers in every arm and state. With the effects running the reason mix moves: animation 8 to 9 (threaded)
  and 8 to 10 (bundled), filterWithCompositedDescendants 2 to 1 and 2 to 0, opacityWithCompositedDescendants 3 to 2 and 3 to 1,
  transformWithCompositedDescendants 9 to 8. The control equals faithful. Memory (Inspector) 110/105/105/105, 121/116/116/116 and 120/115/115/115
  MB for faithful/arm/control/order at m0.25/0.5/0.75 in the threaded arm: arm equals control (order drift). The bundled arm at m0.75 is 124 MB
  against control 115 and IOSurface gpu region 226/320 MB against control 201/274 MB (206/298 faithful); the first run of this session showed
  the same direction (217/352 against 205/285), so about +20 to +30 MB repeats (cause INFERRED: the platform keeps an animated layer with
  backing where faithful's platform at fade 0 has none). Threaded alone: no difference beyond drift.
- CI pairing: gate 39846842455; webkit-sim 39846909558 (workflow ends failure from the r3 vm, only r1/r2 used), const-bounds reference
  39846941236, bundled webkit-sim 39846948148; counts 39851664186 (const-bounds), 39851674587 (threaded and bundled); trajectory 39846814254
  (red, harness artifact) and 39855506403. CI Composite per frame for the open push: const-bounds 213/151/158/169, threaded 275/236/425/552,
  bundle 150/308/140/176; the morph note's verdict stays negative on cost.
- The local Simulator cannot confirm or refute that cost (timing refused, below).

## Pain dark scroll (pain-dark-scroll), five states around the flip (offset 888)

- Arm vs base2 and base3: 0 changed px at all five states (pixel-identical to the later faithful loads,
  MEASURED), against the later-load floor 6,804 / 6,323 / 4,355 / 3,107 / 4,711 px (within at every state).
  Against the first load 337k-355k px, which is Finding 1, so the control "aa" is the outlier and the grade
  is "Q". The honest reading is the nearest-later-load figure 0.
- The arm never sets is-pain-dark (the flag replaces the class); its pixels equal base2 at every state,
  including y+0 where base2 is dark, so the visible flip lands at the same offset (MEASURED).
- Census: layers 110 (faithful) vs 114 (arm, +4), memory 98 vs 110 MB (+12 MB), IOSurface gpu region
  113-115 / 245-267 MB (first load) vs 154 / 287 MB (arm) and 151-154 / 293-301 (control): arm vs control
  within about 10 MB. The CI census note (HOLD adds overlap-promoted canvas 14.3 MB and inner 12.0 MB) is
  consistent with +12 MB (INFERRED link).
- CI pairing: gate 39828600078, webkit-sim 39828605244, counts 39828614430, base counts 39818734599 and
  39818749535, later webkit-sim 39856782689 (base) and 39856789295 (HOLD; backing at scroll 1500/3000
  87.0/101.3 vs 99.0/113.3 MB).

## people-o-preview-translate: not measurable here

The hover scroll exists only at windows wider than 860 px; the Simulator viewport is 430 px. macOS Safari
is blocked by the locked screen (below). `results/gpu-safari/people-o-preview-translate.json` states both
reasons. CI gate 39850908365; CI counts blocked by chromium-desktop-crash, so no CI Simulator row.

## Timing arms are refused

Morph Composite and render-server ms per push, pain toggle-frame duration and the people-o hover scroll
need a quiet Mac. `results/gpu-safari/quiet-refusal.json` (2026-10-23T01:18:49Z, Simulator booted, lane
idle): 18 readings, 0 quiet, 18 refused (available memory 118-432 MB with the Simulator booted; why=avail
18/18; reason counts: availability 18, compress 1); load 3.13-3.56 against
a floor-maximum of 8.00 and a load margin of 1.00; no steady idle floor (baselineFloorCenti null), so no
pass runs. The Lean quiet rule is what refuses; the refusal is a finding, not a failure. Use the CI
Simulator Composite figures cited above for timing.

## macOS Safari arms: followUp

The Mac screen was locked (IOConsoleLocked true): `document.visibilityState` hidden, rAF 0 frames in
600 ms, WebDriver screenshots all black. `mac-capture.mjs` refuses a hidden window or a flat screenshot
instead of recording black. After an unlock: `pnpm -s fw slot acquire --kind measure --lease 3000`, then
`node results/gpu-safari/lane/run.mjs mac all`. IOSurface per push needs Instruments on macOS Safari (not
run); the Simulator number here is a vmmap proxy.

## The "connection closed by this tool" error of round 1

Not a lane bug (INFERRED for who sent it; the sequence is MEASURED from the log). The log started with
"SIGTERM: cleaning up"; `withSession`'s own signal handler (`packages/measure-webkit/src/session.mjs:81`)
closes the client, so the pending call reports the `wip.mjs:32` closed error, and the process exited 130.
An external signal (a killed tool call, its process group, or a released stale slot token) stopped it.
Fix: fresh slot token, the lane in its own process group, and `run.mjs` now prints "stopped by <sig> sent to
this process (not a lane fault)".

## TS stand-ins (temporary; to be Lean-proved or generated)

`ringSplit`, `glassOf`, `glassDelta`, `againstLoads`, `FLIP_SCAN` (pix.mjs, reduce.mjs, sim-capture.mjs),
`elapsedAt`, `wantEffects`, `PUSH_EXPR`, `STEP_EXPR` (plan.mjs, sim-capture.mjs), `parseIOSurface`, `simServicePids`, `iosurfaceSample` (iosurface.mjs), `summary.mjs`, `quiet-refusal.mjs`.
`grade` is the existing Lean-backed cell grade. Moving the lane to `packages/measure-webkit` is a follow-up.

## Limits

Local numbers are paired evidence, not a gate. IOSurface is a vmmap proxy. One Simulator session per
zone; load-order drift of 10-20 MB is not removed, only bracketed by control and base3. Timing arms are
refused; macOS Safari arms wait for an unlocked Mac.
