---
id: 2026-11-03-touch-window-loss
kind: note
title: "Lost touch-lock windows: 1458 of 2016 planned windows lost over 7 smoothness runs; the restart chain loses most, refusals second, and the verdict-ready jobs are 2 of 84"
status: review
created: 2026-11-03
topics: [webkit, simulator, touch, measure, ci]
---

# Touch window loss

Task `touch-window-loss`, branch `worktree-wf_5bf9b435-920-1`. No new CI: the seven `smoothness` runs 41391781282, 41402584809, 41422536168,
41436626306, 41460411752, 41475879793, 41503168296 (12 job slots each, 24 planned windows per job, 2016 in all). Tables: `results/touch-window-loss/window-loss.md`
and `.json` (made by `packages/measure-webkit/src/window-loss-cli.mjs --root <downloaded artifacts> --out results/touch-window-loss`). The Simulator is not the phone.

## Method

- CONFIRMED (code): every planned window `i` of a job is the slot `repOrder(i / 4)[i % 4]`. A recorded row gets a class from its `status` and the refusal of its frames
  (`rowClass`, Lean `WindowLoss.rowClass`). A window with no row gets the class of how the job ended (`endClass`: the `INCOMPLETE (...)` reason in `sim.log` when present, else the
  artifact's `incomplete`, because `touch-lock.json` is rewritten after each window with "walk not finished" even when the hard stop killed a job that logged the real reason).
  A job with no artifact is `noArtifact`. Lean proves the class counts of a job sum to 24 (`jobCounts_total`), of a run to `jobs * 24` (`runCounts_total`), of an arm to 6
  (`armCounts_total`), and harness + simulator + ok = the total (`side_partition`). TS replays 43 Lean golden lines (`window-loss.test.mjs`).
- MEASURED: row arm equals the slot arm in all 78 artifacts (`armMismatch` 0). A `-retry` artifact replaces its slot (6 slots). 6 slots have no artifact: 41391781282 job 10 (upload failed),
  41402584809 jobs 7 (cancelled) and 9 (failed), 41436626306 jobs 1, 2 (cancelled), 41460411752 job 3 (cancelled).
- The earlier note counted status `ok` windows only. Here `ok` is a window the verdict keeps (status ok and `refusal` none); `noOpen`, `tooShort`, `lockMoved` are status-ok windows `touchlock.refusal` rejects.

## Result (MEASURED, all 7 runs)

| class | windows | share | side |
|---|---|---|---|
| ok (kept) | 558 | 27.7% | ok |
| restartFailed | 408 | 20.2% | simulator |
| noOpen | 248 | 12.3% | harness (INFERRED) |
| noArtifact | 144 | 7.1% | harness (CI job) |
| inspectorDead | 133 | 6.6% | simulator |
| walkDeadline | 121 | 6.0% | harness |
| planShort | 100 | 5.0% | harness |
| driverNotReady | 96 | 4.8% | simulator |
| tooShort | 75 | 3.7% | harness (INFERRED) |
| evaluateTimeout | 73 | 3.6% | simulator |
| jobCut | 38 | 1.9% | harness |
| pageLost, swipeLate, beginLate | 13, 8, 1 | 1.1% | simulator |

Sides: ok 558, harness 726, simulator 732 of 2016. Per run (288 planned): ok 71, 46, 66, 105, 80, 94, 96 in run order above; per job and arm in the md. Run 41503168296 loses 192
of 288 once refusals count (the earlier note's 143 counted status-ok windows as kept).

Job-end causes behind the no-row classes (`touch-lock.json` `incomplete`, `sim.log` INCOMPLETE line):
- restartFailed: "fault lost-mid-walk: restart failed: push server: no ready file after N s" (41503168296 sim-2 `sim.log:17`, launch `driver-launch-stuck@470s`), or a restart still in flight when the 2070 s hard stop fell.
- driverNotReady: "fault touch-driver-not-ready: push server: no ready file after 505 s" (41475879793 sim-3 `sim.log:15`; 41402584809 sim-2 `sim.log:28`): 4 jobs, 0 rows.
- inspectorDead: "rebooting the Simulator once: the inspector is dead (socket up, proxy down, page missing)" (41503168296 sim-5 `sim.log:30`, sim-12 `sim.log:21`) and the reboot then failed.
- evaluateTimeout: a deadline cut after "Runtime.evaluate timed out after 120000 ms" (41503168296 sim-12 `sim.log:15`).

## The restart chain (MEASURED, TS glue from sim.log)

36 of the 78 artifact jobs stalled and restarted the push server at least once (38 restarts). Stall kinds: pageLost 18, swipeLate 10, "ok" (done file late, `doneInTime` false) 8, beginLate 2.
After the first stall, 494 windows were lost and 9 ran ok. The push server became ready after 7 of the 38 restarts (118 to 434 s, median 310 s); the rest ran into the 470 s launch cut or the deadline.

| first stall | jobs | lost after | ok after | ready after (s) |
|---|---|---|---|---|
| pageLost | 17 | 240 | 0 | 310, 266, 118 |
| ok | 7 | 72 | 2 | 434 |
| swipeLate | 10 | 145 | 7 | 243, 389 |
| beginLate | 2 | 37 | 0 | never |

So a stall ends the job in practice: restart readiness is the Simulator limit the previous task closed (`11-03-touch-restart-device.md`). The windows after it are `restartFailed`,
`inspectorDead`, `evaluateTimeout`, `walkDeadline` and `jobCut` (a successful restart still costs up to 434 s of the 2400 s `deadlineAt`).

## The refusal layer (MEASURED; cause INFERRED)

323 windows (noOpen 248, tooShort 75) ran to status `ok` and were refused, 27% of the 881 status-ok windows. The share falls with the rep: noOpen/ran by rep 0 to 5 = 94/257, 71/205, 43/165,
29/132, 7/72, 4/50 (37% down to 8%). It is the same with and without a stall (83/312 vs 165/569) and in every run (27% to 42%). The window after a noOpen is a noOpen 43% (97 of 226) against 28% overall.
MEASURED earlier on the same artifacts: noOpen windows start the touch late (`obs.beginAt` median about 4 to 5 s against 1 to 2 s) and deliver fewer moves (40 to 47 against 76 to 78), and the page
stops about 676 px short of the end. INFERRED: a cold page or driver at the start of a job, which our rep order meets first (the arms are warmer by rep 2 and `orig`, always last in a rep, has the fewest noOpen: 43 of 199 ran, against 66 of 229, 71 of 226 and 68 of 227 for base, lock, pin).

## Sufficiency and jobs needed (MEASURED rates, WalkBudget names)

Per job, sufficient = every arm has at least `minKept` (5) kept windows. Over 84 slots (missing artifacts count as not sufficient):

| criterion | jobs | `jobsFor(minSamples, a, 84, target)` |
|---|---|---|
| every arm at minKept kept (refusals applied) | 2 of 84 | not reachable within `jobsCap` 30 |
| every arm at minKept status-ok | 15 of 84 | 23 |
| every arm at minSamples (3) kept | 16 of 84 | 22 |

The plan assumes `jobsNeeded` 10 (rate 2/5); `lateRate` 5/15 gives `lateJobs` 12. At the measured rates 12 jobs are far short, with `margin` 7 spare. Per run, 41436626306 alone reaches 5 of 12 (status ok), which is `jobsNeeded` 10.

## The single change that recovers the most windows

Counterfactual upper bounds (INFERRED; each assumes the lost windows would have run like a kept one):

| lever | kept windows | sufficient jobs of 84 |
|---|---|---|
| today | 558 | 2 |
| every refused window rerun ok (retry in place) | 881 | 15 |
| every window after the first stall ran ok | 1052 | 16 |
| both | 1370 | 48 |

By windows the stall chain (494) is larger than refusals (323), but its cause is the Simulator limit (restart readiness) and no harness change has evidence yet. The largest loss a harness
change can reach is the refused windows. Recommended change (follow-up, not made here): a window whose row is status `ok` but `refusal` is `noOpen` or `tooShort` is rerun from a fresh load at the
same slot, up to 2 more times while the deadline allows, and the rerun replaces the refused row. Code path: `packages/measure-webkit/src/touchlock-run.mjs:139-148` (the attempt loop that calls `oneWindow`; add the
refusal test before `rows.push(got)` at line 148) with `refusal` from `touchlock.mjs:44`. The `walk-budget` plan must price it: each rerun is a window (about 40 to 60 s). At the measured 63% keep rate
two reruns recover about 280 of the 323 if refusals were independent (they are not: the next window after a noOpen is a noOpen 43% of the time), so expect less. It does not move the stall chain (lines 100-113): a job
that stalls still ends, so the jobs needed stay at 23 unless the chain is also reduced. A warm-up window before rep 0 is the alternative with the same code path.

## What this note does not show

- The cause of noOpen (cold start vs touch timing) was not isolated; no CI was run.
- `noArtifact` is CI infrastructure (cancelled, upload failed), classed harness for the split only because it is not a Simulator fault.
- TS stand-ins (not golden-checked): `logFacts`, `restartTally`, `firstStall`, `jobOf` and the CLI (reading `sim.log` and the artifact), and the lever and first-stall tables.
