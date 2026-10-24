// The real-touch driver of the toolbar-throttle probe (I/O glue): builds the XCUITest bundle in driver/ once (xcodegen, then
// xcodebuild build-for-testing in a temp dir; nothing is written into the repository) and runs its drag test against the booted
// Simulator, which swipes in Mobile Safari with real touches. Every child runs in its own process group and is stopped by `stop`.
import { spawn, spawnSync } from 'node:child_process';
import { cpSync, mkdirSync, mkdtempSync, readdirSync, rmSync, createWriteStream } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const children = new Set();

/** Run a command in its own process group; resolves {code, signal, timedOut}. Output goes to `logFile`. */
export function runGroup(cmd, args, { cwd, env = process.env, timeoutMs, logFile }) {
  return new Promise((resolve, reject) => {
    const out = logFile ? createWriteStream(logFile, { flags: 'a' }) : null;
    const p = spawn(cmd, args, { cwd, env, detached: true, stdio: ['ignore', out ? 'pipe' : 'ignore', out ? 'pipe' : 'ignore'] });
    children.add(p);
    if (out) { p.stdout.pipe(out, { end: false }); p.stderr.pipe(out, { end: false }); }
    let timedOut = false;
    const timer = setTimeout(() => { timedOut = true; try { process.kill(-p.pid, 'SIGTERM'); } catch { /* gone */ } }, timeoutMs);
    p.on('error', (e) => { clearTimeout(timer); children.delete(p); out?.end(); reject(e); });
    p.on('close', (code, signal) => {
      clearTimeout(timer); children.delete(p); out?.end();
      try { process.kill(-p.pid, 'SIGKILL'); } catch { /* group already gone */ }
      resolve({ code, signal, timedOut });
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

/** One pass of touches: cycles of a slow drag up and down. Resolves {code, timedOut, logFile}. Mode `finish` drags past the page end. */
export async function dragPass(driver, { udid, cycles = 4, dragPt = 360, velocity = 120, holdMs = 600, mode = 'drags', target = 'springboard', timeoutMs = 300000, tag = 'pass', log = () => {} }) {
  if (!DRAG_TESTS[mode]) throw new Error(`unknown drag mode ${mode}`);
  const env = { ...process.env, TEST_RUNNER_FW_CYCLES: String(cycles), TEST_RUNNER_FW_DRAG_PT: String(dragPt),
    TEST_RUNNER_FW_VELOCITY: String(velocity), TEST_RUNNER_FW_HOLD_MS: String(holdMs), TEST_RUNNER_FW_TARGET: target };
  const logFile = join(driver.dir, `${tag}.log`);
  // the driver's output goes to its log file, so this line is what the stall watchdog sees while the touches run
  const t0 = Date.now();
  const beat = setInterval(() => log(`${tag}: touches running, ${Math.round((Date.now() - t0) / 1000)} s`), 30000);
  const r = await runGroup('xcodebuild', ['test-without-building', '-xctestrun', driver.xctestrun, '-destination', `id=${udid}`,
    `-only-testing:DriverUITests/DragTests/${DRAG_TESTS[mode]}`, '-resultBundlePath', join(driver.dir, `${tag}.xcresult`)], { cwd: driver.dir, env, timeoutMs, logFile }).finally(() => clearInterval(beat));
  return { ...r, logFile };
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
