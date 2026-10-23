---
id: 2026-10-2x-gpu-safari-lane
kind: note
title: "GPU arms on the Simulator and macOS Safari: a same-session pixel, census and memory lane, and why timing is refused"
status: draft
created: 2026-10-23
authors: [agent:measure-engineer]
topics: [measurement, webkit, simulator, safari, gpu, nav, morph, pain, iosurface, noise-floor]
---

# GPU arms: the Simulator lane and macOS Safari (local, paired with CI)

Every number below is a local reading, from the iOS Simulator (sections up to the timing refusal) or from macOS Safari on the real GPU (its own section), from one session per zone on one Mac, paired
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

The first measured faithful load differs from later loads. Not at every state: at nav m0.1 the A/A control is the odd load (base-base3 14,236, base2-base3 45,635), and in the morph run the order probe is (base-base2 0). The pair-1,2 floor then includes the odd load, so it is the larger, conservative floor. base2 and base3 are pixel-identical at nav
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
  59,857 / 19,437 / 9,121 / 8,717 / 13-17 px) is not used (it includes the first load). bar-fixed and logo-3d differ from clip-box by about 2k px
  at the logo/bar; all three share the fixed 406x791 box, which explains the common diff (MEASURED; cause
  INFERRED).
- Histogram at clip-box m0.5: 84% differ by 1 level, 12% by 2-3, 3.5% by 4-15, 1,457 px by 16 or more. At
  m0.9: 90% by 1, 18,061 px by 16 or more. The large deltas are subpixel text shifts (box 406 wide vs
  405.19, content centred, about 0.4 CSS px; INFERRED from the shot comparison, images look identical).
- Glass (backdrop blur area) median colour delta: 0 on the pill rect, [-1,0,0] on the union mask at
  m0.25/0.5 against A/A [0,0,0] (MEASURED). No colour shift of the glass beyond one level.
- Edge ring (3 device px around the faithful pill): clip-box 5,143 / 6,211 / 8,617 / 8,742 / 9,178 changed
  px against the A/A ring 12 / 2 / 0 / 2 / 0, so the pill edge moved clearly more than noise (MEASURED;
  this is the look change of the fixed box). Out-of-mask changed px: 74-179.
- Census: 208 layers in faithful, clip-box and bar-fixed; logo-3d 209 (transform3D 0 to 1, one more layer);
  bar-fixed and logo-3d: overlap 5 to 4, stacking 169 to 170, willChange 173 to 174 (MEASURED).
- Not a lane artifact (MEASURED): stateSeen shows equal --morph and scrollY 5267 for faithful, arm and control
  at every state, and the arm shots are stable at m0.5 and m0.9 for all three arms (unstable, graded invalid: m0.1 all three, m0.25 bar-fixed, m0.75 clip-box and logo-3d; the changed px there, 365k-852k, is still 8x or more above the later-load floor). The CI breakpoint gate covers rest states and the trajectory
  covers rects, so neither sees these mid-morph pixels. The three nav flags change the look mid-animation
  (pill edge ring, subpixel content shift up to maxDelta 220 at m0.9) and go to the user look-review class.
- Memory 100-117 MB arm vs 107-132 MB faithful, but the control and base3 drift the same way (order drift).
  IOSurface (vmmap proxy, not Instruments) e.g. m0.5 gpu region/MB: faithful 220/303, arm 213/290,
  control 213/287: no difference beyond drift.
- CI pairing: breakpoint-gate nav-clip-box 39842609609, bar-fixed 39846092556, logo-3d 39848853982;
  trajectory 39842561544 / 39842569267 / 39842581192. webkit-sim rows: 39872562267 clip-box (failure; v1/r1 failed, r2 pair usable), 39872566438 bar-fixed (failure; r1/r2 failed, r3 pair usable), 39872570182 logo-3d (success); task nav-fixed-followups reduces them.

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
  is "Q". The reading is the nearest-later-load figure 0.
- The arm never sets is-pain-dark (the flag replaces the class); its pixels equal base2 at every state,
  including y+0 where base2 is dark, so the visible flip lands at the same offset (MEASURED).
- Census: layers 110 (faithful) vs 114 (arm, +4), memory 98 vs 110 MB (+12 MB), IOSurface gpu region
  113-115 / 245-267 MB (first load) vs 154 / 287 MB (arm) and 151-154 / 293-301 (control): arm vs control
  within about 10 MB. The CI census note (HOLD adds overlap-promoted canvas 14.3 MB and inner 12.0 MB) is
  consistent with +12 MB (INFERRED link).
