// The pixel verdict: a port of lean/Fw/Gate/Pixel.lean (`verdict`), checked against the Lean golden vectors
// packages/contracts/golden/gate/pixel.jsonl (test/verdict.test.mjs). All numbers are non-negative integers.
//   tol   = { ppm, delta, countAA }
//   stats = { total, changed, aa, maxDelta, aaMaxDelta, settled }
// Verdict: 'unsettled' when not settled; 'fail' on an empty canvas; 'pass' exactly when the counted changes are at most
// `ppm` parts per million of the canvas and the largest counted channel delta is at most `delta`; else 'fail'.

/** The default tolerance (the Lean `Tol` defaults). A per-part override lives in tolerances.json. */
export const DEFAULT_TOL = Object.freeze({ ppm: 2000, delta: 64, countAA: false });

export const effChanged = (t, st) => st.changed + (t.countAA ? st.aa : 0);
export const effDelta = (t, st) => Math.max(st.maxDelta, t.countAA ? st.aaMaxDelta : 0);
export const within = (t, st) => effChanged(t, st) * 1_000_000 <= t.ppm * st.total && effDelta(t, st) <= t.delta;

export function verdict(t, st) {
  if (st.settled === false) return 'unsettled';
  if (st.total === 0) return 'fail';
  return within(t, st) ? 'pass' : 'fail';
}
