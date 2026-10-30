---
id: 2026-10-30-end-floor-probe
kind: note
title: "end-floor-probe: the harness probe does not force the floor; with no harness rAF at all WKTR still reads one style recalc per rendering update, and the 55 flip tracks are idle 1 to 6 rAF samples (333 to 543 ms) after creation"
status: draft
created: 2026-10-30
topics: [webkit, wktr, end-of-page, floor, style-recalc, harness-artifact, lean, negative-result]
---

# end-floor-probe

Task `end-floor-probe`, branch `ci/end-floor-probe` (worktree branch `worktree-wf_66d56fde-3dd-1`), follow-up of
`10-2x-end-floor-window.md`. Q1: does the harness's own per-frame probe force the one style recalc per frame that WKTR
reads at the end of the page? Q2: when do the flip tracks leave the running state, sampled from the frame they are created? WKTR
(Simulator `internals.styleRecalcCount`) stands in for iOS Safari; every number is a class count, never phone time.

## Answer
- Q1: the probe is innocent (MEASURED, wktr run 41002916093, 3 of 3 jobs, `results/end-floor-probe/r1/verdict.txt`). The primary pair, probe on
  (`pbon`) against probe off (`pboff`, the counter read only at the window start and end), reads 600 against 599 recalcs per 576 frames in
  j1, 590 against 588 in j2, 596 against 600 in j3, 102 to 104 per 100 frames in both arms. Lean verdict per job `probeInnocent`;
  overall: `end-floor-probe overall primary: probeInnocent (jobs probeInnocent probeInnocent probeInnocent)`.
- The harness floor is therefore not an artifact of the probe. What the page costs on WKTR at the end of the page is one style recalc per
  rendering update (MEASURED, wktr run 41007945679, `results/end-floor-probe/r2/verdict.txt`): with no harness rAF callback at all
  (`pbnoraf`, a 1.5 s timer window, counter read at its start and end), 927 recalcs over 927 rendering updates in j1, 925 over 922 in j2,
  931 over 930 in j3, `rate 100 per 100 rendering updates`, verdict `end-floor-probe overall no harness rAF: probeInnocent (jobs
  probeInnocent probeInnocent probeInnocent)`. The probe-on arm of the same run reads 589, 595 and 591 recalcs against 588, 588 and 589
  rendering updates in the same 576 rAF callbacks.
- No probe call group carries any of it (MEASURED, run 41002916093): switching off, one group per arm, the counter reads around the frame
  (`pbconly` keeps only these), the tick probe (`pbnotk`), the phase read (`pbnoph`), the glint SVG clock (`pbnogh`) or the MessageChannel
  hop (`pbnomc`) leaves the rate at 102 to 104 per 100 frames in 15 of 15 job-arm pairs, each `probeInnocent`. The repeat of the primary pair
  (`pbon#2` against `pboff#2`) reads the same in 3 of 3 jobs. With every CSS animation and SMIL clock paused (`pbpon` against `pbpoff`)
  both arms read 102 to 104 per 100 frames, `probeInnocent` in 3 of 3 jobs.
- Q2: the 55 flip tracks are created running and idle again by the 1st to 6th harness rAF callback after creation (one sample per rAF callback; the first callback lands hundreds of ms after creation, so a cancel at sample 1 is an upper bound, not a frame count) (MEASURED, run 41002916093,
  `results/end-floor-probe/r1/verdict.txt`): at sample 0 (a microtask after the creating `Element.animate`) every rep reads 55 tracks made,
  55 running, 0 pending, 0 idle; the first sample at which all 55 read idle is sample 2 to 6 in j1, 1 to 2 in j2, 2 to 5 in j3, 333 to 543 ms
  after creation; `end-floor-cre overall cancel: all cancelled (jobs all cancelled | all cancelled | all cancelled)`. Lean tick class per
  rep: `elsewhere` in 36 of 36 reps (the tracks settle, and recalcs continue after them); `repClass_transient` is never the verdict, because
  the recalcs do not stop when the tracks do. After the cancel the sampler reads 133, 136 and 133 recalcs per 100 frames over 36 frames per
  job (the sampler runs a tick probe per frame; a probe-on figure).
- Together (INFERRED): the end-of-page floor on WKTR is one recalc per rendering update that does not depend on the flip tracks (they are
  idle after at most 6 frames), on the page's CSS animations and SMIL clocks (paused arm reads the same), or on anything the harness reads.
  What sets `needsStyleRecalc` at every rendering update stays open (follow-up, `geom-recalc-source`). No flag was changed.

