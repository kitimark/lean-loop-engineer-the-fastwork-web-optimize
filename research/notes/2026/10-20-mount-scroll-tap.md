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
- Expected counts (INFERRED from the prior runs below): Chromium `trace.FunctionCall` falls by about 463 per run on
  swipe-v1 and about 459 on swipe-touch-v1 against main's v2-proved arm (`morph.mount:shift`). All other counts should
  stay equal. No new variant: the change refactors the existing `shift` paths exactly.
- Not measured yet: the dispatch of chromium-counts, breakpoint-gate and webkit-sim was refused in this agent's
  sandbox. The exact commands are in the handoff `docs/team/handoffs/mount-scroll-tap.md`.

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

- Every +1 frame is a frame whose `scrollY` moved (MEASURED). In the other moved frames the +1 is offset by other
  calls that differ in the same frame (INFERRED).
- The sum is about one call per moved frame, minus 45 in the faithful mount frame (116 on swipe-v1, 125 on
  swipe-touch-v1), where faithful mounts the panel and the dormant arm does not.
- Prediction for the pending runs (tap against main, v2-proved, 3 runs each): `FunctionCall` total lower by about
  463 (swipe-v1) and 459 (swipe-touch-v1). `FireAnimationFrame`, `EventDispatch`, layers, style and layout counts
  should not move.

Pending, all with preset v2-proved: chromium-counts on ci/mount-scroll-tap-base (main fefd858d) and ci/mount-scroll-tap,
both profiles, 3 runs. Then breakpoint-gate with `fw=morph.mount:shift` on both engines, and webkit-sim with target
rewrite on both refs. Commands: the handoff.

## Proofs

`lean/Fw/Parts/MorphMountOpt.lean`, section "The scroll stamp after mount (`tap`)". No sorry. `check.sh` is green.

- `mountV_stays`: the variant never unmounts. `mountV_prefix`: streams equal before `t0` give equal mount flags up
  to `t0`.
- `mountV_tail_irrelevant`: if two streams agree before `t0` and `mountV x t0` holds, the mount flags are equal at
  every frame. `armV_tail_irrelevant` lifts this to the variant's scenes. `visSame_tail` and `E_after_mount_tail`
  combine it with `visSame_mount` and `E_after_mount`.
- Stamp model: `Ev` (time, entry, push, scroll, warm check, active), `step`, `run tap`, `warmAt`, `listening`.
  `run_tap`: the mount flags are equal at every step, and the stamps are equal while unmounted.
- `tickOf_tap`: the `Tick` streams are equal, so every arm built from them is equal (`armV_tap`; `armD` of
  `MorphMountDormant` reads the stream only through `mountO` and `mountV`, so it is equal as well).
- `tap_no_stamp_after_mount`: after mount, only a taken push writes the stamp. `shift_stamps_after_mount`: under
  `shift` each scroll after mount writes it.
- `calls_shift`: `calls false e n = calls true e n + scrollsAfterMount e n`.
- Golden: `packages/contracts/golden/parts/morph-mount-tap.jsonl` (16 lines: `warmStill` at the 150 ms edge and 6
  replay streams), generated by `lean/scripts/MorphTapGolden.lean` and checked in `check.sh`.
  `apps/site/src/parts/morph.mount/tap.golden.test.ts` replays it with `logic.mountNextWarm` and `logic.warmStill`.
  The detach in `index.tsx` is glue; the replay restates its rule (listener heard while not `tap` or not mounted).

## What this changes in the plan

- `morph.mount:shift` and `shift-dormant` both get the saving without a new flag. Preset inclusion stays the lead's
  decision; the v2-proved preset file is not touched.
- General lesson: a listener whose only reader stops reading at a state change is dead work after that change. Detach
  it at the transition. The proof shape is reusable: the reader's input stream is unchanged (tail irrelevance), so
  every downstream scene is equal.
