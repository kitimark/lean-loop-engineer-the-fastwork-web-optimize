# Do the 4 sweepDoc animations cause the 2 recalcs per frame in WebKit flips

Question (task geom-sweep-paused, graph r558): the geom-timed flip reads 2 style recalcs per frame in WKTR with `ThreadedTimeBasedAnimationsEnabled` off (pref OFF, the iOS proxy). Do the 4 `sweepDoc`
background-position CSS animations in `section[data-fw=platform]` cause them? If yes, a same-look compositor sweep (`geom-sweep-compositor`, rank 1 of `10-26-end-of-page-variants.md`) is justified.
Investigation only: no site edit, no phone run. WKTR is the iOS 26.5 simulator build on GitHub Actions, not iOS Safari, never phone time; its frame clock is slow (3 flip frames, 25 to 50 idle frames per second).

## Answer
- No, not in the flip (MEASURED, 6 jobs, 2 runs). Pausing exactly the 4 sweepDoc animations leaves flip recalcs per frame at 1.67 to 2.17 against 2.0 to 2.17 unpaused: a drop of 0 to 17 percent, where the Lean rule asks for 75 percent (`explainMin` 750 per mille).
  Pausing every running document animation (`-a`) also leaves 1.83 to 2.0 per frame. The flip's own tween accounts for the 2.
- In idle the sweep is half of the recalcs (MEASURED): 2.0 per frame unpaused, 1.0 with the sweep paused (3 of 3 jobs in run 2, 1.0 to 1.2 in run 1), and the same 1.0 with all animations paused. Pausing everything except the sweep (`-o`) leaves 2.0.
  So 1 recalc per frame is the sweep and 1 per frame is a source that is not an animation. Frames per second in idle rise when the sweep is paused (run 2 j1: 36.5 to 39.5 per window with the sweep paused, 51.5 with everything paused).
- The Lean verdict is `inconclusive` for every job and for both runs, because the precondition fails: idle with the sweep paused must read at most 0.25 recalcs per frame (`idleOffMax` 25) and reads 1.0 to 1.23 (Lean `why` = `idle-not-off`, 6 of 6 jobs).
  Not retuned afterwards. The same data under the rule's own reading: flips fall under `notMax` (250 per mille) in 6 of 6 jobs, so a floor-corrected rule would read `not the sweep` (INFERRED, not Lean-decided).
- `geom-sweep-compositor` is not justified by the flip evidence. It could still be justified for idle (half of idle recalcs and about 1 ms of style per idle frame in the proxy), which is a different claim and not the phone's flip long frames.
- Next step (one): `geom-recalc-source`, attribute the recalc that remains with all animations paused (below).

## Runs (CI branch ci/geom-sweep-paused, WKTR accel lane, mode `sweep-thr-off`, main code with `morph.geom:on,morph.tween:geom-timed`, pref OFF)
| run | push | arms | jobs |
| --- | --- | --- | --- |
| 40665823632 | c9fa2502d | `sw-<warm,flip,idle>[-p][-t]`, order and reverse order | 3 |
| 40670621458 | 59ac87237 | run 1 arms plus diagnostic sets `sw-<idle,flip>-a` (all running animations paused) and `-o` (all except sweepDoc), plus an animation inventory | 3 |
Results: `results/geom-sweep-paused/run1/`, `run2/` (reports), `jobs.txt` (table below). Reducers `jobOf`, `why`, `overall` in `packages/measure-wktr/src/sweep-pause.mjs`, a TS stand-in that replays the Lean golden
`packages/contracts/golden/device/sweep-pause.jsonl` (decision in `lean/Fw/Device/SweepPause.lean`, one theorem per branch). The report-to-Job step `jobOf` is glue, not golden-replayed.

Identity (MEASURED, every row): 4 CSSAnimations named `sweep-module_sweepDoc_*` whose targets sit in the platform section ("Document", "Earn", "Secure", "Organized"); playState `running` and next tick 0 unpaused,
`paused` and `inf` (`internals.timeToNextAnimationTick`) paused. The page holds 36 animations at the platform position, 22 of them CSS animations inside the section.
The flip path engaged in every job (a geom track set was created by the wheel step; 2 flips per arm, 3 frames each).

