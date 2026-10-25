# toolbar-wktr-gate: the WKTR forced-inset gate for the morph arm and the unthrottle exemption

## Answer

- **The hooks exist in our WKTR build (CONFIRMED, run 40223882394).** The archive `nm` check (jobs j1, j2, j3) counts each
  symbol once: `WTR::UIScriptControllerIOS::beginInteractiveObscuredInsetsChange`, `...::endInteractiveObscuredInsetsChange`,
  `WTR::UIScriptControllerCocoa::setObscuredInsets`. In the running WKTR the page reads `typeof uiController.<hook>` as
  `function` for all three, in every one of the 24 reports.
- **The gate passes on all four flags (MEASURED, run 40223882394, 3 jobs, 2 passes per flag per job, 24 of 24 reports).**
  Verdict line per job: `VERDICT toolbar-gate pass`.
- **Every report agrees with Lean.** Arm sequence, take sequence and the unthrottle exemption per flag equal the rows of
  `packages/contracts/golden/parts/morph-mount-toolbar.gate.jsonl`, which `Fw.Parts.MorphMountToolbarGolden` generates from
  `Fw.Parts.MorphMountToolbar` (section "The WKTR forced-inset gate").
- **What WKTR observes and what Node derives (CONFIRMED, `toolbar-page.mjs`, `gate.mjs`).** WKTR observes two things per
  flag: the viewport height and the platform rect after each inset step (so the arm sequence), and the wait from
  `setObscuredInsets` until `visualViewport.height` changes (so the exemption). It sends no touches and runs no
  gesture code. The take sequences in the table come from Node: `gate.mjs` feeds the observed arm sequence to the
  production `gesture.ts` `step`, and compares the result with the Lean golden. So the takes are not an engine
  observation; they show that the production machine, on the arms the engine produced, gives the Lean takes.

## Negative control: the gap comes from the scroll-driven exemption (MEASURED, run 40231779387)

The `compositable` arm is the same page as `default` plus one time-based `transform` animation (`translateX`, 400 ms,
linear, infinite; `CONTROL_CSS` in `toolbar-page.mjs`), which WebKit can run on the compositor (INFERRED; not observed in WKTR; the Lean not-lifted verdict follows from progressBased = false alone) and has no scroll timeline. Lean
decides it is not exempt: `controlPage` holds one non-progress-based accelerated animation, so `control_page_not_lifted`
(`compositable_does_not_lift`) gives `throttled true controlPage`, and the golden row is `gateExempt compositable false`
(`Fw.Parts.MorphMountToolbar` `compositable_throttled`; `exempt_only_unthrottle` now covers all five arms).

Run 40231779387 (3 jobs, 2 passes per arm, 30 of 30 reports pass, `VERDICT toolbar-gate pass` in each job): the page reports
one running animation on a `DocumentTimeline` in every `compositable` report, and the median wait after the first set is
81-83 ms for all four throttled arms, `compositable` 82-83 ms (j1 82, 82; j2 82, 82; j3 83, 82), `unthrottle` 31-32 ms. The
82 ms of `compositable` sits 32 ms above the 50 ms bound and the page has an animated element, as `unthrottle` does. So the
32 ms of `unthrottle` comes from the progress-based main-thread scroll-driven animation, not from extra content or any
running animation.

## What the gate forces

The page calls the three hooks the way `UIHelper.beginInteractiveObscuredInsetsChange` / `setObscuredInsets` /
`endInteractiveObscuredInsetsChange` do (`ui-helper.js:2018-2050`, `UIScriptControllerIOS.mm:1486-1494@862f17d`). Each step
is `scrollTo`, then `setObscuredInsets(inset,0,0,0)` with insets 10, 20, 30, 40 and back 30, 20, 10, 0. It does not use the
UIHelper wrapper, because that wrapper waits for a content-rect update after every set and would hide the wait to measure.

