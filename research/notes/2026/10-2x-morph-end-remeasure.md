---
id: 2026-10-2x-morph-end-remeasure
kind: note
title: "Morph end bricks re-measured on the merged throttle path: release and its compositions stop the re-open fights on the first stretch (win), clamp and flip do not (no-win); unthrottle alone lifts the still runs; no trade"
status: review
created: 2026-10-25
topics: [morph, end-of-page, touch, simulator, webkit, bricks, ci, pin]
---

# Morph end bricks re-measured on the merged throttle path

## Answer

- MEASURED: three runs of the merged `[throttle:morph-end]` path (40158609202, 40167641467, 40193540518) give at least 4 usable passes for every composition (table below). Verdict per brick against the faithful passes of the same jobs (Lean `Fw.Measure.MorphEndCount.verdictOf`): **release win, all three win, all three + `engine.scroll:unthrottle` win, clamp no-win, flip no-win**. No brick is a trade.
- MEASURED, with a limit: the three wins are first-stretch wins only. In every release, all and all+unthrottle pass the panel opens once and the finger never returns to the end in the later drag cycles (open starts 1 per pass against 4 for the faithful page), so 0 spring-back fights and 1 reversal per open start (the close) stand against 1.46 fights and 2.46 reversals on the faithful first stretch (n 13). Whether the panel re-opens when the user drags back later is not exercised by this lane (phone step).
- MEASURED: only `engine.scroll:unthrottle` lifts the still runs (1-9 frame runs per 1000 frames 4.2 against 24.7 to 34.8 for every other composition).
- MEASURED: clamp has nothing to clamp: its first write sits at 5220 to 5226 (maxScrollY 5227 or more) and its re-open fights are the faithful page's (3.46 against 3.50 per open start, overlap). Flip is higher than faithful in push 3 (n 3 against 2) and overlaps when pooled (n 7 against 3).
- MEASURED, pin: the stored pin (first `scrollTo` while open) sits at 5220 to 5226 (median 5222 faithful, 5223 clamp, 5220 flip) and at or under maxScrollY in 100 of 104 stretches, while the scrollY at the open frame ranges 5184 to 5342 (median 5228, 77 of 123 above that frame's maxScrollY, median +29 px). The two notes read different quantities. See "The pin" below.
- Lost work (named): 3 of the 10 push-3 jobs were lost runners (sim 1, 3, 10: "hosted runner lost communication" after 94, 104 and 80 min, no artifact), sim 2 ended exit 130 (our watchdog) with one usable pass. Task `macos-vm-evidence` owns the fix; its checked investigation found no telemetry for any lost job, cause unknown.

## Tables

Pooled over run 40158609202 (jobs 1, 2: partial, 4 six-arm jobs lost to frozen runners and the 90 min step), run 40167641467 (jobs 1, 3 to 10; job 2 failed at 90 min, job 9 cancelled but its artifact exists) and run 40193540518 (jobs 2, 4 to 9). Four drag cycles per pass, finish lane, Simulator page 430 x 775 at dpr 3 with real XCUITest touches. Full tables: `results/morph-end-remeasure/pooled-runs-40158609202-40167641467-40193540518.md` (all jobs), `.../run-40193540518.md` (push 3 alone).

| Composition | Usable passes (push 3 alone) | Faithful passes in those jobs | Open starts | Reversals per open start | Fights per open start | Reversals / fights per 1000 finish-zone frames | 1-9 frame still runs per 1000 frames | Closes (finger down) / re-opens (finger up) | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| faithful (rewrite) | 13 (6) | - | 52 | 193 / 52 = 3.71 | 168 / 52 = 3.23 | 10.2 / 8.9 | 24.7 | 52 / 39 | base |
| clamp | 6 (0) | 4 | 24 | 4.25 (faithful 4.38) | 3.46 (3.50) | 11.9 / 9.6 | 30.6 | 24 / 18 | no-win (overlap, overlap) |
| flip | 7 (3) | 3 | 28 | 4.36 (3.08) | 3.29 (2.75) | 12.3 / 9.3 | 28.0 | 28 / 21 | no-win (overlap pooled; higher, higher in push 3) |
| release | 7 (3) | 4 | 7 | 1.00 (3.81) | 0.00 (3.25) | 2.1 / 0 | 34.8 | 7 / 0 | win (lower, lower) |
| all three | 4 (2) | 4 | 4 | 1.00 (4.00) | 0.00 (3.50) | 1.8 / 0 | 26.4 | 4 / 0 | win (lower, lower) |
| all three + unthrottle | 6 (3) | 5 | 6 | 1.00 (3.95) | 0.00 (3.35) | 1.3 / 0 | 4.2 | 6 / 0 | win (lower, lower, still runs lifted) |

Run ids: faithful in every job except push-3 job 9; clamp only in runs 40158609202 and 40167641467 (push 3 dropped it, 6 passes there); push-3 passes per composition: faithful 6, flip 3, release 3, all 2, all+unthrottle 3. The "per open start" columns are the Lean unit; per 1000 frames is a cross-check (the zone frames of release arms are 1/3 of the faithful ones because the finger never returns to the end after the first stretch). The "faithful" figures in brackets come from the passes of the same jobs only (TS stand-in: the selection of faithful passes in the same job, `morph-end-report.mjs` `brickRow`).

First stretch against later stretches (lock reducer, `results/morph-end-remeasure/pins.md`):

| Arm | Stretches | Reversals mean | Fights mean | Displaced frames median |
|---|---|---|---|---|
| faithful first | 13 | 2.46 | 1.46 | 3 |
| faithful later | 39 | 4.13 | 2.13 | 9 |
| clamp first / later | 5 / 18 | 3.40 / 4.72 | 1.80 / 2.39 | 10 / 12 |
| flip first / later | 7 / 21 | 3.00 / 4.81 | 1.43 / 2.62 | 9 / 10 |
| release first | 7 | 1.00 | 0.00 | 0 |
| all first | 6 | 1.00 | 0.00 | 0 |
| all + unthrottle first | 6 | 1.00 | 0.00 | 0 |

The comparison that holds is first stretch against first stretch: release-type compositions 1.0 and 0 against 2.46 and 1.46. Later stretches (4.1 reversals and 2.1 fights on the faithful page) are the re-open fights the bricks target and are not exercised by release arms (INFERRED cause: after the first release the harness drag path no longer reaches the end in the release pass; one release pass, job 5, shows scrollY parked at 4108 px from frame 1200 on).

## Verdict per brick

| Brick | Verdict | n (usable, composition / faithful) | Evidence |
|---|---|---|---|
| clamp | no-win | 6 / 4 | fights and reversals overlap the faithful page; the pin it caps is already at the end (MEASURED) |
| flip | no-win | 7 / 3 | overlap pooled; higher than faithful in push 3 (5.58 reversals, 4.08 fights per open start against 3.50, 3.00; n 3 against 2) |
| release | win (first stretch) | 7 / 4 | 1.0 and 0 against 3.81 and 3.25; no re-open after the first release; later stretches not exercised |
| all three | win (first stretch) | 4 / 4 | same as release; still runs not lifted (26.4) |
| unthrottle (added to all three) | win | 6 / 5 | as above and 4.2 still runs against 24.7 |
| trade | none | | no composition improves one count while worsening another |

Every number is MEASURED on CI (Simulator, real XCUITest touches). Pooling per open start across the three runs is INFERRED to be sound (same cycles, same page); the faithful baseline differs between jobs, hence the same-job selection. The 4, 4 and 5 same-job faithful passes behind the three wins are few; the verdict rule needs every brick pass beyond every faithful pass, and they are.

## The pin at 5220-5223 against 5227-5330

Two different readings of "the pin".

- `10-2x-morph-end-measure.md` (run 40126807029 job 4) read the instant `scrollTo` writes while open (`rec.ca`): the stored pin the page applies. CONFIRMED in code: that is `pinAfter` (`apps/site/src/parts/morph.tween/end.logic.ts:61`, `isActive(s.tw) && !free(h, s) ? s.pin : r.scrollY`), the scrollY read when a push starts from an inactive panel. Here (104 stretches with a write): 5183 to 5279; faithful median 5222, clamp 5220 to 5226, flip median 5220; at or under maxScrollY (+1 px) in 100 of 104. MEASURED.
- `10-2x-morph-reopen.md` (5227 to 5330, median 5258) reads the scroll position at the open from rest. Here the scrollY at the first frame of an open stretch: 5184 to 5342, median 5228 over 123 starts, first opens of a pass median 5250, later opens 5226; 77 of 123 are above that frame's maxScrollY (maxScrollY 5191 to 5267, toolbar collapsed or expanded), median +29 px, up to +115 px. In 57 of 104 stretches the open frame is above the first write by more than 1 px. MEASURED.
- INFERRED: the push is accepted a frame or more before the open frame is recorded; the finger keeps carrying the page into the rubber band in between, so the stored pin sits at the real end while the page at the open frame is already past it. Both ranges occur in this one Simulator lane, so the Simulator versus phone is not the cause. Not tested: the lag between push and open frame (needs the push frame in the recorder).
- So clamp has little to do in this lane: the pin is at the end already (first write 5220 to 5226, `rec.ca` of 24 clamp stretches never above maxScrollY), but the page itself leaves the end by up to 115 px, which is the fight the pin then pulls back.

## Method and Lean

- Counting of closes and re-opens by finger direction, spring-back fights, and the brick verdict are specified and proved in `lean/Fw/Measure/MorphEndCount.lean` (theorems `counted_once`, `close_after_rise`, `reopen_after_fall`, `fight_up_lowers`, `fight_down_raises`, `brickVerdict_win`, `brickVerdict_trade`, `brickVerdict_noWin`, `verdictOf_self`); the golden `packages/contracts/golden/device/morph-end-count.jsonl` is replayed by `packages/measure-webkit/test/throttle-morph-end.test.mjs` against the twin `src/throttle/morph-end.mjs` (the TS stand-in of the earlier note is gone: the twin is checked against the Lean golden).
- TS stand-ins left (not Lean-checked): the choice of faithful passes in the same jobs (`brickRow`) and the report glue.
- The merged path ran: `[throttle:morph-end]` on `toolbar-throttle.yml`, ten three-arm jobs in pushes 2 and 3 (faithful first, then two compositions in turn; push 1 had four six-arm jobs), max-parallel 3 (the Lean widths table), rotate 0.
- The touch-push lane: only the smoothness `[touch-lock]` job exists (arms orig/base/lock in `src/touchlock-cli.mjs`, outside this task's writes). Run 40158609210 (push 1): lock 1.0 fights and 1.25 reversals per run against base 2.0 and 3.5 and orig 2.2 and 3.8 (4, 4 and 6 accepted windows), `results/morph-end-remeasure/touch-lock-run-40158609210.md`. It is the flick lane's reference, not a per-composition measure.

## Limits (named)

- The iOS Simulator stands in for the iPhone: the counts and still runs are engine and harness measures, not felt smoothness (phone step).
- Lost VMs: run 40193540518 sim 1, 3, 10 (lost communication after 94, 104 and 80 min), sim 2 exit 130 (our watchdog, likely blocked in a `simctl` call, one usable pass); run 40158609202 lost all four six-arm jobs; run 40167641467 job 2 failed at 90 min. The start-up stall is a named failure. Composition n above counts only usable passes (push-3 jobs 4 to 9 plus the earlier runs).
- Push-3 job 9 lost its faithful pass; its flip and release passes have no same-job faithful baseline and are not used in the verdict.
- `all` has 4 usable passes and 2 in push 3; reported with its n.
- At most 3 pushes (all used); free macOS runners shared and may queue (push 3 ran 7 h).
- Later-cycle behaviour of release is not exercised (see above).

## Phone review (for the lead's step)

On the phone, drag past the end of the home page, release, drag back, on `/?fw=morph.end.release:on`, `/?preset=morph-end-all`, and `/?fw=morph.end.clamp:on,morph.end.flip:on,morph.end.release:on,engine.scroll:unthrottle`, against the plain page. Questions: does the panel still re-open when the finger drags back to the end a second time (the CI lane never reached it); does the page feel steadier after release; does unthrottle make the drag smoother. Clamp and flip need no review (no-win).
