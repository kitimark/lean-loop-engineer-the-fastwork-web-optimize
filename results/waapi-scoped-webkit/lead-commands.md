# waapi-scoped-webkit: what the lead runs (no CI run was possible from this branch)

Reason: `pnpm fw ci push ci/waapi-scoped-webkit --dry` reports that smoothness and trajectory-probe would not start
(push guard rule `unchanged`: no input differs from main). The task's writes hold no workflow input, so a push from
this branch cannot start a count lane. Nothing below was run; each command is INFERRED from the lane docs.

## 1. Simulator counts per finish zone (item 1)

Existing Simulator touch windows run with the Web Inspector Timeline off (`touch-push.mjs:32`, `sim-cadence.mjs:113`),
so a Simulator row has no RecalculateStyles/Layout counts. Counts per zone exist only in the macOS Playwright WebKit
leg (`webkit-mac`, smoothness.yml). Dispatch it with the arm `morph.tween:waapi-scoped` against the base:

    pnpm -s fw run --trajectory --ref ci/waapi-scoped-webkit --fw morph.tween:waapi-scoped --engines playwright-webkit --widths 390 --diagnostic

(at most 2 dispatches; poll with `pnpm fw ci wait --branch ci/waapi-scoped-webkit --workflow trajectory-probe`).

## 2. Stale nav class in the Simulator (item 2)

The source already writes `data-fw-morph` at push, at each threshold crossing and at settle (`waapi.driver.ts`,
waapi-threshold-attr). The recorder reads only `--morph` (`recorder.mjs` `endTouchJs`), so an end-of-window read cannot
see a class that was stale mid-morph. `recorder-nav-class-sampler.patch` (applies with `git apply`; checked) adds
`navClasses`, a histogram of `className|data-fw-morph` sampled every 40 ms. It touches
`packages/measure-webkit/src/profile/recorder.mjs`, outside this task's writes; the `sim-cadence.mjs` row field that
carries `navClasses` into the report is not written. A stale class shows as `is-morphing` absent (or `is-expanded`
absent) at a sampled `data-fw-morph` above `MORPHING_CUT` / `EXPANDED_CUT` (`nav/logic.ts:55-64`).
