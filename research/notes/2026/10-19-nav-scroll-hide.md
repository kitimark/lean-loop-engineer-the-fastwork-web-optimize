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
the original's class names, which the port DOM does not have. After wiring them to the port's hooks, hidden state, onset and
offset, transform path and end state equal the original's at 861, 1280, 1440 and 1920 px in Chromium and WebKit, within the
named differences below.

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
by the visual-diff overlay server; the original from `snapshot/site`. Per arm: a warm-up scroll over the page (content-visibility
sections otherwise shift the layout by ~48 px mid-run), then scroll from one viewport above the section to half a viewport past its
end in 16 px steps with 3 native rAF per step, down then up, per frame class list, computed transform, opacity, visibility,
header rect, sticky rect. Positions are matched on the grid value u (distance from the section top). Then held positions every half
viewport (700 ms), one captured transition per distinct edge (rAF frames against `getAnimations()` timing and the browser's own
easing), and a real mouse-wheel pass (100 px every 60 ms). Never any animation seek.

## Results (MEASURED)

Runs, all on `ci/nav-scroll-hide-check`: baseline 39250254933 (10db0eae). Fixed: 39251940538 (push, b5bbbd3f), 39253432942 and
39253457408 (dispatch, b5bbbd3f), 39257593393 (push, 3be14b42). The WebKit job of 39253457408 was not used. Chromium: 4 fixed runs,
WebKit: 3 fixed runs, each on separate jobs.

Hidden state per step, steps that differ (orig vs port; down/up; 4 chromium runs, 3 webkit runs):

| width | chromium | webkit |
|---|---|---|
| 860 | 0/0 in all runs | 0/0 |
| 861 | 0/0 | 0/0 |
| 1280 | 0/0 | 0/0 |
| 1440 | 0/0 | 0/0 |
| 1920 | 1/1 in all 4 runs (step u=3304) | 0/0 |

Onset and offset (live u of the first frame that changes, run 39257593393):

| engine | width | orig on / off (down) | port on / off (down) |
|---|---|---|---|
| chromium | 861 | -47.39 / 2480.61 | -47.39 / 2480.61 |
| chromium | 1280 | -46.19 / 2481.81 | -47.19 / 2480.81 |
| chromium | 1440 | -34.19 / 2797.81 | -35.19 / 2796.81 |
| chromium | 1920 | -38.19 / 3353.81 | -39.19 / 3368.81 |
| webkit | 861, 1280, 1440, 1920 | equal to the digit | equal to the digit |

Up edges mirror the down edges in every row. Transform path: all four captured edges per width have the same animation list
(opacity .28 s and transform .32 s `cubic-bezier(.16,1,.3,1)`, visibility .32 s delay), end at translate -88, opacity 0, hidden
(on) and 0, 1, visible (off). Max distance of sampled frames from the browser's own easing: Chromium <= 0.16 px (both arms),
WebKit <= 2.6 px (3 to 7 frames per transition on the CI machine, so this is sampling).

Real wheel, first frame hidden/visible per direction, port minus orig: Chromium within 6 px at every width (the wheel moves 100 px per 60 ms and frames land within a few px);
WebKit within one 100 px tick (orig differs from itself by one tick between runs, for example 2336 vs 2448 at 861/1280).

## Differences and their causes

1. Chromium 1920 px, one step each way (u=3304): the original's section bottom there is 868.19 against the item bottom 868, so
   `sectionBottom > itemBottom + 1` is false; the port's is 869.19, true. Cause: the section is 4208 to 4215 px high in the
   original and 4219 to 4220 in the port (about 5 px; 1 to 3 px at 1280 and 1440), so the 1 px threshold falls one step apart.
   Layout, not the rule. The visual gate owns it. WebKit heights differ by 0 to 1 px and the edges are equal.
2. Chromium edges 1 px apart at 1280 and 1440 (-46.19 vs -47.19): section top 1106 vs 1105 and 1206 vs 1205. Same cause.
3. Held positions, WebKit only, first position inside the stuck zone (u asked 0, live u about 49): in 1 or 2 of the 5 widths in each of the 3
   runs the port stays visible for the whole 700 ms hold while the original is hidden. Chromium showed it once in 4 runs
   (1920). Run 39257593393 (WebKit 861): the original is visible at 50 ms and hidden by 250 ms; the port stays visible through
   500 ms and the end. The 540 px jump shifts the layout by ~49 px in both arms. INFERRED: the original's lazily mounted deferred
   sections register more scroll callbacks after the jump and each registration requests a frame that re-runs every callback,
   so the nav re-measures; the port mounts everything at once, gets one frame, and has no later event. Impact: after a
   programmatic jump into the zone (anchor link, find in page) the port nav can stay visible until the next scroll event.
   Gradual scrolling and the wheel never show it. Not fixed here: a re-measure after the layout settles is new behaviour.
4. Frame counts and `getAnimations()` lists differ in WebKit captures (3 to 7 frames); some captures show only transform because
   the opacity animation already ended. The computed transition is equal, so this is capture timing.

## Also found

- The overlay server of visual-diff served `.css` and `.js` as `application/octet-stream`. The browser then ignored the
  stylesheets and did not run the module, so the port arm was unstyled and unhydrated (sticky `static`, 0 CSS rules). Fixed in
  `visual-diff/src/serve.mjs` (`DOC_TYPES`, test). Earlier visual-diff lane results for the rewrite arm were not re-examined here; the lead should
  check whether they were produced with the old server (I saw the unstyled page in a local WebKit run only).
- `splashSelector` in `nav/index.tsx:65` (`.hero.is-ring-splash-done`) is still dead; it feeds `readyChange` only.
- After merge, run `part-footprint --check` when a nav file moves lines; the golden holds line numbers.

## Limits

Mobile and other sections out of scope. Pixel equality is the visual gate's job. The analysis code is TS with unit tests, no Lean
golden. The wheel pass and WebKit captures are timing-sensitive; the sweep and edges are not.
