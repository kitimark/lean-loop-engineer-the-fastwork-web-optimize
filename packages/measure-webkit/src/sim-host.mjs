export const END_MARGIN_S = 60;
export const SCROLL_RETRY_S = 589;
export const PASS_RETRY_S = 436;
export const LOAD_CEIL_CENTI = 132000;

export const gateBoundS = (stepMin) => Math.max(0, stepMin * 60 - END_MARGIN_S);

export const retryFits = (elapsedS, needS, boundS) => boundS === null || boundS === undefined || elapsedS + needS <= boundS;

export const afterFailure = (tries, maxTries, elapsedS, needS, boundS) => tries < maxTries && retryFits(elapsedS, needS, boundS);

export const hostOk = (loadCenti) => loadCenti <= LOAD_CEIL_CENTI;

export function afterPass(startCenti, endCenti, tries, maxTries, elapsedS, needS, boundS) {
  if (hostOk(startCenti) && hostOk(endCenti)) return 'count';
  return afterFailure(tries, maxTries, elapsedS, needS, boundS) ? 'redo' : 'refuse';
}

export const centi = (load1) => Math.round(load1 * 100);

export function stepGate(env = process.env, now = Date.now) {
  const t0 = Number(env.FW_MEASURE_T0_MS), stepMin = Number(env.FW_WK_STEP_MIN);
  const ok = env.FW_MEASURE_T0_MS && env.FW_WK_STEP_MIN && Number.isFinite(t0) && Number.isFinite(stepMin) && stepMin > 0;
  return { boundS: ok ? gateBoundS(stepMin) : null, elapsedS: () => (ok ? Math.round((now() - t0) / 1000) : 0) };
}
