---
id: 2026-10-2x-unthrottle-parts-measure
kind: note
title: "unthrottle-parts on the CI Simulator: hero confirmed over 3 jobs (both flags lift it), commission gains but is not the predicted pulses, platform never exercised"
status: review
created: 2026-10-24
topics: [lag, webkit, ios-toolbar, scroll-driven, engine.scroll, measure, phone]
---

# Per-part throttle predictions measured on the CI Simulator

Task `unthrottle-parts-measure`. Predictions: `10-2x-unthrottle-parts.md` (Lean `Fw.Device.ThrottleParts`, golden
`packages/contracts/golden/device/throttle-parts.jsonl`). Reducer: `packages/measure-webkit/src/throttle/parts.mjs`,
checked against that golden in `test/throttle-parts.test.mjs`. Summaries: `results/unthrottle-parts/`.

## Answer first

- **Hero (hero.exit) agrees with the Lean prediction in all four arms, over 3 separate CI jobs.** MEASURED. Run
  40098348176, 6 usable passes per arm. Throttled arms show still runs of 5-6 frames; both lifting arms remove them.
- **`engine.scroll:throttle-lift` and `engine.scroll:unthrottle` give the same hero result.** MEASURED: 6 band runs in
  3585 and 3596 mid-moving frames (hero value strictly between 0 and 1000 while the toolbar moved; 1.7 per 1000), against
  37.4 for the rewrite; per 1000 moving frames 1.4 against 32.4. Verdict `lifted` for both.
- **Commission gains from the lift, but Lean predicted the wrong pattern for it.** MEASURED, rest run 40101702393, 3 jobs:
  the rewrite shows 23 band runs in 753 mid-moving frames (30.5 per 1000) where Lean (`pulses`, a chase) predicts fewer
  than 10; lift shows 0 in 729 and unthrottle 1 in 985, both verdict `lifted`. The Lean part verdict is `disagree`
  (rewrite and original arms). Per job the rewrite has 10, 13 and 0 band runs; the third job's rewrite passes recorded
  only 50 mid-moving frames, so two jobs carry the result (named, not a 3-job claim).
- **People agrees on the rewrite and both lifted arms, disagrees on the original arm.** MEASURED, rest, 3 jobs: 0 band
  runs in 1741, 1639 and 1641 mid-moving frames. The original arm has 18 in 1467 (12.3 per 1000); per job 4, 8 and 6, so
  it crosses 10 only in the pool (the threshold is on the pooled sum). The original runs different code from the modeled
  part, so this is a reference reading, not a refutation of the rewrite (INFERRED).
- **Platform has no data.** Drag and finish modes never showed a mid value; in rest mode the platform anchor was not found
  on any of the 3 jobs, so its 3 passes per arm were skipped. Cause unknown; follow-up.
- **Finish mode gave nothing but capture reversal counts.** Hero, people, commission and platform are exited or not yet
  reached in the finish zone; the fade shows 4 frames per pass. No arm has 3 jobs (named, not claimable).
- **CI and phone agree on the direction of hero still runs and max step, not on stall counts.** See the phone section.

## Method

- Arms: original, rewrite, lift (`throttle-lift`), unthrottle (the shipped text). Original and rewrite are throttled
  mode; lift and unthrottle are lifted mode (the Lean `predicted(mode, source, shape)` inputs).
- A page-side rAF recorder stores six custom-property series next to scrollY: hero `--exit-opacity`, people
  `--future-shrink`, commissionEnter `--commission-enter-shrink`, commission `--commission-shrink`, platform
  `--platform-shrink`, fade `--morph-fade`.
- Still run: consecutive frames with the same shown value, counted while the series is strictly between 0 and 1000 and
  the toolbar was moving. Band: 5-6 frames at 60 Hz. The reducer uses a cadence-aware band [K, K+1], K from the median
  frame gap (`throttleK`). Lean `bandFor` states it, with `bandFor_60hz : bandFor 1667 = (5, 6)`; the reducer's `bandFor`
  replays the golden `bandFor` lines.
