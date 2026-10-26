# platform.glint:hold-freeze

Rank 2 of research/notes/2026/10-26-end-of-page-variants.md. Status: built and proved; no CI count yet (see Results).

## What the flag does
The two repeating 5 s `<animate>` per glint dash (x1, x2 over six key times) become a ring of five pieces per attribute,
one per key-time segment, each with `fill="freeze"` and a `begin` equal to the end of the piece before it (segment 0 also
begins at `indefinite`). A segment where the value moves is an `<animate from to>` ramp, a segment where it holds is a
`<set>`. Per side three of five segments hold both attributes (left [1,2,4], right [0,3,4]); only there is no
non-`<set>` animation active. The two segment-0 pieces get `beginElement()` where the faithful arm calls it on its pair.
Before that, and after the dash unmounts, the static attributes (the rest values) apply, as in the original.

## Lean (lean/Fw/Parts/PlatformGlintHold.lean, no sorry)
- `hold_premise`, `hold_same_segments`: which segments hold, decided over X1 and X2.
- `hold_eq_faithful`: the hold sample equals the original at every elapsed time (class E).
- `active_unique`, `active_exists`, `active_seg`, `active_latest`: exactly one ramp or set piece per attribute is active.
- `ticking_hold` (0 against 2 while holding), `ticking_ramp`, `ticking_le` (never more than the original): the work claim.
- Golden packages/contracts/golden/parts/platform-glint-hold.jsonl (107 lines), replayed by
  apps/site/src/parts/platform.glint/hold.test.ts (sample, ticking, plan, const, and the pause and resume-seek runs).

## One SMIL clock writer
The flag adds no writer. The clock is paused and seeked only by `createPause` (platform.glint/pause.ts), reached from
`platform:faded-pause` (platform/index.tsx) or `platform.glint:offscreen-pause`, which already conflict. The golden `run`
lines drive `createPause` against a model of the SVG container and read the hold pieces at the frames after each event:
they equal the Lean values, so `pauseAnimations` and the resume seek keep hold-freeze equal to the original.
INFERRED (not run): that each engine re-evaluates the begin chain correctly after `setCurrentTime`; the look premise
on both engines is the check.

## Engine tick rules (CONFIRMED, code path shown)
- WebKit Source/WebCore/svg/animation/SVGSMILElement.cpp:1074-1088@862f17d `calculateNextProgressTime`: for an active
  element whose duration is indefinite or that is a `<set>`, the next progress time is the interval end (or the
  repeating-duration end); otherwise `elapsed + m_timeContainer->animationFrameDelay()`, every frame.
- Chromium third_party/blink/renderer/core/svg/animation/svg_smil_element.cc:1285-1301@f842f52 `NextProgressTime`: the
  same split, `interval_.end` for indefinite duration or `SVGSetElement`, `presentation_time` (next frame) otherwise.
- Not shown by these lines: the cost of a frame the container still runs for another element. That stays INFERRED; the
  counts decide.

## Results
Not delivered in this builder run: the breakpoint gate, the look premise and Chromium base vs flag runs need workflow
inputs only the lead dispatches (commands in the handoff). WebKit z5000 waits for task wk-sim-hang (not landed on main).
Premise and TS replay: hold.test.ts passes locally (unit tests, not a measurement).
