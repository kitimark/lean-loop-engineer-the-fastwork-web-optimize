---
id: 2026-10-20-gate-green-baseline
kind: note
title: "gate-green-baseline: the WebKit phone-rotation matchMedia cell was a harness fault (page.setViewportSize resets the screen to the viewport); fixed, no excuse added"
status: draft
created: 2026-10-20
topics: [gate, webkit, playwright, device-width, sweeps, lean]
---

Question: why is the WebKit cell `matchMedia =Lean | sweep:phone-rotation` (stops #1 and #3) not comparable, and does the gate pass
once it is comparable, with no excuse and no wider tolerance?

Unit of decision: the WebKit phone-rotation matchMedia cell. Items below it are follow-ups.

## Cause (CONFIRMED by artifact, source and a local debug run)

- Artifact (run 39362804966, WebKit, `phone-rotation` stop 1, both arms): the matchMedia values equal each other and Lean's, but
  `viewport.screenWidth` is 932 and `screenHeight` 430, where the stop requests a device width of 430 and height 932 (`PHONE` of `spec.mjs`).
- The gate's own check (`Fw.Gate.envChecks`, entry `deviceWidth`) holds when the reported screen width equals the request or lies on the
  same side of every device-width edge (the site has one, 500 | 501). 932 and 430 lie on different sides, so the state is "not achieved",
  every Lean-vector check in it is `na` (`truthItems_lean_na`), and the cell is not comparable.
- Why 932: `page.setViewportSize` in playwright-core 1.64.1 stores `{ viewport, screen: { ...viewportSize } }`
  (`lib/coreBundle.js:23896`), then `Page.setScreenSizeOverride` applies the screen (`coreBundle.js:48789`). The context `screen` option
  only holds until the first live resize. `engines.mjs` resized WebKit through `setViewportSize`, so each rotation to 932x430 also
  made the screen 932x430. The old comment in `engines.mjs` ("a live resize cannot change it") was wrong for the screen.
- WebKit side (pinned clone WebKit@862f17d): `device-width` reads `LocalFrame::screenSize()`
  (`Source/WebCore/css/query/MediaQueryFeatures.cpp:362-372`), which returns the override when set
  (`Source/WebCore/page/LocalFrame.cpp:1200-1203`); `setOverrideScreenSize` is `LocalFrame.cpp:1220-1227`. The caller is Playwright's
  protocol patch, which is not in Apple's tree, so that part rests on the playwright-core source above.
- Only the phone sweep differs: the desktop and touch sweeps have device size equal to viewport size.
- Local debug run (not a result, this Mac): after a plain resize `screen.width` follows the viewport and `max-device-width: 500px`
  turns false; after the harness resize it stays 430 and the query stays true, through three rotations.

## Fix (harness, no excuse)

- `packages/gate-breakpoints/src/engines.mjs`, WebKit `resize`: sets the page's emulated size (viewport and screen) itself with the
  call a `window.open` popup makes (`setEmulatedSizeFromWindowOpen`) and applies both in one `updateEmulatedViewportSize`
  (`coreBundle.js:48764`). The pure part, `webkitEmulatedSize(env)`, is checked against the golden. If the internals are missing it
  falls back to `setViewportSize`, so the gate would report the stop not achieved again, never pass it.
- Lean `lean/Fw/Gate/WebkitScreen.lean`: `plain_resize_unmet` (a plain resize leaves the device width unmet at exactly
  `phone-rotation` stops 1 and 3), `kept_resize_met` (with the screen at the device width every stop of every sweep meets the
  check), `deviceWidthHolds_eq_check` (ties it to `envChecks`), `no_exemption_phone_rotation` and `phone_rotation_never_excused`
  (no reading of that sweep is excused, in either engine).
- The theorem asked for ("an excused cell never hides a comparable failing reading") already stands in `Fw.Gate.Exit`:
  `excused_not_fail`, `exemptions_verdict`, `Reading.ok_not_fail`, `engineVerdictC_ne_pass_of_reading`. The allowlist is unchanged
  (5 entries); the fix needed none.
- Golden `packages/contracts/golden/gate/webkit-screen.jsonl` (69 lines: a pin of the playwright-core behaviour and one line per stop
  after the first), `lean/scripts/WebkitScreenGolden.lean --check` in `check.sh`. TS test
  `packages/gate-breakpoints/test/webkit-screen.test.mjs` (4 tests): golden stops equal `sweepDefs`, `webkitEmulatedSize` equals the
  kept screens, a plain resize misses exactly the two stops, and playwright-core's source still has the pinned lines.
- Tests: gate-breakpoints 144/144, `scripts/ci-paths.test.mjs` 41/41, apps/runner (tsc + land-inputs, ci-triggers) 57/57,
  `sh lean/scripts/check.sh` green. One new read declared: the golden in the `lean.yml` row of `Fw.Ci.Trigger.table`.

## Measurement (MEASURED, CI breakpoint-gate, no flags, both engines, full gate)

Tree of every run: 22bab3bc (the fix commit 8f9814ff plus an empty request commit). Default config (config ede2c7641aacf2d2), no flags.

| run | trigger | workflow | Chromium | WebKit |
|---|---|---|---|---|
| 39368032874 | push `[ci:breakpoint-gate]` | success | pass: 7049 pass, 7 excused, 0 fail, 0 cells not ok | pass: 6765 pass, 291 excused, 0 fail, 0 cells not ok |
| 39369683085 | `fw run --gate --engines both` | success | same | same |
| 39370632229 | `fw run --gate --engines both` | success | same | same |

Each run: 504 cells, 7056 readings per engine, 0 unsettled samples. Before the fix (run 39362804966) the WebKit verdict was incomplete
(`matchMedia =Lean | sweep:phone-rotation` not comparable) and the merge job exited non-zero. The three runs are the newest
gate runs on the branch; none failed or was cancelled between them.

## Limits

- The fix uses Playwright internals (in-process client, `toImpl`, `setEmulatedSizeFromWindowOpen`); a Playwright upgrade must keep the
  pin test green or the cell turns not comparable again (loudly, as an `incomplete` WebKit verdict).
- Only the screen size is kept; the screen height is not read by any condition.
- Not measured: Safari on the phone or the iOS Simulator (their screen is the device's own).
