---
id: nav-scroll-hide
kind: finding
title: "The nav hides over the people section in the original; the port never did, now it does"
status: draft
created: 2026-10-19
inputs: [apps/site/src/parts/nav/, packages/visual-diff/src/navscroll.mjs, docs/team/handoffs/dead-selectors.md]
---

# Nav hide over the people section: original vs port

Question: scrolling through the people section on desktop, the header moves up and disappears. Does the port do the same?

Answer (MEASURED, CI): before the fix the port never hid the nav at any desktop width. One cause: the nav's default selectors were
the original's class names, which the port DOM does not have. After wiring them to the port's hooks the nav hides and shows over
the people section at 861, 1280, 1440 and 1920 px in Chromium and WebKit, with the same class flip, the same CSS transition and
the same end states as the original (7 runs). It does not hide at 860 px in either arm. Differences remain and each is listed
below with its cause or "cause unknown": section layout 1 to 12 px apart in Chromium (moves the edges by 1 px, and by one step at
1920), the Chromium transform starts 0 to 3 frames after the class flip and the port waits longer on 42 of 111 edge pairs
(shorter on 12), and a WebKit race after a programmatic jump that leaves either arm's nav in the wrong state for up to 700 ms.

## How each side decides (CONFIRMED, source)

| | original | port |
|---|---|---|
| stuck test | sticky item is `position: sticky`, `itemTop <= cssTop + 1`, `sectionBottom > itemBottom + 1` (2.DyWL8TcE.js N2:12921-12935) | `nav/logic.ts:46-49`, same terms |
| direction | none, the test uses geometry only | none |
| hide class | `is-scroll-hidden` and `is-profile-sticky-hidden` when stuck and not morphing (N2:13224-13231) | `nav/logic.ts:62-64`, `:94` |
| hide CSS | visibility hidden, opacity 0, `translate(-50%) translateY(calc(-100% - 24px))`; opacity .28 s, transform .32 s `cubic-bezier(.16,1,.3,1)`, visibility 0 s after .32 s | `nav/nav.module.css:63-76`, same values (computed transition equal in all 10 arm/width pairs of run 39257593393) |
| sticky item | `.start-selling-profile-sticky`, top 48 px, width >= 861 and reduced motion off | `[data-fw="people-sticky"]`, `people.deck/deck.module.css:779-790`, same media |
| breakpoint | 861 px | 861 px (w860 never hides in either arm) |

The original file is minified into one line; N2 line numbers are the ones `nav/logic.ts` already cites.

## The defect (CONFIRMED, run 39250254933)

`nav/index.tsx` defaulted `stickySelector` to `.start-selling-profile-sticky` and `sectionSelector` to `#profile-showcase,
.start-selling-profile`. The port renders neither class, so `measureSticky` returned "not present" and `stuck` was always false.
Footprint extraction already listed both as dead selectors; `dead-selectors.md` filed it as a follow-up.

Baseline (port unfixed), both engines, all four sticky widths: 158 (861, 1280), 177 (1440) and 212-213 (1920) of the steps differ
between arms in each direction; the port has no `is-scroll-hidden` anywhere; the nav stays at top 16 while the original goes to -72
(translate -88 plus the base 16).

## The fix (commit b5bbbd3f)

`nav/index.tsx:66-67` now default to `PROFILE_STICKY_SELECTOR` and `PROFILE_SECTION_SELECTOR` (`nav.hitTest/probe.ts:37-38`), the
hooks nav.hitTest already used. Not a decision change, so no new Lean rule. Checks: a liveness test pins the defaults
(`pain.notes/liveness.test.ts`); `part-footprint --write` moved 70 line numbers and dropped the two dead-selector rows and the
unresolved nav rect; `FootprintRows.lean` and `footprint-diff.gen.json` regenerated, `lake build` 536 jobs and
`ContractsGolden --check` pass.

## Method (TS stand-in: analysis in `navscroll-analyze.mjs`, no Lean golden)

Playwright on the CI image (Chromium 156.0.8078.4 and WebKit), widths 860, 861, 1280x800, 1440x900, 1920x1080. Both arms are served
by the visual-diff overlay server, concurrently in one browser; the original from `snapshot/site`. Per arm: a warm-up scroll over the
page (content-visibility sections otherwise shift the layout by ~48 px mid-run), then scroll from one viewport above the section to
half a viewport past its end in 16 px steps with 3 native rAF per step, down then up, per frame class list, computed transform,
opacity, visibility, header rect, sticky rect. Positions are matched on the grid value u (distance from the section top). Then held
positions every half viewport (700 ms; since run 39257593393 also the flag at 50, 250 and 500 ms), one captured transition per
distinct edge (rAF frames against `getAnimations()` timing and the browser's own easing), and a real mouse-wheel pass (100 px every
60 ms). Since run 39264165879 a captured transition also logs, in execution order, the scroll events, the nav's class mutations, the
transitionrun/transitionstart events and every frame sample, and per frame the start time and pending flag of each running
transition. Never any animation seek. The `navscroll` job runs only on a dispatch with `-f navscroll=true`.

