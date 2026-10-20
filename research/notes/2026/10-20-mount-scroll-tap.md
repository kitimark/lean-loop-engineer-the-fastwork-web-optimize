---
id: 2026-10-20-mount-scroll-tap
kind: note
title: "morph.mount shift: detach the window scroll stamp listener at mount"
status: draft
created: 2026-10-20
topics: [morph.mount, shift, shift-dormant, scroll, FunctionCall, lean]
---
# morph.mount shift: detach the window scroll stamp listener at mount

## Answer

- Under `morph.mount:shift` and `shift-dormant` the passive window scroll listener `onScrollMotion` only writes
  `lastMotion`. Its only reader, `warmCheck`, returns once the panel is mounted. The change removes the listener inside
  `mount()` right after `mounted = true` (apps/site/src/parts/morph.mount/index.tsx). It covers every mount path
  (warm check, observer entry, taken push). The cleanup's second `removeEventListener` is a no-op.
- Lean proves the change exact: with or without the listener, the frame inputs of the mount rule are the same
  stream (`tickOf_tap`). So the mount flag, every scene and `VisSame E` against the original are unchanged.
  `calls_shift` counts the saved calls: one per scroll event after mount.
- Measured (round 3, 3 runs per profile and ref, branch minus base under `?preset=v2-proved`): Chromium
  `trace.FunctionCall` falls by 462, 463, 463 on swipe-v1 and by 459, 455, 459 on swipe-touch-v1. Per frame,
  `FunctionCall - FireAnimationFrame` sums to -463 in every swipe-v1 run, which is the number of scroll-moved frames,
  and to -459, -455, -459 on swipe-touch-v1 (459 scroll-moved frames). No frame outside the scroll-moved frames is at
  -1. No new variant: the change refactors the existing `shift` paths exactly.
- Not a pass on two rows of the pinned unit (details under "Round 2 runs"):
  - swipe-v1 branch run 1 has one `FireAnimationFrame` more than the base (1688 against 1687). The other five branch
    runs are equal to the base.
  - Both gate flags show one chromium cell that is not ok on the branch only: commission `pain-1440-600-1440#0`. It
    has the margin-inline signature of main's known intermittent cell, but by accepted limit (i) it needs one rerun
    of both refs by the lead.
- A component test (jsdom) runs the real effect of `MorphMount` under `shift` and `shift-dormant` and fails when the
  removal at mount is deleted or wrongly guarded (mutants below).

## Mechanism (engine source)

- Chromium queues one scroll event per scrolled target per frame and dispatches it to the window in the frame's
  event step. CONFIRMED: `Document::EnqueueScrollEventForNode` (third_party/blink/renderer/core/dom/document.cc:6626-6634@f842f52)
  and `ScriptedAnimationController::DispatchEvents` (scripted_animation_controller.cc:129, window dispatch at 157-160@f842f52).
  The document's scroll event bubbles to the window, so each window listener is called once.
- Each top-level listener call is one `FunctionCall` trace event. CONFIRMED: `V8ScriptRunner::CallFunction` emits
  it only at microtask depth 0 (third_party/blink/renderer/bindings/core/v8/v8_script_runner.cc:879-884@f842f52, raw
  fetch). That each listener call reaches `CallFunction` at depth 0 is INFERRED.
- WebKit dispatches the pending scroll events in `Document::runScrollSteps` (Source/WebCore/dom/Document.cpp:5960,
  dispatch at 6018@862f17d), with `CanBubble::Yes` at the document. CONFIRMED. One listener call fewer per rendering
  update with a page scroll follows (INFERRED, source only).
- The page's other scroll listener (`engine/scroll.ts`, passive) stays, so the event is still dispatched. The removed
  listener was passive, so no scroll ever waited on it. `EventDispatch` should not change.
- The panel warm-mounts before the profile starts. MEASURED in the morph-layers probe: under `shift` the panel's 1 s
  interval is installed at virtual time 167 ms, and frame 0 starts later (`startVirtualMs` 20000). Source:
  `research/notes/2026/10-20-morph-layers.md`, section "Real-dump checks". So in the profiles the listener is dead
  in every frame.

