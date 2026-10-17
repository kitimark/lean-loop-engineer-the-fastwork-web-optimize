/**
 * Pure scheduling decisions of the MotionClock (no DOM, no timers). Golden vectors, when lean-parts provides them:
 * packages/contracts/golden/parts/engine.clock.jsonl (see clock.logic.test.ts).
 *
 * Two kinds of frame subscriber:
 *  - shared (default): all share one requestAnimationFrame registration per frame (optimised variants);
 *  - own (`{ own: true }`): every subscriber holds its own registration per frame, so the page's rAF callback count
 *    equals the original's (e.g. one spring per digit) (faithful variants).
 */

/** What the shared loop must do after the shared subscriber count changed. */
export function sharedLoopAction(sharedSubs: number, loopActive: boolean): 'start' | 'stop' | 'none' {
  if (sharedSubs > 0 && !loopActive) return 'start';
  if (sharedSubs === 0 && loopActive) return 'stop';
  return 'none';
}

/** rAF callbacks the clock has registered per frame (steady state). */
export function rafRegistrationsPerFrame(sharedSubs: number, ownSubs: number): number {
  return (sharedSubs > 0 ? 1 : 0) + ownSubs;
}

/** After a frame: does a subscriber's loop re-request a frame. Shared: while any shared subscriber remains. Own: while it is subscribed. */
export function rerequest(kind: 'shared' | 'own', sharedSubs: number, stillSubscribed: boolean): boolean {
  return kind === 'shared' ? sharedSubs > 0 : stillSubscribed;
}

/** Timers the clock has registered: one real setInterval per `interval()` call that is not yet cancelled. */
export function timerRegistrations(intervals: number): number {
  return intervals;
}

/** Accepted interval period (a real setInterval clamps below 0 and treats NaN as 0; the clock rejects them). */
export function validInterval(ms: number): boolean {
  return Number.isFinite(ms) && ms >= 0;
}
