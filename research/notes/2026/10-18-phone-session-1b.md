---
id: 2026-10-18-phone-session-1b
kind: note
title: "Phone session 1b: Light-mode gap check and the first finger-swipe frame timing on the original"
status: review
created: 2026-10-18
topics: [webkit, iphone, device, frame-timing, gap-harness]
---

# Phone session 1b

Follow-up to `10-17-phone-session-1.md`. Data: `results/phone/2026-10-18-s1b/` (README has the tables). Labels: MEASURED =
numbers in those files; INFERRED = my reading.

## gap-light
- MEASURED: with the phone in Light appearance, `gaps device-drive` gives 8 of 8 cells agree with Lean and the Simulator, and
  all five checks W, X, T, S, L pass. In session 1 only S failed, and only on `dark`; so the Dark appearance was the whole
  difference (CONFIRMED by the per-record diff list holding `dark` alone, in the Dark rerun at the start of this session).

## swipe-baseline (original page, finger)
- MEASURED: 911 moving frames in a 100 s recording of a person swiping up and down the page: 11.4 per 100 over 34 ms, 2.6 per
  100 over 50 ms, longest 81 ms, median 17 ms (scripted scrollTo in session 1: 28.7, 22.9, 164 ms, 17 ms).
- MEASURED: jank under the finger sits in the first 2500 px (zones 0 to 2500: 1.2 to 7.3 per 100 over 50 ms, except 20 per 100
  in 1500 with 25 frames) and is absent from 3000 px on (0 to 1.9). Session 1's scripted scroll has the same shape (all of
  it before 3000 px) but 5 to 10 times more bad frames in those zones.
- INFERRED: the difference is the scroll mechanism, not the page: `scrollTo` per frame forces main-thread work on every frame,
  while a finger scroll is compositor driven and the page's main thread only runs rAF between scroll updates. The scripted
  figures therefore overstate user-visible jank; the finger figure is the one for the metric. rAF intervals measure main-thread
  frame production, not what the display shows (INFERRED limit).

## Limits
- One recording, one person, one device: no spread; swipe speed and path are not controlled (about 100 s of up and down passes).
- The counts-under-swipe (Timeline) arm and the rewrite arm were not run in this session (device time, and the person had
  finished); `device-cli.mjs swipe --timeline` and `--target rewrite --site <dist/aot>` exist for the next session.
- Two attempts at the start still read Dark and one recording failed on an inspector timeout while a finger was down; the
  recorder now retries a timed-out poll (`pollErrors` in the file is 0 for the kept run).