## Measurements

Prior runs (commit f59fdbf0, image sha256:8f0e17f5): faithful against `?fw=morph.mount:shift-dormant`, 3 runs each,
artifact `chromium-counts-rewrite-r{1,2,3}`, file `counts.json`. Reduction: per frame,
`trace.FunctionCall - trace.FireAnimationFrame` of the dormant arm minus faithful. Per-run rows:
`results/mount-scroll-tap/prior-faithful-vs-shift-dormant.json`.

| profile | runs (faithful, dormant) | scroll-moved frames | +1 frames (r1/r2/r3) | +1 frames outside moved | FunctionCall total, faithful / dormant | sum of diff |
|---|---|---|---|---|---|---|
| swipe-v1 | 39325709978, 39325721909 | 463 | 422 / 447 / 418 | 0 | 4371 / 4788 (r3 4372) | 417 / 417 / 417 |
| swipe-touch-v1 | 39325727288, 39325741608 | 459 | 422 / 439 / 436 | 0 | 6308 / 6725 (r3 6721) | 417 / 417 / 413 |

- Each frame at exactly +1 is a frame whose `scrollY` moved (MEASURED). The converse does not hold: 418 to 447 of
  the 463 moved frames (swipe-v1) are at +1. In the other moved frames other calls differ in the same frame
  (INFERRED).
- The summed diff is 417 per run (413 in one swipe-touch-v1 run). It includes the faithful mount frame (116 on
  swipe-v1, 125 on swipe-touch-v1), where faithful mounts the panel and the dormant arm does not; that frame alone is
  -45.
- Prediction for the branch-against-base runs (round 3, v2-proved, 3 runs each), INFERRED:
  - upper bound 463 (swipe-v1) and 459 (swipe-touch-v1): Chromium queues at most one scroll event per scrolled target
    per frame and the window listener hears it once, so the change saves at most one call per scroll-moved frame.
  - lower bound about 462 (swipe-v1) and 458 (swipe-touch-v1): the prior summed diff (417, and 413 in one
    swipe-touch-v1 run) plus the 45 calls of the faithful mount frame. That frame is -45 in every prior run, and
    branch and base (both `shift`) do not have it.
  - `FireAnimationFrame`, `EventDispatch`, layers, style and layout counts should not move.

### Round 2 runs

Base: `ci/mount-scroll-tap-base` at 8a82226a, the merge-base with main. Branch: `ci/mount-scroll-tap` at 52cd4856. The
lead dispatched every run. chromium-counts inputs: target rewrite, preset v2-proved, runs 3, image run 39049264131. The
profile and `?preset=v2-proved` are read from each run's `counts.json` (`profile.id`, `meta.search`), and
`morph.mount` is `shift` in the loaded config of all 12 runs. The gate flag is read from the run's merge log
(`Flags: ?fw=...`).

| lane | inputs | base run | branch run | verdict |
|---|---|---|---|---|
| chromium-counts | swipe-v1 | 39357724420 | 39357738977 | not a pass: `FireAnimationFrame` +1 in run 1 |
| chromium-counts | swipe-touch-v1 | 39357727065 | 39357741879 | pass |
| breakpoint-gate | fw=morph.mount:shift | 39357730181 | 39357744868 | not equal: branch-only chromium cell, lead rerun under limit (i) |
| breakpoint-gate | fw=morph.mount:shift-dormant | 39357733045 | 39357747743 | not equal: branch-only chromium cell, lead rerun under limit (i) |
| webkit-sim | target rewrite, preset v2-proved | 39357736128 (success) | 39357750346 (success) | recorded |

#### Counts (MEASURED)

Reduction, the same as for the prior table: per frame, `trace.FunctionCall - trace.FireAnimationFrame`, branch minus
base, summed per run. Per-run rows: `results/mount-scroll-tap/branch-vs-base.json`.

