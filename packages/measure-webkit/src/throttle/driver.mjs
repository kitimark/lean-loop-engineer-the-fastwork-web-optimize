// The real-touch driver of the toolbar-throttle probe (I/O glue): builds the XCUITest bundle in driver/ once (xcodegen, then
// xcodebuild build-for-testing in a temp dir; nothing is written into the repository) and runs its drag test against the booted
// Simulator, which swipes in Mobile Safari with real touches. Every child runs in its own process group and is stopped by `stop`.
import { spawn, spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, createWriteStream } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { listDevices, sleep } from '../sim.mjs';
import { timeoutScale } from '../timeouts.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const children = new Set();

/**
 * Run a command in its own process group; resolves {code, signal, timedOut, killedBy}. Output goes to `logFile`. SIGTERM at the hard
 * `timeoutMs` or when `watch.check(elapsedMs)` returns a reason (polled every `watch.everyMs`); SIGKILL `graceMs` later to the group.
 */
export function runGroup(cmd, args, { cwd, env = process.env, timeoutMs, logFile, watch = null, graceMs = 20000 }) {
  return new Promise((resolve, reject) => {
    const out = logFile ? createWriteStream(logFile, { flags: 'a' }) : null;
    const p = spawn(cmd, args, { cwd, env, detached: true, stdio: ['ignore', out ? 'pipe' : 'ignore', out ? 'pipe' : 'ignore'] });
    children.add(p);
    if (out) { p.stdout.pipe(out, { end: false }); p.stderr.pipe(out, { end: false }); }
    const t0 = Date.now();
    let timedOut = false, killedBy = null, grace = null;
    const killGroup = (why) => {
      if (timedOut) return;
      timedOut = true; killedBy = why;
      try { process.kill(-p.pid, 'SIGTERM'); } catch { /* gone */ }
      grace = setTimeout(() => { try { process.kill(-p.pid, 'SIGKILL'); } catch { /* gone */ } }, graceMs);
    };
    const timer = setTimeout(() => killGroup('timeout'), timeoutMs);
    const ticker = watch ? setInterval(() => { const why = watch.check(Date.now() - t0); if (why) killGroup(why); }, watch.everyMs) : null;
    const clear = () => { clearTimeout(timer); clearTimeout(grace); if (ticker) clearInterval(ticker); };
    p.on('error', (e) => { clear(); children.delete(p); out?.end(); reject(e); });
    p.on('close', (code, signal) => {
      clear(); children.delete(p); out?.end();
      try { process.kill(-p.pid, 'SIGKILL'); } catch { /* group already gone */ }
      resolve({ code, signal, timedOut, killedBy });
    });
  });
}

/** Stop every group this module started (also from a signal handler). */
export function stop() {
  for (const p of children) { try { process.kill(-p.pid, 'SIGTERM'); } catch { /* gone */ } }
}

/** The .xctestrun of a finished build in `dir`. */
export function findDriver(dir) {
  const prods = join(dir, 'dd', 'Build', 'Products');
  const xctestrun = readdirSync(prods).find((f) => f.endsWith('.xctestrun'));
  if (!xctestrun) throw new Error(`no .xctestrun in ${prods}`);
  return { dir, xctestrun: join(prods, xctestrun) };
}

/**
 * Build the driver into `dir` (a new temp dir when absent). Returns {dir, xctestrun}. Without `udid` the build targets any iOS
 * Simulator, so it can run before the Simulator boots (a build next to a booted Simulator on the 3-vCPU runner starved it).
 */
export async function buildDriver({ udid, dir: given, log = () => {}, timeoutMs = 600000 }) {
  const dir = given ?? mkdtempSync(join(tmpdir(), 'fw-throttle-driver-'));
  mkdirSync(dir, { recursive: true });
  cpSync(join(HERE, 'driver'), dir, { recursive: true });
  const logFile = join(dir, 'build.log');
  const gen = spawnSync('xcodegen', ['generate'], { cwd: dir, encoding: 'utf8' });
  if (gen.status !== 0) throw new Error(`xcodegen failed: ${(gen.stderr || gen.stdout || '').slice(-400)}`);
  const t0 = Date.now();
  const r = await runGroup('xcodebuild', ['build-for-testing', '-project', 'FwThrottleDriver.xcodeproj', '-scheme', 'FwThrottleDriver',
    '-destination', udid ? `id=${udid}` : 'generic/platform=iOS Simulator', '-derivedDataPath', join(dir, 'dd')], { cwd: dir, timeoutMs, logFile });
  if (r.code !== 0) throw new Error(`xcodebuild build-for-testing failed (code ${r.code}${r.timedOut ? ', timed out' : ''}); log tail in ${logFile}`);
  log(`driver built in ${Math.round((Date.now() - t0) / 1000)} s`);
  return findDriver(dir);
}

