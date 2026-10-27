import { readFileSync } from 'node:fs';

const GOLDEN = readFileSync(new URL('../../contracts/golden/measure/sim-host.jsonl', import.meta.url), 'utf8')
  .trim().split('\n').map((l) => JSON.parse(l));
const C = GOLDEN.find((g) => g.op === 'constants');

export const END_MARGIN_S = C.endMarginS;
export const SCROLL_NEED_S = C.scrollNeedS;
export const PASS_NEED_S = C.passNeedS;
export const NAV_WAIT_MS = C.navWaitMs;
export const LOAD_CEIL_CENTI = C.loadCeilCenti;

export const gateBoundS = (stepMin) => Math.max(0, stepMin * 60 - END_MARGIN_S);

export const retryFits = (elapsedS, needS, boundS) => boundS === null || boundS === undefined || elapsedS + needS <= boundS;

export const tabNeedS = (waitMs) => Math.floor((waitMs + 999) / 1000);

export const tabFits = (elapsedS, waitMs, boundS) => retryFits(elapsedS, tabNeedS(waitMs), boundS);

export const afterFailure = (tries, maxTries, elapsedS, needS, boundS) => tries < maxTries && retryFits(elapsedS, needS, boundS);

export const hostOk = (loadCenti) => loadCenti <= LOAD_CEIL_CENTI;

export function afterPass(startCenti, endCenti, tries, maxTries, elapsedS, needS, boundS) {
  if (hostOk(startCenti) && hostOk(endCenti)) return 'count';
  return afterFailure(tries, maxTries, elapsedS, needS, boundS) ? 'redo' : 'refuse';
}

export const centi = (load1) => Math.round(load1 * 100);

export const lagMs = (tickMs, sinceMs) => Math.max(0, sinceMs - tickMs);

export const blocked = (tickMs, sinceMs) => tickMs > 0 && tickMs <= lagMs(tickMs, sinceMs);

export const frozen = (tickMs, sinceMs, hostCalls) => blocked(tickMs, sinceMs) && hostCalls === 0;

export const clockStart = (nowMs, lastOutMs, tickMs, sinceMs, hostCalls) =>
  (frozen(tickMs, sinceMs, hostCalls) ? Math.min(lastOutMs + lagMs(tickMs, sinceMs), nowMs) : lastOutMs);

export const silenceMs = (nowMs, lastOutMs, tickMs, sinceMs, hostCalls) =>
  Math.max(0, nowMs - clockStart(nowMs, lastOutMs, tickMs, sinceMs, hostCalls));

export const silenceStalled = (silence, limitMs) => limitMs < silence;

export const failsIn = (isFrozen, fails) => (isFrozen ? 0 : fails);

export const relaunchPlan = (fresh) => GOLDEN.find((g) => g.op === 'plan' && g.fresh === Boolean(fresh)).steps;

export function stepGate(env = process.env, now = Date.now) {
  const t0 = Number(env.FW_MEASURE_T0_MS), stepMin = Number(env.FW_WK_STEP_MIN);
  const ok = env.FW_MEASURE_T0_MS && env.FW_WK_STEP_MIN && Number.isFinite(t0) && Number.isFinite(stepMin) && stepMin > 0;
  return { boundS: ok ? gateBoundS(stepMin) : null, elapsedS: () => (ok ? Math.round((now() - t0) / 1000) : 0) };
}