- CI pairing: gate 39828600078, webkit-sim 39828605244, counts 39828614430, base counts 39818734599 and
  39818749535, later webkit-sim 39856782689 (base) and 39856789295 (HOLD; backing at scroll 1500/3000
  87.0/101.3 vs 99.0/113.3 MB).

## people-o-preview-translate

Simulator: not measurable. The hover scroll exists only at windows wider than 860 px and the Simulator viewport is 430 px;
`results/gpu-safari/people-o-preview-translate.json` states it. macOS Safari: measured, see the macOS Safari section. CI gate
39850908365; CI counts blocked by chromium-desktop-crash, so there is no CI Simulator row.

## Timing arms are refused

Morph Composite and render-server ms per push, pain toggle-frame duration and the people-o hover scroll
need a quiet Mac. `results/gpu-safari/quiet-refusal.json` (2026-10-23T01:18:49Z, Simulator booted, lane
idle): 18 readings, 0 quiet, 18 refused (available memory 118-432 MB with the Simulator booted; why=avail
18/18; reason counts: availability 18, compress 1); load 3.13-3.56 against
a floor-maximum of 8.00 and a load margin of 1.00; no steady idle floor (baselineFloorCenti null), so no
pass runs. The Lean quiet rule is what refuses; the refusal is a finding, not a failure. Use the CI
Simulator Composite figures cited above for timing.

macOS Safari, same rule: `results/gpu-safari/mac-quiet-refusal.json` (2026-10-23T10:27:41Z, unlocked Mac, lane idle): 12 readings,
0 quiet, 12 refused (why=holders 12); load 2.83-3.71 against a floor-maximum of 8.00 and a load margin of 1.00; baselineFloorCenti null.
Other agents' builds hold the Mac, so no Composite or render-server pass ran on macOS either (MEASURED). The lane records cadence only.

## macOS Safari arms (real Apple GPU, measured 2026-10-23, task gpu-safari-mac)

Unit: the nav, morph (alone and bundled), pain, people-o arms, plus hero.exit:threaded, each against faithful in one session, reduced
against the later-load floor as above, paired with the Simulator rows (`results/gpu-safari/mac-vs-sim.json`, from `lane/pairs.mjs`).
The Mac is not the phone: the readings answer "does the arm render differently on the real GPU", not "is it smoother on the iPhone".

Session (MEASURED): macOS 27 Safari 27.0.1 through safaridriver (no "Allow remote automation" refusal), `measure` slot, screen unlocked
all session. Window 430 wide (DPR 2, viewport 430x880, scroll range 5229 px); the people zone a 1280x1000 window (viewport 1280x948).
Shot runs (UTC ids, PNGs stay in `$TMPDIR`, never committed): nav `gpu-safari-mac-2026-10-23T10-13-13-503Z`, morph
`...10-17-23-955Z` (repeat `...10-27-49-373Z`), pain `...10-19-05-456Z`, hero `...10-24-40-822Z` (repeat `...10-29-30-206Z`), people
`...10-31-08-209Z`. No CI run exists for the Mac rows (lane exception (c), the real GPU runs only here); the CI rows they pair with are in
`lane/ci-pairs.mjs`.

Reading rule on the Mac (MEASURED). Most nav, morph and hero cells grade "invalid": the two shots of one state differ (the page is not
fully frozen on the Mac, even with the effects paused), so the grade says nothing. The reading is the changed-px count of the arm against its nearest
later faithful load, set against the later-load A/A floor (pair i=1, j=2), exactly as for the Simulator. A Mac floor is larger than the
Simulator's in the morph zone (26k to 70k px against 1.5k to 8.6k) because the platform's blur is rasterised by the GPU and varies between loads.