/** The XCUITest method of each drag mode in DragTests.swift: the hero exit drags, or the drags past the page end. */
export const DRAG_TESTS = Object.freeze({ drags: 'testDrags', finish: 'testFinish' });

// ---- the readiness / watchdog / retry machine: the TS twin of lean/Fw/Device/SimTouch.lean (golden device/sim-touch.jsonl) ----

/** The constants of Fw.Device.SimTouch (seconds unless named otherwise). */
export const SIM_TOUCH = Object.freeze({ probeTries: 6, probeGapS: 10, probeBudgetS: 60, startS: 300, gapS: 120, capBaseS: 300, capPressS: 45,
  pollS: 5, restartS: 600, stepLimitS: 5400, typicalPassS: 420, passEvents: 5 });

/** Presses of a pass: a hero-exit cycle is two presses, a finish cycle three. */
export const presses = (mode, cycles) => (mode === 'finish' ? 3 : 2) * cycles;
/** Hard cap in seconds on one touch run of `n` presses. */
export const capS = (n) => SIM_TOUCH.capBaseS + n * SIM_TOUCH.capPressS;
/** The stall rule: 'ok' | 'startup' | 'press' | 'cap' after `elapsed` s with `marks` marks seen, the last `since` s ago. */
export function stall(n, elapsed, marks, since) {
  if (capS(n) <= elapsed) return 'cap';
  if (marks === 0) return SIM_TOUCH.startS <= elapsed ? 'startup' : 'ok';
  return SIM_TOUCH.gapS <= since ? 'press' : 'ok';
}
/** The Simulator is booted, the Safari page answers and the driver is built. */
export const ready = (sim, page, driver) => Boolean(sim && page && driver);

/** A pass before its first probe. Phases: probing | touching | restarting | done | failed:<notReady|touchesFailed|restartFailed|protocol>. */
export const initPass = () => ({ phase: 'probing', attempt: 1, restarts: 0 });
export const terminal = (s) => s.phase === 'done' || s.phase.startsWith('failed:');
const lose = (s, f) => (s.restarts === 0 ? { phase: 'restarting', attempt: s.attempt, restarts: 1 } : { phase: `failed:${f}`, attempt: s.attempt, restarts: s.restarts });
/** One event of a pass (readyYes | readyNo | touchesOk | touchesFail | restartOk | restartFail). */
export function step(s, e) {
  if (terminal(s)) return s;
  const keep = (phase) => ({ phase, attempt: s.attempt, restarts: s.restarts });
  if (s.phase === 'probing' && e === 'readyYes') return keep('touching');
  if (s.phase === 'probing' && e === 'readyNo') return lose(s, 'notReady');
  if (s.phase === 'touching' && e === 'touchesOk') return keep('done');
  if (s.phase === 'touching' && e === 'touchesFail') return lose(s, 'touchesFailed');
  if (s.phase === 'restarting' && e === 'restartOk') return { phase: 'probing', attempt: s.attempt + 1, restarts: s.restarts };
  if (s.phase === 'restarting' && e === 'restartFail') return keep('failed:restartFailed');
  return keep('failed:protocol');
}
/** A pass after a list of events, and how many of them it consumed. */
export function exec(s, events) {
  let used = 0;
  for (const e of events) { if (terminal(s)) break; s = step(s, e); used++; }
  return { state: s, used };
}

/** The stall watch of one touch run: feed it the seconds elapsed and the mark names seen; it keeps when each mark was first seen. */
export function touchWatch(n) {
  const seen = [];
  let last = 0;
  return {
    seen,
    verdict(elapsedS, names) {
      for (const name of names) if (!seen.some((m) => m.name === name)) { seen.push({ name, atS: elapsedS }); last = elapsedS; }
      return stall(n, elapsedS, seen.length, elapsedS - last);
    },
  };
}

