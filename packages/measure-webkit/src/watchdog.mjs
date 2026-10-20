// Fail fast instead of hanging (glue, no measurement logic). Two guards for the CLI process:
//   stall : no line on stdout/stderr for `stallMs` -> say so with the last line and the open handles, then SIGTERM ourselves
//           (session.mjs turns SIGTERM into its cleanup and exit 130); a hard exit follows `graceMs` later.
//   exit  : the command finished but the process is still alive `exitMs` later (an open socket or child keeps the event loop
//           running; seen on CI as a step that printed its result and then sat until the 50 minute step timeout) -> say which
//           resources are open and exit with the command's own code.
// The timers are unref'ed, so they never keep a healthy process alive. Counts never depend on any of this.
import { timeoutScale } from './timeouts.mjs';

/** Default stall limit: 90 s of silence, scaled like every other wait (12 min at FW_WK_TIMEOUT_SCALE 8); FW_WK_STALL_MS overrides (the workflow passes Lean's `stallMs`, the same 12 min). */
export const defaultStallMs = (env = process.env) => {
  const n = Number(env.FW_WK_STALL_MS);
  return Number.isFinite(n) && n > 0 ? n : Math.round(90000 * timeoutScale(env));
};

/** True when `now - lastAt` exceeds the limit (the one rule of the stall guard). */
export const stalled = (now, lastAt, limitMs) => now - lastAt > limitMs;

/** The kinds of open resources, counted: { Timeout: 1, TCPSocketWrap: 2, ... }. */
export function openResources(info = process.getActiveResourcesInfo()) {
  const out = {};
  for (const k of info) out[k] = (out[k] || 0) + 1;
  return out;
}

/**
 * Watch this process. Returns { done(code) } to call when the command has finished.
 * @param {{stallMs?:number, graceMs?:number, exitMs?:number, say?:(s:string)=>void, now?:()=>number, kill?:()=>void, exit?:(c:number)=>void}} o
 */
export function watch({ stallMs = defaultStallMs(), graceMs = 15000, exitMs = 20000, say = (s) => process.stderr.write(`${s}\n`), now = Date.now, kill = () => process.kill(process.pid, 'SIGTERM'), exit = (c) => process.exit(c) } = {}) {
  let last = now(), lastLine = '(no output yet)', fired = false;
  const stamp = (chunk) => { last = now(); const t = String(chunk).trim(); if (t) lastLine = t.split('\n').pop().slice(0, 200); };
  for (const s of [process.stdout, process.stderr]) {
    const w = s.write.bind(s);
    s.write = (chunk, ...rest) => { stamp(chunk); return w(chunk, ...rest); };
  }
  const tick = setInterval(() => {
    if (fired || !stalled(now(), last, stallMs)) return;
    fired = true;
    say(`error: stalled: no output for ${Math.round((now() - last) / 1000)} s (limit ${Math.round(stallMs / 1000)} s); last line: "${lastLine}"; open: ${JSON.stringify(openResources())}`);
    process.exitCode = 3;
    kill();
    setTimeout(() => exit(3), graceMs).unref();
  }, Math.max(1000, Math.min(30000, Math.round(stallMs / 10))));
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
