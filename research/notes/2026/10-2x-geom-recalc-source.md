# Which source runs the 1 style recalc per frame that is left when every animation is paused (WebKit)

Question (task geom-recalc-source, graph r560): with every running animation paused, WKTR with `ThreadedTimeBasedAnimationsEnabled` off (pref OFF, the iOS proxy) still runs 1 style recalc per frame in idle, and the geom-timed flip reads 2.
Which page-side action, if any, is present in those frames? Investigation only: no site edit, no phone run. WKTR is the iOS 26.5 simulator build on GitHub Actions, not iOS Safari, never phone time; its frame clock is slow (flip windows of 3 frames, 35 to 55 idle frames per second).

## Answer
- No page-side source (MEASURED, 3 runs, 9 jobs): the Lean verdict is `engine-internal` for idle in 9 of 9 jobs and for the flip in 7 of 9 jobs (the other 2 are `no-frames`, below). Overall `engine-internal` in every run and over all 18 job results; next step by the Lean rule: `no page-side fix: read the WebKit invalidation path`.
- Nothing the page does is present in the recalc frames (MEASURED): over the observed idle arms (295 to 499 frames per job, 294 to 477 of them with a recalc) 0 frames hold a DOM mutation (no attribute, childList or text change), 0 frames hold a rAF callback, and one timer site (the `gc` interval of the site's clock) is present in 10 to 21 frames (3 to 7 percent). No key covers the 90 percent of recalc frames the rule asks for.
- The recalc updates no element (MEASURED): `internals.lastStyleUpdateSize` is 0 for every readable recalc of the observed idle arm (`rs-idle-obs`, 1000 of 1000 per mille in 9 of 9 jobs); the forced-flush arm `rs-idle-obsf` read 2 recalcs over 9 jobs (r1 j3, r2 j3), both 18 elements. WebKit sets that size to 0 when the resolver finds nothing to change (Document.cpp:2914@862f17d), the count increments after it (2936): style was marked dirty and the resolve changed nothing.
- It does not come from page callbacks (MEASURED): swallowing every page rAF callback leaves 94 to 100 recalcs per 100 frames, swallowing every page timer callback leaves 94 to 100 (floor 94 to 101, observed 96 to 103, `engine.scroll` and the site clock are inside both swallows).
- It does not come from animations (MEASURED, diagnostic, outside the Lean decision): cancelling all 36 document animations (not only pausing the 5 to 11 running ones) leaves 93 to 100 per 100 frames in 3 of 3 jobs of runs 2 and 3.
- It happens before the first frame callback (MEASURED in run 2 and 3, 6 jobs): the recalcs counted before the probe's first rAF callback of the frame equal the recalcs of the frame (pre-callback rpf100 equals rpf100 in every arm, 93 to 100). INFERRED: it is one of the rendering-update steps before the callbacks (Page.cpp:2290-2329@862f17d: Resize, Scroll, MediaQueryEvaluation, AdjustVisibility (2303-2305, adjustVisibilityInRepeatedlyTargetedRegions), Animations, Fullscreen, Immersive, VideoFrameCallbacks) or a task before the update. The probe's callback is not guaranteed to be the first one.
- It needs rendered body content (MEASURED, run 3): `display:none` on `body` leaves 11, 0 and 0 recalcs per 100 frames (j1 to j3) and removing the body children leaves 0, 0 and 0.
- Flip (MEASURED): the flip-start frame has 3 to 4 recalcs with the nav writes (`mut:nav#style`, `mut:nav#data-fw-morph`, written by the site clock's interval `T`, `entry-client` call site); the other 2 frames of the window have the floor 1. So the flip's "2 per frame" is the floor 1 plus the tween's own recalcs spread over 3 frames; the flip has no quiet frame, the Lean verdict has no contrast there and reads `engine-internal` because no key covers the recalc frames.
- Run 3 flips: in 2 of 3 jobs the flip never engaged (3 wheels, no track created, `no-frames`); that voids those two flip results, it is not a verdict. Runs 1 and 2 engaged in 6 of 6.

## Runs (CI branch ci/geom-recalc-source, WKTR accel lane, mode `recalc-thr-off`, main code with `morph.geom:on,morph.tween:geom-timed`, pref OFF, 3 jobs each)
| run | push | arms |
| --- | --- | --- |
| 40792245957 | c536e5c0f | `rs-warm`, `rs-<idle,flip>-<floor,obs,obsf>` in order and reverse, `rs-idle-blockraf`, `rs-idle-blocktimer` in order and reverse |
| 40795367330 | 1576aad26 | run 1 plus the pre-callback recalc count per frame and the diagnostic `rs-idle-cancel` |
| 40797685228 | ee443d434 | run 2 plus the diagnostics `rs-idle-hide` and `rs-idle-empty` |
Results: `results/geom-recalc-source/r1`, `r2`, `r3` (`j<n>-accel-recalc-thr-off-1.json`, `tally.txt`), `table.txt`, `verdict.txt`. Decision `lean/Fw/Device/RecalcSource.lean` (thresholds fixed before any data, never retuned; one theorem per branch), golden
`packages/contracts/golden/device/recalc-source.jsonl`, TS stand-in `packages/measure-wktr/src/recalc-source.mjs` that replays the golden (the report-to-Job step `jobOf` is glue, not golden-replayed). Probe: `packages/measure-wktr/src/mid-page.mjs` (`rsArm`, `rsWindow`).
A frame is the stretch between two MessageChannel tasks that follow a rendering update, so a mutation and the recalc it causes fall in one frame. Keys per frame: `mut:` (part and attribute), `raf:` and `timer:` (call site, 3 stack frames, origin stripped), `cssom:`, `anim:`.

## Table: recalcs per 100 frames, frames in the arm (MEASURED; idle, all running animations paused)
| run job | floor | observed | swallow rAF | swallow timers | cancel all | hide body | empty body | quiet frames | Lean idle / flip |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| r1 j1 | 95/224 | 100/212 | 98/195 | 99/199 | - | - | - | 1 | internal / internal |
| r1 j2 | 101/167 | 99/176 | 100/167 | 100/173 | - | - | - | 1 | internal / internal |
| r1 j3 | 99/203 | 103/177 | 99/224 | 100/203 | - | - | - | 1 | internal / internal |
| r2 j1 | 94/266 | 96/253 | 94/294 | 94/297 | 93/151 | - | - | 8 | internal / internal |
| r2 j2 | 100/163 | 99/166 | 100/178 | 99/177 | 100/95 | - | - | 1 | internal / internal |
| r2 j3 | 100/225 | 99/198 | 100/215 | 100/211 | 100/104 | - | - | 1 | internal / internal |
| r3 j1 | 100/220 | 99/202 | 98/179 | 99/195 | 99/135 | 11/151 | 0/151 | 1 | internal / no-frames |
| r3 j2 | 100/154 | 100/151 | 100/140 | 100/149 | 100/89 | 0/152 | 0/151 | 1 | internal / no-frames |
| r3 j3 | 100/186 | 100/197 | 100/143 | 100/135 | 98/72 | 0/152 | 0/151 | 0 | internal / internal |
The observer shifts the floor by at most 5 per 100 (Lean gate 25). Each idle arm runs 2500 ms; each flip arm 4 flips of one window each, both orders.

## Why this is not an animation or a page callback (CONFIRMED source, INFERRED consequence)
- `Document::resolveStyle` runs only when style is dirty (`updateStyleIfNeeded` checks `needsStyleRecalc()`), so something marks it every frame. The animation path marks style at `AnimationTimelinesController::updateAnimationsAndSendEvents`
  (`animation->tick()`, AnimationTimelinesController.cpp:177) through `KeyframeEffect::animationDidTick` (KeyframeEffect.cpp:2129), `invalidate` (1731) and `invalidateElement` (127-134), but only on a frame the timeline scheduled
  (`m_animationResolutionScheduled`, DocumentTimeline.cpp:194), and a paused animation's next tick is infinite (`scheduleNextTick`, 357-405). Cancelling every animation leaves the count unchanged (MEASURED), so that path is not the one.
- The counter itself is a pure read (Internals.cpp:4431-4455@862f17d) and the floor arm has no observer, so the probe does not cause it (observer shift at most 5 per 100).

## Next step (one)
By the Lean rule: no page-side fix; read the WebKit invalidation path. Concretely, task `geom-recalc-bisect` (probe only, no site edit): in idle with every animation paused, hide one top-level child of `body` at a time (then one `[data-fw]` part at a time inside the child whose removal drops the rate), read the recalc rate with the same arms, and stop at the subtree whose hide takes it below 25 per 100 (the Lean `fellMax`).
Then read in WebKit what in that subtree marks style dirty without a change (the steps before the callbacks). Only when that names a page element or style feature does a same-look fix task exist.
This also bounds `geom-sweep-compositor`: the sweep is 1 of the 2 idle recalcs (geom-sweep-paused, MEASURED), the other is this engine-internal recalc and is not removed by moving the sweep.

## Limits
Candidate coverage: mutations, rAF, setTimeout/setInterval, insertRule/deleteRule/replaceSync and animate are wrapped; event listeners (scroll, resize, pointer), ResizeObserver and IntersectionObserver callbacks, microtasks, CSSStyleRule.style writes and adoptedStyleSheets are not (the pre-callback, hide and empty arms point away from them; geom-recalc-bisect wraps or bounds them).
WKTR is not iOS Safari and its frame clock is slow; the frame counts per job differ (72 to 297 per arm). Call-site attribution from `Error().stack` is best effort (the site's clock is one call site, three frames are kept). The probe's callback is not guaranteed to be the first rAF callback, so "before the first callback" is INFERRED.
`cancel`, `hide` and `empty` are diagnostics outside the Lean decision and run last (they change the page). 2 of 3 run-3 flips did not engage. No phone run.
