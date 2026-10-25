---
id: 2026-10-2x-morph-end-remeasure
kind: note
title: "Morph end bricks re-measured on the merged throttle path: on like-for-like first stretches release is a trade (fewer re-open fights, more still runs), all three and all three + unthrottle win, clamp and flip do not"
status: review
created: 2026-10-25
topics: [morph, end-of-page, touch, simulator, webkit, bricks, ci, pin]
---

# Morph end bricks re-measured on the merged throttle path

## Answer

- MEASURED: three runs of the merged `[throttle:morph-end]` path (40158609202, 40167641467, 40193540518) give at least 4 usable passes for every composition (table below). Lean decides the verdict (`Fw.Measure.MorphEndCount.verdictOf`) on like-for-like exposure: the first open stretch of every pass, one open start per pass on both sides, against the faithful passes of the same jobs, and the finish still runs per job. Result: **clamp no-win, flip no-win, release trade, all three win, all three + `engine.scroll:unthrottle` win**, the wins on the first stretch only. Release is a trade because its 1-9 frame still runs per 1000 frames are higher than the faithful pass of the same job in all 4 jobs (34.8 against 23.0 pooled over those jobs; 24.7 over all 13 faithful passes: a1 43.8 v 25.6, b7 33.2 v 27.8, c5 41.2 v 17.0, c7 27.2 v 23.2); `all` is lower in two jobs and higher in two, so it is not worse in every job.
- MEASURED: whole-pass rates show release, all and all+unthrottle as wins, but that is an exposure effect. A release-type pass has one open start (the first stretch), a faithful pass has four, and the later faithful stretches fight more (4.13 reversals and 2.13 pin turns against 2.46 and 1.46 on the first stretch, n 39 and 13). Compared first stretch against first stretch the reversals overlap (release-type 1 per stretch, the close; faithful 0 to 5 per stretch), so reversals are no win. The spring-back fights (writes against the finger) are 0 in all 17 release-type first stretches against 1 to 5 in the faithful ones (same-job faithful mean 2.25 to 3.00), which is what the Lean verdict counts as lower. On the other fight reading, pin turns (TouchLock fights per first stretch) the release-type passes are 0 in every pass and the faithful ones 0 to 3, so they overlap and the three bricks would be no-win; the spring-back reading is the Lean unit, the pin-turn reading is stated as the sensitivity.
- MEASURED: only `engine.scroll:unthrottle` lifts the still runs (1-9 frame runs per 1000 frames 4.2 against 24.7 to 34.8 for every other composition).
- MEASURED: clamp has nothing to clamp: its first write sits at 5220 to 5226 (maxScrollY 5227 or more) and its re-open fights are the faithful page's (3.46 against 3.50 per open start, overlap). Flip is higher than faithful in push 3 (n 3 against 2) and overlaps when pooled (n 7 against 3).
- MEASURED, pin: the stored pin (first `scrollTo` while open) sits at 5183 to 5279 (median 5222 faithful, clamp 5220 to 5226, flip median 5220) and at or under maxScrollY (+1 px) in 100 of 104 stretches, while the scrollY at the open frame ranges 5184 to 5342 (median 5228, 77 of 123 above that frame's maxScrollY, median +29 px). The two notes read different quantities. See "The pin" below.
- MEASURED: after the first close the release-type page drifts away from the end (min scrollY 3513 to 4067 px in all 19 release, all and all+unthrottle passes with a record, 4953 px or more in every other pass) under the same 12 touches, so later stretches never happen; the cause of the drift is untested. It is a difference between the pages that no count above measures and it goes to the phone review.
- Lost work: 3 of the 10 push-3 jobs were lost runners (sim 1, 3, 10: "hosted runner lost communication" after 94, 104 and 80 min, no artifact), sim 2 ended exit 130 (our watchdog) with one usable pass. Task `macos-vm-evidence` owns the fix; its checked investigation found no telemetry for any lost job, cause unknown.

## Tables

Pooled over run 40158609202 (jobs 1, 2: partial, 4 six-arm jobs lost to frozen runners and the 90 min step), run 40167641467 (jobs 1, 3 to 10; job 2 failed at 90 min, job 9 cancelled but its artifact exists) and run 40193540518 (jobs 2, 4 to 9). Four drag cycles per pass, finish lane, Simulator page 430 x 775 at dpr 3 with real XCUITest touches. Full tables: `results/morph-end-remeasure/pooled-runs-40158609202-40167641467-40193540518.md` (all jobs), `.../run-40193540518.md` (push 3 alone).

| Composition | Usable passes (push 3 alone) | Faithful passes in those jobs | Open starts | Reversals per open start | Fights per open start | Reversals / fights per 1000 finish-zone frames | 1-9 frame still runs per 1000 frames | Closes (finger down) / re-opens (finger up) | Whole-pass context (not the decision) |
|---|---|---|---|---|---|---|---|---|---|
| faithful (rewrite) | 13 (6) | - | 52 | 193 / 52 = 3.71 | 168 / 52 = 3.23 | 10.2 / 8.9 | 24.7 | 52 / 39 | base |
| clamp | 6 (0) | 4 | 24 | 4.25 (faithful 4.38) | 3.46 (3.50) | 11.9 / 9.6 | 30.6 | 24 / 18 | whole-pass overlap, overlap |
| flip | 7 (3) | 3 | 28 | 4.36 (3.08) | 3.29 (2.75) | 12.3 / 9.3 | 28.0 | 28 / 21 | whole-pass overlap pooled; higher, higher in push 3 |
| release | 7 (3) | 4 | 7 | 1.00 (3.81) | 0.00 (3.25) | 2.1 / 0 | 34.8 | 7 / 0 | whole-pass lower, lower (exposure effect, see below) |
| all three | 4 (2) | 4 | 4 | 1.00 (4.00) | 0.00 (3.50) | 1.8 / 0 | 26.4 | 4 / 0 | whole-pass lower, lower (exposure effect) |
| all three + unthrottle | 6 (3) | 5 | 6 | 1.00 (3.95) | 0.00 (3.35) | 1.3 / 0 | 4.2 | 6 / 0 | whole-pass lower, lower (exposure effect), still runs lifted |

Run ids: faithful in every job except push-3 job 9; clamp only in runs 40158609202 and 40167641467 (push 3 dropped it, 6 passes there); push-3 passes per composition: faithful 6, flip 3, release 3, all 2, all+unthrottle 3. The "per open start" columns are the Lean unit; per 1000 frames is a cross-check (the zone frames of release arms are 1/3 of the faithful ones because the finger never returns to the end after the first stretch). The "faithful" figures in brackets come from the passes of the same jobs only (TS stand-in: the selection of faithful passes in the same job, `morph-end-report.mjs` `brickRow`).

Decision table: the first open stretch of each pass, one open start per pass on both sides (Lean `perStretch`), against the faithful passes of the same jobs, and the still runs job by job (`results/morph-end-remeasure/pooled-runs-40158609202-40167641467-40193540518.md`, last table; the report calls `verdictOf`):

| Composition | First stretches (brick / faithful in the same jobs) | Reversals in the first stretch (faithful) | Spring-back fights in the first stretch (faithful) | Reversals / fights vs faithful | 1-9 frame still runs per 1000 frames, per job (faithful of the same job) | Still runs | Lean verdict |
|---|---|---|---|---|---|---|---|
| clamp | 5 / 4 | 3.40 (3.75) | 3.00 (3.50) | overlap / overlap | a1 30.6 (25.6), b1 30.1 (12.7), b3 24.0 (26.2), b8 33.8 (31.8) | not worse in every job | no-win |
| flip | 7 / 3 | 3.00 (1.67) | 2.71 (2.00) | overlap / overlap | b1 25.5 (12.7), c5 29.3 (17.0), c7 30.8 (23.2) | worse in every job | no-win |
| release | 7 / 4 | 1.00 (2.25) | 0.00 (2.25) | overlap / lower | a1 43.8 (25.6), b7 33.2 (27.8), c5 41.2 (17.0), c7 27.2 (23.2) | worse in every job | trade |
| all three | 4 / 4 | 1.00 (2.25) | 0.00 (2.75) | overlap / lower | b10 16.0 (27.4), b7 24.1 (27.8), c6 33.9 (28.5), c8 27.2 (24.6) | not worse in every job | win |
| all three + unthrottle | 6 / 5 | 1.00 (2.80) | 0.00 (3.00) | overlap / lower | b10 11.4 (27.4), b8 2.2 (31.8), c4 1.5 (29.1), c6 4.8 (28.5), c8 7.8 (24.6) | lifted | win |

Sensitivity: against all 13 faithful first stretches (not only the same jobs) the verdicts are the same (release trade, the others as above); the spring-back fights of the faithful passes are 1 to 5, those of every release-type pass 0. On pin turns (TouchLock fights, below) the reading is different, see the Answer.

First stretch against later stretches (lock reducer, `results/morph-end-remeasure/pins.md`):

| Arm | Stretches | Reversals mean | Pin turns mean (TouchLock fights) | Displaced frames median |
|---|---|---|---|---|
| faithful first | 13 | 2.46 | 1.46 | 3 |
| faithful later | 39 | 4.13 | 2.13 | 9 |
| clamp first / later | 5 / 18 | 3.40 / 4.72 | 1.80 / 2.39 | 10 / 12 |
| flip first / later | 7 / 21 | 3.00 / 4.81 | 1.43 / 2.62 | 9 / 10 |
| release first | 7 | 1.00 | 0.00 | 0 |
| all first | 6 | 1.00 | 0.00 | 0 |
| all + unthrottle first | 6 | 1.00 | 0.00 | 0 |

The decision table compares first stretch against first stretch. Later stretches (4.1 reversals and 2.1 pin turns on the faithful page) are the re-open fights the bricks target and are not exercised by release-type arms: MEASURED, after the first close the release-type page drifts away from the end (min scrollY 3513 to 4067 px in all 19 release, all and all+unthrottle passes with a record, 4953 px or more in every other pass) under the same 12 touches, so later stretches never happen; the cause of the drift is untested. The open starts per pass are therefore 1 against 4, and a rate over whole passes mixes the first stretch of one side with all four of the other.

## Verdict per brick

Decided by Lean `verdictOf` (better: reversals or spring-back fights lower in every brick first stretch than in any faithful one, or the still runs lifted; worse: reversals or fights higher likewise, or the still runs higher than the faithful pass of the same job in every comparable job).

| Brick | Verdict | n (first stretches, brick / faithful) | Evidence |
|---|---|---|---|
| clamp | no-win | 5 / 4 | reversals and fights overlap the faithful page; the pin it caps is already at the end (MEASURED) |
| flip | no-win | 7 / 3 | reversals and fights overlap; the still runs are higher than faithful in all 3 comparable jobs, but nothing improves |
| release | trade | 7 / 4 | spring-back fights 0 against 2.25 (lower), reversals overlap; still runs 34.8 against 23.0 per 1000 frames, higher in all 4 jobs. First stretch only; the page then drifts from the end (untested cause) |
| all three | win (first stretch only) | 4 / 4 | spring-back fights 0 against 2.75, reversals overlap, still runs lower in 2 jobs and higher in 2 (26.4 against 26.9 pooled); n is small |
| unthrottle (added to all three) | win (first stretch only) | 6 / 5 | as above and 4.2 still runs against 28.1 (lifted, lower in all 5 jobs) |

Release is the one trade: it stops the writes against the finger in the first stretch and leaves more still runs than the faithful page. Whether `all` (the same three bricks) shows no such rise is a difference of 2 higher and 2 lower jobs and is not decided.

Every number is MEASURED on CI (Simulator, real XCUITest touches). Pooling per open start across the three runs is INFERRED to be sound (same cycles, same page); the faithful baseline differs between jobs, hence the same-job selection. The 4, 4 and 5 same-job faithful passes behind the three verdicts are few; the verdict rule needs every brick pass beyond every faithful pass.

## The pin at 5183-5279 against 5184-5342

Two different readings of "the pin".

- `10-2x-morph-end-measure.md` (run 40126807029 job 4) read the instant `scrollTo` writes while open (`rec.ca`): the stored pin the page applies. CONFIRMED in code: that is `pinAfter` (`apps/site/src/parts/morph.tween/end.logic.ts:61`, `isActive(s.tw) && !free(h, s) ? s.pin : r.scrollY`), the scrollY read when a push starts from an inactive panel. Here (104 stretches with a write): 5183 to 5279; faithful median 5222, clamp 5220 to 5226, flip median 5220; at or under maxScrollY (+1 px) in 100 of 104. MEASURED.
- `10-2x-morph-reopen.md` (5227 to 5330, median 5258) reads the scroll position at the open from rest. Here the scrollY at the first frame of an open stretch: 5184 to 5342, median 5228 over 123 starts, first opens of a pass median 5250, later opens 5226; 77 of 123 are above that frame's maxScrollY (maxScrollY 5191 to 5267, toolbar collapsed or expanded), median +29 px, up to +115 px. In 57 of 104 stretches the open frame is above the first write by more than 1 px. MEASURED.
- INFERRED: the push is accepted a frame or more before the open frame is recorded; the finger keeps carrying the page into the rubber band in between, so the stored pin sits at the real end while the page at the open frame is already past it. Both ranges occur in this one Simulator lane, so the Simulator versus phone is not the cause. Not tested: the lag between push and open frame (needs the push frame in the recorder).
- So clamp has little to do in this lane: the pin is at the end already (first write 5220 to 5226, `rec.ca` of 24 clamp stretches never above maxScrollY), but the page itself leaves the end by up to 115 px, which is the fight the pin then pulls back.

## Method and Lean

- Counting of closes and re-opens by finger direction, spring-back fights, and the brick verdict are specified and proved in `lean/Fw/Measure/MorphEndCount.lean` (theorems `counted_once`, `close_after_rise`, `reopen_after_fall`, `fight_up_lowers`, `fight_down_raises`, `brickVerdict_win`, `brickVerdict_win_iff`, `brickVerdict_trade_rev`, `brickVerdict_trade_fight`, `brickVerdict_trade_still`, `brickVerdict_noWin`, `stillWorseOf_iff`, `verdictOf_still_worse`, `rates_perStretch`, `verdictOf_self`; `brickVerdict` takes `stillWorse` beside `stillLifted`, and `stillWorseOf` decides it job by job); the golden `packages/contracts/golden/device/morph-end-count.jsonl` is replayed by `packages/measure-webkit/test/throttle-morph-end.test.mjs` against the twin `src/throttle/morph-end.mjs`.
- TS stand-ins left (not Lean-checked): the choice of faithful passes in the same jobs and the grouping of the still runs by job (`brickRow`), the selection of the first open stretch of a pass and its writes (`firstStretch`; the reducers it calls are the Lean twins), and the report glue. The rev and fight comparison pools the jobs (every brick first stretch against every faithful one of the same jobs); only the still runs are decided job by job.
- The merged path ran: `[throttle:morph-end]` on `toolbar-throttle.yml`, ten three-arm jobs in pushes 2 and 3 (faithful first, then two compositions in turn; push 1 had four six-arm jobs), max-parallel 3 (the Lean widths table), rotate 0.
- The touch-push lane: only the smoothness `[touch-lock]` job exists (arms orig/base/lock in `src/touchlock-cli.mjs`, outside this task's writes). Run 40158609210 (push 1): lock 1.0 fights and 1.25 reversals per run against base 2.0 and 3.5 and orig 2.2 and 3.8 (4, 4 and 6 accepted windows), `results/morph-end-remeasure/touch-lock-run-40158609210.md`. It is the flick lane's reference, not a per-composition measure.

## Limits

- The iOS Simulator stands in for the iPhone: the counts and still runs are engine and harness measures, not felt smoothness (phone step).
- Lost VMs: run 40193540518 sim 1, 3, 10 (lost communication after 94, 104 and 80 min), sim 2 exit 130 (our watchdog, likely blocked in a `simctl` call, one usable pass); run 40158609202 lost all four six-arm jobs; run 40167641467 job 2 failed at 90 min. Composition n above counts only usable passes (push-3 jobs 4 to 9 plus the earlier runs).
- Push-3 job 9 lost its faithful pass; its flip and release passes have no same-job faithful baseline and are not used in the verdict.
- `all` has 4 usable passes and 2 in push 3; reported with its n.
- At most 3 pushes (all used); free macOS runners shared and may queue (push 3 ran 7 h).
- Later-cycle behaviour of the release-type compositions is not exercised: the page drifts from the end after the first close and the cause is untested (see above). Their wins and trade are first-stretch verdicts.
- Why the open frame lags the stored pin stays INFERRED; testing it needs the push frame in the recorder (follow-up).

## Phone review (for the lead's step)

On the phone, drag past the end of the home page, release, drag back, on `/?fw=morph.end.release:on`, `/?preset=morph-end-all`, and `/?fw=morph.end.clamp:on,morph.end.flip:on,morph.end.release:on,engine.scroll:unthrottle`, against the plain page. Questions: does the panel still re-open when the finger drags back to the end a second time (the CI lane never reached it); does the page drift away from the end after the first close (the CI release-type page drops to scrollY 3513-4067 px in all 19 passes while the plain page stays at 4953 px or more; the cause is untested) and does that feel wrong; does the page feel steadier after release; does unthrottle make the drag smoother; does the release page show more stillness stalls than the plain page (more 1-9 frame still runs in all 4 comparable jobs). Clamp and flip need no review (no-win).