- Verdict per lifted arm: Lean `verdict` against the rewrite (`lifted` needs rewrite runs at least 10 and a rate at
  most a fifth of it).
- Agreement rule, Lean `judge` (`Fw.Device.ThrottleParts`), replayed from the golden (240 judge lines) by `parts.mjs`:
  a throttled arm of a stills part agrees at 10 or more band runs; a lifted arm of a stills part agrees when
  `StillRuns.verdict [] base arm = lifted`; pulses and no-stills agree below 10 band runs; an arm without mid-moving
  frames is no-data. Per part, Lean `partVerdict`: any disagreement decides, else an agreement (partial when an arm has
  no data), else no-data. **Boundary:** the stills test is `10 <= runs`, the pulses and no-stills test is `runs < 10`, so
  exactly 10 band runs agrees for a stills part and disagrees for a pulses part (theorems `judge_stills_throttled_agree`,
  `judge_none_boundary`). Commission is predicted pulses; its rewrite arm at exactly 10 therefore falls on disagree.
- Modes: `drags` (hero drag mode, the toolbar-throttle lane), `finish` (sim-finish-throttle's finish mode), `rest`
  (my addition: the page is placed 60 px above the first ramp the page finds, anchors people, commissionEnter, platform
  by round, 3 rounds) so that the rest-zone parts are exercised. The lane yml on this branch reproduces all three runs
  (`parts-cli.mjs`, four arms, `[throttle:rest]`, `ROUNDS`, timeouts 75 and 58 minutes).

## Hero, drag mode (run 40098348176, 3 jobs, 6/6 usable passes per arm)

| arm | band runs / mid-moving frames | per 1000 mid-moving | stalls per 1000 pairs | max step | verdict | predicted | match |
|---|---|---|---|---|---|---|---|
| original | 38 / 2818 | 13.5 | 192.3 | 175 | reference | stills | agree |
| rewrite | 139 / 3714 | 37.4 | 133.4 | 67 | reference | stills | agree |
| lift | 6 / 3585 | 1.7 | 154.9 | 42 | lifted | no-stills | agree |
| unthrottle | 6 / 3596 | 1.7 | 146.6 | 50 | lifted | no-stills | agree |

- Per job, rewrite 50, 43, 46 band runs against lift 2, 3, 1 and unthrottle 0, 4, 2: the effect holds on every job.
  MEASURED.
- Median frame gap 17 ms (60 Hz), so the 5-6 band is in its domain.
- The rewrite has more still runs than the original (37.4 vs 13.5). MEASURED, same order on the phone (below). The cause is
  not established here (the original also has fewer mid-moving frames, 2818 vs 3714).
- In drag mode people, commission and platform had no mid value and fade was never found (the page is at the top), so
  those four parts are no-data in this mode. That is an expected property of the mode, not a defect.

## Per part, all modes

| part (series) | Lean predicts | drags | finish | rest | verdict (Lean `partVerdict`) |
|---|---|---|---|---|---|
| hero.exit (hero) | stills throttled, none lifted | 4 arms measured, 3 jobs | no mid values | no mid values | agree, MEASURED |
| people.card (people) | pulses throttled, none lifted | no mid values | no mid values | 18/1467, 0/1741, 0/1639, 0/1641 (3 jobs) | disagree on the original arm only; rewrite and both lifted arms agree |
| commission (commissionEnter, commission) | pulses throttled, none lifted | no mid values | no mid values | 14/883, 23/753, 0/729, 1/985 (3 jobs, 2 with frames) | disagree (rewrite and original show stills); both lifted arms `lifted` |
| platform.shrink (platform) | stills throttled, none lifted | no mid values | no mid values | anchor not found, passes skipped | no-data |
| morph.panel (fade) | none (time based, not hit) | series never found | 0 band runs in 4 frames per pass (4 passes) | series never found | agree (partial), not claimable |

Rest-mode cells are band runs / mid-moving frames per arm in the order original, rewrite, lift, unthrottle.
Finish mode: run 40101695202 (attempt 1 summary and the rerun summary). Rest mode: run 40101702393.

**Threshold boundary (Lean `judge`, decided at exactly 10 band runs).** A stills part agrees at 10 or more band runs
(`10 <= runs`); a pulses or no-stills part agrees below 10 (`runs < 10`). So exactly 10 agrees for a stills part and
disagrees for a pulses part: `judge_stills_throttled_agree` and `judge_none_boundary`. The commission rewrite arm
sat at exactly 10 in the first reading (job 1 only, 2 passes); Lean puts that on disagree. The 3-job pool is 23, off the line.

Rest-mode detail (run 40101702393, MEASURED, 3 jobs, 6 usable passes per arm; 3 platform passes per arm skipped):

| series | arm | band runs / mid-moving frames | per 1000 mid-moving | stalls per 1000 pairs | max step | verdict |
|---|---|---|---|---|---|---|
| people | original | 18 / 1467 | 12.3 | 6.8 | 134 | reference |
| people | rewrite | 0 / 1741 | 0 | 4.5 | 70 | reference |
| people | lift | 0 / 1639 | 0 | 4.4 | 83 | no-data (base below 10) |
| people | unthrottle | 0 / 1641 | 0 | 3.7 | 96 | no-data (base below 10) |
| commission | original | 14 / 883 | 15.9 | 60.4 | 189 | reference |
| commission | rewrite | 23 / 753 | 30.5 | 4.9 | 152 | reference |
| commission | lift | 0 / 729 | 0 | 9.3 | 53 | lifted |
| commission | unthrottle | 1 / 985 | 1.0 | 18.8 | 115 | lifted |

Commission per job (band runs / mid-moving frames): rewrite 10/349, 13/354, 0/50; lift 0/342, 0/348, 0/39; unthrottle
1/332, 0/367, 0/286; original 6/324, 4/298, 4/261.

- People has no band runs in the rewrite, so the lifted arms are `no-data` for the verdict; they match the prediction
  (none). The original's 18 are the only people reading above the line.
- `commissionEnter` and `commission` are the same rows: the two custom properties move together in the recording.
- The commission rewrite has band stills where people (also a chase in Lean) has none. INFERRED: commission's writer
  is not a pure chase on the toolbar-moving range, so its Lean class (`chase`, predicted `pulses`) should be revisited
  (follow-up, not changed here).

Finish mode (run 40101695202, MEASURED): attempt 1 gave one original and one rewrite pass from job 1; the rerun
(attempt 2) gave one original pass (job 2) and one lift pass (job 3); job 1 stalled at start in the rerun, job 2's
rewrite pass timed out, job 3's original and rewrite failed (`simctl list devices` ETIMEDOUT) and its unthrottle touch driver timed out. No unthrottle pass delivered data.
The only series with frames is the fade (4 frames per pass, 0 band runs). Capture reversals while the morph is open:
original 4 and 4, rewrite 6, lift 6.

## Phone comparison

Source: `results/phone/2026-10-24-throttle-lift/summary.json` (read, not re-measured). The phone counts stalls over
the whole pass; CI counts per 1000 frame pairs (consecutive frames) of the drag, so only the order across arms is compared.

| arm | phone hero stalls (per pass) | phone hero max step | CI hero stalls per 1000 frame pairs | CI hero max step |
|---|---|---|---|---|
| original | 115 and 109 | 587 and 683 | 192.3 | 175 |
| rewrite | 122 | 338 | 133.4 | 67 |
| lift | 64 (look pass) | 204 | 154.9 | 42 |
| unthrottle | not on the phone pass list | | 146.6 | 50 |

- Hero band runs per exit frame on the phone (the phone summary's exit frames), against band runs per mid-moving frame on
  CI (same kind of count, restricted to the toolbar-moving class; the classes are not identical, INFERRED). Phone: original 29/717 and 27/812 (about 33-40 per 1000), rewrite 90/1200 and
  28/280 (75-100 per 1000), lift 0-6 per 263-1415 frames (about 0-4 per 1000). CI per 1000 mid-moving: 13.5, 37.4, 1.7. Same order and
  same verdict (`lifted`); the CI rates are about 2.5-3x lower. MEASURED on both.
- Max step shrinks original, rewrite, lift on both. Agree.
- **Stall counts do not agree.** The phone lift pass halves hero stalls (122 to 64); on CI the lifted arms keep
  stalls per 1000 pairs at the rewrite's level (133 to 155 and 147). MEASURED. INFERRED reason: the CI Simulator
  frame pacing has its own stalls (CPU-bound Simulator, no real compositor), which the lift does not touch; the
  phone's stalls come with the throttle freeze. The still-run count and max step are the transferable CI signals;
  the stall count is not.
- Fade on the phone: 0 stalls, max step 1000 in every pass, 0 band runs. CI fade: 0 band runs (4 frames). Both agree
  with the Lean class (time based, not hit).
- People on the phone: 25, 21, 23, 14 stalls, max step 219, 172, 161, 217. CI rest: max step 134, 70, 83, 96.
  Directionally the same order, different scale; the phone pass is a long scroll, the CI pass a short anchor.

## Follow-up list: parts that gain

1. **hero.exit**: gains from both `throttle-lift` and `unthrottle` (rate down by a factor of 22). Already the shipped
   target; nothing more to do for the engine flag.
2. **commission**: gains (23 to 0 and 1 band runs per about 750 to 985 frames; verdict `lifted` for both flags). Its Lean
   class predicted `pulses`; reclassify (follow-up) and measure on a third job with frames.
3. **platform.shrink**: Lean predicts a gain, but the series was never mid in drag or finish mode, and the rest-mode
   anchor was not found. Find why (the writer is gated only for variant `mq`, not the default; the anchor search or the
   40 px scan step; a position beyond maxY 5267), then measure.
4. **people.card**: no gain visible on the rewrite and none predicted; the original arm's 18 band runs are a reference
   reading. Keep for the phone.
5. A part verdict that ignores the original arm (the original is not the modeled code) would turn people.card to agree;
   a Lean change to `partVerdict`, not made here.

No-data parts (named, by reason; the recorder does not store them): the harmless and not-hit parts of the golden with
shapes `step-look`, `step-idle`, `no-read`, `capture` (morph.mount, morph.tween) and the threaded sources
(hero.exit threaded variant). Capture parts have a supplementary reading only: scrollY reversals while the morph is
open, finish mode: original 4 and 4, rewrite 6, lift 6. Not a verdict.

## Limits and lost passes

- Finish mode: see the finish paragraph above. The reruns (`gh run rerun --failed`, no dispatch) added jobs 2 and 3; job 1
  stalled at start again. Finish passes run near 28 fps on CI (33-38 ms gaps), outside the 5-6 band's domain; the
  cadence-aware band [K, K+1] with `bandFor` is used and named. Finish has no arm with 3 jobs: not claimable.
- Rest mode: after the rerun all 3 jobs delivered 6 usable passes per arm (job 1 from attempt 1). The 3 platform passes
  per arm were skipped on every job (anchor not found). Job 3's commission passes recorded few mid-moving frames
  (50, 39 and 286 of rewrite, lift, unthrottle).
- Hero finish mode has no mid values: hero is exited by the time the finish zone starts. Expected.
- Three dispatches were the cap and were used; the reruns of failed jobs are not dispatches.
- The pooled threshold: the 10-run line is on the sum over a pool, so a larger pool crosses it more easily (people
  original: 4, 8, 6 per job, 18 pooled). Named; the Lean `judge` is not per-job.
- The phone is not re-measured. Touch-driver retries (suffix `-a2`) and warm-up stalls may lose passes; they are listed
  in each summary table's lost-reasons block.
- TS stand-ins (no Lean golden, reporting only, no verdict): the no-data reasons (`noDataReason`), the capture reversal
  count (`captureRow`). `judge`, `partVerdict` and `bandFor` are Lean-defined and replayed from the golden.
