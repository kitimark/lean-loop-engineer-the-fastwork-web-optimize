# geom-prewarm: holding the geom-timed flip tracks and layout in idle does not pass A4 and does not remove the late first commit

Status: PARKED, not landed (lead 2026-10-28): the held-set design fails A4 in every band (run 40648228042). Code stays on branch worktree-wf_066a7844-684-1 (2ac8461ca).

Status: PARKED, not landed (finding). Branch worktree-wf_066a7844-684-1 (CI branch ci/geom-prewarm), three pushes used, no phone run.
Question: if the 55 geom-timed track animations and the flip tree are built and held paused while the platform is near and idle, does the first take
get cheap (desktop: no 96-650 ms build in the push) and does the first flip stop ticking on the main thread mid-tween on WebKit, with the rest state
unchanged (gate A4)?

## Runs (MEASURED, GitHub Actions, never phone time)
| push | commit | wktr | breakpoint-gate |
| --- | --- | --- | --- |
| 1 | 4db117d42 | 40636360090 ok | 40636360067 fail (A3a desktop, A4 all) |
| 2 | 779167974 | 40640739377 ok | 40640739317 fail (A3a 12/12, A4 0/12, both engines) |
| 3 | 9b0a3100d | 40648228102 ok (j1 j2 j3) | 40648228042 fail (flip-cell chromium, flip-cell playwright-webkit) |

## Push 3, gate (run 40648228042, flip verify, 12 bands, both engines)
- A3a 12/12 and A5 12/12 on Chromium and WebKit. A4 0/12 on both engines; the two repeat passes (3 bands each) also 0/3 per pass on both.
- The flip cell: Chromium passes its cell readings and fails only at verify. WebKit `morph.geom:on` fails 3 of 48 readings (360x640 m=0: columns 0, expected 3).
  The same cell failed on earlier pushes of other branches (note geom-track-style), so it is not attributed to the hold (INFERRED; not isolated).
- A4 cause, MEASURED in `verify-<engine>.json` (`baseWidth` against the width after the leave), identical on both engines:

| band | 320 | 360 | 390 | 430 | 640 | 768 | 1024 | 1280 | 1440 | 1920 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nav width read as base (held tree) | 296 | 336 | 366 | 406 | 616 | 728 | 984 | 1240 | 1398 | 1398 |
| maxDev against the rest width after the leave | 8 | 8 | 8 | 8 | 8 | 8 | 8 | 256 | 414 | 414 |

  After the leave the nav is at its rest width (984 at 1280, 288 at 320); while the tree is held it is the final box (1240 at 1280, +8 px at every phone
  and tablet band). So the held `.is-flip` tree lays the nav out differently at rest: this is a layout and hit-testing change outside the flip, not
  only a harness base-read artefact. Verdict: the held-set design as built cannot pass A4 and does not keep the rest state's layout. Moving the read
  would hide it, not fix it.
- First enter take, ms (`take ms`, first of four): desktop (>= 640) 0-1 ms on both engines (held set used). Phone bands fall back and stay slow:
  Chromium 68 (320), 68 (360), 76 (390), 86 (430); WebKit 1 (320), 185 (360), 232 (390), 248 (430). Push 2 had the same split (1 ms against 96-120 ms
  Chromium and 320-650 ms WebKit phone widths). Why the phone bands fall back is not isolated (INFERRED: the ready or fresh rule after the viewport settle).

## Push 3, WKTR (run 40648228102, iPhone 17 iOS 26.5 simulator build, 3 jobs, accel-prewarm readout)
Tracks per sample: accelerated (a) and ticking (running, not accelerated), of 55. pref ON = `mid`, pref OFF = `mid-thr-off`.
Held at first push means the probe saw 55 tracks adopted (`prewarmed` 55, created on push 0). A second flip's `created on push` 55 counts the rebuild inside the arm (trace: build, then fast).

| job | pref | first flip held? | first flip, mid-tween | second flip: set built before push | second flip, mid-tween |
| --- | --- | --- | --- | --- | --- |
| j1 | ON | no (not-ready, no build until after the leave) | no mid sample (3 frames in 803 ms) | 390 ms | p30 0 a / 55 tick; p80 47 / 8 |
| j2 | ON | yes (built 3.2 s before) | p30, p50, p80: 47 a / 8 tick | 90 ms | p30 0 / 55; p50, p80 47 / 8 |
| j3 | ON | no | p30 at 968 ms: 47 / 8 (sampled late) | 250 ms | p30 0 / 55; p50, p80 47 / 8 |
| j1 | OFF | yes | p30: 25 a / 30 tick | 248 ms | p30, p80: 25 / 30 |
| j2 | OFF | no | no mid sample | 281 ms | p30, p80: 25 / 30 |
| j3 | OFF | no | p30, p50, p80: 25 / 30 | 90 ms | p30, p50, p80: 25 / 30 |

