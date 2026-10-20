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
- Expected counts (INFERRED, range from the prior runs below): Chromium `trace.FunctionCall` falls by 417 to 463 per
  run on swipe-v1 and by 413 to 459 on swipe-touch-v1 against the base's v2-proved arm (`morph.mount:shift`). All
  other counts should stay equal. No new variant: the change refactors the existing `shift` paths exactly.
- A component test (jsdom) runs the real effect of `MorphMount` under `shift` and `shift-dormant` and fails when the
  removal at mount is deleted or wrongly guarded (mutants below).
- Not measured yet: every run needs workflow inputs (preset, profile, fw), and a `ci/*` push runs the workflow
  defaults (preset `original`, fw empty), which never select `shift`. Dispatch is refused in this agent's sandbox.
  The exact commands are in the handoff `docs/team/handoffs/mount-scroll-tap.md`; the Round 2 table below takes the
  run ids and verdicts.

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
- Prediction for the pending runs (branch against base, v2-proved, 3 runs each), INFERRED, as a range:
  - upper bound 463 (swipe-v1) and 459 (swipe-touch-v1): Chromium queues at most one scroll event per scrolled target
    per frame and the window listener hears it once, so the change saves at most one call per scroll-moved frame.
  - lower bound 417 (swipe-v1) and 413 (swipe-touch-v1): the summed diff measured on the prior pair. It already
    subtracts the 45 calls of the faithful mount frame, a difference that branch and base (both `shift`) do not have.
  - `FireAnimationFrame`, `EventDispatch`, layers, style and layout counts should not move.

### Round 2 runs (pending dispatch)

Base: `ci/mount-scroll-tap-base` at the merge-base with main. Branch: `ci/mount-scroll-tap`. All chromium-counts runs:
target rewrite, preset v2-proved, runs 3, image run 39049264131. The commission margin-inline cells and the WebKit
phone-rotation matchMedia not-comparable cell are known not-ok cells on main; the base gate runs show whether the
branch's not-ok set is the same.

| lane | inputs | base run | branch run | verdict |
|---|---|---|---|---|
| chromium-counts | swipe-v1 | pending | pending | pending |
| chromium-counts | swipe-touch-v1 | pending | pending | pending |
| breakpoint-gate | fw=morph.mount:shift | pending | pending | pending |
| breakpoint-gate | fw=morph.mount:shift-dormant | pending | pending | pending |
| webkit-sim | target rewrite, preset v2-proved | pending | pending | pending |

Per-frame diff to fill: per frame, `trace.FunctionCall - trace.FireAnimationFrame`, branch minus base, summed per
run, with the count of frames at -1 and the frames outside scroll-moved frames that differ. WebKit counts stay
source-only where the lane gives none.

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
