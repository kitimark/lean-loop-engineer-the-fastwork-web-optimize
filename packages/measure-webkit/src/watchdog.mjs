// Fail fast instead of hanging (glue, no measurement logic). Two guards for the CLI process:
//   stall : no line on stdout/stderr for `stallMs` -> say so with the last line and the open handles, then SIGTERM ourselves
//           (session.mjs turns SIGTERM into its cleanup and exit 130); a hard exit follows `graceMs` later.
//   exit  : the command finished but the process is still alive `exitMs` later (an open socket or child keeps the event loop
//           running; seen on CI as a step that printed its result and then sat until the 50 minute step timeout) -> say which
//           resources are open and exit with the command's own code.
// The timers are unref'ed, so they never keep a healthy process alive. Counts never depend on any of this.
//
// Second guard, `run` (task sim-step-watchdog, incident inc-sim-step-unbounded): the workflow step runs every session command
// as `node src/watchdog.mjs run ... -- <command>`. At the step's deadline (Lean: Fw.Measure.SimBound.watchdogMin, passed in by the
// plan) it ends the command's whole process group (TERM, grace, KILL), prints one `watchdog` line naming the session and the
// last pass, and exits 6 (Lean: watchdogExit), so the steps after the measuring step still run inside the job limit. A VM that
// freezes completely stops this process too and stays unobservable.
import { spawn } from 'node:child_process';
import { appendFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { timeoutScale } from './timeouts.mjs';
import { BOUNDS } from './inspector.mjs';

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

/** Exit code of a command the watchdog ended: Lean's `Fw.Measure.SimBound.watchdogExit` (the BOUNDS table is checked against measure.simBounds.jsonl by test/fwcore.test.mjs). */
export const WATCHDOG_EXIT = BOUNDS.watchdogExit;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** True while any process of group `pgid` exists (kill signal 0 throws ESRCH when none is left). */
export function groupAlive(pgid, kill = process.kill) {
  try { kill(-pgid, 0); return true; } catch (e) { return e.code === 'EPERM'; }
}

/**
 * End a whole process group: SIGTERM, wait up to `graceMs` for it to be gone, SIGKILL, wait up to `killWaitMs`.
 * Returns { termSent, killSent, gone } (`gone` false = something survived the KILL).
 */
export async function endGroup(pgid, { graceMs, killWaitMs = BOUNDS.killWaitMs, kill = process.kill, alive = (g) => groupAlive(g, kill), pollMs = 50 } = {}) {
  const out = { termSent: false, killSent: false, gone: false };
  const waitGone = async (ms) => { for (let t = 0; t < ms && alive(pgid); t += pollMs) await sleep(pollMs); return !alive(pgid); };
  try { kill(-pgid, 'SIGTERM'); out.termSent = true; } catch { /* the group is already gone */ }
  if (await waitGone(graceMs)) { out.gone = true; return out; }
  try { kill(-pgid, 'SIGKILL'); out.killSent = true; } catch { /* gone between the check and the signal */ }
  out.gone = await waitGone(killWaitMs);
  return out;
}

/** The one `watchdog` line: the session, the last pass, the last output line and what happened to the group. */
export function watchdogLine({ label, elapsedS, budgetS, pass, lastLine, pgid, ended }) {
  const how = !pgid ? 'no command started (no time left)' : `ended process group ${pgid}: TERM ${ended.termSent ? 'sent' : 'not needed'}, KILL ${ended.killSent ? 'sent' : 'not needed'}, ${ended.gone ? 'group gone' : 'SURVIVORS left'}`;
  return `watchdog: ${label}: not finished ${elapsedS} s into the step (limit ${budgetS} s); pass: ${pass ?? '(none started)'}; last line: "${lastLine ?? '(no output)'}"; ${how}`;
}

/**
 * Run `cmd` in its own process group and end the group at `deadlineMs` (epoch ms). Output is mirrored to this process and
 * appended to the files. Resolves { code, fired }: the command's own exit code, or WATCHDOG_EXIT when the watchdog ended it.
 * @param {{cmd:string,args?:string[],label:string,deadlineMs:number,startMs?:number,graceMs:number,killWaitMs?:number,stdoutFile?:string,stderrFile?:string,say?:(s:string)=>void,echoOut?:(s:string|Buffer)=>void,echoErr?:(s:string|Buffer)=>void,now?:()=>number}} o
 */
export async function runBounded({ cmd, args = [], label, deadlineMs, startMs = Date.now(), graceMs, killWaitMs = BOUNDS.killWaitMs, stdoutFile, stderrFile, say = (s) => process.stderr.write(`${s}\n`), echoOut = (b) => process.stdout.write(b), echoErr = (b) => process.stderr.write(b), now = Date.now }) {
  const budgetS = Math.round((deadlineMs - startMs) / 1000);
  const fire = (pgid, pass, lastLine, ended) => say(watchdogLine({ label, elapsedS: Math.round((now() - startMs) / 1000), budgetS, pass, lastLine, pgid, ended }));
  for (const f of [stdoutFile, stderrFile]) if (f) writeFileSync(f, '');
  if (deadlineMs - now() <= 0) { fire(null, null, null, null); return { code: WATCHDOG_EXIT, fired: true }; }
  const child = spawn(cmd, args, { detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
  let pass = null, lastLine = null, exited = null;
  const take = (file, echo) => (chunk) => {
    echo(chunk);
    if (file) appendFileSync(file, chunk);
    for (const l of String(chunk).split('\n')) {
      const t = l.trim();
      if (!t) continue;
      lastLine = t.slice(0, 200);
      if (/^pass \d+\/\d+/.test(t)) pass = t.slice(0, 80);
    }
  };
  child.stdout.on('data', take(stdoutFile, echoOut));
  child.stderr.on('data', take(stderrFile, echoErr));
  const done = new Promise((resolve) => {
    child.on('exit', (code, signal) => { exited = { code: code ?? (signal ? 1 : 0) }; resolve(); });
    child.on('error', (e) => { exited = { code: 127 }; say(`watchdog: ${label}: cannot start ${cmd}: ${e.message}`); resolve(); });
  });
  let interrupted = null;
  const onSig = (sig) => () => { interrupted = sig; };
  const onInt = onSig('SIGINT'), onTerm = onSig('SIGTERM');
  process.on('SIGINT', onInt); process.on('SIGTERM', onTerm);
  let deadlineTimer, poll;
  const timer = new Promise((resolve) => { deadlineTimer = setTimeout(() => resolve('deadline'), Math.max(0, deadlineMs - now())); });
  const sig = new Promise((resolve) => { poll = setInterval(() => { if (interrupted) resolve('signal'); }, 100); });
  const why = await Promise.race([done.then(() => 'exit'), timer, sig]);
  clearTimeout(deadlineTimer); clearInterval(poll);
  process.off('SIGINT', onInt); process.off('SIGTERM', onTerm);
  if (why === 'exit') {
    // the command is gone: end what it left in its group (a proxy, a helper) so nothing outlives the session
    if (child.pid && groupAlive(child.pid)) await endGroup(child.pid, { graceMs: Math.min(graceMs, 2000), killWaitMs });
    child.stdout.destroy(); child.stderr.destroy();
    return { code: exited.code, fired: false };
  }
  const ended = await endGroup(child.pid, { graceMs, killWaitMs });
  child.stdout.destroy(); child.stderr.destroy();
  if (why === 'signal') { say(`watchdog: ${label}: ${interrupted} to the watchdog; ended process group ${child.pid} (${ended.gone ? 'group gone' : 'SURVIVORS left'})`); return { code: 130, fired: false }; }
  fire(child.pid, pass, lastLine, ended);
  return { code: WATCHDOG_EXIT, fired: true };
}

/** The fault `hang`: a command that ignores SIGINT, SIGTERM and SIGHUP, has a child that does the same, prints a pass line and never exits. */
export function hangStub(role, log = (s) => process.stderr.write(`${s}\n`)) {
  for (const s of ['SIGINT', 'SIGTERM', 'SIGHUP']) process.on(s, () => log(`${role} ${process.pid}: ${s} ignored`));
  if (role === 'hang') {
    const kid = spawn(process.execPath, [fileURLToPath(import.meta.url), 'hang-child'], { stdio: ['ignore', 'inherit', 'inherit'] });
    process.stdout.write(`grandchild ${kid.pid}\n`);
    log('pass 1/2');
  }
  let n = 0;
  setInterval(() => log(`${role} ${process.pid}: scroll step ${++n}`), 1000);
}

function parseRun(argv) {
  const o = {};
  const i = argv.indexOf('--');
  if (i < 0 || i === argv.length - 1) throw new Error('usage: watchdog.mjs run --label L (--budget-min M | --budget-s S) --grace-ms G [--start-s T] [--stdout-file F] [--stderr-file F] -- <command> [args]');
  const flags = argv.slice(0, i);
  for (let j = 0; j < flags.length; j += 2) o[flags[j].replace(/^--/, '')] = flags[j + 1];
  o.cmd = argv[i + 1]; o.args = argv.slice(i + 2);
  return o;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [sub, ...rest] = process.argv.slice(2);
  if (sub === 'hang' || sub === 'hang-child') hangStub(sub);
  else if (sub === 'run') {
    try {
      const o = parseRun(rest);
      const num = (v, name) => { const n = Number(v); if (v === undefined || !Number.isFinite(n) || n < 0) throw new Error(`--${name} must be a number >= 0, got "${v}"`); return n; };
      const startMs = o['start-s'] !== undefined ? num(o['start-s'], 'start-s') * 1000 : Date.now();
      const budgetMs = o['budget-s'] !== undefined ? num(o['budget-s'], 'budget-s') * 1000 : num(o['budget-min'], 'budget-min') * 60000;
      runBounded({ cmd: o.cmd, args: o.args, label: o.label ?? o.cmd, startMs, deadlineMs: startMs + budgetMs, graceMs: num(o['grace-ms'], 'grace-ms'), stdoutFile: o['stdout-file'], stderrFile: o['stderr-file'] })
        .then((r) => process.exit(r.code), (e) => { console.error(`watchdog: ${e.message}`); process.exit(2); });
    } catch (e) { console.error(`watchdog: ${e.message}`); process.exit(2); }
  } else { console.error('usage: watchdog.mjs run ... | hang'); process.exit(2); }
}