## Table: recalcs per frame, per job (MEASURED; arms plain, no forced flush)
| run job | flip unpaused | flip sweep paused | flip all paused | idle unpaused | idle sweep paused | idle all paused | idle all but sweep | Lean why |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 j1 | 2.17 | 1.83 | - | 1.96 | 1.23 | - | - | idle-not-off |
| 1 j2 | 2.17 | 1.83 | - | 2.00 | 1.18 | - | - | idle-not-off |
| 1 j3 | 2.00 | 1.67 | - | 2.00 | 1.02 | - | - | idle-not-off |
| 2 j1 | 2.00 | 2.00 | 2.00 | 1.97 | 1.00 | 1.00 | 1.98 | idle-not-off |
| 2 j2 | 2.17 | 2.17 | 2.00 | 1.97 | 1.17 | 0.99 | 1.96 | idle-not-off |
| 2 j3 | 2.17 | 1.83 | 1.83 | 1.97 | 1.05 | 0.99 | 1.97 | idle-not-off |
Flip frames are 6 per arm per job (2 flips x 3), so one extra recalc moves a cell by 0.17. Overall (Lean `overall`, minValid 2): `inconclusive` for run 1, for run 2 and for all 6 jobs.

## Style ms (timed flush; a proxy, INFERRED where it is used)
`-t` arms force `document.getAnimations()` (a style flush) then a layout flush at the start of every frame callback and time each; Internals has no style-time API, and `performance.now` in WKTR has 1 ms steps.
Style ms over frames, flip unpaused / sweep paused: run 1 14/6, 6/6; 10/6, 12/6; 8/6, 2/6; run 2 10/6, 6/6; 17/6, 8/6; 5/6, 10/6 (sum 64 ms against 44 ms). The sign flips in 2 of 6 jobs: no usable flip style drop at this resolution
(style drops per job 571, -201, 750, 399, 529, -1000 per mille; Lean `styleUsable` needs 100 us per frame unpaused and reads it, but the job is already invalid on idle).
Idle (1 s windows): unpaused 54 to 76 ms over 49 to 76 frames (about 1.0 to 1.1 ms per frame); sweep paused 5 to 33 ms over 54 to 95 frames (0.1 to 0.4 ms per frame). The sweep is about 1 ms of style per idle frame in the proxy (INFERRED: forced flushes themselves add recalcs).

## The recalc that is not an animation (MEASURED count, source INFERRED)
- Inventory (MEASURED, run 2 j1, 36 document animations before the pause): exactly 5 are `running`: the 4 sweepDoc and 1 infinite `cue-module_scrollFloat`. The rest are `finished` (iterations 1: nav earn, accent strokeIn, cue copyIn, secureNetwork, invoice) or already `paused` (morph up/down tracks, deck vinylSpin, commission frames).
  So `-a` paused those 5 and `-o` paused only scrollFloat: the sweep is the whole animation share of idle and scrollFloat is not the residual (`-o` stays at 2.0).
- With every running animation paused, idle still shows 1 recalc per frame (3 of 3 jobs, 0.99 to 1.00), and the recalc count is the engine's own: `Document::m_styleRecalcCount` increments once per `resolveStyle` that ran the tree resolver (Document.cpp:2936@862f17d, CONFIRMED), read by `Internals::styleRecalcCount` (Internals.cpp:4441@862f17d).
- It is mostly an empty update: `lastStyleUpdateSize` (Document.cpp:2914, `m_lastStyleUpdateSizeForTesting`) reads 0 in the plain paused arms, so the recalc changes no element's style.
- Where in the frame (INFERRED): in `-t` arms the forced flush at the start of the frame callback finds a pending recalc in 16 of 80 frames when the sweep is paused (run 1 j1) but in 60 of 60 when it runs. The rendering update runs `Animations` (Page.cpp:2307-2309@862f17d) before `AnimationFrameCallbacks` (Page.cpp:2329-2330), so the sweep dirties style before page callbacks;
  the residual is dirtied after our callback, in later page script or in the engine. The site keeps a rAF loop of the original's smooth-scroll engine (`apps/site/src/parts/engine.scroll/logic.ts:49`), a candidate, not shown.
- The per-recalc element count `lastStyleUpdateSize` read in the frame callback is unreliable for flips (6.83 per frame in one job, 0 in the others) because it reports only the last recalc before the read.

## Next probe: geom-recalc-source (named, not run)
In the accel lane, pref OFF, arm `all paused` idle and flip: (1) a MutationObserver (attributes, childList, subtree) counting mutations per frame by target and attribute, (2) a wrapper around `requestAnimationFrame` counting registrations by call site per frame,
(3) per-recalc element count by forcing the flush at the end of the frame (a `MessageChannel` task after the rAF phase) and reading `lastStyleUpdateSize` once per recalc. A result that names one script or attribute makes the flip's 2 per frame a flip tween (1) plus that source (1).

## Limits
Investigation only. WKTR is not iOS Safari. 3 jobs per run, 2 flips of 3 frames each per arm. Style ms is a timed flush (a proxy). The diagnostic sets `-a` and `-o` are not in the Lean decision (TS stand-in, listed). No phone run.
