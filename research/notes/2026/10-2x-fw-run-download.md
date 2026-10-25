---
id: 2026-10-25-fw-run-download
kind: note
title: "fw run's download died at 40 s because it fetched 210 to 400 MB of build outputs nobody reads; it now fetches only what the store keeps, per piece, with a sized timeout and one retry"
status: review
created: 2026-10-25
topics: [tooling, ci, store, gh-budget, timeouts]
---

# fw run download: the 40 s bound

## Answer

- The 40 s is not a `fw run` setting. `chargedGh` (`apps/runner/src/run.ts:176`) passes no timeout, so `chargedOnce` uses its
  default `GH_BOUNDS.defaultCallTimeoutMs` (`packages/gh-budget/src/charged.ts:42`, killed at `:63`, message `:68`), generated
  from `defaultCallTimeoutMs := 40000` (`lean/Fw/Obs/Timing.lean:1660`). CONFIRMED (source).
- Cause: `fw run` called `gh run download <id> -D dir` with no pattern, which fetches every artifact of the run, the build outputs
  included. MEASURED below: a chromium run is 400 MB, a 3-VM WebKit run about 210 MB; only 5 to 25 MB of that is measurement.
- The 40 s also cannot simply be raised: the call holds the gh-budget lock while it runs (`charged.ts:51-70`), and
  `hung_holder_fits` (`Timing.lean`) proves a holder is killed before a dispatch's 60 s lock wait ends.
- Fix (Lean first, `Fw.Store.downloadPieces`, op `store.download`): download one piece per kept artifact, each with timeout
  15 s + 2 ms/KB of its byte bound (at most 40 s, proved: `piece_fits_hold`), never `chromium-image`, `fwcore`, `site-dist`
  (`build_outputs_skipped`), every shard artifact included (`shard_downloaded`). One retry of a timed-out piece.

## Measured (this Mac, 2026-10-25, plain `gh run download` into scratch, then deleted)

`gh run view --json` has no artifacts field and `gh api` is denied, so sizes come from the downloads themselves.

| run | what | artifacts | size | time |
|---|---|---|---|---|
| 40153927556 | chromium counts, everything | 12 | 400 MB | 92 s |
| 40153920231 | chromium counts, everything | 12 | 400 MB | 423 s |
| 40156382719 | chromium counts, everything | 12 | 400 MB | 122 s |
| 40156384878 | chromium counts, kept pieces only | 5 dirs | 5.5 MB | 9.5 s |
| 40153925235 | webkit 3 VMs, kept pieces only (`webkit-sim-r1..3`, `telemetry-*`) | 7 | 25 MB | 10 s |
| 40153925235 | webkit, `fwcore` + `site-dist` only | 2 | 185 MB | 22 s |

Per artifact (chromium, 40153927556): chromium-image 209 MB, fwcore 158 MB, site-dist 27 MB, each counts shard 1.8 MB,
chromium-classes 40 KB, each telemetry 4 to 8 KB. WebKit: `webkit-sim-r1` 5.0 MB, `r2` 11.9 MB, `r3` 8.0 MB, telemetry 24 to 36 KB.

- The same 400 MB took 92, 122 and 423 s: a 4.6x spread (0.95 to 4.3 MB/s). GitHub-side slowness; named, not fixed.
- The whole WebKit run is 210 MB: 32 s at the fast rate, so it is the 40 s bound that killed it (MEASURED: 25 + 185 MB).
  The three chromium runs failed for the same reason at the slower rate. Run 40156384878 is chromium too (columns); it was measured only for its kept pieces (5.5 MB, 9.5 s), so its full size and whole-run download time are not measured.
- Overhead per call is a few seconds (listing + redirect), so one call per artifact costs about 1 s each (5 pieces in 9.5 s).

## The rule

`timeout(piece) = 15000 + 2 * kb(piece)` ms. `kb`: counts shard 2000 (seen 1844), `chromium-classes` and `telemetry-*` 100
(seen 40, 36), webkit VM 12500 (seen 11856). 2 ms/KB is 0.5 MB/s, half the slowest rate seen. A webkit VM piece gets exactly 40 s
(`piece_fits_hold_webkit_tight`); at 0.5 MB/s its 25 s after the base just carry 12.5 MB; at the slowest rate seen (0.95 MB/s) the transfer takes 13 s, 12 s inside the bound.
Golden `packages/contracts/golden/store/download.jsonl` (7 cases), replayed against fwcore by `apps/runner/test/run-golden.test.ts`.

## Retry and the budget

- Charging (CONFIRMED, `charged.ts:51-70`, `lean/Fw/Ci/Budget.lean:493`): the reservation (`ci.budget.reserve`, cost c) is booked
  before gh runs; `observe` books a correction only when the trace shows more responses than c. A timed-out call is therefore
  charged once, and the responses it served are not booked again.
- The retry is a new call. `retryCost c served = c` if no response was seen, else 1 (the listing again; the artifact itself
  comes from blob storage). That the blob fetch is outside the REST quota is INFERRED; `observe` replaces `remaining` with the
  header value on every response, so an error here corrects itself on the next call (`bucket`, `Budget.lean:470`).
- `retryCost_le`: the retry never costs more than the call. Test `apps/runner/test/run-download.test.ts` reads the ledger:
  `[[2, charged], [1, charged]]` for a timeout that served 1 response and its retry.
- Pieces cost 2 each; a 3-VM WebKit run is 4 pieces = 8 requests, the old whole-run call was 15.

## Demonstration

Re-filing needs no dispatch: `pnpm -s fw run --target rewrite --engines webkit --from-run webkit=40153925235 --sha
f74e3313a0de16a16602eb7e6a9794a7e042f376` (the run's own headSha and inputs: preset original, vms 3). It downloaded 4 pieces and filed
19 artifacts under key `2ef4f3d8966c` in 24 s (14 objects new); a second call printed `cached`.

## Not done (follow-ups)

- `fw ci` (`apps/runner/src/ci.ts:115`) already downloads only `chromium-counts-*` and `chromium-classes` in one call (5.5 MB,
  9.5 s); it keeps the 40 s default and has no retry.
- Existing store entries from before this change hold `fwcore`, `site-dist` and image artifacts; they are not rewritten.

## Original target (WebKit)

An original WebKit run names its VMs `v1..vN` (`SimPlan.origCell`; artifact `webkit-sim-v<i>`) and has the merge job's
`webkit-classes` artifact; a rewrite run names them `r<i>` (`rewCell`). `downloadPieces .webkit .original n` gives
`webkit-sim-v1..vN`, `webkit-classes`, `telemetry-*`. Theorems `webkit_original_downloaded`, `webkit_rewrite_downloaded` and
`webkit_original_classes` tie the patterns to the SimPlan cells. No original-target 3-VM run was re-filed; the golden case
(download.jsonl) and the runner test show the plan, not a live download.
