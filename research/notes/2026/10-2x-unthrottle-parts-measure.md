---
id: 2026-10-2x-unthrottle-parts-measure
kind: note
title: "unthrottle-parts on the CI Simulator: hero confirmed over 3 jobs (both flags lift it), commission a candidate, the other four parts not exercised"
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
- **Only hero is claimable.** The other four parts are no-data or a single job. Finish (run 40101695202) and rest (run
  40101702393) each have one VM with data, below the 3-job rule. Three dispatches were used; no rerun.
- **Commission is the only other part with a visible gain: 10 band runs per 349 frames (rewrite) to 0 and 1 (lift,
  unthrottle).** MEASURED on 1 job, 2 passes per arm. It is a follow-up candidate, not a result.
- **One prediction disagrees, borderline.** Commission is predicted `pulses` (chase), so a throttled arm should show
  fewer than 10 band runs. The rewrite shows exactly 10; original shows 6. The limit is the reducer's threshold
  (`MIN_BASE` 10), so one run decides it. INFERRED: this is noise at n=2 passes, not a refutation.
- **Platform never showed a mid value.** MEASURED: `--platform-shrink` was never strictly between 0.02 and 0.98 in any
  arm (original included) in a full-page scan on the iPhone-sized page. Cause unknown; follow-up.
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
  by round, 3 rounds) so that the rest-zone parts are exercised.

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

| part (series) | Lean predicts | drags | finish | rest | verdict |
|---|---|---|---|---|---|
| hero.exit (hero) | stills throttled, none lifted | 4 arms measured, 3 jobs | no mid values | not exercised | agree, MEASURED |
| people.card (people) | pulses throttled, none lifted | no mid values | no mid values | 4/485, 0/572, 0/512, 0/558 (1 job) | agree (few band runs everywhere), 1 job |
| commission (commissionEnter, commission) | pulses throttled, none lifted | no mid values | no mid values | 6/324, 10/349, 0/342, 1/332 (1 job) | disagree at exactly 10 for rewrite; both lifted arms `lifted` |
| platform.shrink (platform) | stills throttled, none lifted | no mid values | no mid values | never mid in any arm | no-data |
| morph.panel (fade) | none (time based, not hit) | series never found | 0/4 and 0/4 band runs (original, rewrite) | not exercised | agree, 4 frames only, not claimable |

Rest-mode columns are band runs / mid-moving frames per arm in the order original, rewrite, lift, unthrottle. Finish
mode: run 40101695202; rest mode: run 40101702393, 2 usable passes per arm, all from one job.

Rest-mode detail (run 40101702393, MEASURED, 1 job):

| series | arm | band runs / mid-moving frames | per 1000 mid-moving | stalls per 1000 pairs | max step | verdict |
|---|---|---|---|---|---|---|
| people | original | 4 / 485 | 8.2 | 6.0 | 134 | reference |
| people | rewrite | 0 / 572 | 0 | 4.5 | 70 | reference |
| people | lift | 0 / 512 | 0 | 4.2 | 64 | no-data (base below 10) |
| people | unthrottle | 0 / 558 | 0 | 3.5 | 34 | no-data (base below 10) |
| commission | original | 6 / 324 | 18.5 | 59.1 | 169 | reference |
| commission | rewrite | 10 / 349 | 28.7 | 7.2 | 152 | reference |
| commission | lift | 0 / 342 | 0 | 16.3 | 44 | lifted |
| commission | unthrottle | 1 / 332 | 3.0 | 25.1 | 75 | lifted |

- People has too few band runs in any arm for a verdict (the rewrite base is 0, below the 10 that `lifted` needs).
  This matches the Lean class (pulses: a chase, no 5-frame stills) and the phone's "few frames" read. The rows agree
  with the prediction; they do not show a gain.
- `commissionEnter` and `commission` are the same rows: the two custom properties move together in the recording.

## Phone comparison

Source: `results/phone/2026-10-24-throttle-lift/summary.json` (read, not re-measured). The phone counts stalls over
the whole pass; CI counts per 1000 frame pairs of the drag, so only the order across arms is compared.