## Runs (MEASURED)

Rule: every completed run of workflow visual-diff on `ci/nav-scroll-hide-check` whose navscroll job ran on code with the selector
fix. The nav, people.deck and scroll-engine sources are identical in all of them to the final commit except the Nav docstring
(`git diff b5bbbd3f HEAD` over `apps/site/src` touches only hero.countdown, which neither arm's nav reads, and the docstring).
Excluded by that rule: the baseline 39250254933 (before the fix; used only for the defect section). Nothing else is excluded.

| run | commit | trigger | probe version | engines |
|---|---|---|---|---|
| 39251940538 | b5bbbd3f | push | v1 | both |
| 39253432942 | b5bbbd3f | dispatch | v1 | both |
| 39253457408 | b5bbbd3f | dispatch | v1 | both |
| 39257593393 | 3be14b42 | push | v2: held flag at 50/250/500 ms | both |
| 39257616351 | 3be14b42 | dispatch | v2 | both |
| 39257621940 | 3be14b42 | dispatch | v2 | both |
| 39264165879 | 1493b3ce | dispatch | v3: event log, start/pending state | both |

That is 7 Chromium and 7 WebKit runs, each engine on its own job. The cross-run tables, one row per run and width, are in
`research/notes/2026/10-19-nav-scroll-hide-runs.md` (generated: `node packages/visual-diff/src/cli.mjs nav-scroll-report --in <dirs>
--summary`); CI artifacts expire after 14 days.

## Results (MEASURED, 7 runs per engine)

Per width and engine, port minus original; ranges over the 7 runs:

| engine | width | hidden flag differs (steps, down/up) | down onset / offset, live u | up onset / offset | wheel edge diff max | captured edges with other animations |
|---|---|---|---|---|---|---|
| chromium | 860 | never hidden in either arm | | | | |
| chromium | 861 | 0/0 | -1..0 / -1..0 | -1..0 / -1..0 | 100 (6 of 7 runs <= 2) | 0 |
| chromium | 1280 | 0/0 | -1 / -1 | -1 / -1 | 5 | 0 |
| chromium | 1440 | 0/0 | -1 / -1 | -1 / -1 | 4 | 0 |
| chromium | 1920 | 1/1 in 7 of 7 | -4..-1 / +12..+15 | +12..+15 / -4..-1 | 6 | 0 |
| webkit | 860 | never hidden in either arm | | | | |
| webkit | 861 | 0/0 | 0 / 0 | 0 / 0 | 57 | 0 |
| webkit | 1280 | 0/0 | 0 / 0 | 0 / 0 | 99 | 7 |
| webkit | 1440 | 0/0 | 0 / 0 | 0 / 0 | 2 | 15 |
| webkit | 1920 | 0/0 | 0 / 0 | 0 / 0 | 100 | 17 |

- The wheel pass moves 100 px per 60 ms, so a wheel edge is known to one 100 px tick; every difference above is within one tick.
- Edges are the live u of the first frame that changes, so "-1" is the port's edge 1 px earlier. The Chromium 1920 offset sits 12 to 15 px
  later in the port: one 16 px step (difference 1 below).
- Captured transitions: Chromium 0 of 111 pairs differ in their animation list (opacity .28 s, transform .32 s
  `cubic-bezier(.16,1,.3,1)`, visibility .32 s delay); the end states are translate -88, opacity 0, hidden (on) and 0, 1, visible (off).
  WebKit lists differ in 39 captures because the 3 to 7 sampled frames sometimes miss the opacity animation (it ended before the first
  sample); the computed transition is equal. Distance of sampled frames from the browser's own easing, measured from the animation's
  start time: Chromium <= 0.16 px in both arms; WebKit <= 2.6 px.
- Capture misses (an edge whose transition was not caught in one arm, so it is not compared): Chromium 39257621940 w1440 down:on, port
  arm (the class never flips in the 700 ms record; the sweep found the edge in both arms); WebKit 39264165879 w1920 down:off, original
  arm. No other misses.

## Differences and their causes

1. Chromium section layout (cause of the 1 px edge shifts and the 1920 step). The section is taller in the port than in the original
   in Chromium: 1.0 to 2.7 px at 861, 2.5 to 5.3 at 1280, 2.9 to 4.8 at 1440, 2.3 to 11.6 at 1920 (7 runs, recorded geometry); in WebKit
   -0.7 to 0.2 px. The port's height is stable across runs (4219.4 px at 1920); the original's varies by up to 9 px between runs
   (cause unknown). In run 39264165879 the port's section top is 0.4 to 1.5 px above the original's at 861 to 1920, which is the 1 px
   edge shift at 1280 and 1440. The stuck test (`nav/logic.ts:46-49`, as the original's) needs `sectionBottom > itemBottom + 1`;
   at 1920 in Chromium the original's section bottom was 868.19 px against the item bottom 868 at u=3304 (round-0 run), so the test
   is false there and the port's 869.19 makes it true: one 16 px step differs each way, and the off edge is 12 to 15 px apart
   (MEASURED in every run: at grid u 3304 the port's secBottom - stickyBottom is 1.19 px (hidden), the original's
   0.0-0.19 px (visible); the 16 px grid quantises a 2-12 px layout delta into one step). Rule equal, layout different; the visual gate owns the layout. Why Chromium
   lays the port out taller: not examined here (cause unknown).
2. Chromium transform start lag. The class flips on the same frame in both arms (frame 2, 16 of 16 edges in run 39264165879; flip
   frame equal in every run). The transform then starts moving 0 to 3 frames after the flip, in either arm. Mechanism (CONFIRMED,
   run 39264165879 and source): the transform transition exists from the flip frame but has no start time ("pending") for exactly
   as many frames as the lag (32 of 32 records: pending frames = move frame - flip frame). Chromium holds a transition whose
   transform runs on the compositor in `waiting_for_compositor_animation_start_` until the compositor reports its start time;
   a main-thread transition gets its start time at once (`pending_animations.cc` `PendingAnimations::Update` :62-170,
   `NotifyCompositorAnimationStarted` :203-236 @ chromium f842f52). The events before it are identical in both arms
   (scroll, class change, transitionrun, transitionstart, then frames), so the page-side change is the same. The lag is not the
   same: pooled over 111 edge pairs the port's lag is longer on 42, shorter on 12, equal on 57; mean lag original 0.81 frames,
   port 1.12; by edge original/port: down:on 1.26/1.52, down:off 0.86/1.50, up:on 0.11/0.04, up:off 1.04/1.43; maximum 2 original,
   3 port (w1280 down:off). It repeats on the same edge across runs (for example w1280 up:off: original always 1, port 2 in 6 of 7
   runs), so it is not sampling noise alone. Why the compositor start is later in the port: cause unknown. Not tested:
   compositor activation time per arm (needs a Chromium trace). The frame cadence of headless Chromium on the CI machine is uneven
   (gaps of up to 150 ms between rAF frames, both arms run at once), so a lag is counted in those frames, not in display frames; the
   animation itself, once started, follows the same curve in both arms. WebKit shows no lag (0 in 111 of 111 pairs), but its
   3 to 7 frames per transition are 140 to 340 ms apart, so a start lag under one gap cannot be seen there.
3. Held positions after a programmatic jump, WebKit (and once Chromium): either arm, 1 to 3 widths per run, cause unknown
   (CONFIRMED bidirectional). The positions are the first held one inside the stuck zone (u asked 0: 12 of 15 cases; u 540 twice,
   u 400 once), reached by a jump of a few hundred px; some arm's nav is in the wrong state at the end of the 700 ms hold. Over the 7 WebKit runs, 15 positions
   differ at the end: 13 with the original hidden and the port visible, 2 with the original visible and the port hidden (run
   39257621940, w1280: u 0 the port hides only after 500 ms, and u 400 where the original stays visible through the end while the
   port is hidden from 50 ms). Chromium: 1 position in 7 runs (39253457408 w1920 u 0, original hidden, port visible). Time series
   (runs from 39257593393): the original is visible at 50 ms and hidden at 250 or 500 ms in some, visible throughout in others; the
   port likewise. No cause is established and the earlier mechanism guess (lazily mounted sections requesting frames) is withdrawn:
   it predicted the port as the only late arm. The impact on a user is unknown for the same reason; gradual scrolling and the wheel
   never show it. Follow-up: hold 2 s per position and log scroll, resize and rAF calls per arm.
4. WebKit frame counts and `getAnimations()` lists differ between arms in captures (3 to 7 frames; the opacity animation can end
   before the first sample). Computed transition equal in all captures; capture timing.

## Also found

- The overlay server of visual-diff served `.css` and `.js` as `application/octet-stream`. The browser then ignored the stylesheets
  and did not run the module, so the port arm was unstyled and unhydrated (sticky `static`, 0 CSS rules). Fixed in
  `visual-diff/src/serve.mjs` (`DOC_TYPES`, test). Follow-up, not done here: earlier visual-diff lane results for the rewrite arm
  may have been taken from an unstyled page; check one old CI artifact for "Refused to apply style" / MIME errors.
- `splashSelector` in `nav/index.tsx:65` (`.hero.is-ring-splash-done`) is still dead; it feeds `readyChange` only.
- After merge, run `part-footprint --check` when a nav file moves lines; the golden holds line numbers.

## Limits

Mobile and other sections out of scope. Pixel equality is the visual gate's job. The analysis code (edges, comparison, lag counting) is
TS with unit tests and no Lean golden: a TS stand-in. The wheel pass and WebKit captures are timing-sensitive; the sweep and edges are not.