A fixed platform stand-in (height 3/5 of the viewport before any inset, bottom edge 15 px above its bottom) is the object
whose arm the production `armed` decides (`apps/site/src/parts/morph.mount/logic.ts`). The gate feeds the observed rect and
viewport height to the production `armed`, and the observed arm sequence to the production gesture machine (`gesture.ts`
`step`, `gestureOpt`), with Node importing the TS directly. Nothing is copied.

## Per flag (MEASURED, run 40223882394; identical in every job and pass)

Viewport height 810, 800, 790, 780, 790, 800, 810, 820 (vh0 820; `setObscuredInsets` shrinks `visualViewport.height` by the inset).

| flag | arms down / up (WKTR) | takes down (insets 0,10..40) / up (30..0) (Node, from the observed arms) | median wait after the first set (WKTR) |
|---|---|---|---|
| default | 11100 / 0111 | 11100 / 0111 | 82-83 ms |
| touch-first | 11100 / 0111 | 11100 / 0000 | 81-83 ms |
| open-once | 11100 / 0111 | 10000 / 0100 | 82-83 ms |
| unthrottle | 11100 / 0111 | 11100 / 0111 | 32-33 ms |
| compositable (control, run 40231779387) | 11100 / 0111 | 11100 / 0111 | 82-83 ms |

The exemption is a throttle effect, not a look effect. While an interactive obscured-insets change runs and no main-thread
progress-based scroll-driven animation exists, WebKit holds the visible-rect update 100 ms (`WKWebViewIOS.mm:3256-3268@862f17d`).
The three non-exempt flags wait about 82 ms (the 100 ms window minus the time spent before the next set); `unthrottle` runs
the production `@property --fw-ut` scroll timeline (page reports 1 animation) and waits 2 frames (32-33 ms). Lean decides
the verdict at `liftedBelowMs = throttleMs / 2` (50 ms); the observed values sit 17 ms below and 32 ms above it, so one
slow runner would have to add 17 ms to the lifted wait to flip it. No run came near that.

Lean statements (`lean/Fw/Parts/MorphMountToolbar.lean`): `plain_throttled`, `touchFirst_throttled`, `openOnce_throttled`,
`unthrottle_exempt`, `compositable_throttled`, `control_page_not_lifted`, `exempt_only_unthrottle`, `gateGeom_iff`, `down_geoms`, `up_geoms`, and ten take theorems (one per
flag and phase), `unthrottle_same_takes`, `compositable_same_takes`.

## Limits (accepted)

- `setObscuredInsets` is step-wise (one set per step), not per frame like a finger-driven toolbar collapse.
- `lvh`/`svh` are not overridden in WKTR, so viewport-unit values differ from Safari; the gate reads `visualViewport.height`
  and `innerHeight`, which the hook does change.
- WKTR is not Safari and has no real toolbar; the gate shows the engine path (inset change, throttle, arm decision), not the
  look on a phone.
- The wait values are CI-runner timings of one Simulator image (iOS 26.5, WKTR r324039); they decide the exemption only
  through the 50 ms bound.

## TS stand-ins

- The `control-anim` check in `gate.mjs` (the control page reports one running `DocumentTimeline` animation) has no Lean row; it checks the fixture, not a decision.
- `liftedBy` (one comparison) in `packages/measure-wktr/src/gate.mjs`, checked against the `gateLifted` golden rows.
- The page script and driver (`toolbar-page.mjs`, `toolbar-cli.mjs`) are glue: they report observations and hold no decision.
- `ts-ext-hooks.mjs` is a loader hook that lets Node resolve the production TS imports that omit `.ts`.

## Deviation

The gate rows live in a separate golden, `morph-mount-toolbar.gate.jsonl`, not in `morph-mount-toolbar.jsonl`:
`apps/site` `goldenConformance('morph-mount-toolbar', ...)` fails on any `fn` row without a TS implementation, and the gate
functions have none by design. `Fw.Parts.MorphMountToolbarGolden` guards both files with
`include_str`, so no `check.sh` job was added.