- Nav (clip-box, bar-fixed, logo-3d), nearest later load / floor: m0.1 176.6k / 0.7k, m0.25 166.3k / 9.3k, m0.5 102.4k / 12.4k,
  m0.75 12.4k / 2.9k, m0.9 748k / 2.3k for clip-box; bar-fixed is within 3% of it at every state; logo-3d is within 2% except m0.5 (+6%) and m0.75 (15.5k, +25%). Every state sits above the
  floor, by 4.2x to 327x, the same direction as the Simulator (8x to 363669x; its floors were 0 at m0.25 to m0.75). The three arms differ from each other by 3% or less except logo-3d at m0.5 and m0.75, as on the Simulator, so what separates them from faithful on both lanes is one
  shared change of the morph frame (a look-change candidate, for the user's visual review). Glass median delta is 0 (m0.1: -1, 0, 0), like A/A,
  so the frosted bar itself does not move. Status: MEASURED.
- Morph, real push, effects counted (faithful 0, threaded 2, bundled 3): nearest / floor at m0.25, m0.5, m0.75. Threaded 13.0k / 26.4k (within),
  63.8k / 41.3k (1.5x above), 29.5k / 69.6k (within). Bundled 13.5k / 26.4k (within), 77.8k / 41.3k (1.9x above), 56.1k / 69.6k (within).
  The repeat run: threaded 9.7k / 17.9k, 45.3k / 68.4k, 53.6k / 61.2k (all within); bundled 23.5k / 17.9k (1.3x above), 81.4k / 68.4k
  (1.2x above), 59.6k / 61.2k (within). Max pixel delta 2 to 4 levels at m0.25, 20 to 23 at m0.5, about 190 to 200 at m0.75 (text edges). Verdict: INCONCLUSIVE on the Mac. Two sessions
  agree that the morph panel is no more than a few tens of thousands of px from faithful (under 1% of 1.5M px at DPR 2), the same order as the
  A/A control (25k to 130k px), so a small change would hide inside the Mac floor. The Simulator rows (2.4x, 77x, 27x above floor)
  are the clearer ones; the Mac cannot separate the arm from load-to-load blur drift.
- Pain (dark-scroll), five states y-16..y+16: 0 changed px against the later loads at every state, floor 0 (identical on the real GPU;
  y-16, y-1, y+0 grade E, y+1 and y+16 grade Q because the first load is the outlier, finding 1). The Simulator also gave 0 against floors of 3k to 7k.
  MEASURED: the arm without `is-pain-dark` renders the faithful frame at the flip offset on the Mac too.
- hero.exit:threaded, scroll 220/440/660 px (exit 0.25/0.5/0.75 of 880 px; faithful exit opacity 0.75/0.5/0.25):
  the arm is live (`data-exit-live`, 13 scroll animations). x0.25 7.7k / 5.2k (1.5x above), x0.5 20.8k / 2.5k (8.2x above), x0.75 0 / 5.2k
  (identical, grade E). Repeat: x0.25 8.3k / 2.6k (3.1x above), x0.5 5.2k / 3.9k (1.3x above), x0.75 0 / 0 (identical). Max delta 167 and 111 at x0.25 and x0.5 in
  both runs. The direction repeats; the size at x0.5 does not (20.8k then 5.2k). Verdict: a candidate look difference in the middle of the
  exit; it needs a third session before it counts. The CI path-pixel cells of the same arm on the Simulator (runs 39920801675, 39924527942, 39929556147, `results/hero-exit-threaded-pix/`; note `10-2x-hero-exit-threaded-pix`) grade no P cell E or Q and call the differences L (text hold or change outside the masks), INFERRED to be the same class as the Mac readings (max deltas of 167 and 111 levels); a Simulator hero row of this lane (`run.mjs sim hero`) was not taken. Status: MEASURED, not settled.
- people.o:preview-translate (1280 px window, hover on the first face, scroll 3 px per frame for 10, 20, 40 frames; the card must open, the
  lane refuses otherwise): the arm sets `translate: 0px -27px / -54px / -111px` with `top` fixed at 256 px, faithful moves `top` 229 / 202 / 145 px, and the
  card lands at the same rect (544.11, 316 / 262 / 148, 320 x 373.9). The arm equals both earlier faithful loads with 0 changed px at all three states (the
  same frame hash). At f40 the third faithful load (order probe) alone differs, 1.34M px over the whole frame, so the floor there is that one load and
  the arm's reading is "within". MEASURED: translate gives the faithful pixels on the real GPU.
- Layer census and IOSurface: not taken on macOS (the Simulator census is a `vmmap` proxy; macOS Safari needs Instruments). The Mac rows carry
  null census and IOSurface fields.

### Why the bundled arm equals threaded at morph m0.25 (item 2; MEASURED on the Mac by `lane/probe-fade.mjs`, `results/gpu-safari/mac-bundled-vs-threaded.json`)

The threaded and bundled Simulator rows were both 29,272 changed px from faithful at m0.25. The bundled arm adds a third effect, the threaded
platform fade. Two readings could explain the tie: (a) the threaded fade renders exactly like the CSS fade path it replaces, so adding it changes
no pixel, or (b) the platform lies outside the frame, so its fade does not show. The probe pauses each arm at `elapsedAt(m)` after a real push and reads the
platform: its box is 413 x 1854 at top -974 and 47.5% of it lies in the viewport at the bottom of the page, which rules (b) out. At m0.25
faithful and threaded have `--morph-fade` 0.5454545, computed opacity 0.545455 and `blur(5.454545px)`. The bundled arm has three effects, the CSS
variable stays 1, and the computed opacity is still 0.545455 with `blur(5.454545px)`, the same pair that the CSS variable produces. The same holds at m0.5 (0.090907,
blur(10.909113px)) and m0.75 (0, blur(12px)). So (a): the threaded fade computes the same opacity and blur as the CSS path (INFERRED to be by design: `createThreadedFade` takes its keyframes from Lean `PlatformFade`), so the fade adds no style difference at any of the three states. CONFIRMED by the probe on both the opacity and the
filter; it reads the computed style, not pixels, so it proves style equality only. Pixels were identical in the Simulator at m0.25 alone; at m0.5 and m0.75 the two arms' frames differ (hashes differ; at m0.75 both stable, platform opacity 0), so the remaining pixel difference comes from outside the platform's computed style and is not explained here (INFERRED: raster/compositing path or load noise).

### The elapsedAt golden (item 3)

`elapsedAt(m)` in `plan.mjs` is the paused-effect time in ms. Lean `Fw.Measure.GpuElapsed` defines it as the largest time on a 1/1000 ms grid whose
ease-out cubic does not pass `m` (`elapsedMilli`), and proves both sides: `elapsed_not_past` (ease of the time is at most `m`) and `elapsed_next_past` (one
grid step later passes `m`, unless the time is already 680 ms), over `Rat`, without Float. `lean/scripts/GpuElapsedGolden.lean` writes
`results/gpu-safari/lane/elapsed.golden.jsonl` (10 values of `m`, edges included), `lean/scripts/check.sh` checks it is current, and
`lane.test.mjs` checks the TS `elapsedAt` against it to the millisecond grid. `elapsedAt` is therefore no longer a TS stand-in.

## The "connection closed by this tool" error of round 1

Not a lane bug (INFERRED for who sent it; the sequence is MEASURED from the log). The log started with
"SIGTERM: cleaning up"; `withSession`'s own signal handler (`packages/measure-webkit/src/session.mjs:81`)
closes the client, so the pending call reports the `wip.mjs:32` closed error, and the process exited 130.
An external signal (a killed tool call, its process group, or a released stale slot token) stopped it.
Fix: fresh slot token, the lane in its own process group, and `run.mjs` now prints "stopped by <sig> sent to
this process (not a lane fault)".

## TS stand-ins (temporary; to be Lean-proved or generated)

`ringSplit`, `glassOf`, `glassDelta`, `againstLoads`, `FLIP_SCAN` (pix.mjs, reduce.mjs, sim-capture.mjs),
`wantEffects`, `PUSH_EXPR`, `STEP_EXPR`, `HERO_RANGE`, `HERO_SPLASH_DONE`, `HERO_STATE`, the people expressions (`PEOPLE_SETUP`, `PEOPLE_HOVER`, `PEOPLE_SCROLL`, `PEOPLE_STATE`, mac-capture.mjs),
`probe-fade.mjs`, `pairs.mjs` (plan.mjs, sim-capture.mjs, mac-capture.mjs), `parseIOSurface`, `simServicePids`, `iosurfaceSample` (iosurface.mjs), `summary.mjs`, `quiet-refusal.mjs`.
`grade` is the existing Lean-backed cell grade. Moving the lane to `packages/measure-webkit` is a follow-up.

## Limits

Local numbers are paired evidence, not a gate. IOSurface is a vmmap proxy. One Simulator session per
zone; load-order drift of 10-20 MB is not removed, only bracketed by control and base3. Timing arms are
refused on both lanes. The macOS Safari rows are one session each (morph and hero have a repeat); the Mac pages do not freeze as fully as the
Simulator's, so most Mac cells grade "invalid" and the nearest-later-load reading carries them. The phone is not measured.
Follow-ups: people.carousel:crop (its swap is timer-driven, a 220 ms swap in a 1020 ms cycle, so a paused mid-swap frame needs the timers parked or the clock pinned, which WebDriver screenshot latency does not allow); a third hero session and a CI Simulator hero row;
moving the lane to `packages/measure-webkit`.
