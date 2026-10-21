---
id: 2026-10-21-linux-webkit
kind: note
title: "Linux WebKit on a free runner: what sets its frame time, and whether the Web Inspector Timeline can be read from it"
status: final
created: 2026-10-21
authors: [agent:measure-engineer]
topics: [measurement, webkit, linux, timeline, frame-time]
---

# Linux WebKit probe (task linux-webkit-probe)

Question: Playwright's headless WebKit on a free `ubuntu-24.04-arm` runner draws frames about 150 ms apart on our page.
What sets that, does Playwright's translation layer matter, can the Web Inspector Timeline be read from it, and is
there a Linux WebKit closer to iOS? One GitHub run answers the first three (run 39629051205, workflow
`linux-webkit-probe`, two VMs, 20 arms, each arm twice). Code: `packages/measure-webkit/src/linux/`; the tables below
are generated from `results/linux-webkit/*.json` (the reduced artifacts of that run) by `cli.mjs table`; the
tests check that this file equals the regeneration.

Tags: MEASURED = a cell of the run above; CONFIRMED = source read at a pinned commit (WK = WebKit/WebKit@56453fdf,
the base of Playwright 1.64.1 / webkit rev 2370; PW = microsoft/playwright@cfe490d, the v1.64.1 tag; files fetched raw
at those shas); INFERRED = reasoned, not shown.

## Setup in one paragraph

Each arm launches a fresh `webkit.launch` (Playwright-core 1.64.1, browser 27.2), loads a page from a local static
server, waits 1 s, starts the Timeline, reads the page's own `requestAnimationFrame` intervals for a 3 s idle window,
then does 10 `mouse.wheel` steps of 400 px, each followed by a wait until `scrollY` is stable for 3 frames (a settled
step; the wait is capped at 4 s), then stops the Timeline. Pages: `blank` (30000 px tall, empty), `paint` (the same, with the body colour changed
every frame, so every frame repaints), `orig` (our original site, the read-only snapshot). Widths 390 and 1280 CSS px,
device pixel ratio 1 and 3 (viewports 390x844 and 1280x800). Switch arms (width 390, dpr 3, on `paint` and `orig`):
`WEBKIT_SKIA_MSAA_SAMPLE_COUNT=0` (msaa0), `WEBKIT_SKIA_ENABLE_CPU_RENDERING=1` (cpu), `LP_NUM_THREADS=1` (lp1, Mesa's
software rasterizer), `WEBKIT_SHOW_FPS=1` (fps). Round A runs every arm, then round B runs every arm again (A/A on one
VM); the second VM is a different machine of the same kind. The runner: 4 vCPU Neoverse-N2, 16 GB, kernel 6.17, Mesa
25.2.8 (`libgl1-mesa-dri`, `libegl-mesa0`, `mesa-libgallium`), no GPU (artifact `machine-vm<N>.txt`).

## Finding 1: the frame time comes from the page's content cost, which grows with dpr at a fixed width, in software GL, not from the headless backend

- MEASURED: an empty page and a page that repaints every frame hold the 60 Hz cadence (rAF p50 16 ms) at 390 and 1280 CSS px
  with dpr 1, and at 390 px with dpr 3 the repaint page costs 19 ms. So the backend, the Playwright driver and the
  Timeline recording (on in every arm) do not by themselves produce 150 ms gaps.
- MEASURED: the cost of a bare repaint grows with device pixels: 0.33 Mpx 16 ms, 1.0 Mpx 16 ms, 3.0 Mpx 19 ms, 9.2 Mpx
  57 ms (`paint` arms, scroll rAF p50, 4 samples each, range 1-2 ms). The `paint` page is the cheapest content
  there is, so ~57 ms is the floor for a full-viewport frame at 3840x2400 on this VM.
- MEASURED: our page is far above that floor: scroll rAF p50 102 ms (width 390, dpr 1), 229 ms (390, dpr 3, range
  228-233 over 4 samples), 49 ms (1280, dpr 1), 173 ms (1280, dpr 3). That is 12 times the repaint page at the
  same pixel count. The Timeline of the whole recording (idle and 10 steps) at 390/3 shows about 380 Layout, 425 style
  recalculation and 700 Paint records (see the tables), so the page's own work per frame is the cost, and at a fixed width it grows with dpr (102 to 229 ms
  from dpr 1 to 3). Across widths the layout differs (390 px gets the mobile layout), so pixels alone do not order the
  cost: 1280/3 (9.2 Mpx) is faster than 390/3 (3.0 Mpx).
