// Fault injection for the CI proof of the fail-fast path (glue for the test harness, no measurement logic). Off unless
// FW_WK_FAULT is set. The fault starts `FW_WK_FAULT_AFTER_S` seconds after the session connected and then holds: it kills
// again whatever the session starts again, so the inspector stays dead through the one relaunch and the run must give up.
//   kill-safari : the session's own Safari is terminated (simctl terminate of this package's device) every 2 s.
//   kill-proxy  : the proxy this session started is killed (SIGKILL of its child) every 2 s.
export const FAULTS = Object.freeze(['kill-safari', 'kill-proxy']);

/** The fault of the environment, or null. Throws on an unknown name. */
export function faultPlan(env = process.env) {
  const kind = String(env.FW_WK_FAULT ?? '').trim();
  if (!kind) return null;
  if (!FAULTS.includes(kind)) throw new Error(`FW_WK_FAULT must be one of ${FAULTS.join(', ')} (or unset), got "${kind}"`);
  const after = Number(env.FW_WK_FAULT_AFTER_S ?? 120);
  if (!Number.isFinite(after) || after < 0) throw new Error(`FW_WK_FAULT_AFTER_S must be a number of seconds >= 0, got "${env.FW_WK_FAULT_AFTER_S}"`);
  return { kind, afterMs: Math.round(after * 1000), everyMs: 2000 };
}

/**
 * Start the fault. `kill` is one kill (sync or async; it never throws). Returns { stop, kills }.
 * @param {{kind:string, afterMs:number, everyMs:number}} plan
 */
export function armFault(plan, { kill, log = () => {}, now = () => new Date().toISOString() }) {
  let kills = 0, timer = null;
  const first = setTimeout(async () => {
    log(`fault ${plan.kind}: first kill at ${now()} (then every ${plan.everyMs / 1000} s until the run ends)`);
    timer = setInterval(async () => { try { await kill(); kills++; } catch { /* nothing left to kill */ } }, plan.everyMs);
    timer.unref?.();
    try { await kill(); kills++; } catch { /* nothing to kill */ }
  }, plan.afterMs);
  first.unref?.();
  return {
    stop: () => { clearTimeout(first); if (timer) clearInterval(timer); log(`fault ${plan.kind}: stopped at ${now()} after ${kills} kills`); },
    get kills() { return kills; },
  };
}
