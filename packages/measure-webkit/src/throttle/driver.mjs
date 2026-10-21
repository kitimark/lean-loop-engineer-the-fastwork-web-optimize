// The real-touch driver of the toolbar-throttle probe (I/O glue): builds the XCUITest bundle in driver/ once (xcodegen, then
// xcodebuild build-for-testing in a temp dir; nothing is written into the repository) and runs its drag test against the booted
// Simulator, which swipes in Mobile Safari with real touches. Every child runs in its own process group and is stopped by `stop`.
import { spawn, spawnSync } from 'node:child_process';
import { cpSync, mkdtempSync, readdirSync, rmSync, createWriteStream } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { T } from '../timeouts.mjs';

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

/** Build the driver. Returns {dir, xctestrun}. `udid` names the Simulator device (never printed). */
export async function buildDriver({ udid, log = () => {}, timeoutMs = 600000 }) {
  const dir = mkdtempSync(join(tmpdir(), 'fw-throttle-driver-'));
  cpSync(join(HERE, 'driver'), dir, { recursive: true });
  const logFile = join(dir, 'build.log');
  const gen = spawnSync('xcodegen', ['generate'], { cwd: dir, encoding: 'utf8' });
  if (gen.status !== 0) throw new Error(`xcodegen failed: ${(gen.stderr || gen.stdout || '').slice(-400)}`);
  const t0 = Date.now();
  const r = await runGroup('xcodebuild', ['build-for-testing', '-project', 'FwThrottleDriver.xcodeproj', '-scheme', 'FwThrottleDriver',
    '-destination', `id=${udid}`, '-derivedDataPath', join(dir, 'dd')], { cwd: dir, timeoutMs, logFile });
  if (r.code !== 0) throw new Error(`xcodebuild build-for-testing failed (code ${r.code}${r.timedOut ? ', timed out' : ''}); log tail in ${logFile}`);
  const prods = join(dir, 'dd', 'Build', 'Products');
  const xctestrun = readdirSync(prods).find((f) => f.endsWith('.xctestrun'));
  if (!xctestrun) throw new Error('no .xctestrun after build-for-testing');
  log(`driver built in ${Math.round((Date.now() - t0) / 1000)} s`);
  return { dir, xctestrun: join(prods, xctestrun) };
}

/** One pass of touches: cycles of a slow drag up and down. Resolves {code, timedOut, logFile}. */
export async function dragPass(driver, { udid, cycles = 4, dragPt = 360, velocity = 120, holdMs = 600, timeoutMs = T(120000), tag = 'pass' }) {
  const env = { ...process.env, TEST_RUNNER_FW_CYCLES: String(cycles), TEST_RUNNER_FW_DRAG_PT: String(dragPt),
    TEST_RUNNER_FW_VELOCITY: String(velocity), TEST_RUNNER_FW_HOLD_MS: String(holdMs) };
  const logFile = join(driver.dir, `${tag}.log`);
  const r = await runGroup('xcodebuild', ['test-without-building', '-xctestrun', driver.xctestrun, '-destination', `id=${udid}`,
    '-only-testing:DriverUITests/DragTests/testDrags', '-resultBundlePath', join(driver.dir, `${tag}.xcresult`)], { cwd: driver.dir, env, timeoutMs, logFile });
  return { ...r, logFile };
}

/** Remove the temp build. */
export function cleanup(driver) {
  if (driver?.dir) rmSync(driver.dir, { recursive: true, force: true });
}
