// Timeouts of the I/O glue (waiting for Safari, the page target, replies). Not measurement logic: a slow machine (a
// CI runner with 3 vCPUs boots the Simulator and Safari several times slower than a Mac) needs longer waits, and the
// counts do not depend on them. FW_WK_TIMEOUT_SCALE multiplies every default wait (default 1 = the local values).
export const timeoutScale = (env = process.env) => {
  const s = Number(env.FW_WK_TIMEOUT_SCALE ?? 1);
  return Number.isFinite(s) && s > 0 ? s : 1;
};
/** Scale a default wait in ms. */
export const T = (ms, env = process.env) => Math.round(ms * timeoutScale(env));
/** Tries of a load + scroll step before the run fails (default 2: one retry from a fresh load after a reconnect). */
export const attempts = (env = process.env) => {
  const n = Number(env.FW_WK_ATTEMPTS ?? 2);
  return Number.isInteger(n) && n >= 1 ? n : 2;
};