| profile | run | frames | scroll-moved | FunctionCall base / branch | delta | FireAnimationFrame base / branch | per-frame sum | frames at -1 | -1 outside moved |
|---|---|---|---|---|---|---|---|---|---|
| swipe-v1 | 1 | 503 | 463 | 4412 / 3950 | -462 | 1687 / 1688 | -463 | 425 | 0 |
| swipe-v1 | 2 | 503 | 463 | 4412 / 3949 | -463 | 1687 / 1687 | -463 | 425 | 0 |
| swipe-v1 | 3 | 503 | 463 | 4412 / 3949 | -463 | 1687 / 1687 | -463 | 419 | 0 |
| swipe-touch-v1 | 1 | 531 | 459 | 6329 / 5870 | -459 | 1722 / 1722 | -459 | 418 | 0 |
| swipe-touch-v1 | 2 | 531 | 459 | 6325 / 5870 | -455 | 1722 / 1722 | -455 | 419 | 0 |
| swipe-touch-v1 | 3 | 531 | 459 | 6325 / 5866 | -459 | 1722 / 1722 | -459 | 439 | 0 |

- Every `FunctionCall` delta lies in [-470, -400] and at the predicted 462-463 (swipe-v1) and 458-459
  (swipe-touch-v1), except swipe-touch-v1 run 2 at -455. `scrollY` is the same per frame on both refs in all 6 pairs.
- Frames outside the scroll-moved frames whose per-frame value differs: 2, 4, 6 (swipe-v1) and 4, 7, 4
  (swipe-touch-v1); none of them is at -1. Calls that move between neighbouring frames give these (INFERRED).
- `FireAnimationFrame` differs in swipe-v1 run 1: +1 in total. Frame 0 has 0 on the base and 2 on the branch, and 17
  later frames differ by one in either direction. `RequestAnimationFrame` is 1778 against 1779 in the same run. By
  accepted limit (iii) this row is not a pass; the lead decides. The per-frame sum is -463 there too, as in runs 2 and
  3.
- Other counts whose branch value falls outside [min, max] of the base's 3 runs, per run (base r1/r2/r3; branch
  r1/r2/r3):

| profile | count | base | branch |
|---|---|---|---|
| swipe-v1 | metric.JSEventListeners | -68 / -68 / -68 | -70 / -70 / -70 |
| swipe-v1 | metric.Documents | 9 / 9 / 9 | 8 / 9 / 9 |
| swipe-v1 | metric.LayoutObjects | 176 / 175 / 176 | 176 / 173 / 180 |
| swipe-v1 | metric.Nodes | 380 / 379 / 380 | 377 / 377 / 384 |
| swipe-v1 | trace.EventDispatch | 1537 / 1537 / 1537 | 1536 / 1537 / 1537 |
| swipe-v1 | trace.InvalidateLayout | 408 / 408 / 408 | 406 / 408 / 408 |
| swipe-v1 | trace.Layout | 354 / 354 / 354 | 353 / 354 / 354 |
| swipe-v1 | trace.Layout.dirtyObjects | 9477 / 9477 / 9477 | 9475 / 9477 / 9477 |
| swipe-v1 | trace.Layout.totalObjects | 336602 / 336602 / 336602 | 336595 / 336602 / 336602 |
| swipe-v1 | trace.Paint | 2221 / 2220 / 2223 | 2220 / 2219 / 2219 |
| swipe-v1 | trace.RequestAnimationFrame | 1778 / 1778 / 1778 | 1779 / 1778 / 1778 |
| swipe-v1 | trace.UpdateLayoutTree.elementCount | 24149 / 24153 / 24154 | 24143 / 24147 / 24141 |
| swipe-touch-v1 | metric.JSEventListeners | -67 / -67 / -67 | -69 / -69 / -69 |
| swipe-touch-v1 | census.activeTileAreaPx | 2927063040 / 2926686208 / 2926669824 | 2926669824 / 2927079424 / 2927079424 |
| swipe-touch-v1 | census.activeTiles | 46331 / 46327 / 46325 | 46325 / 46333 / 46333 |
| swipe-touch-v1 | census.drawingAreaPx | 6032937126 / 6030904320 / 6030902866 | 6030900166 / 6032942874 / 6032945478 |
| swipe-touch-v1 | census.drawingLayers | 27214 / 27215 / 27213 | 27213 / 27217 / 27217 |
| swipe-touch-v1 | census.layers | 30555 / 30556 / 30554 | 30554 / 30558 / 30558 |
| swipe-touch-v1 | census.tiles | 53255 / 53251 / 53249 | 53249 / 53257 / 53257 |
| swipe-touch-v1 | trace.EventDispatch | 1663 / 1663 / 1663 | 1663 / 1664 / 1663 |
| swipe-touch-v1 | trace.ImageDecodeTask (frames and run level) | 703 / 705 / 703 | 701 / 703 / 703 |
| swipe-touch-v1 | trace.InvalidateLayout | 462 / 463 / 464 | 461 / 463 / 464 |
| swipe-touch-v1 | trace.Layout | 413 / 413 / 414 | 412 / 413 / 414 |
| swipe-touch-v1 | trace.Layout.dirtyObjects | 11527 / 11525 / 11529 | 11523 / 11525 / 11529 |
| swipe-touch-v1 | trace.Layout.totalObjects | 428419 / 428373 / 428426 | 428366 / 428373 / 428426 |
| swipe-touch-v1 | trace.MajorGC | 9 / 9 / 9 | 9 / 10 / 9 |
| swipe-touch-v1 | trace.MinorGC | 4 / 3 / 4 | 3 / 2 / 4 |
| swipe-touch-v1 | trace.UpdateLayer | 20313 / 20314 / 20312 | 20312 / 20315 / 20315 |
| swipe-touch-v1 | trace.cc.SynchronizeTrees | 96 / 96 / 96 | 96 / 94 / 94 |