- MEASURED (relative effect on `orig`, 390 px, dpr 3, base 229.5 ms; A/A noise of these cells up to 13 %):
  `LP_NUM_THREADS=1` 617 ms (x2.7, far outside noise); `WEBKIT_SKIA_ENABLE_CPU_RENDERING=1` 157.5 ms (-31 %, outside
  noise); `WEBKIT_SKIA_MSAA_SAMPLE_COUNT=0` 182.5 ms (-20 %, at the edge of the noise: A 181, B 202 on vm1);
  `WEBKIT_SHOW_FPS=1` 192.5 ms (-16 %, unexplained: the switch should only count frames; no cause found, so no claim). On
  the `paint` page the same switches move 19 ms to 19-21 ms (cpu +2) and lp1 to 49.5 ms.
- MEASURED: the WebGL renderer string reads "Apple GPU" in every arm (WebKit hides the real name from pages). The string
  is not evidence of hardware. The proof that Mesa's software rasterizer does the work is the effect of
  `LP_NUM_THREADS=1` (a variable only llvmpipe reads): INFERRED from that effect that the GL path is llvmpipe. Mesa
  packages are on the VM (MEASURED, `machine-vm<N>.txt`).
- MEASURED (`WEBKIT_SHOW_FPS`, the compositor's own count in the page console, `fps` arms): the repaint page logs
  49-58 FPS after a warm-up line of 8.4-8.6 (`paint-w390-d3-fps`, round A); our page logs values from 2.8 to 62 (`orig-w390-d3-fps`, vm1 A). The lines have no timestamps and repeat
  (LayerTreeHost.cpp:427-435 posts one per finished frame while the value is set), so they are not attributed to idle or
  scroll. The per-step Composite counts (15-70 per step against 8 rAF frames) show the compositor finishing more frames
  than the main thread renders, so the slow loop is the main-thread rendering update, not the compositor (INFERRED).
- CONFIRMED (WK Tools/wpe/backends/fdo/HeadlessViewBackendFdo.cpp:54, :87-101, :111): the headless view is the libwpe
  fdo backend in SHM mode (`wpe_fdo_initialize_shm`), always visible, and it completes a frame at most every 1/60 s
  (`G_USEC_PER_SEC / 60`, :96): a cap at 60 Hz, which the blank page reaches, not a floor of 150 ms.
- CONFIRMED (WK Source/WebKit/WebProcess/glib/WebProcessGLib.cpp:210-213; Source/WebCore/platform/graphics/skia/
  SkiaPaintingEngine.cpp:68-85): tiles are rastered with Skia on a GL context unless
  `WEBKIT_SKIA_ENABLE_CPU_RENDERING` is set to a value other than "0"; with no GPU the GL context is Mesa's, so the
  GL raster runs on the same 4 CPUs.
- CONFIRMED (WK Source/WebCore/platform/graphics/skia/PlatformDisplaySkia.cpp:67-81, :202-216): the default MSAA
  sample count is 8 on x86 and 4 elsewhere for WPE/GTK, overridden by `WEBKIT_SKIA_MSAA_SAMPLE_COUNT` (0 or 1 = off).
- CONFIRMED (WK Source/WebKit/WebProcess/WebPage/CoordinatedGraphics/ThreadedCompositor.cpp:726-734; Source/WebKit/
  WebProcess/WebPage/CoordinatedGraphics/LayerTreeHost.cpp:431-434): `WEBKIT_SHOW_FPS=<seconds>` sets the FPS
  window and each completed frame may add a console message "FPS: n" to the page. The value in these arms is
  1; the lines are not one per second (ThreadedCompositor.cpp:747-766 sets the value once per interval, and every
  finished frame posts a line while it is set).
- What stays open: the split of the 229 ms between the main thread (layout, style, script) and tile raster is not
  measured here. The CPU-raster arm moves it by 31 % and one raster thread by 170 %, so raster in software is a large share; the
  Timeline cannot separate them (Finding 3).

## Finding 2: Playwright's translation layer is not the cause

- MEASURED: the intervals are read inside the page (rAF callbacks, `performance.now()` deltas), with no protocol message
  between two callbacks; commands are sent only between steps, and the only traffic during a step is the Timeline
  event stream. The blank arm, driven the same way with that stream on, holds 16 ms (Finding 1), and the `mouse.wheel` call returns in 15 ms there (one frame; Playwright waits one rAF
  before it dispatches the wheel on WebKit: PW packages/playwright-core/src/server/webkit/wkInput.ts:155-168, the
  wait at :160). On `orig` at 390/3 the call returns in 107 ms while the frames are 229 ms apart: the call is
  shorter than one frame gap.
- MEASURED earlier (research/notes/2026/10-21-trajectory-probe.md:118): in-page reads cost 0.4 ms on Chromium and
  1 ms on WebKit against frame gaps of 17 and about 150 ms.
- CONFIRMED (PW packages/playwright-core/src/server/webkit/wkConnection.ts:103): `WKSession` is a thin
  JSON message channel to the Web Inspector backend; nothing in it sits between rAF callbacks.

## Finding 3: the Timeline can be read from Linux WebKit, with a narrower event set than on Cocoa

- MEASURED: 80 arm runs (2 VMs x 20 arms x 2 rounds), 0 errors, 0 Timeline errors, 800 of 800 steps delimited by the
  `fw-s<i>` / `fw-e<i>` stamps. MEASURED: 773 of 800 steps settled (`scrollTimedOutSteps`); the 27 that hit the 4 s cap are
  24 in `orig-w390-d3-lp1` (6 of 10 steps in each of the 4 samples) and 3 single steps in `orig-w390-d1` vm1 A,
  `orig-w1280-d1` vm1 A and `orig-w390-d3` vm2 A; the shown per-step table (`orig-w390-d3` vm1) has all 20 settled. The route is Playwright's own page session (`page._connection.toImpl(page).delegate._session`)
  with `Timeline.start {maxCallStackDepth: 1}` and `Timeline.eventRecorded`; no extra WebKit launch option. Event
  types seen: RequestAnimationFrame, FireAnimationFrame, FunctionCall, TimeStamp, Composite, Paint, Layout, InvalidateLayout, ScheduleLayout,
  RecalculateStyles, ScheduleStyleRecalculation, ObserverCallback, LargestContentfulPaint, TimerInstall, TimerFire,
  TimerRemove, CancelAnimationFrame, EventDispatch.
- MEASURED: Paint and Composite exist on WPE. The expected gap did not happen. `RenderingFrame` (the record that wraps one frame)
  never appears.
- CONFIRMED (WK Source/WebCore/inspector/agents/page/PageTimelineAgent.cpp:118-160 and :361-378): the RenderingFrame
  record is only started under `#if PLATFORM(COCOA)`. CONFIRMED (Source/WebCore/page/Page.cpp:2594 and :2608 with
  Source/WebKit/WebProcess/WebPage/CoordinatedGraphics/LayerTreeHost.cpp:424 and :428-434): Composite is wrapped
  from `willStartRenderingUpdateDisplay` to `didCompleteRenderingUpdateDisplay`, which the WPE compositor calls when
  its frame finished (`didRenderFrame`). Both hooks are posted to the main thread from the compositor thread
  (ThreadedCompositor.cpp:579-584, :606-612), so on Linux one Composite record is one finished compositor frame, but its
  start and duration are main-thread drain times (MEASURED: duration p90 0 ms, records arrive in bursts, orig-w390-d3 vm1 A
  raw); count Composite, never time it. The Page.cpp comment itself calls the name inexact, and it is not Cocoa's CA commit.
- CONFIRMED (Source/WebCore/inspector/agents/InspectorTimelineAgent.cpp:102-108, :170-183, :340-348): `start`
  with a call stack depth, and `performance.mark` becomes a TimeStamp record with its own time; the probe stamps zones with
  `performance.mark` and `console.timeStamp`, so each stamp appears twice (the generated table says so).
- MEASURED A/A: record counts of the same arm in the two rounds differ by 0-2 % for the blank and repaint pages and by up to 11 % for
  `orig` at dpr 1 (the frame count itself varies by that much when frames are slow); at 390/3 the totals are
  17894 / 17899 (vm1) and 17462 / 18338 (vm2). The per-step table shows the 10 steps twice (A and B):
  Layout, style and Paint counts per step agree within a few records (for example Paint 99 and 99 in step 0), the
  Composite counts differ more (step 4: 61 and 70). Counts per step are a reading, not a class: this note does not
  claim a deterministic or stable class for any cell (the class policy runs on 3 independent VMs; this run has 2).
- Limit: these are Linux event counts with Linux meanings. They do not predict the iOS record counts one for one, and
  no timing here is a phone's.

## Finding 4: no open-source Linux WebKit is closer to iOS Safari; the options and their cost

- CONFIRMED (raw sources above, PW browser_patches/webkit/pw_run.sh:29-35, webkit.ts:56-61 and :124-125):
  Playwright's headless WebKit is the WPE MiniBrowser with the libwpe fdo backend; the headed build is the GTK
  MiniBrowser. The headless path in this run is therefore the one measured. The GTK build under `xvfb-run` was not run
  (not in the pinned unit).
- CONFIRMED: every Linux WebKit shares WebCore (style, layout, script) with Safari and paints with Skia. iOS uses
  remote layer trees, CoreAnimation and GPU-process raster. At the Playwright base (and WebKitGTK/WPE 2.54.1)
  the compositor also uses Skia (`UseSkiaForComposition`, UnifiedWebPreferences.yaml:9325-9335); older
  releases (WPE 2.48.3, GTK 2.52.6) composite with TextureMapper. WPE and GTK are equally far from iOS only at the same version.
- CONFIRMED (Launchpad / Debian package indexes, 2026-10-21; https://launchpad.net/ubuntu/noble/+source/webkit2gtk and
  https://packages.debian.org/search?keywords=wpewebkit): Ubuntu 24.04 arm64 has WebKitGTK 2.52.6 with
  `webkit2gtk-driver`; WPE WebKit is only in Debian (trixie 2.48.3, sid 2.54.1), where 2.48.3 rasterizes on the CPU
  by default for WPE (WebProcessGLib.cpp:174-185@wpewebkit-2.48.3). These are driven by WebDriver, not Playwright.
- INFERRED: building WebKit from source on 4 cores takes hours; the apt route takes minutes. Neither was run.
- The numbers of Finding 1 are the missing public "frame rate without a GPU" for this stack (no public figure found).
  Choice for the lane: keep Playwright's WPE (nearest WebCore, one env var for CPU raster) and read ratios, not times.

## What this lane can and cannot stand in for

- Can: relative changes in main-thread and raster work of the same page between two builds on the same kind of
  VM (record counts per zone, frame-interval ratios, a switch's effect), with the Timeline's zone stamps;
  checking a change on the engine that Playwright ships; running with no phone and no Simulator.
- Cannot: a phone's GPU. The VM has no GPU; GL is software on 4 vCPU (Neoverse-N2) and the paint cost scales with the
  device pixels of that CPU (a bare repaint is 19 ms at 3 Mpx and 57 ms at 9 Mpx), so absolute frame times
  are the VM's, not an iPhone's. Not iOS's compositor path (Skia and the compositor thread against CoreAnimation and a GPU
  process), no `RenderingFrame`, a different Composite. Not Safari's version of WebCore (the Playwright base is WebKit
  main). Felt smoothness stays a phone measurement.
- Accepted limits of this unit: software GL on the CI VM; one workflow run of 2 VMs (no 3-VM class counts yet);
  the cause of the `fps` arm's 16 % lower frame time is open; the split between main thread and raster is open.

## Tables (generated)

<!-- generated:linux-webkit-tables begin -->
Generated by `node packages/measure-webkit/src/linux/cli.mjs table` from `results/linux-webkit/*.json`: 2 VM file(s) of run(s) 39629051205; each arm ran twice per VM (A, B). Do not edit by hand.

### Frame intervals (ms between rAF callbacks)

Median over all samples (VMs x rounds); the p50 columns add (min-max) of the per-sample p50.

| arm | samples | idle rAF p50 | idle rAF p90 | scroll rAF p50 | scroll rAF p90 | scroll rAF max | wheel call p50 (ms) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `blank-w390-d1` | 4 | 16 (16-16) | 16 | 16 (16-16) | 16 | 17 | 15 |
| `blank-w390-d3` | 4 | 16 (16-16) | 16.5 | 16 (16-16) | 17 | 20.5 | 15 |
| `blank-w1280-d1` | 4 | 16 (16-16) | 16 | 16 (16-16) | 16 | 17 | 15 |
| `blank-w1280-d3` | 4 | 16 (16-16) | 16.5 | 17 (17-17) | 52 | 83.5 | 15 |
| `paint-w390-d1` | 4 | 16 (16-16) | 16 | 16 (16-16) | 16.5 | 17.5 | 15 |
| `paint-w390-d3` | 4 | 17.5 (17-18) | 19 | 19 (19-20) | 21.5 | 25 | 19 |
| `paint-w1280-d1` | 4 | 16 (16-16) | 16 | 16 (16-16) | 16 | 17 | 15 |
| `paint-w1280-d3` | 4 | 56 (55-57) | 58 | 57.5 (57-59) | 64 | 74 | 58 |
| `orig-w390-d1` | 4 | 21.5 (16-62) | 122 | 102 (97-106) | 426 | 1899.5 | 61.5 |
| `orig-w390-d3` | 4 | 21 (17-25) | 64 | 229.5 (228-233) | 738.5 | 1938.5 | 107 |
| `orig-w1280-d1` | 4 | 32 (18-32) | 36 | 49 (43-52) | 189 | 1087.5 | 17.5 |
| `orig-w1280-d3` | 4 | 132 (91-2520) | 1242 | 173 (166-176) | 655.5 | 1205.5 | 119 |
| `paint-w390-d3-msaa0` | 4 | 17.5 (17-18) | 19.5 | 19 (19-20) | 21 | 26 | 18.5 |
| `orig-w390-d3-msaa0` | 4 | 17.5 (17-18) | 48.5 | 182.5 (181-202) | 684 | 1446.5 | 97.5 |
| `paint-w390-d3-cpu` | 4 | 19.5 (19-20) | 21.5 | 21 (21-22) | 24 | 26.5 | 22 |
| `orig-w390-d3-cpu` | 4 | 17 (17-17) | 46.5 | 157.5 (154-175) | 375.5 | 1025.5 | 84 |
| `paint-w390-d3-lp1` | 4 | 47 (47-47) | 48 | 49.5 (49-50) | 53 | 64 | 48 |
| `orig-w390-d3-lp1` | 4 | 77.5 (70-84) | 156.5 | 617 (610-622) | 2061.5 | 4114 | 334 |
| `paint-w390-d3-fps` | 4 | 17.5 (17-18) | 19 | 19.5 (19-20) | 21.5 | 25 | 18 |
| `orig-w390-d3-fps` | 4 | 17 (16-17) | 50.5 | 192.5 (188-203) | 716.5 | 1354.5 | 76.5 |

### A/A: the two rounds of each arm on the same VM

| arm | vm1 scroll p50 A / B | vm2 scroll p50 A / B | vm1 Timeline records A / B | vm2 Timeline records A / B | largest abs(A-B) / mean (scroll p50) |
| --- | --- | --- | --- | --- | --- |
| `blank-w390-d1` | 16 / 16 | 16 / 16 | 1904 / 1904 | 1904 / 1904 | 0 % |
| `blank-w390-d3` | 16 / 16 | 16 / 16 | 1905 / 1912 | 1912 / 1905 | 0 % |
| `blank-w1280-d1` | 16 / 16 | 16 / 16 | 1906 / 1906 | 1909 / 1909 | 0 % |
| `blank-w1280-d3` | 17 / 17 | 17 / 17 | 1403 / 1410 | 1396 / 1403 | 0 % |
| `paint-w390-d1` | 16 / 16 | 16 / 16 | 3631 / 3631 | 3631 / 3631 | 0 % |
| `paint-w390-d3` | 19 / 19 | 19 / 20 | 3321 / 3309 | 3278 / 3234 | 5.1 % |
| `paint-w1280-d1` | 16 / 16 | 16 / 16 | 3631 / 3631 | 3631 / 3631 | 0 % |
| `paint-w1280-d3` | 57 / 57 | 58 / 59 | 1584 / 1592 | 1584 / 1576 | 1.7 % |
| `orig-w390-d1` | 106 / 97 | 103 / 101 | 19358 / 17329 | 18221 / 17043 | 8.9 % |
| `orig-w390-d3` | 228 / 228 | 231 / 233 | 17894 / 17899 | 17462 / 18338 | 0.9 % |
| `orig-w1280-d1` | 49 / 43 | 49 / 52 | 11598 / 10964 | 9901 / 9168 | 13 % |
| `orig-w1280-d3` | 172 / 166 | 176 / 174 | 8327 / 8136 | 7894 / 7943 | 3.6 % |
| `paint-w390-d3-msaa0` | 19 / 19 | 19 / 20 | 3318 / 3309 | 3185 / 3220 | 5.1 % |
| `orig-w390-d3-msaa0` | 181 / 202 | 184 / 181 | 17907 / 18265 | 17324 / 17940 | 11 % |
| `paint-w390-d3-cpu` | 21 / 22 | 21 / 21 | 3069 / 3036 | 3023 / 2989 | 4.7 % |
| `orig-w390-d3-cpu` | 175 / 154 | 160 / 155 | 17371 / 17232 | 17447 / 16622 | 12.8 % |
| `paint-w390-d3-lp1` | 49 / 49 | 50 / 50 | 1738 / 1730 | 1719 / 1708 | 0 % |
| `orig-w390-d3-lp1` | 610 / 618 | 622 / 616 | 21539 / 21735 | 20561 / 21016 | 1.3 % |
| `paint-w390-d3-fps` | 19 / 19 | 20 / 20 | 3328 / 3290 | 3210 / 3217 | 0 % |
| `orig-w390-d3-fps` | 203 / 195 | 188 / 190 | 18351 / 17389 | 18156 / 18255 | 4 % |

### Timeline records over the whole recording (3 s idle and 10 steps; median over samples)

Records are counted as nested (a FunctionCall inside a FireAnimationFrame is two records). Each zone stamp is emitted twice (`performance.mark` and `console.timeStamp`), so TimeStamp = 2 x stamps.

| arm | records | Layout | RecalculateStyles | FunctionCall | FireAnimationFrame | Paint | Composite | TimeStamp | steps delimited | steps settled |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `blank-w390-d1` | 1904 | 0 | 0 | 567 | 567 | 28 | 130 | 44 | 10 / 10 | 10 / 10 |
| `blank-w390-d3` | 1909 | 0 | 0 | 566 | 566 | 36 | 130 | 44 | 10 / 10 | 10 / 10 |
| `blank-w1280-d1` | 1908 | 0 | 0 | 568 | 568 | 30 | 130 | 44 | 10 / 10 | 10 / 10 |
| `blank-w1280-d3` | 1403 | 0 | 0 | 421 | 421 | 38 | 57 | 44 | 10 / 10 | 10 / 10 |
| `paint-w390-d1` | 3631 | 0 | 377 | 567 | 567 | 754 | 377 | 44 | 10 / 10 | 10 / 10 |
| `paint-w390-d3` | 3294 | 0 | 342 | 513 | 513 | 684 | 342 | 44 | 10 / 10 | 10 / 10 |
| `paint-w1280-d1` | 3631 | 0 | 377 | 567 | 567 | 754 | 377 | 44 | 10 / 10 | 10 / 10 |
| `paint-w1280-d3` | 1584 | 0 | 155 | 255 | 255 | 310 | 154 | 44 | 10 / 10 | 10 / 10 |
| `orig-w390-d1` | 17775 | 336 | 399 | 888 | 540 | 782 | 859 | 44 | 10 / 10 | 10 / 10 |
| `orig-w390-d3` | 17897 | 384 | 425 | 942 | 532 | 696 | 544 | 44 | 10 / 10 | 10 / 10 |
| `orig-w1280-d1` | 10433 | 258 | 322 | 803 | 505 | 609 | 220 | 44 | 10 / 10 | 10 / 10 |
| `orig-w1280-d3` | 8040 | 205 | 285 | 724 | 374 | 487 | 84 | 44 | 10 / 10 | 10 / 10 |
| `paint-w390-d3-msaa0` | 3265 | 0 | 339 | 509 | 509 | 678 | 338 | 44 | 10 / 10 | 10 / 10 |
| `orig-w390-d3-msaa0` | 17924 | 396 | 442 | 978 | 582 | 706 | 578 | 44 | 10 / 10 | 10 / 10 |
| `paint-w390-d3-cpu` | 3030 | 0 | 313 | 474 | 474 | 626 | 312 | 44 | 10 / 10 | 10 / 10 |
| `orig-w390-d3-cpu` | 17302 | 381 | 429 | 923 | 579 | 801 | 719 | 44 | 10 / 10 | 10 / 10 |
| `paint-w390-d3-lp1` | 1725 | 0 | 171 | 276 | 276 | 341 | 170 | 44 | 10 / 10 | 10 / 10 |
| `orig-w390-d3-lp1` | 21278 | 376 | 410 | 1061 | 424 | 614 | 304 | 44 | 10 / 10 | 4 / 10 |
| `paint-w390-d3-fps` | 3254 | 0 | 338 | 507 | 507 | 676 | 337 | 44 | 10 / 10 | 10 / 10 |
| `orig-w390-d3-fps` | 18206 | 395 | 436 | 972 | 580 | 687 | 576 | 44 | 10 / 10 | 10 / 10 |

### Timeline per settled step, A and B

Arm `orig-w390-d3`, vm1, run 39629051205

| step | A window ms | A frames | A Layout | A Styles | A FnCall | A Paint | A Composite | B window ms | B frames | B Layout | B Styles | B FnCall | B Paint | B Composite |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 1407.2 | 8 | 16 | 17 | 54 | 99 | 21 | 1356.2 | 8 | 15 | 18 | 53 | 99 | 21 |
| 1 | 5256 | 8 | 30 | 34 | 83 | 67 | 22 | 3722.1 | 8 | 23 | 28 | 74 | 58 | 21 |
| 2 | 2262.1 | 8 | 15 | 23 | 62 | 34 | 15 | 2429.2 | 7 | 15 | 21 | 49 | 52 | 18 |
| 3 | 3204.1 | 8 | 28 | 32 | 72 | 48 | 39 | 3089 | 8 | 26 | 31 | 71 | 53 | 40 |
| 4 | 2312.4 | 8 | 33 | 36 | 85 | 60 | 61 | 2266.2 | 8 | 38 | 39 | 85 | 66 | 70 |
| 5 | 3067.2 | 9 | 36 | 31 | 83 | 72 | 62 | 2778.2 | 8 | 35 | 33 | 78 | 66 | 58 |
| 6 | 2054.2 | 8 | 38 | 38 | 77 | 40 | 65 | 2019 | 8 | 36 | 40 | 78 | 38 | 70 |
| 7 | 2250.5 | 8 | 38 | 41 | 95 | 65 | 51 | 2153.4 | 8 | 45 | 47 | 98 | 69 | 56 |
| 8 | 3563.8 | 8 | 29 | 38 | 97 | 57 | 17 | 3130.3 | 8 | 29 | 35 | 88 | 54 | 19 |
| 9 | 2486.3 | 8 | 34 | 39 | 91 | 40 | 15 | 2428.2 | 8 | 30 | 35 | 92 | 41 | 15 |

### Renderer string (the page sees only WebKit's masked name) and WEBKIT_SHOW_FPS

| arm | WebGL renderer string | FPS lines (first of first sample) |
| --- | --- | --- |
| `blank-w390-d1` | Apple GPU | none |
| `orig-w390-d3` | Apple GPU | none |
| `paint-w390-d3-fps` | Apple GPU | 8 lines; console: FPS: 0.0015530309 ; console: FPS: 8.573478 |
| `orig-w390-d3-fps` | Apple GPU | 22 lines; console: FPS: 0.0015340025 ; console: FPS: 35.34318 |

### Failed runs and Timeline errors

none
<!-- generated:linux-webkit-tables end -->
