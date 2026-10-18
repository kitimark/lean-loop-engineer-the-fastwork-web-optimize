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
/** Offset of the first observation of a stop from the stop base, ms (Lean Fw.Gate.Freeze.mainOff): room for the post-resize
 *  advance and the longest settle wait (Lean mainOff_fits). */
export const MAIN_OFF_MS = 2000;
/** Length of one observation slot, ms (Lean Fw.Gate.Freeze.slotMs). */
export const SLOT_MS = 4000;
/** Real-time grace the original gets after `load` before its clock is advanced, ms: its hydration has no flag to wait on. */
export const ORIG_GRACE_MS = 1500;

/** Lean Fw.Gate.Freeze.instant: the absolute fake time of the observation of rank `k` of a stop with base `b`. */
export const instant = (b, k) => b + MAIN_OFF_MS + SLOT_MS * k;
/** Lean Fw.Gate.Freeze.stopSpan: the length of a stop with `n` overlay and view readings. */
export const stopSpan = (n) => MAIN_OFF_MS + SLOT_MS * (n + 2);
/** Lean Fw.Gate.Freeze.stopBase: the base of stop `i` of a sweep (stop 0 is the first load). */
export const stopBase = (i, n) => READY_TO_MS + i * stopSpan(n);
/** Lean Fw.Gate.Freeze.ovRank / mountRank / viewRank: the rank of the overlay `j`, of the mount reading, of the view reading `q`. */
export const ovRank = (j) => 1 + j;

/** Fw.Gate.Freeze.pageOf: the page of a sweep a part is read on, 'mounted' when either arm has a mount step for it, else 'plain'. */
export const pageOf = (mountOrig, mountRewrite) => (mountOrig || mountRewrite ? 'mounted' : 'plain');
export const mountRank = (nOv) => nOv + 1;
export const viewRank = (nOv, q) => nOv + 2 + q;

/** Lean Fw.Gate.Freeze.Step.apply over a list of steps `['rel', d] | ['hold', t]`: the clock after the work. */
export const clockAfter = (c, work) => work.reduce((x, [k, v]) => (k === 'rel' ? x + v : Math.max(x, v)), c);
/** Lean Fw.Gate.Freeze.readings: the clock at every observation (after the stage's work the harness holds to `at`). */
export function readings(c, stages) {
  const out = [];
  for (const { work, at } of stages) {
    c = Math.max(clockAfter(c, work), at);
    out.push(c);
  }
  return out;
}
/** Lean Fw.Gate.Freeze.fits: every stage's work ends at or before its instant. */
export function fits(c, stages) {
  for (const { work, at } of stages) {
    if (clockAfter(c, work) > at) return false;
    c = at;
  }
  return true;
}

/** Lean Fw.Gate.Freeze.freezeTime: the current time the freeze pass gives an animation (iterations null = infinite). */
export const freezeTime = (a) => (a.iterations === null ? a.delay + Math.floor(a.dur / 2) : a.delay + a.iterations * a.dur);

/** Lean Fw.Gate.Freeze.frozenTrace: observation i has frames = i and t = STEP_MS * i. */
export function frozenTrace(run, stable, hover) {
  const n = Math.min(run.length, stable.length);
  return Array.from({ length: n }, (_, i) => ({ running: run[i] ?? 0, frames: i, stable: stable[i] ?? 0, hoverInside: hover, t: STEP_MS * i }));
}

/** The wait over a frozen page (what Lean waitList gives for the golden traces). */
export const frozenWait = (policy, run, stable, hover) => waitTrace(policy, frozenTrace(run, stable, hover));

/** A sample's record of the observations that were not at their instant (the clock was already past it). */
export const newRec = () => ({ misses: [] });
/** Record a miss when the clock `got` is not the instant `at` asked for; true when it is. */
export function checkAt(rec, label, at, got) {
  if (got === at) return true;
  rec.misses.push({ label, at, got });
  return false;
}
/**
 * One observation at the absolute instant `T` (Lean Fw.Gate.Freeze.readings): hold the clock to T, freeze the animations, and
 * check that the clock reads T. A session without a frozen clock (the gaps lane, FW_GATE_FROZEN=0) observes at once.
 */
export async function observeAt(s, T, freeze, rec, label) {
  if (!s.holdTo) return true;
  await s.holdTo(T);
  await s.evaluate(freeze);
  return checkAt(rec, label, T, s.clockMs());
}
/** Lean Fw.Gate.Freeze.instantOutcome folded into the sample: null when every reading was on time (that changes nothing, Lean
 *  fit_keeps_outcome); a late reading makes the sample unsettled (Lean unfit_never_pass). */
export const lateWait = (rec) => (rec.misses.length === 0 ? null : { outcome: 'unsettled', observations: 0, waitedMs: 0, parked: true });
