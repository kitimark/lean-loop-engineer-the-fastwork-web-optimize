---
id: 2026-10-2x-toolbar-throttle
kind: note
title: "Toolbar-collapse throttle probe: real touches on the iOS 27 Simulator reproduce the hero exit's 5-6 frame still runs (16 per 1000 exit frames) and the scroll-driven-animation lift removes them (0 of 9,740 frames), 3 of 3 CI jobs"
status: review
created: 2026-10-22
topics: [lag, webkit, ios-toolbar, scroll-driven, hero.exit, engine.scroll, simulator, xcuitest, measure, phone]
---

# Does a scroll-driven animation lift Safari's toolbar-collapse scroll throttle?

Task `toolbar-throttle-probe`. It tests one claim of `10-22-smooth-candidates.md`: while Mobile Safari's toolbar collapses
under a finger, WebKit sends the web process one visible-rect update per 100 ms, and a page with a scroll-driven
animation that the compositor cannot run alone lifts that throttle. WebKit cites `@862f17d`.

## Answer

- **The flag lifts the throttle in the Simulator (MEASURED, 3 of 3 CI jobs).** Real XCUITest touches on Mobile Safari
  in the pinned iOS 27.0 Simulator, hero exit range, same viewport: the default build has 163 still runs of exactly 5 or
  6 frames in 10,104 exit frames (16.1 per 1000), the build with `?fw=engine.scroll:throttle-lift` has 0 in 9,740.
  The verdict is `lifted` in every job and pooled (Lean `Fw.Device.StillRuns.verdict`, run `39667548341`).
- **The unmodified original shows the same stepping (MEASURED).** 53 band runs in 5,290 exit frames (10 per 1000; one job
  is lower, 3.9, with one of its two passes lost). So the stepping is Safari's, not the rewrite's.
- **The mechanism is CONFIRMED by source.** `Source/WebKit/UIProcess/API/ios/WKWebViewIOS.mm:3256-3268@862f17d`: while
  `_isChangingObscuredInsetsInteractively` and the page has no main-thread scroll-driven animation, visible-content-rect
  updates wait 100 ms "to save power". `Source/WebKit/WebProcess/WebPage/Cocoa/WebPageCocoa.mm:2357@862f17d` sets
  `hasMainThreadScrollDrivenAnimations = document->hasProgressBasedScrollDrivenAnimation()`, and
  `Source/WebCore/animation/AnimationTimelinesController.cpp:267-279@862f17d` makes it true when a progress-based timeline
  has an animation whose keyframe effect is not completely accelerated.
- **Limit (INFERRED):** the Simulator runs the same WebKit UI-process code but has no phone GPU or power state. That the
  phone behaves like the Simulator, and that the user feels this stepping as lag, is not shown by the count. The user's felt phone pass
  (below) agrees with the Simulator. The flag is a diagnostic: never in a preset; its shippable form is `engine.scroll:unthrottle` (note `10-2x-throttle-lift-ship.md`).

## What was built

| Piece | Where | Check |
|---|---|---|
| Still-run count and verdict | `lean/Fw/Device/StillRuns.lean` (runs, `bandRuns` 5-6, `shortRuns` 1-9, `exitFrames`, `throttleK`, `Verdict`; one theorem per verdict branch) | `lake build`; golden `packages/contracts/golden/device/stillruns.jsonl` (40 cases) |
| TS twin of the count | `packages/measure-webkit/src/throttle/stillruns.mjs` | `test/throttle-stillruns.test.mjs` replays the golden |
| Diagnostic flag | `apps/site/src/parts/engine.scroll/part.json` variant `throttle-lift` (ablation, `diagnostic: true`), `throttle.ts`, `index.tsx:16` | `throttle.test.ts`; not in any preset |
| Real-touch driver | `packages/measure-webkit/src/throttle/driver/` (XCUITest, built with xcodegen), `driver.mjs` | CI runs below |
| Recorder and table | `recorder.mjs`, `probe.mjs`, `report.mjs`, `cli.mjs` | `test/throttle-report.test.mjs` |
| CI workflow | `.github/workflows/toolbar-throttle.yml` (3 jobs, 3 arms x 2 rounds, order rotated per round) | Lean rows in `Fw.Ci.Trigger`, `Steps`, `Overflow`, `Pool.Caps` |

The flag adds a fixed invisible element with `animation-timeline: scroll(root block)` that animates a registered custom
property (`@property --fw-tl`) with `animation-duration: auto`. A custom property is not a compositor property, so the
effect is not completely accelerated, which is the condition in `AnimationTimelinesController.cpp`. The element is
invisible and fixed, so it draws nothing (INFERRED from the CSS; no pixel comparison was made).

The count: a *still run* is a maximal run of consecutive frames with the same `scrollY`, inside the hero exit range
(value strictly between 0 and 1) and between two moving frames. A band run lasts 5 or 6 frames. At 60 Hz, 100 ms is
`throttleK 1667 = 5` frames (theorem `throttleK_60hz`), and every frame time from 1429 to 1999 (hundredths of a ms, 14.29 to 19.99 ms; theorem throttleK_mem_band: 1429 <= d < 2000) gives 5 or 6
(`throttleK_mem_band`). The frame time in every CI pass is a median of 17.0 ms (job 1, checked per pass).

