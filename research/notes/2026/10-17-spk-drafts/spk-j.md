---
id: 2026-10-17-spk-j
kind: note
title: "SPK-j: harness neutrality (clock shim vs free-running in Chromium; seek overhead in WebKit)"
status: draft
created: 2026-10-17
topics: [spike, decision-record, harness-neutrality, chromium, webkit]
---

# SPK-j (DRAFT decision record)

**Question (PLAN Appendix B).** Harness neutrality: clock shim with native rAF vs free-running (Chromium); seek
overhead per accelerated animation (WebKit).

**Status: PARTIAL.** WebKit half answered (MEASURED); Chromium half open.

## WebKit half: seek overhead. Answer
Seeking accelerated animations costs a fixed number of style records per step, not one per animation, in N = 10..100.
Free-running accelerated animations cost no main-thread style records.

| N animations | `animation` layers | style records free / seeked | layout free / seeked | paint free / seeked | composite free / seeked |
|---|---|---|---|---|---|
| 0 | 0 | 0 / 0 | 0 / 0 | 0 / 0 | 119 / 119 |
| 10 | 10 | 0 / 122 | 0 / 2 | 0 / 4 | 119 / 119 |
| 50 | 50 | 0 / 122 | 0 / 2 | 0 / 16 | 119 / 119 |
| 100 | 100 | 0 / 122 | 0 / 2 | 0 / 30 | 119 / 119 |

(60 steps of 2 rAF each, about 2.03 `RecalculateStyles` per step; all 32 rows deterministic in all 4 passes.)

- Evidence: `packages/measure-webkit/README.md` "Seek overhead" @ddc91b2; fixture `packages/measure-webkit/fixtures/seek.html`
  and `src/seek.mjs` @1d6c88c; `docs/team/handoffs/meas-webkit.md` @a65aaa7. MEASURED (iOS 27.0 Simulator, Mac host).
- **Decision to record:** tag `RecalculateStyles`, `Layout` and `Paint` as `harness-induced` for every seeked WebKit run;
  `Composite` is clean. The PLAN's "invalidates style per animation per step" does not hold on this build for N up to
  100 (one invalidation per step). Limit: N > 100 and non-transform/opacity animations are untested (INFERRED same).

## Chromium half: clock shim vs free-running. Status OPEN
What exists:
- The shim virtualises `Date`, timers, `performance.now`, `Math.random`; `requestAnimationFrame` stays native, with one
  deliberate deviation: the rAF timestamp argument is the virtual frame time (`packages/measure-chromium/README.md`
  "One virtual frame" @ddc91b2). MEASURED: with the native timestamp a page saw hours of elapsed time and ended its
  animations at once (2,040 rAF callbacks instead of 2,459).
- With `--deterministic-mode` compositor animations are disabled, so `Animation.compositeFailedBits` describes a
  main-thread run; compositor status needs the free-running census (README, "Count types").
- No run compares shimmed counts with free-running counts of the same page.

Missing: a paired comparison (shim on vs a free-running headed or headless run) per count family, to say which
families the shim changes. `meas-chromium-2` has uncommitted work in its worktree (clock shim, run loop, fixtures); I did
not read it and it is not evidence.

**Evidence commit:** `1d6c88c` (WebKit lane), `e01f9e5` (Chromium lane), `ddc91b2`; HEAD `30e3264`.

## Next step
- Chromium paired shim/free-running comparison, then a table of "harness-induced" families. Owner: measure-engineer
  (meas-chromium-2). Needs SPK-h only for the N1 slices.
- WebKit: repeat the seek fixture on the pilot parts' real animations (not only transform/opacity fixtures). Owner:
  measure-engineer (meas-webkit-2).

## What this changes in the plan
- §4.2: replace the WebKit seek-cost sentence by the measured one; add the `harness-induced` tag rule. Appendix B:
  SPK-j "partial: WebKit answered, Chromium open".
