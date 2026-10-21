---
id: 2026-10-21-webkit-cancelled-flake
kind: note
title: "Why webkit/loopback/compare/cancelled-same-origin-0 failed land runs: the grant landing page is left with a lazy image request in flight"
status: final
created: 2026-10-21
authors: [agent:measure-engineer]
topics: [measurement, webkit, e2e-preview, flake]
---

# webkit-cancelled-flake (2026-10-21)

Question: why does `packages/e2e-preview` fail `webkit/loopback/compare/cancelled-same-origin-0` on land-lane runs,
and what fixes it without a retry or a longer timeout?

## Answer

- The failure is the suite's own page change, not a defect of the compare page. The suite opens the grant landing page
  (arm `/`), waits for the network to be idle plus 300 ms, then calls `page.goto(compare)`. The landing page has a lazy
  image (`service-strawberry.jpg`) whose request starts just inside that wait window or just after it. The navigation
  start makes WebKit cancel every subresource loader of the old document, so Playwright reports `requestfailed`
  "Load request cancelled" for a request that belongs to the previous document. The log was reset right before the
  `goto`, so the next load (compare) is charged with it. MEASURED, CONFIRMED (below).
- Fix (in `packages/e2e-preview/src/suite.mjs`): leave the landing page through `about:blank` and wait until every
  request the page asked for has ended (finished or failed), then reset the log. The suite now also records that wait
  as a check, `landing-page-requests-ended`.
- No retry, no longer timeout, no quarantine list. The assertion itself is unchanged: a cancelled same-origin request
  during a load is still a failure.

## Evidence

Failed land runs (logs read): 39416621069, 39495702143, 39546479081, 39573231550 (the land report counted 6: it counts the failed
`cancelled-same-origin-0` checks in each run's `out/webkit.json`, INFERRED, the report is not kept; two of the six have no log left). All four print the same line: `1 cancelled of 1 failed: GET /selling/sellers/photographer/service-strawberry.jpg
Load request cancelled`, with navigations `main compare, frame blank, frame blank, frame /, frame /, frame /`. No other
webkit test failed in any of the 18 land failure logs read. The ids of those 18 were not written down when they were read and
cannot be recovered from this repository, so only the four above are named; `gh run list --workflow land.yml --status failure`
lists the candidates. MEASURED for the four, not re-checkable for the other 14.

Trace (`--trace`, run 39596410734, job 9 of 10, 1 failure in 200 compare loads), time in ms from load start:

| ms | event |
|---|---|
| 175 | grant visited |
| 1852 | landing page load |
| 2653 | landing settled (network idle + 300 ms); log reset; `goto(compare)` called |
| 2656 | the **landing page (main frame)** requests `service-strawberry.jpg` |
| 2666 | `requestfailed` "Load request cancelled" for that main-frame request |
| 2726 | compare `framenavigated` |
| 3870 | compare's own strawberry request (child frame) finishes fine |

In the framed compare page the image gets its `src` about 74 ms after window load and is requested about 700 ms after
load, so on the landing page the request lands at the end of the fixed wait. MEASURED.

Engine source, WebKit tag WebKit-7625.1.29.10.29 (iOS 27.0, sha 862f17dcae0a): `FrameLoader::continueLoadAfterNavigationPolicy`
(Source/WebCore/loader/FrameLoader.cpp:4176, `stopAllLoaders` at :4279) calls `FrameLoader::stopAllLoaders` (:2189),
which calls `DocumentLoader::stopLoading` (DocumentLoader.cpp:324), which calls `stopLoadingSubresources`
(DocumentLoader.cpp:2022-2034) and `cancel()`s every subresource loader except prefetch. CONFIRMED. That Playwright's
Linux WebKit build shares this code is INFERRED.

Deterministic proof, a debug flag `--provoke n` that adds n uncached image requests on the landing page just before
it is left (6 targets x 3 repeats x 10 jobs = 180 loads each):

| code | run | loads with `cancelled-same-origin-0` failed |
|---|---|---|
| before the fix (plain `goto`) | 39599085320 | 180 of 180 |
| after the fix (`about:blank` + wait) | 39599115237 | 0 of 180 (0 of 3630 checks) |

MEASURED. With the cause provoked, every target that goes through the landing page fails on the old code, so the
cause is this, not a compare-only quirk.

Green natural repeats on the fixed code: run 39599136251 (commit ee2fe74e), 10 jobs x 6 targets x 20 loads =
1200 loads, 24200 checks, 0 failures; the new check `landing-page-requests-ended` read "none open" in all 1200.
Runner `ubuntu24-arm64 20261012.149.1`, node 24.22.0, 4 cpus (`ubuntu-24.04-arm`, the land lane's image). MEASURED.

Natural rate on idle CI runners is low, so the natural repeats alone cannot separate fix from luck:
run 39596410734 (old code) had 1 strawberry cancel in 200 compare loads; run 39597361506 (old code, all 6 targets,
1200 loads) had 1; two pairs of 1000 compare loads (39600742129 fixed code, 39600767374 old code) had 0 each. So the
natural rate on the old code is 2 in 2400 loads (200 + 1200 + 1000), about 0.1 %, and at most 0.5 % by the 1-in-200 run; the land lane's loaded runners raise it. The provoke pair is the proof,
the natural repeats are the green record. MEASURED.

## A second flake, found on the way (not fixed here)

Runs 39597361506, 39600742129 and 39600767374 also showed HTTP 502 `preview server not reachable` from the arm app
(`apps/console-api/src/preview/arm-app.ts:88`) on a module script, a stylesheet or `GET /`. It happens on the fixed
and on the old code, 3 of 1000 loads and 5 of 1000 loads, so it does not depend on this fix. A 502 on a module script
shows up as "Load request cancelled" too, so it can turn the same test red with a different cause (run 39600742129 is
red for that reason: its strawberry check passed in all 1000 loads). INFERRED cause: a reused keep-alive socket to
the preview server (the shared `http.Agent`, `keepAlive`, `maxSockets 64`, line 25) that the server closed, so the
request fails with a connection error that the `catch` turns into a 502 without a retry. Cause found and fixed in task preview-502-flake: `research/notes/2026/10-2x-preview-502-flake.md` (the inference was
right about the reused socket; the closing side was the test rig's tap, not the preview server).

## Open

- Why the natural cancels were seen on `compare` only in the 200 and 1200-load runs: statistically weak (1 event); the
  provoke run shows every landing-page target is exposed. INFERRED.
- The 502 flake above: a new graph task for `apps/console-api` (log the upstream error code, then decide between
  retry-once on a stale reused socket and a fresh socket for a first request).
- `docs/team/tools/preview-e2e.md` lines 79-80 say leaving a page mid-import makes the browser cancel the import; add
  the landing-page rule and the harness flags `--only`, `--repeat`, `--trace`, `--provoke`. The file is outside this
  task's writes.
- The `.github/workflows/webkit-cancelled-flake.yml` repeat workflow lived only on the `ci/webkit-cancelled-flake`
  branch commits; the final commit removes it (the Lean table of workflows has no row for it).
