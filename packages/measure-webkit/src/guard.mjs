// Liveness guard of the Simulator's inspector (glue: the rule, the limits and the exit code are Lean's, Fw.Measure.SimBound,
// via inspector.mjs; the recovery is Fw.Device.SimRelaunch, checked against golden/device/sim-relaunch.jsonl). Every tick of
// the stall watchdog, and at the start of every attempt, one probe runs; two failed probes in a row (or a gone socket) make the
// inspector dead. Then the device is asked whether it is still booted: Safari is relaunched once (device up), the device is
// rebooted once (device down, or Safari died again, or its relaunch failed), and a death after both budgets ends the run with
// exit code 4. The next attempt of the pass runs after the recovery. Every wait here is a Lean bound and is not scaled by
// FW_WK_TIMEOUT_SCALE.
import { BOUNDS, inspectorReply, InspectorDeadError } from './inspector.mjs';
import { CALL, deviceBooted, rebootDevice } from './sim.mjs';
import { wait } from './simretry.mjs';

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

/** Worst seconds of one simctl call: every try at its limit plus the waits between tries (Lean: `callWorstS`). */
export const callWorstS = (limitS) => CALL.tries * limitS + (CALL.tries - 1) * (wait(1) / 1000);
/** Seconds the recover path may take (Lean: `detectS`, `relaunchS`, `rebootS`, `boundS init`). */
const detectS = BOUNDS.detectMs / 1000 + callWorstS(CALL.stateMs / 1000);
const relaunchS = BOUNDS.relaunchMs / 1000;
const rebootS = callWorstS(CALL.shutdownMs / 1000) + callWorstS(CALL.bootMs / 1000) + callWorstS(CALL.bootstatusMs / 1000) + relaunchS;
export const RECOVER = Object.freeze({ detectS, relaunchS, rebootS, worstS: 3 * detectS + relaunchS + rebootS, passEvents: 5 });

/** Lean: `init`. Phases: running, relaunching, rebooting, done, failed:<name>. */
export const initPass = () => ({ phase: 'running', attempt: 1, relaunches: 0, reboots: 0 });
export const terminal = (s) => s.phase === 'done' || s.phase.startsWith('failed:');
/** Lean: `step`. Events: passOk, deadUp, deadDown, relaunchOk, relaunchFail, rebootOk, rebootFail. */
export function step(s, e) {
  const to = (phase, o = {}) => ({ ...s, phase, ...o });
  if (terminal(s)) return s;
  if (s.phase === 'running') {
    if (e === 'passOk') return to('done');
    if (e === 'deadUp') return s.relaunches === 0 ? to('relaunching', { relaunches: 1 }) : s.reboots === 0 ? to('rebooting', { reboots: 1 }) : to('failed:deadAgain');
    if (e === 'deadDown') return s.reboots === 0 ? to('rebooting', { reboots: 1 }) : to('failed:deadAgain');
  } else if (s.phase === 'relaunching') {
    if (e === 'relaunchOk') return to('running', { attempt: s.attempt + 1 });
    if (e === 'relaunchFail') return s.reboots === 0 ? to('rebooting', { reboots: 1 }) : to('failed:relaunchFailed');
  } else if (s.phase === 'rebooting') {
    if (e === 'rebootOk') return to('running', { attempt: s.attempt + 1 });
    if (e === 'rebootFail') return to('failed:rebootFailed');
  }
  return to('failed:protocol');
}
/** Lean: `exec`. */
export const exec = (s, es) => es.reduce(step, s);
/** Lean: `used`: the events taken before the pass is over. */
export function used(s, es) {
  let n = 0;
  for (const e of es) { if (terminal(s)) break; n++; s = step(s, e); }
  return n;
}
/** Lean: `cost`: the seconds an event may take in the phase it arrives in. */
export function cost(s, e) {
  if (s.phase === 'running' && (e === 'deadUp' || e === 'deadDown')) return RECOVER.detectS;
  if (s.phase === 'relaunching' && (e === 'relaunchOk' || e === 'relaunchFail')) return RECOVER.relaunchS;
  if (s.phase === 'rebooting' && (e === 'rebootOk' || e === 'rebootFail')) return RECOVER.rebootS;
  return 0;
}
/** Lean: `timeUsed`. */
export function timeUsed(s, es) {
  let t = 0;
  for (const e of es) { if (terminal(s)) break; t += cost(s, e); s = step(s, e); }
  return t;
}

const describe = (p) => `socket ${p.socket ? 'up' : 'gone'}, proxy ${p.proxy ? 'up' : 'down'}, page ${p.page ? 'listed' : 'missing'}`;

/**
 * @param {{probe:()=>Promise<{socket:boolean,proxy:boolean,page:boolean}>, relaunch:()=>Promise<void>, repair?:()=>Promise<void>,
 *   reboot?:(()=>Promise<void>)|null, deviceUp?:()=>boolean|Promise<boolean>,
 *   log?:Function, onDead?:(e:Error)=>void, tickMs?:number, probeMs?:number, relaunchMs?:number, rebootMs?:number}} o
 *   probe: one liveness probe (never throws). relaunch: Safari once more (within BOUNDS.relaunchMs). repair: runs after a
 *   single failed probe that does not yet make the inspector dead (the session starts the proxy again). reboot: shutdown and
 *   boot the device (null: none can be done); relaunch runs after it. deviceUp: is the device still booted.
 */
