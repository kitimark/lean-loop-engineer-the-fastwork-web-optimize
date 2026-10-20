// Liveness guard of the Simulator's inspector (glue: the rule, the limits and the exit code are Lean's, Fw.Measure.SimBound,
// via inspector.mjs). Every tick of the stall watchdog, and at the start of every attempt, one probe runs; two failed probes
// in a row (or a gone socket) make the inspector dead: Safari is relaunched once, and a second death ends the run with exit
// code 4. Every wait here is the Lean bound and is not scaled by FW_WK_TIMEOUT_SCALE, so the bound that Lean proves is the
// bound that runs.
import { BOUNDS, inspectorReply, inspectorAfterRelaunch, InspectorDeadError } from './inspector.mjs';

/** `p` rejected with an error after `ms`; the timer never outlives `p`. */
export function within(ms, what, p) {
  let t;
  const late = new Promise((_, rej) => { t = setTimeout(() => rej(new Error(`${what} took longer than ${Math.round(ms / 1000)} s`)), ms); });
  return Promise.race([p, late]).finally(() => clearTimeout(t));
}

/** Run `steps` ([{name, ms, run}]) one after the other, each within its own bound. */
export async function runSteps(steps, { log = () => {} } = {}) {
  for (const st of steps) {
    const t0 = Date.now();
    await within(st.ms, st.name, Promise.resolve().then(st.run));
    log(`  relaunch: ${st.name} done in ${Math.round((Date.now() - t0) / 1000)} s (bound ${Math.round(st.ms / 1000)} s)`);
  }
}

const describe = (p) => `socket ${p.socket ? 'up' : 'gone'}, proxy ${p.proxy ? 'up' : 'down'}, page ${p.page ? 'listed' : 'missing'}`;

/**
 * @param {{probe:()=>Promise<{socket:boolean,proxy:boolean,page:boolean}>, relaunch:()=>Promise<void>, repair?:()=>Promise<void>,
 *   log?:Function, onDead?:(e:Error)=>void, tickMs?:number, probeMs?:number, relaunchMs?:number}} o
 *   probe: one liveness probe (never throws). relaunch: Safari once more (within BOUNDS.relaunchMs). repair: runs after a
 *   single failed probe that does not yet make the inspector dead (the session starts the proxy again).
 */
export function createGuard({ probe, relaunch, repair = null, log = () => {}, onDead = () => {}, tickMs = BOUNDS.tickMs, probeMs = BOUNDS.probeMs, relaunchMs = BOUNDS.relaunchMs }) {
  let relaunched = false, fails = 0, busy = null, dead = null, timer = null;

  async function decide(why, withRepair) {
    let p;
    try { p = await within(probeMs, 'the probe', probe()); } catch { p = { socket: true, proxy: false, page: false }; }
    const r = inspectorReply({ relaunched, fails, ...p });
    fails = r.fails;
    if (!r.ok) log(`inspector probe failed (${why}): ${describe(p)}; ${fails} failed in a row`);
    if (r.action === 'giveUp') {
      log(`giving up: the inspector is dead again after Safari was relaunched (${describe(p)}); exit code ${r.exitCode}`);
      throw new InspectorDeadError(`the inspector is dead again after Safari was relaunched (${describe(p)})`);
    }
    if (r.action === 'relaunch') {
      log(`relaunching Safari once: the inspector is dead (${describe(p)})`);
      relaunched = true; fails = 0;
      let worked = true, failure;
      try { await within(relaunchMs, 'the relaunch', relaunch()); } catch (e) { worked = false; failure = e; }
      if (inspectorAfterRelaunch(worked) === 'giveUp') {
        log(`giving up: relaunching Safari failed: ${failure.message}; exit code ${r.exitCode}`);
        throw new InspectorDeadError(`the inspector is dead and relaunching Safari failed: ${failure.message}`);
      }
      log('Safari relaunched; the inspector answers');
      return { ok: true, relaunched: true };
    }
    if (!r.ok && withRepair && repair) await repair();
    return { ok: r.ok, relaunched: false };
  }

  /** One probe and its action. Concurrent calls share one run. Throws InspectorDeadError once the run must end. */
  function check(why = 'attempt', { repair: withRepair = false } = {}) {
    if (dead) return Promise.reject(dead);
    if (!busy) {
      busy = decide(why, withRepair).catch((e) => { if (e instanceof InspectorDeadError) { dead = e; onDead(e); } throw e; }).finally(() => { busy = null; });
    }
    return busy;
  }

  /** Probe on every tick of the stall watchdog's period; a tick that finds a probe still running is skipped. */
  function start() {
    timer = setInterval(() => { if (!busy && !dead) check('tick').catch(() => {}); }, tickMs);
    timer.unref?.();
  }
  function stop() { if (timer) clearInterval(timer); timer = null; }

  return { check, start, stop, get relaunched() { return relaunched; }, get fails() { return fails; }, get dead() { return dead; } };
}