- `metric.JSEventListeners` is the only count that moves in every branch run: 2 lower per run on both profiles. The
  counter falls in the destructor of the listener object, CONFIRMED (`JSBasedEventListener::~JSBasedEventListener`,
  third_party/blink/renderer/bindings/core/v8/js_based_event_listener.cc:38-41@f842f52, raw fetch). So a removed
  listener is counted until a GC frees it. That the branch's extra 2 are the wrappers freed by the GC in the frames
  where `metric.Documents` also falls (frames 125-130 on swipe-v1, 80-81 on swipe-touch-v1) is INFERRED.
- The other rows are single-run moves of a few units in either direction, mostly in swipe-v1 branch run 1, the run with
  the extra `FireAnimationFrame`. That they are timing noise is INFERRED; the base runs, 3 per profile, give no wider
  range to test it against.

#### Gate (MEASURED, merge job log of each run)

| flag | engine | base not-ok set | branch not-ok set |
|---|---|---|---|
| morph.mount:shift | chromium | none (0 cells not ok, 7 excused) | commission `pain-1440-600-1440#0` |
| morph.mount:shift | playwright-webkit | matchMedia `phone-rotation#1`, `#3` not-comparable | the same |
| morph.mount:shift-dormant | chromium | none (0 cells not ok, 7 excused) | commission `pain-1440-600-1440#0` |
| morph.mount:shift-dormant | playwright-webkit | matchMedia `phone-rotation#1`, `#3` not-comparable | the same |

- The branch-only chromium cell, in both runs: commission `inner` `margin-inline-start/end` orig `0px` against rewrite
  `96px`, and `rows` `margin-inline-end` orig `0px` against `8px`, at stop 0 of `pain-1440-600-1440`. The stale value is
  on the original arm, which the change does not touch. The same reading on the same sweep failed on main without a
  `morph.mount` flag in runs 39313815482 and 39314391342, and on `desktop-1512-320-1512` in the no-flag run
  39314718340 (research/notes/2026/10-20-commission-margin-recur.md:49-54 on main). The base runs at 8a82226a did not
  hit it.