/** Raised by dragPass when the readiness probe never says yes; no touch run was started. */
export class NotReadyError extends Error {
  constructor(probe) { super(`not ready after ${probe.tries} probes (sim ${probe.sim}, page ${probe.page}, driver ${probe.driver})`); this.probe = probe; }
}

/** Probe up to `tries` times, `gapS` apart, until the Simulator, the page and the driver are all ready. `checks` return booleans (a throw counts as false). */
export async function probeLoop(checks, { tries = SIM_TOUCH.probeTries, gapS = SIM_TOUCH.probeGapS, nap = sleep, log = () => {} } = {}) {
  const t0 = Date.now();
  const seen = { sim: false, page: false, driver: false };
  for (let i = 1; i <= tries; i++) {
    for (const k of Object.keys(seen)) seen[k] = await Promise.resolve().then(checks[k]).then(Boolean, () => false);
    const ok = ready(seen.sim, seen.page, seen.driver);
    log(`ready probe ${i}/${tries}: sim ${seen.sim}, page ${seen.page}, driver ${seen.driver}`);
    if (ok) return { ready: true, tries: i, waitedS: Math.round((Date.now() - t0) / 1000), ...seen };
    if (i < tries) await nap(gapS * 1000);
  }
  return { ready: false, tries, waitedS: Math.round((Date.now() - t0) / 1000), ...seen };
}

// hooks the CLI sets per session: `page` (async, true when the open Safari page answers), `capOnceS` (debug: a cap for the next measured touch run)
const hooks = { page: null, capOnceS: null };
let lastTouchRec = null;
const runsOfTag = new Map();
export const setTouchHooks = (h) => Object.assign(hooks, h);
/** The record of the latest dragPass call (ready probe, marks, elapsed, stall verdict, log file), or null. */
export const lastTouch = () => lastTouchRec;
export const resetTouch = () => { lastTouchRec = null; };

const markNames = (dir) => { try { return readdirSync(dir).filter((f) => f === 'started' || /^press-\d+$/.test(f)); } catch { return []; } };
const withDeadline = (p, ms) => Promise.race([p, new Promise((_, rej) => setTimeout(() => rej(new Error('probe check timed out')), ms).unref?.())]);

/**
 * One pass of touches: cycles of a slow drag up and down. Mode `finish` drags past the page end. First the readiness probe (Simulator
 * booted, page answering, driver built), then xcodebuild under the stall watch (the Lean stall rule on the progress marks the XCUITest writes).
 * Resolves {code, signal, timedOut, killedBy, logFile, touch}; throws NotReadyError (no run started) when the probe never says yes.
 * Each call has its own result bundle and log: a second call with the same `tag` becomes `<tag>-t2` (xcodebuild refuses an existing bundle).
 */