export function createGuard({
  probe, relaunch, repair = null, reboot = rebootDevice, deviceUp = deviceBooted, log = () => {}, onDead = () => {},
  tickMs = BOUNDS.tickMs, probeMs = BOUNDS.probeMs, relaunchMs = BOUNDS.relaunchMs, rebootMs = RECOVER.rebootS * 1000,
}) {
  let st = initPass(), fails = 0, busy = null, dead = null, timer = null;

  async function recover(what, first = null) {
    let ev = first;
    if (!ev) {
      let up = false;
      try { up = await within(RECOVER.detectS * 1000, 'the device check', Promise.resolve().then(() => deviceUp())); } catch { /* no answer: down */ }
      log(`the device is ${up ? 'booted' : 'not booted'}`);
      ev = up ? 'deadUp' : 'deadDown';
    }
    let relaunchError = null, rebootError = null;
    for (;;) {
      st = step(st, ev);
      fails = 0;
      if (st.phase === 'relaunching') {
        log(`relaunching Safari once: ${what}`);
        try { await within(relaunchMs, 'the relaunch', Promise.resolve().then(relaunch)); ev = 'relaunchOk'; } catch (e) { relaunchError = e; ev = 'relaunchFail'; }
      } else if (st.phase === 'rebooting') {
        log(`rebooting the Simulator once: ${what}`);
        try {
          if (!reboot) throw new Error('no reboot is available');
          await within(rebootMs, 'the reboot', (async () => { await reboot({ log }); await relaunch(); })());
          ev = 'rebootOk';
        } catch (e) { rebootError = e; ev = 'rebootFail'; }
      } else break;
    }
    if (terminal(st) && st.phase !== 'done') {
      const why = {
        'failed:deadAgain': `the inspector is dead again after Safari was relaunched and the device was rebooted (${what})`,
        'failed:relaunchFailed': `the inspector is dead and relaunching Safari failed: ${relaunchError?.message}`,
        'failed:rebootFailed': `the inspector is dead and rebooting the Simulator failed: ${rebootError?.message}${relaunchError ? `; relaunching Safari failed: ${relaunchError.message}` : ''}`,
      }[st.phase] ?? `the recover path broke its protocol (${st.phase})`;
      log(`giving up: ${why}; exit code ${BOUNDS.deadExit}`);
      throw new InspectorDeadError(why);
    }
    log('recovered; the inspector answers');
    return { ok: true, relaunched: true };
  }

  async function decide(why, withRepair) {
    let p;
    try { p = await within(probeMs, 'the probe', probe()); } catch { p = { socket: true, proxy: false, page: false }; }
    const r = inspectorReply({ relaunched: false, fails, ...p });
    fails = r.fails;
    if (!r.ok) log(`inspector probe failed (${why}): ${describe(p)}; ${fails} failed in a row`);
    if (r.dead) return recover(`the inspector is dead (${describe(p)})`);
    if (!r.ok && withRepair && repair) await repair();
    return { ok: r.ok, relaunched: false };
  }

  const guarded = (p) => p.catch((e) => { if (e instanceof InspectorDeadError) { dead = e; onDead(e); } throw e; }).finally(() => { busy = null; });

  /** One probe and its action. Concurrent calls share one run. Throws InspectorDeadError once the run must end. */
  function check(why = 'attempt', { repair: withRepair = false } = {}) {
    if (dead) return Promise.reject(dead);
    if (!busy) busy = guarded(decide(why, withRepair));
    return busy;
  }

  /**
   * Relaunch Safari for a lost page target. The guard's one relaunch is shared with the dead-inspector rule: it rejects when
   * Safari was relaunched already. A relaunch the guard started meanwhile counts as this one. A relaunch that fails reboots the
   * device once, like the dead-inspector rule.
   */
  async function relaunchTab() {
    if (dead) throw dead;
    if (st.relaunches > 0) throw new Error('Safari was relaunched already');
    if (busy) { await busy.catch(() => {}); if (dead) throw dead; if (st.relaunches > 0) return; }
    busy = guarded(recover('the page target is lost', 'deadUp'));
    await busy;
  }

  /** Probe on every tick of the stall watchdog's period; a tick that finds a probe still running is skipped. */
  function start() {
    timer = setInterval(() => { if (!busy && !dead) check('tick').catch(() => {}); }, tickMs);
    timer.unref?.();
  }
  function stop() { if (timer) clearInterval(timer); timer = null; }

  return {
    check, relaunchTab, start, stop,
    get relaunched() { return st.relaunches > 0; }, get rebooted() { return st.reboots > 0; }, get fails() { return fails; }, get dead() { return dead; },
  };
}
