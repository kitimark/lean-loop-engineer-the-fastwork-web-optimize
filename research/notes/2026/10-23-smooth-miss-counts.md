---
id: 2026-10-23-smooth-miss-counts
kind: note
title: "Skipped-slot and over-25 ms counts beside the bad-frame count, in both cadence lanes"
status: review
created: 2026-10-23
authors: [agent:lean-prover]
topics: [lag, smoothness, cadence, skipped-slots, chromium, webkit, simulator, real-touch, histograms]
---

# Miss counts in the cadence lanes

Task `smooth-miss-counts`, from `10-22-lag-coverage.md`. Branch `worktree-wf_052bd076-8ce-1`. Every number below is MEASURED on GitHub
Actions (run ids given); CI Simulator and Playwright WebKit are not the phone.

## What changed

| piece | where | status |
| --- | --- | --- |
| `over25`, `over34`, `over50`, `skips`, `longGaps`, `Counts`, `countsOf` | `lean/Fw/Gate/Smooth.lean` | CONFIRMED (builds, `lean/scripts/check.sh` green) |
| `over50 <= over34 <= over25 <= frames`, `over34 = badTenths 340`, `hitches <= over50`, `longGaps <= skips`, an interval of at most one slot (16.67 ms) is no skip; an interval over 2 slots is a skip (`longGaps <= skips`), `countsOf_ordered`, `Counts.add_ordered` | same file | CONFIRMED |
| 39 golden lines for the counts | `packages/contracts/golden/gate/smooth.jsonl` | CONFIRMED (`--check` up to date) |
| TS twin `countsOf`, `sumCounts` (checked against the golden) | `packages/gate-breakpoints/src/smooth/reduce.mjs` | TS stand-in, tested against the Lean golden |
| counts per row, per run and pooled; Chromium `Browser.getHistograms` read per window | `src/smooth/{cadence,cadence-table,launch}.mjs` | glue |
| WebKit rows carry `th`; counts in the mac and sim tables; `end touch` as its own window | `packages/measure-webkit/src/profile/{report,sim-cadence}.mjs` | glue |
| real finger swipes at the end of the page (one long XCUITest `PushServer`) | `src/touch-push.mjs`, `src/throttle/driver/UITests/PushServer.swift` | glue, partly working (below) |

A skipped slot is an interval that advances the 60 Hz slot count by 2 or more (`skips`); the integers are hundredths of a
millisecond from the page's timestamps, so the counts are exact.

## Chromium cadence, run 39897279523 (6 jobs, widths 390 and 1280, 3 sets each, 7 reps per arm)

Counts summed over the 3 jobs of a width (frames / over 25 / over 34 / over 50 / skipped slots).

| width | window | orig | base | aa | cand |
| --- | --- | --- | --- | --- | --- |
| 390 | end | 2524 / 107 / 22 / 8 / 107 | 2529 / 97 / 16 / 8 / 97 | 2526 / 101 / 16 / 10 / 101 | 2526 / 95 / 20 / 13 / 95 |
| 390 | hero | 3622 / 27 / 0 / 0 / 27 | 3624 / 55 / 22 / 21 / 55 | 3618 / 51 / 21 / 21 / 51 | 3628 / 52 / 22 / 22 / 52 |
| 1280 | end | 1565 / 795 / 226 / 84 / 795 | 1616 / 796 / 234 / 78 / 796 | 1592 / 783 / 239 / 93 / 783 | 1609 / 792 / 234 / 85 / 792 |
| 1280 | hero | 3255 / 628 / 106 / 23 / 628 | 3257 / 636 / 133 / 20 / 636 | 3257 / 635 / 129 / 23 / 635 | 3256 / 635 / 127 / 22 / 635 |

- Skipped slots equal the over-25 count in every cell: Chromium paints on exact vsync slots, so an interval above 25 ms is
  at least 2 slots. The two counts only separate on WebKit.
- Across the 3 jobs only one pair is told apart: at 390 hero, orig has fewer over-34 and over-50 intervals than base, aa and
  cand (orig 0 / 0, rewrite arms 21 to 22 over 34 ms and 21 to 22 over 50 ms). Every other pair and window is "not told apart".
  The rewrite arms (base = aa = cand) agree with each other, so that gap is a difference between orig and rewrite at 390
  hero (INFERRED: the three rewrite arms agree, which an A/A split would not).