## Table (MEASURED)

Run `39667548341`, commit `525ac1c0`, jobs sim 1 to 3 (separate macOS 27 VMs, 3 vCPU), 2 rounds x 3 arms per job, 4
up-and-down drag cycles per pass (360 pt at 120 pt/s, 600 ms holds). Source: the job `toolbar-throttle-table` artifact,
rebuilt from the three job files with `cli.mjs report`.

| job | arm | passes (usable) | exit frames | band runs (5-6 frames) | per 1000 exit frames | runs of 1-9 frames | toolbar moved |
|---|---|---|---|---|---|---|---|
| 1 | rewrite | 2 (2) | 3265 | 49 | 15.0 | 432 | 2 |
| 1 | lift | 2 (2) | 3316 | 0 | 0 | 396 | 2 |
| 1 | original | 2 (2) | 2029 | 24 | 11.8 | 278 | 2 |
| 2 | rewrite | 2 (2) | 3382 | 58 | 17.1 | 456 | 2 |
| 2 | lift | 2 (2) | 3255 | 0 | 0 | 492 | 2 |
| 2 | original | 2 (2) | 1984 | 24 | 12.1 | 263 | 2 |
| 3 | rewrite | 2 (2) | 3457 | 56 | 16.2 | 436 | 2 |
| 3 | lift | 2 (2) | 3169 | 0 | 0 | 383 | 2 |
| 3 | original | 2 (1) | 1277 | 5 | 3.9 | 85 | 1 |
| all | rewrite | 6 (6) | 10104 | 163 | 16.1 | 1324 | 6 |
| all | lift | 6 (6) | 9740 | 0 | 0 | 1271 | 6 |
| all | original | 6 (5) | 5290 | 53 | 10.0 | 626 | 5 |

"Toolbar moved" counts passes where the visual viewport grew by 40 pt (775 to 815), so the toolbar really collapsed;
it is the same pair the phone passes showed. One original pass was excluded (touch driver timed out, retry failed).

Two earlier runs on the same page and flag read as failed in `fw ci state`; they are context, not pooled with the table:

- `39659502492` failed: job 3 had no rewrite pass (the first measured page was lost); jobs 1 and 2 gave rewrite 17.4 per 1000
  (lift 0 of 9,904 frames, original 10.6).
- `39652336316` failed: jobs 1 and 3 got no Safari tab (the driver build starved the Simulator); job 2 alone gave rewrite
  15.7, lift 0, original 16.0.

Both point the same way as the table.

What the table does not say: the count of runs of 1-9 frames is the same with and without the flag (1,271 vs 1,324).
The flag removes the 100 ms band, not every short pause. Whether the exit then looks smoother is the phone question.

## Harness facts learned on the runner (MEASURED)

- Building the XCUITest bundle next to the booted Simulator starved Safari on the 3-vCPU runner (jobs 1 and 3 of run
  `39652336316` got no tab for minutes). The build now runs before the Simulator boots, with a generic Simulator
  destination (about 75-90 s).
- The first page of a job was lost in 4 of 6 early jobs: the first `openurl` is dropped and asked again, and the first
  XCUITest launch relaunches Safari, so the page reloads after the recorder started. One unrecorded warm-up session
  (load plus one touch cycle) removes this; a pass with a lost page or hung touches is retried once.
- Touches take 60-185 s per pass on the runner (about 50 s on a Mac). The driver output goes to a file, so the harness
  logs a line every 30 s or the 300 s stall watchdog kills the job.
- The VM load average reads 400-770 during the passes (the Simulator, not the probe); counts do not depend on timing
  waits, only on frame times of about 17 ms.

## Phone pass (user, 2026-10-24, felt, one person, preview)

The user opened the production build on the real iPhone with `?fw=engine.scroll:throttle-lift` and scrolled through the
hero exit. Verbatim: "looks the same and hero-exit is a lot of improve, no laggy on hero exit".

- **What it shows (felt, one person, one preview session):** the page looks the same with the flag, and the hero-exit lag
  the user felt without it is gone. This matches the Simulator count (163 band runs to 0).
- **What it does not show:** no recorded `scrollY` series from the phone, so no still-run count on the device; one
  person; no blind A/B. A recorded phone session is a separate lead step (`docs/team/tools/device-replay.md`).
- **Consequence:** the shippable form is `engine.scroll:unthrottle` (task `throttle-lift-ship`, note
  `10-2x-throttle-lift-ship.md`); `throttle-lift` stays the diagnostic. The earlier line "If the flag helps on the phone,
  the shipped candidate is the threaded scroll-driven exit" is superseded: the flag helped.

## TS stand-ins (not proved)

`report.mjs` (which passes count: touch exit code, hero value found, travel, enough frames; the per-job sums) and
`recorder.mjs` (page-side frame recorder) are reductions and glue not checked against a Lean golden. `stillruns.mjs` is
golden-checked. The CSS text of `throttleLiftCss()` is not Lean-derived. The earlier `rec-1..4` raw phone records were
not available; the committed goldens of `stillruns.jsonl` are synthetic stair patterns, not device data.