- By accepted limit (i), the gate rows stay open until the lead reruns base and branch once per flag. If the cell
  clears, it is listed as a flake with both run ids. If it stays branch-only, the gate row fails.
- The playwright-webkit verdict is `incomplete` on both refs for the same matchMedia cell, so that cell is main's.

#### webkit-sim (recorded, counts not claimed)

- Base 39357736128 and branch 39357750346: both `success`. Job `sim (rewrite, 430, 1, ?preset=v2-proved, <sha>, r1)`
  ran on 8a82226a and on 52cd4856. The WebKit saving stays source-only (Mechanism above).

## Proofs

`lean/Fw/Parts/MorphMountOpt.lean`, section "The scroll stamp after mount (`tap`)". No sorry. `check.sh` is green.

- `mountV_stays`: the variant never unmounts. `mountV_prefix`: streams equal before `t0` give equal mount flags up
  to `t0`.
- `mountV_tail_irrelevant`: if two streams agree before `t0` and `mountV x t0` holds, the mount flags are equal at
  every frame. `armV_tail_irrelevant` lifts this to the variant's scenes. `visSame_tail` and `E_after_mount_tail`
  combine it with `visSame_mount` and `E_after_mount`.
- Stamp model: `Ev` (time, entry, taken push, wheel or touchmove input, scroll, warm check, active), `step`,
  `run tap`, `warmAt`, `listening`. `step` stamps on a push, on any input (`take` in `index.tsx` writes `lastMotion`
  before it tests `takes`, so an untaken push stamps too) and on a scroll the listener hears.
  `run_tap`: the mount flags are equal at every step, and the stamps are equal while unmounted.
- `tickOf_tap`: the `Tick` streams are equal, so every arm built from them is equal (`armV_tap`; `armD` of
  `MorphMountDormant` reads the stream only through `mountO` and `mountV`, so it is equal as well).
- `tap_no_stamp_after_mount`: after mount, only a push or a wheel or touchmove input writes the stamp. `shift_stamps_after_mount`: under
  `shift` each scroll after mount writes it.
- `calls_shift`: `calls false e n = calls true e n + scrollsAfterMount e n`.
- Golden: `packages/contracts/golden/parts/morph-mount-tap.jsonl` (17 lines: `warmStill` at the 150 ms edge and 7
  replay streams, the last with untaken input that delays the warm mount), generated by
  `lean/scripts/MorphTapGolden.lean` and checked in `check.sh`. `apps/site/src/parts/morph.mount/tap.golden.test.ts`
  replays it with `logic.mountNextWarm` and `logic.warmStill`. The replay restates the listener rule in TS and is
  checked against the Lean golden; it does not test the component.
- Component test: `apps/site/src/parts/morph.mount/tap.component.test.ts` (vitest, jsdom). For `shift` and
  `shift-dormant` it renders `MorphMount`, spies on `window.addEventListener` and `removeEventListener`, and mounts
  by each path: an intersecting entry, a taken wheel push, and the warm check after a quiet 150 ms (a scroll before it
  delays the mount). Each case asserts: the scroll listener is added once, passive; it is not removed before mount;
  it is removed exactly once at mount, with the same function; a scroll after mount no longer calls it; the cleanup
  removes it once more. `faithful` adds no scroll stamp listener.
- Mutants of the removal line in `index.tsx`, each run against the component test (7 tests):

| mutant | failed tests |
|---|---|
| line deleted | 6 |
| `if (!shift)` | 6 |
| `if (shift && pushed)` | 4 |
| `if (shift && intersecting)` | 4 |
| `if (variant === 'shift')` | 3 |
| `removeEventListener(..., true)` (capture, does not match) | 6 |

## What this changes in the plan

- `morph.mount:shift` and `shift-dormant` both get the saving without a new flag. Preset inclusion stays the lead's
  decision; the v2-proved preset file is not touched.
- General lesson: a listener whose only reader stops reading at a state change is dead work after that change. Detach
  it at the transition. The proof shape is reusable: the reader's input stream is unchanged (tail irrelevance), so
  every downstream scene is equal.