| arm | phone hero stalls | phone hero max step | CI hero stalls per 1000 | CI hero max step |
|---|---|---|---|---|
| original | 115 and 109 | 587 and 683 | 192.3 | 175 |
| rewrite | 122 | 338 | 133.4 | 67 |
| lift | 64 (look pass) | 204 | 154.9 | 42 |
| unthrottle | not on the phone pass list | | 146.6 | 50 |

- Hero band runs per exit frame, phone: original 29/717 and 27/812 (about 33-40 per 1000), rewrite 90/1200 and
  28/280 (75-100 per 1000), lift 0-6 per 263-1415 frames (about 0-4 per 1000). CI: 13.5, 37.4, 1.7. Same order and
  same verdict (`lifted`); the CI rates are about 2.5-3x lower. MEASURED on both.
- Max step shrinks original, rewrite, lift on both. Agree.
- **Stall counts do not agree.** The phone lift pass halves hero stalls (122 to 64); on CI the lifted arms keep
  stalls per 1000 pairs at the rewrite's level (133 to 155 and 147). MEASURED. INFERRED reason: the CI Simulator
  frame pacing has its own stalls (CPU-bound Simulator, no real compositor), which the lift does not touch; the
  phone's stalls come with the throttle freeze. The still-run count and max step are the transferable CI signals;
  the stall count is not.
- Fade on the phone: 0 stalls, max step 1000 in every pass, 0 band runs. CI fade: 0 band runs (4 frames). Both agree
  with the Lean class (time based, not hit).
- People on the phone: 25, 21, 23, 14 stalls, max step 219, 172, 161, 217. CI rest: max step 134, 70, 64, 34.
  Directionally the same order, different scale; the phone pass is a long scroll, the CI pass a short anchor.

## Follow-up list: parts that gain

1. **hero.exit**: gains from both `throttle-lift` and `unthrottle` (rate down by a factor of 22). Already the shipped
   target; nothing more to do for the engine flag.
2. **commission**: candidate gain (10 to 0 and 1 band runs). Needs at least 3 jobs of rest mode to claim.
3. **platform.shrink**: Lean predicts a gain, but the series was never mid on this page in any arm. Find why the
   writer's ramp is never strictly between 0.02 and 0.98 in the scan (the writer is gated only for variant `mq`,
   not the default; a short ramp, a coarse scan step of 40 px, or a position beyond maxY 5267 are candidates), then
   measure.
4. **people.card**: no gain visible and none predicted (pulses); keep for the phone.

No-data parts (named, by reason; the recorder does not store them): the harmless and not-hit parts of the golden with
shapes `step-look`, `step-idle`, `no-read`, `capture` (morph.mount, morph.tween) and the threaded sources
(hero.exit threaded variant). Capture parts have a supplementary reading only: scrollY reversals while the morph is
open, finish mode, 1 pass per arm: original 4, rewrite 6. Not a verdict.

## Limits and lost passes

- Finish mode: VM 1 gave original and rewrite (1 pass each). Lift and unthrottle timed out in the touch driver in both
  attempts (300 s). VM 2 original timed out in both attempts. VM 3 failed at start (`simctl list devices`,
  ETIMEDOUT). So finish has no lifted arms. The finish passes run near 28 fps on CI (33-38 ms gaps), outside the 5-6
  band's domain; the cadence-aware band is used and named.
- Rest mode: VM 2 and VM 3 stalled in warm-up (runner load 562, no Safari tab). Four platform passes were skipped
  (anchor not found). 8 usable passes, all VM 1.
- Hero finish mode has no mid values: hero is exited by the time the finish zone starts. Expected.
- Three dispatches were the cap. `gh run rerun --failed` on the two failed runs would add jobs without a dispatch;
  not done (lead decides).
- The phone is not re-measured. Touch-driver retries (suffix `-a2`) may have lost passes; they are listed in each
  summary table's lost-reasons block.
- TS stand-ins (no Lean golden, reporting only, no verdict): the no-data reasons (`noDataReason`), the capture reversal
  count (`captureRow`). `judge`, `partVerdict` and `bandFor` are Lean-defined and replayed from the golden.