## WebKit source for each probe call (862f17d)
None of the probe calls resolves style, so none can raise the counter. The probe reads only Element.animate results (mid-page.mjs:89); on CSS animations, StyleOriginatedAnimation overrides bindingsPlayState, bindingsCurrentTime and bindingsPending to flush pending style changes (StyleOriginatedAnimation.cpp:134-144@862f17d).
- The counter is `Document::resolveStyle`'s `++m_styleRecalcCount` (`Document.cpp:2936`), reached from `updateStyleIfNeeded` only when
  `needsStyleRecalc()` holds (`Document.cpp:3025-3050`). Group `c`: `Internals::styleRecalcCount` returns the field (`Internals.cpp:4441-4448`,
  `Document.h:1557`); `lastStyleUpdateSize` returns `m_lastStyleUpdateSizeForTesting` (`Internals.cpp:4450-4456`). Reads only.
- Group `p`: `Animation.playState` and `currentTime` are `bindingsPlayState` and `bindingsCurrentTime` (`WebAnimation.idl:55-63`,
  `WebAnimation.h:135-140`), which call `playState()` (`WebAnimation.cpp:791-820`) and `currentTime()` (`WebAnimation.cpp:493-520`): field and
  timeline-time reads. The only `updateStyleIfNeeded` in that file is in `commitStyles` (`WebAnimation.cpp:1809`), which the harness never calls.
- Group `t`: `Internals::timeToNextAnimationTick` returns `WebAnimation::timeToNextTick` (`Internals.cpp:1552-1555`,
  `WebAnimation.cpp:1917-1928`); `Internals::acceleratedAnimationsForElement` asks `AnimationTimelinesController::acceleratedAnimationsForElement`
  (`Internals.cpp:1534-1546`), which reads the renderer's composited layer's `acceleratedAnimationsForTesting`
  (`AnimationTimelinesController.cpp:422-431`, `GraphicsLayerCA.cpp:5299-5330`). No style or layout flush.
- Group `g`: `SVGSVGElement::getCurrentTime` is `SMILTimeContainer::elapsed` (`SVGSVGElement.cpp:585-588`, `SMILTimeContainer.cpp:94-101`), a clock
  read; `closest`, `getAttribute` and `isConnected` are tree reads.
- Group `m`: a `MessageChannel` post schedules a task and flushes nothing.
- The no-rAF arm counts frames with `internals.renderingUpdateCount`, which `Page::updateRendering` increments (`Page.cpp:2396-2397`) only
  after `startTrackingRenderingUpdates` (`Page.cpp:2198-2199`). Run 41002916093 read 0 here (`rendering updates 0` in
  `results/end-floor-probe/r1/rows.txt`) because the page never turned the counter on; the page now does (`mid-page.mjs:680-688`) and run
  41007945679 reads it.
- Source predicts innocence (CONFIRMED from `Document.cpp:3025-3050`, `WebAnimation.cpp:791-820`, `Internals.cpp:1534-1560`); the measurement agrees (MEASURED).

## The Lean parts
- Module `Fw.Device.EndFloorProbe` (`lean/Fw/Device/EndFloorProbe.lean`). Constants `probeBand = 10` (:8) and `minFrames = 288` (:11), fixed
  before the data. `verdict` (:42) maps a probe-on and a probe-off reading (frames, recalcs, source) to `probeCauses`, `probePartial`,
  `probeInnocent`, `noFloor` or `unread`. One theorem per branch: `verdict_unread_on_short` (:49), `verdict_unread_off_short` (:53),
  `verdict_unread_unequal` (:57), `verdict_noFloor` (:62), `verdict_causes` (:65), `verdict_partial` (:70), `verdict_innocent` (:76), plus
  `causes_lowers` (:84) and `self_never_blames` (:96). Frames of a rAF-counted pair must be equal; a rendering-update count is allowed to
  differ (rates are per 100 frames).
- Creation samples: `cancelFrame` (:122) is the first sample at which every made track is idle; `cancelFrame_none` (:135),
  `cancelFrame_first` (:160) and `cancelVerdict_all` (:182) state it. Tick class per rep is the existing `repClass_transient`
  (`EndFloorWindow.lean:169`).
- Golden `packages/contracts/golden/device/end-floor-probe.jsonl` (37 lines), replayed by
  `packages/measure-wktr/test/end-floor-probe.test.mjs` against the TS port `end-floor-probe.mjs`. Line formatting (`jobLinesP`,
  `rowLineP`) is an unproved stand-in. Page code: `pbWindow`, `pbNoRaf`, `creRun` in `packages/measure-wktr/src/mid-page.mjs`.

## Limits and follow-ups
- WKTR stands in for iOS Safari; the phone is the device check. 2 of the 3 allowed pushes were used.
- Probe-off frames are counted by rAF callbacks (a probe-free frame counter does not exist); the no-rAF arm counts rendering updates, so
  its frame total is not the rAF total. The two agree to within 1 to 7 per window in the probe-on arm (589 against 588 and so on).
- The first push read 0 rendering updates in every arm (counter off); the second push, 2 arms in 3 jobs, fixes only that. Nothing else
  changed between them.
- The cre sampler runs its own tick probe per sample, so its after-cancel rate is a probe-on figure; the pair rates above carry the claim.
- Follow-up: why `needsStyleRecalc` is set at every rendering update (`geom-recalc-source`), with the no-rAF arm as the probe-free reading.
