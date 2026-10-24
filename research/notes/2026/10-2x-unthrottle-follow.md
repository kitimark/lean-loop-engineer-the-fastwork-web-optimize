---
id: 2026-10-2x-unthrottle-follow
kind: note
title: "engine.scroll:unthrottle-follow: no steady gain over unthrottle on scrollY still runs in the Simulator; the hero value shows 41 percent fewer still runs on a lens chosen after the data (INFERRED); loop proved in Fw.Parts.EngineScrollFollow"
status: review
created: 2026-10-25
topics: [lag, webkit, ios-toolbar, scroll-events, engine.scroll, lean, phone]
---

# unthrottle-follow: keep requesting frames while scrollY moves

Task `unthrottle-follow`. Lean: `lean/Fw/Parts/EngineScrollFollow.lean` (golden `packages/contracts/golden/parts/engine-scroll-follow.jsonl`,
38 lines). Site: `apps/site/src/parts/engine.scroll/follow.ts`, flag `?fw=engine.scroll:unthrottle-follow`. WebKit cites `@862f17d`.
Inputs: `10-2x-webkit-throttles.md` (rank 1), `10-2x-unthrottle-preset.md`, `10-2x-unthrottle-parts.md`.

## Answer first

- **Verdict (pinned unit): no steady gain over unthrottle.** scrollY still runs per 1000 moving frames: unthrottle 110.2,
  follow 96.5 pooled; 109.1 vs 108.1 in run 1, 111.2 vs 84.3 in run 2 (MEASURED; mixed). Post-hoc finding, lens chosen
  after run 1 (INFERRED): hero value (the part output) still runs per 1000 mid-moving frames: unthrottle 174.5, follow 103.0 (-41 percent); run 1 173.1 vs 115.2, run 2 175.8 vs 90.5. Follow is lower in all 6 of 6 job
  comparisons (MEASURED, runs 40109924058 and 40116376544, one iOS 27 Simulator pass per arm per job, 6 passes per arm). The scrollY series
  the page reads does not need the loop and shows no steady gain: per 1000 moving frames unthrottle 111.2 vs follow 84.3 in run 2, 109.1 vs
  108.1 in run 1 (MEASURED; mixed, so no claim).
