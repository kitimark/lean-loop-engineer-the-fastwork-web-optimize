// The frozen clock of the gate run (gate-shard-balance round 2). TS twin of lean/Fw/Gate/Freeze.lean, checked against
// packages/contracts/golden/gate/freeze.jsonl by test/freeze.test.mjs. The decisions (what settled means under the frozen
// clock, what the freeze pass does to an animation) are in Lean; this file holds their twins and the glue constants.
//
// Protocol (both arms, both engines, identical): the page clock (Date, timers, requestAnimationFrame, performance.now) is
// installed frozen before the page loads (Playwright page.clock) and is advanced only by the harness. Real time is used only
// to wait for what the fake clock cannot drive (network, hydration, a real rendering frame). Before every observation the
// document's CSS and Web animations are frozen (page.mjs freezeAnimations).
import { waitTrace } from './settle.mjs';

/** One 60 Hz frame, ms (Lean Fw.Gate.Freeze.stepMs). */
export const STEP_MS = 16;
/** Absolute fake time both arms are held to after load, ms: the original's hero splash (rAF + 1140 ms fallback timer) and the
 *  rewrite's entrance timers have run (harness choice; the frozen-time frames are compared, not this number). */
export const HOLD_LOAD_MS = 8000;
/** Fake time at the end of waitReady, ms (absolute): both arms start their first settle wait at the same instant. */
export const READY_TO_MS = 10000;
/** Fake time advanced after a live resize, ms: the same in both arms (debounced resize handlers and timers have run). */
export const POST_RESIZE_MS = 1000;
/** Before a resize the clock is aligned to the next multiple of this, ms: the settle wait reads at most (F + 1) steps = 976 ms
 *  (Lean Fw.Gate.Freeze.settleSpan), so POST_RESIZE_MS + 976 < GRID_MS and both arms leave each stop at the same instant. */
export const GRID_MS = 2000;
/** Real-time grace the original gets after `load` before its clock is advanced, ms: its hydration has no flag to wait on. */
export const ORIG_GRACE_MS = 1500;

/** The next multiple of `grid` strictly after `elapsed` (the absolute instant a stop is aligned to). */
export const alignTarget = (elapsed, grid = GRID_MS) => (Math.floor(elapsed / grid) + 1) * grid;

/** Lean Fw.Gate.Freeze.freezeTime: the current time the freeze pass gives an animation (iterations null = infinite). */
export const freezeTime = (a) => (a.iterations === null ? a.delay + Math.floor(a.dur / 2) : a.delay + a.iterations * a.dur);

/** Lean Fw.Gate.Freeze.frozenTrace: observation i has frames = i and t = STEP_MS * i. */
export function frozenTrace(run, stable, hover) {
  const n = Math.min(run.length, stable.length);
  return Array.from({ length: n }, (_, i) => ({ running: run[i] ?? 0, frames: i, stable: stable[i] ?? 0, hoverInside: hover, t: STEP_MS * i }));
}

/** The wait over a frozen page (what Lean waitList gives for the golden traces). */
export const frozenWait = (policy, run, stable, hover) => waitTrace(policy, frozenTrace(run, stable, hover));
