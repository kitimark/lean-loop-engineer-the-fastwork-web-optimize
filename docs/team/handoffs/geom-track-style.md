# geom-track-style handoff (graph r552)

Branch worktree-wf_ee9ffcfe-af8-1, worktree .claude/worktrees/wf_ee9ffcfe-af8-1 (under the main checkout), last commit c0c08b81b (+ later), CI branch ci/geom-track-style.
CI runs: push 1 (7a177f5f4): lean 40611977358 FAILED (overflow golden, fixed in 9e416d653); breakpoint-gate 40611977476 FAILED only in flip-cell playwright-webkit morph.geom:on (site-side flake, not the probe; the 3 track-accel jobs r1..r3 passed); wktr 40611977559 CANCELLED after j1, j2 finished (j3 lost). Push 2: not sent yet (1 of 2 left after it).

Verified from push-1 artifacts (track-accel-r1..r3, wktr-j1, j2; scratch in the session scratchpad gts/):
- Chromium scrubbed (390/768/1440): 0 failures named, 0 cc starts added, tracks stay paused: nothing on the compositor (Lean: notPlaying).
- Chromium timed: filter tracks (2 at <=720, 3 above) fail `filter-moves-pixels` in all 3 reps; opacity, scale, transform, translate, backdrop-filter get cc starts. One more main-thread track in every band: column:0 translate fails `no-visible-change` (constant keyframes, colTx v 0 = 0): Lean gate `constantTrack` added (c0c08b81b). Live image rows beyond the Lean sample (12 at 390, 6 else): 8 image transforms at 390 fail `target-invalid-compositing-state+no-visible-change` (hidden / unpainted target, compositor_animations.cc:491 CompositorPropertyAnimationsHaveNoEffect), not modelled.
- Per-frame style work (Chromium trace): scrubbed sweep ~1.02 recalc/frame in every arm; elements/frame all 50 / none 10 / idle 8 (390); no-translate -17, no-transform -16, others ~0. Timed flip: still ~1 recalc/frame, 55-100 el/frame, no-translate -18, no-transform -17 el, though cc started the translate/transform tracks: mechanism OPEN, push 2 adds invalidation-tracking reasons.
- WebKit (wktr j1, j2): scrubbed all 55 tracks paused, accel=false for all. Timed: j1 not engaged; j2 engaged but tracks already idle (tween ended on the slow frame clock) at the mid readout; push 2 adds early readouts + wheel retries.

Open: push 2 results; note research/notes/2026/10-2x-geom-track-style.md; ledger note; check.sh at final commit; package tests; merge main; plan lint; dry land; fw review ready.
Lane tag before pushing: `pnpm -s fw ci push --branch ci/geom-track-style --lanes breakpoint-gate,wktr --dry`; the head message must hold `[ci:breakpoint-gate] [ci:wktr] [accel]`.
Conventions: scratch in the session scratchpad; compound shell commands are refused, use Edit/Write; commit trailers per CLAUDE.md.