export async function dragPass(driver, { udid, cycles = 4, dragPt = 360, velocity = 120, holdMs = 600, mode = 'drags', target = 'springboard', timeoutMs, tag = 'pass', log = () => {} }) {
  if (!DRAG_TESTS[mode]) throw new Error(`unknown drag mode ${mode}`);
  const nth = (runsOfTag.get(tag) ?? 0) + 1;
  runsOfTag.set(tag, nth);
  const passTag = nth === 1 ? tag : `${tag}-t${nth}`;
  const n = presses(mode, cycles);
  const capOnce = tag === 'warm-up' ? null : hooks.capOnceS;
  if (capOnce != null) hooks.capOnceS = null;
  const rec = { tag: passTag, mode, presses: n, capS: capOnce ?? capS(n), ready: null, marks: [], elapsedS: null, code: null, killedBy: null, logFile: join(driver.dir, `${passTag}.log`) };
  lastTouchRec = rec;
  rec.ready = await probeLoop({
    sim: () => listDevices().some((d) => d.udid === udid && d.state === 'Booted'),
    page: () => (hooks.page ? withDeadline(hooks.page(), 20000) : true),
    driver: () => existsSync(driver.xctestrun),
  }, { log: (l) => log(`${passTag}: ${l}`) });
  if (!rec.ready.ready) throw new NotReadyError(rec.ready);
  const marksDir = join(driver.dir, `${passTag}.marks`);
  rmSync(marksDir, { recursive: true, force: true });
  mkdirSync(marksDir, { recursive: true });
  const env = { ...process.env, TEST_RUNNER_FW_CYCLES: String(cycles), TEST_RUNNER_FW_DRAG_PT: String(dragPt),
    TEST_RUNNER_FW_VELOCITY: String(velocity), TEST_RUNNER_FW_HOLD_MS: String(holdMs), TEST_RUNNER_FW_TARGET: target,
    TEST_RUNNER_FW_DIR: marksDir, TEST_RUNNER_FW_WAIT_SCALE: String(timeoutScale()) };
  const w = touchWatch(n);
  const check = (elapsedMs) => {
    const elapsedS = Math.floor(elapsedMs / 1000);
    const before = w.seen.length;
    const v = capOnce != null && elapsedS >= capOnce ? 'cap' : w.verdict(elapsedS, markNames(marksDir));
    if (w.seen.length > before) log(`${passTag}: ${w.seen.slice(before).map((m) => m.name).join(', ')} at ${elapsedS} s`);
    return v === 'ok' ? null : v;
  };
  // the driver's output goes to its log file, so this line is what the stall guard of the CLI sees while the touches run
  const t0 = Date.now();
  const beat = setInterval(() => log(`${passTag}: touches running, ${Math.round((Date.now() - t0) / 1000)} s, ${w.seen.length} marks`), 30000);
  const destSecs = Math.min(120, Math.round(30 * timeoutScale()));
  const r = await runGroup('xcodebuild', ['test-without-building', '-xctestrun', driver.xctestrun, '-destination', `id=${udid}`, '-destination-timeout', String(destSecs),
    `-only-testing:DriverUITests/DragTests/${DRAG_TESTS[mode]}`, '-resultBundlePath', join(driver.dir, `${passTag}.xcresult`)],
  { cwd: driver.dir, env, timeoutMs: timeoutMs ?? (rec.capS + 60) * 1000, logFile: rec.logFile, watch: { everyMs: SIM_TOUCH.pollS * 1000, check } }).finally(() => clearInterval(beat));
  check(Date.now() - t0);
  Object.assign(rec, { marks: w.seen, elapsedS: Math.round((Date.now() - t0) / 1000), code: r.code, killedBy: r.killedBy });
  if (r.killedBy) log(`${passTag}: touch run stopped (${r.killedBy}) after ${rec.elapsedS} s with ${w.seen.length} marks`);
  return { ...r, logFile: rec.logFile, touch: rec };
}

/**
 * One long run of the push server (driver/UITests/PushServer.swift): it swipes on request through files in `dir` (go-<n> asks,
 * done-<n> answers, ready first, stop last). Returns at once: {state, exited, logFile}; `state.ended` flips when xcodebuild ends.
 */
export function serve(driver, { udid, dir, push, maxS = 2400, tag = 'serve' }) {
  const env = { ...process.env, TEST_RUNNER_FW_DIR: dir, TEST_RUNNER_FW_DRAG_PT: String(push.dragPt), TEST_RUNNER_FW_VELOCITY: String(push.velocity),
    TEST_RUNNER_FW_HOLD_MS: String(push.holdMs), TEST_RUNNER_FW_MAX_S: String(maxS) };
  const logFile = join(driver.dir, `${tag}.log`);
  const state = { ended: false, code: null, timedOut: false };
  const exited = runGroup('xcodebuild', ['test-without-building', '-xctestrun', driver.xctestrun, '-destination', `id=${udid}`,
    '-only-testing:DriverUITests/PushServer/testServe', '-resultBundlePath', join(driver.dir, `${tag}.xcresult`)], { cwd: driver.dir, env, timeoutMs: (maxS + 120) * 1000, logFile })
    .then((r) => { Object.assign(state, { ended: true, code: r.code, timedOut: r.timedOut }); return r; });
  return { state, exited, logFile };
}

/** Remove the temp build. */
export function cleanup(driver) {
  if (driver?.dir) rmSync(driver.dir, { recursive: true, force: true });
}