- Histograms (`Browser.getHistograms` for ScrollJank, Smoothness, Checkerboarding): the call answers (not null) but every one
  of 336 windows returns an empty list. INFERRED cause: getHistograms reads browser-process histograms only
  (browser_handler.cc:643-652@f842f52), and the child-process histograms are not merged within the 600 ms wait; whether the
  headless shell records them at all is not tested. The lane has no histogram data. The plumbing stays (it costs one call per window) for a headed run.

## WebKit, run 39901005729 (mac x3, Simulator x3)

Mac (Playwright WebKit, real `page.mouse.wheel`, so the end window is a real wheel path), counts pooled over 3 jobs (6 reps per
arm and job with the Timeline on, 5 with it off):

| window | Timeline | arm | over 25 | over 34 | over 50 | skipped | frames |
| --- | --- | --- | --- | --- | --- | --- | --- |
| hero | on | orig | 1286 | 1234 | 724 | 1294 | 2501 |
| hero | on | base | 276 | 211 | 127 | 313 | 2360 |
| hero | on | aa | 269 | 182 | 97 | 313 | 2344 |
| end | on | orig | 618 | 437 | 206 | 627 | 1125 |
| end | on | base | 516 | 333 | 201 | 538 | 1137 |
| end | on | aa | 519 | 356 | 198 | 534 | 1137 |

Hero: orig vs base is "second" (the rewrite has fewer misses) in 3 of 3 jobs, with the Timeline on and off. End: "same" in
3 of 3. On WebKit skipped slots exceed over-25 (hero base 313 vs 276) because an interval of 16.7 to 25 ms can cross two slot
boundaries when frames sit off the 60 Hz grid; `skips` counts such intervals, not the slots lost (INFERRED).

Simulator: the end-of-page real touch worked for the first end window of each of the 3 jobs (251 to 353 frames, touchmove
seen, morph opened) and for the second end window of job 1 only:

| window | arm | n | over 25 | over 34 | over 50 | skipped | frames |
| --- | --- | --- | --- | --- | --- | --- | --- |
| end touch | orig | 3 (1+1+1) | 459 | 162 | 53 | 475 | 693 |
| end touch | base | 1 | 225 | 39 | 17 | 207 | 292 |

n is below the sufficiency line, so no verdict. After the first push, `Timeline.stop timed out after 60000 ms` (the touch
windows last 60 to 130 s on the runner and hold 20 to 40 thousand records) and the retry fell back to the synthetic wheel; jobs
2 and 3 ended INCOMPLETE. One xcodebuild start per window was worse (about 60 to 90 s each, run 39897310152), hence one long
`PushServer` per job (ready after 51 to 198 s). A fix attempt (Timeline.stop wait 240 s for touch windows, run 39909042070) was worse:
sim jobs 1 and 3 hit the 50 minute step limit and were cancelled (no artifact), job 2 timed out even on its first touch window
and kept 0 touch end windows of 15 (the rest ran on the synthetic wheel). The mac jobs of that run repeat run 39901005729:
hero orig vs base is "second" and end is "same" in 3 of 3 jobs again, so the mac verdicts hold over 6 jobs of 2 runs. The real
touch in the CI Simulator is therefore not a reliable lane; what stands is the 3 first-window rows above, with n below the line. The Simulator hero window of orig also keeps only 1 to 7 frames per window
(pre-existing starvation on the runner), so orig hero in the Simulator has no usable counts.

## Not done

- `lag/probe.mjs` `morphRun` still sends a synthetic WheelEvent: `lag/report.mjs` assumes fixed idle/open/close frame counts,
  and a real push has a variable length. Split into task morph-real-wheel: a real-path morph run needs a report that takes phases by marker, not by
  count. The real wheel (mac) and real touch (Simulator, partly) are in the cadence legs instead.
- Chromium jank and smoothness histograms: empty in headless shell, see above.
- Phone: none of this is phone time.