- The set was held at the first push in 2 of 6 first flips (4 of 6: `not-ready` at 3.7-8.3 s, the first push at 6.9-9.4 s created the tracks itself, build only after the leave).
  The held first flip in j2 (pref ON) was accelerated from p30 (47 / 8); the held first flip in j1 (pref OFF) still ticked 30 tracks, same as fresh pref-OFF flips.
- Pref OFF: 25 accelerated and 30 ticking in all 5 sampled flips (first and second), held or built shortly before the push. The hold does not change the pref-OFF ticking (MEASURED, n = 5 flips in 3 jobs).
- Pref ON: the 8 ticking tracks are the same with and without the hold (47 / 8 steady state).

## Late first commit: per creation, not per page (INFERRED from push 3, small n)
The earlier note (10-2x-geom-webkit-midflip.md) read the quiet second flip (47 a / 0 tick at p50 and p80) and suggested the late first commit is a one-time
per-page cost (first compositing of the flip tree's layers, decode). Push 3 does not support that:
- Pref ON, second flip, in 3 of 3 jobs: the set was built 90-390 ms before the push (the rewarm after the leave) and at p30 (354-707 ms into the flip) every track
  ticked (0 a / 55 tick); at p50 and p80 47 were accelerated. The page had already flipped once and its layers existed, yet a fresh set was committed only
  between about 350 and 520 ms after its creation.
- Pref ON, j2 first flip: the set built 3.2 s earlier was accelerated at p30. So the cost follows the age of the animation objects (creation to first commit
  of the order of 350-500 ms in WKTR; the WKTR frame clock is slow, 3 to 30 frames per 700 ms), not whether the page flipped before.
- Limits: one run, n = 3 per row; the p30 sample is a single time point; WKTR is not iOS Safari. The p30 point cannot place the commit more precisely than 350-520 ms.
A one-time warm-up flip per page would therefore not remove the cost in this reading: the next flip's tracks are new Animation objects and pay their own creation latency.

## Negative part and lesson
- The hold gives what it was built for only where it is held: desktop first take 0-1 ms against 96-650 ms, and in the one held pref-ON first flip no main-thread ticking at p30.
- It costs the rest state: the held flip tree changes the nav box (+8 px on phones, +256 to +414 px at 1280 and above) and A4 fails in 24 of 24 band-engine cells (and 12 of 12 repeat cells).
  It is also held in only 2 of 6 first flips in WKTR (ready too late), falls back on phone bands in the gate, and does not touch the pref-OFF ticking (30 of 55).
- General lesson: a "create once, hold, play per flip" design must hold only things with no layout effect. Holding the tree that carries `.is-flip` moves
  layout, so the rest state is not the rest state. State the rest-equivalence (layout and computed style with the hold equal those without) before building the hold, and
  keep the gate's A4 as the check on it. The probe-side stand-in (a `__fwPrewarm` opt-in flag, uncommitted WIP, stashed) would only have hidden the production default and was not tested.

## Next design (not built; needs a push budget)
1. Hold the tracks without the flip layout. Create the 55 Animations paused or in their before-phase (delay, no fill) on the flip elements without `.is-flip`, so the
   rest layout is the base's and the tracks have no effect at rest. Measure on WKTR whether before-phase animations still reach the compositor (INFERRED: WebKit adds
   accelerated animations with a begin time to the layer; not shown). Lean: `rest_equiv` (with no active phase the computed style and box of every tracked element
   equal those without tracks), `play_from_hold` (a push from a held before-phase set equals the push that creates them: same keyframes, same start time), `held_rewarm`
   (the existing ready, fresh, rewarm rules, keep `held_refused_keeps`). Gate: A4 must show base equal to the rest width.
2. A lead-time rule. Evidence: a set built >= 3 s before the push is accelerated at p30, one built <= 400 ms before ticks at p30. Lean: a hold lead time L >= commit latency
   (350-520 ms in WKTR, to be measured on the phone) before a push may use the set; otherwise create on push as today. Needs the leave-to-push gap data, since the rewarm
   after a leave (1000 ms) is shorter than L in a quick re-flip.
3. Discard: one warm-up flip per page (the late commit is per creation here), and moving the A4 base read (it would hide a real rest-layout change).
Any of these needs the phone's commit latency before the Lean bound is meaningful (not run here).

## Verdict
park. Items: gate A4 on both engines not met (0/12, 0/12); WKTR first-flip mid-tween shown only for the 2 held cases; look report not graded; no dry land (gate fails).
