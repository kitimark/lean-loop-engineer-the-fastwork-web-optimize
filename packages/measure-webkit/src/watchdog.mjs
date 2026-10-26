// Fail fast instead of hanging (glue, no measurement logic). Two guards for the CLI process:
//   stall : no line on stdout/stderr for `stallMs` -> say so with the last line and the open handles, then SIGTERM ourselves
//           (session.mjs turns SIGTERM into its cleanup and exit 130); a hard exit follows `graceMs` later.
//   exit  : the command finished but the process is still alive `exitMs` later (an open socket or child keeps the event loop
//           running; seen on CI as a step that printed its result and then sat until the 50 minute step timeout) -> say which
//           resources are open and exit with the command's own code.
import { timeoutScale } from './timeouts.mjs';
import { pendingCalls } from './sim.mjs';

export const defaultStallMs = (env = process.env) => {
  const n = Number(env.FW_WK_STALL_MS);
  return Number.isFinite(n) && n > 0 ? n : Math.round(90000 * timeoutScale(env));
};

export const stalled = (now, lastAt, limitMs) => now - lastAt > limitMs;

export const lagMs = (tickMs, sinceMs) => Math.max(0, sinceMs - tickMs);
export const tickBlocked = (tickMs, sinceMs) => tickMs > 0 && tickMs <= lagMs(tickMs, sinceMs);

export function openResources(info = process.getActiveResourcesInfo()) {
  const out = {};
  for (const k of info) out[k] = (out[k] || 0) + 1;
  return out;
}

/**
 * @param {{stallMs?:number, graceMs?:number, exitMs?:number, say?:(s:string)=>void, now?:()=>number, kill?:()=>void, exit?:(c:number)=>void}} o
 */
export function watch({ stallMs = defaultStallMs(), graceMs = 15000, exitMs = 20000, say = (s) => process.stderr.write(`${s}\n`), now = Date.now, kill = () => process.kill(process.pid, 'SIGTERM'), exit = (c) => process.exit(c), pending = pendingCalls, tickMs = Math.max(1000, Math.min(30000, Math.round(stallMs / 10))) } = {}) {
  let last = now(), lastTick = last, lastLine = '(no output yet)', fired = false, muted = false, worstLagMs = 0, blocks = 0;
  const stamp = (chunk) => { if (muted) return; last = now(); const t = String(chunk).trim(); if (t) lastLine = t.split('\n').pop().slice(0, 200); };
  for (const s of [process.stdout, process.stderr]) {
    const w = s.write.bind(s);
    s.write = (chunk, ...rest) => { stamp(chunk); return w(chunk, ...rest); };
  }
  const calls = (t) => JSON.stringify(pending(t).map((c) => `${c.what} ${Math.round(c.ageMs / 1000)} s of ${Math.round(c.boundMs / 1000)} s`));
  const tick = setInterval(() => {
    const t = now(), since = t - lastTick;
    lastTick = t;
    if (tickBlocked(tickMs, since)) {
      worstLagMs = Math.max(worstLagMs, lagMs(tickMs, since));
      blocks++;
      muted = true;
      try { say(`warning: event loop blocked: the ${Math.round(tickMs / 1000)} s tick came ${Math.round(lagMs(tickMs, since) / 1000)} s late; host calls running: ${calls(t)}`); } finally { muted = false; }
    }
    if (fired || !stalled(t, last, stallMs)) return;
    fired = true;
    say(`error: stalled: no output for ${Math.round((t - last) / 1000)} s (limit ${Math.round(stallMs / 1000)} s); last line: "${lastLine}"; open: ${JSON.stringify(openResources())}; host calls running: ${calls(t)}; event loop blocked ${blocks} time(s), worst ${Math.round(worstLagMs / 1000)} s`);
    process.exitCode = 3;
    kill();
    setTimeout(() => exit(3), graceMs).unref();
  }, tickMs);
  tick.unref();
  return {
    done(code) {
      clearInterval(tick);
      process.once('exit', (c) => say(`cli: exit ${c}`));
      setTimeout(() => {
        say(`error: forced exit: the command finished but ${Math.round(exitMs / 1000)} s later the process is alive; open: ${JSON.stringify(openResources())}`);
        exit(code ?? process.exitCode ?? 0);
      }, exitMs).unref();
    },
  };
}