- **Why: the second throttle is live in the Simulator.** With `scroll` events counted per frame (run 2), unthrottle gets an event in 424 of
  every 1000 moving frames, so the engine runs a frame in about one of every 2.4 moving updates; rewrite 236 and the original 147 (MEASURED). The
  loop restores a frame at every moving update (follow's event rate is the same, 421.5: the loop adds frames, not events). Lean:
  `gain_iff` (the loop beats the event-driven engine over two or more moving updates iff the window is two updates or more),
  `eventFrames_one` (window 1: no gain), `follow_part_no_stills` and `event_part_stills` (strictly monotone part: no still run with the loop;
  `throttleK d` equal frames per move per window without it).
- **Band runs of 5-6 frames in the part output: rewrite 197, original 70, unthrottle 7, follow 0** (6, 5, 6, 6 passes; MEASURED). The page-read
  band runs (scrollY): rewrite 312, original 132, unthrottle 0, follow 0 (that lens is the preset's `lifted` verdict; unchanged by the loop).
- **Same look, stateless parts only.** `follow_same_look`: a part whose frame output is `f y` shows `f (u t)` at every loop frame, as the lifted
  mode does (CONFIRMED in Lean). A chasing part (commission GAIN 0.22 per frame, people.card, people.deck) gets more frames per second while the
  finger moves, so it settles sooner: a look change on wide viewports, INFERRED, not measured; look-change class for the user's review.
- **Cost and safety.** The loop runs only while scrollY moves and 8 still frames after; 3600 frames at most per gesture; zero frames when idle;
  none without `(pointer: coarse)`: `frames_bounded`, `stops_after_still`, `idle_zero`, `drive_idle`, `fine_never_requests`,
  `scrollend_stops`. A gesture with 9 still frames inside it stops the loop until the next `scroll` event (golden row `stairs p=9`). CPU/power
  cost of one rAF per moving frame: not measured (INFERRED small: the engine already runs its callbacks on 42 percent of moving frames).

## The loop (Lean `step`, `drive`)

State: last y read, still frames in a row, frames run, on. A frame that reads `y` while on: still := (y = last ? still + 1 : 0), frames += 1,
next frame requested iff no `scrollend`, still < 8 and frames < 3600. A frame while off wakes it iff y moved; an unmoved y changes nothing.
The loop is an engine callback ordered first (`FOLLOW_ORDER`), so it reads `y` once through the engine and calls `ScrollEngine.request()`;
a separate rAF or clock subscriber is not added. `stillMax = 8 > bandHi = 6` (`stillMax_gt_band`): the 5-6 frame plateaus of a 100 ms throttle
do not stop it (`plateau_survives`); `moving_runs_every_update`: while every update moves it runs a frame at each update.

| Lean theorem | Says |
|---|---|
| `frames_bounded`, `drive_frames_le` | at most `frameCap` loop frames per gesture |
| `stops_after_still` | `stillMax` still frames turn it off |
| `idle_zero`, `drive_idle`, `idle_drive_zero` | an idle loop requests and runs nothing |
| `fine_never_requests`, `coarse_steps` | the guard of `unthrottle` applies |
| `moving_runs_every_update`, `follow_gt_event`, `gain_iff` | one frame per moving update; beats the event engine iff the window >= 2 |
| `follow_reads_newest`, `event_read_age_lt`, `follow_same_look` | newest scrollY; event read is up to p - 1 updates old |
| `follow_part_no_stills`, `event_part_stills` | the part-output lens of the measurement |

## Measurement (CI only)

Lane: `toolbar-throttle` push, hero drag mode, commit tag `[throttle:follow]` (workflow and `throttle/cli.mjs` as of commits `cf29b0739` and `dc1c93383`; main's workflow now runs `parts-cli.mjs` with fixed arms and has no follow arm, so a rerun needs `unthrottle-follow` added there first): arms rewrite, unthrottle, unthrottle-follow, original; 1 round of
8 drag cycles per job, arm order rotated by job (3 jobs). iOS 27 Simulator on a macOS runner; stand-in for the iPhone. Denominators: **moving
frames** = recorded frames with the visual-viewport (toolbar) class `moving`; **mid-moving frames** = moving frames with the hero value strictly
between 0 and 1. Pooled over both runs (all jobs; the original lost one pass in run 2):

| arm | passes | moving frames | mid-moving frames | part still runs | per 1000 moving | per 1000 mid-moving | part band runs (5-6) | scrollY still runs | per 1000 moving | max step px |
|---|---|---|---|---|---|---|---|---|---|---|
| rewrite | 6 | 8635 | 7216 | 1081 | 125.2 | 149.8 | 197 | 1040 | 120.4 | 78 |
| original | 5 | 5716 | 4926 | 655 | 114.6 | 133.0 | 70 | 651 | 113.9 | 41 |
| unthrottle | 6 | 8515 | 7072 | 1234 | 144.9 | 174.5 | 7 | 938 | 110.2 | 37 |
| unthrottle-follow | 6 | 8406 | 7039 | 725 | 86.2 | 103.0 | 0 | 811 | 96.5 | 42 |

Per run, part still runs per 1000 mid-moving frames (job 1 / 2 / 3): run 40109924058 unthrottle 177.7 / 173.1 / 168.9, follow 116.4 / 99.5 / 128.0;
run 40116376544 unthrottle 179.5 / 162.7 / 186.5, follow 83.8 / 112.1 / 73.4. Max step is the largest scrollY step between two moving frames;
it is set by the drag velocity, not by the arm. Scroll events per 1000 moving frames (run 40116376544 only, recorder change in `dc1c93383`):
rewrite 236.4, original 146.7, unthrottle 424.1, follow 421.5.

## Limits

- **The part-output lens was chosen after run 1.** The pinned lens (scrollY still runs) is not expected to move with the loop, since the loop changes
  only when the engine runs, not where WebKit puts scrollY (INFERRED; no Lean theorem yet, follow-up); the part lens (`ThrottleParts.rowsOf`: the shown value as its own series) is the one the Lean model predicts. Run 2
  repeated it with 3 of 3 jobs in the same direction. INFERRED as the right lens; the declared lens shows no steady gain.
- **The hero-value still-runs lens (174.5 vs 103.0 per 1000 mid-moving frames) was chosen after seeing the data (INFERRED).** On the
  pinned lens, scrollY, there is no steady gain over unthrottle (109.1 vs 108.1 in run 1, 111.2 vs 84.3 in run 2, mixed). The verdict follows the
  pinned unit (scrollY): no gain on it; the part-output gain is a finding on a lens picked after the fact, not a new verdict lens.
- One pass per arm per job, 6 per arm; the Simulator is not the phone (phone feel is the user's step); the part columns were reduced locally from the CI
  artifacts by `follow-report.mjs` (TS stand-in; the CI report job of those runs prints the scrollY columns and the verdict lines only).
- Finish mode (the page end) is a follow-up if the user wants it. Not measured: Low Power Mode, power, the phone.

## Follow-ups

- Breakpoint gate for the flag, both engines: PASSED, run 40125463870 on head 8cb61aace (CONFIRMED, lead). Command: `pnpm -s fw run --gate --engines both --fw engine.scroll:unthrottle-follow --ref ci/unthrottle-follow-gate`.
- Trajectory probe and morph cell before the flag can join `v2-proved` (`Fw.Preset.Gen` lists it as registered, not a member).
- Look check of chasing parts on wide viewports under the loop (look-change class).
- Lean why for no gain on scrollY: a theorem that the recorder's scrollY series is u in both arms, so its still runs are equal.
- Tie the newest-scrollY theorem to `drive`: the list of y read by `drive s ys` equals `ys` while every update moves (follow_reads_newest is about the lifted mode only).
