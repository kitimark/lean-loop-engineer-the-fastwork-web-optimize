// Retry gate and host gate of the Simulator lane: the decisions of Lean's Fw.Measure.SimHost, replayed against
// packages/contracts/golden/measure/sim-host.jsonl by test/sim-host.test.mjs.

/** Seconds after the gate bound kept for the kill and the watchdog's exit (Lean `endMarginS`). */
export const END_MARGIN_S = 60;
/** Longest wait from a failed scroll attempt to the end of its retried scroll step, seconds (Lean `Seen.scrollRetryS`). */
export const SCROLL_RETRY_S = 589;
/** Longest wait from a failed pass attempt to the end of the repeated pass, seconds (Lean `Seen.passRetryS`). */
export const PASS_RETRY_S = 436;
/** 1-minute load average, in hundredths, up to which a host is measured on (Lean `loadCeilCenti`). */
export const LOAD_CEIL_CENTI = 132000;

/** The latest second of the measuring step at which retried work may end. */
export const gateBoundS = (stepMin) => Math.max(0, stepMin * 60 - END_MARGIN_S);

/** A retry started `elapsedS` into the step whose work takes at most `needS` fits when it ends within `boundS` (null: no bound). */
export const retryFits = (elapsedS, needS, boundS) => boundS === null || boundS === undefined || elapsedS + needS <= boundS;

/** Whether to retry after an attempt threw: `tries` done of `maxTries`, and the retry fits. */
export const afterFailure = (tries, maxTries, elapsedS, needS, boundS) => tries < maxTries && retryFits(elapsedS, needS, boundS);

/** Whether the host is fit for a counted pass at this load average (hundredths). */
export const hostOk = (loadCenti) => loadCenti <= LOAD_CEIL_CENTI;

/** What to do with a finished pass: 'count', 'redo' or 'refuse'. */
export function afterPass(startCenti, endCenti, tries, maxTries, elapsedS, needS, boundS) {
  if (hostOk(startCenti) && hostOk(endCenti)) return 'count';
  return afterFailure(tries, maxTries, elapsedS, needS, boundS) ? 'redo' : 'refuse';
}

/** Load average (1 minute) as hundredths. */
export const centi = (load1) => Math.round(load1 * 100);

/**
 * The step clock: `elapsedS()` since the measuring process was launched (FW_MEASURE_T0_MS, set by tick.mjs launch) and `boundS`
 * from FW_WK_STEP_MIN (the plan's step_min). Either missing or not a number: no bound (null), as on a local run.
 */
export function stepGate(env = process.env, now = Date.now) {
  const t0 = Number(env.FW_MEASURE_T0_MS), stepMin = Number(env.FW_WK_STEP_MIN);
  const ok = env.FW_MEASURE_T0_MS && env.FW_WK_STEP_MIN && Number.isFinite(t0) && Number.isFinite(stepMin) && stepMin > 0;
  return { boundS: ok ? gateBoundS(stepMin) : null, elapsedS: () => (ok ? Math.round((now() - t0) / 1000) : 0) };
}
