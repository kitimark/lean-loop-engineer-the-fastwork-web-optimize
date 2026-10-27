import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { runGroup, findDriver, serve } from './throttle/driver.mjs';
import { deviceBuildArgs, keychainTeam } from './device-xcui.mjs';
import { logTail, TOUCH_PUSH } from './touch-push.mjs';
import { sleep } from './sim.mjs';

export const RUNNER_ID = 'dev.fastwork-study.throttle-driver.xctrunner';
const DRIVER_SRC = fileURLToPath(new URL('./throttle/driver/', import.meta.url));

export const PUSH_SWIFT = `import XCTest

/// Phone push server: a swipe up, a hold, a swipe down, a hold per request. Requests arrive as files in this app's Documents folder
/// (\`go-<n>\`, \`stop\`); answers are marker lines in the test output. Parameters: TEST_RUNNER_FW_DRAG_PT, VELOCITY, HOLD_MS, MAX_S.
final class PushServer: XCTestCase {
    private func number(_ key: String, _ fallback: Double) -> Double {
        Double(ProcessInfo.processInfo.environment["FW_" + key] ?? "") ?? fallback
    }

    func testServe() throws {
        let dragPt = number("DRAG_PT", 300)
        let velocity = number("VELOCITY", 600)
        let hold = number("HOLD_MS", 1000) / 1000
        let maxSeconds = number("MAX_S", 2400)
        let files = FileManager.default
        let docs = files.urls(for: .documentDirectory, in: .userDomainMask)[0].path
        for name in (try? files.contentsOfDirectory(atPath: docs)) ?? [] where name.hasPrefix("go-") || name == "stop" {
            try? files.removeItem(atPath: docs + "/" + name)
        }
        NSLog("FWPUSH step home")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.5)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        NSLog("FWPUSH step snapshot")
        let height = springboard.frame.height
        XCTAssertGreaterThan(height, 0)
        NSLog("FWPUSH step activate")
        XCUIApplication(bundleIdentifier: "com.apple.mobilesafari").activate()
        Thread.sleep(forTimeInterval: 2.0)
        let span = min(dragPt, height * 0.6) / height
        let gesture = XCUIGestureVelocity(rawValue: velocity)
        let from = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        let to = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78 - span))
        NSLog("FWPUSH ready %d", Int(height))

        let started = Date()
        var next = 0
        while Date().timeIntervalSince(started) < maxSeconds && !files.fileExists(atPath: docs + "/stop") {
            if files.fileExists(atPath: docs + "/go-\\(next)") {
                let t0 = Date()
                from.press(forDuration: 0.05, thenDragTo: to, withVelocity: gesture, thenHoldForDuration: hold)
                let t1 = Date()
                to.press(forDuration: 0.05, thenDragTo: from, withVelocity: gesture, thenHoldForDuration: hold)
                let t2 = Date()
                NSLog("FWPUSH done %d ok %d %d", next, Int(t1.timeIntervalSince(t0) * 1000), Int(t2.timeIntervalSince(t1) * 1000))
                next += 1
            } else {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        NSLog("FWPUSH stopped")
    }
}
`;

export function parseMarkers(text) {
  const out = { ready: null, done: new Map(), steps: [] };
  for (const m of text.matchAll(/FWPUSH (ready (\d+)|done (\d+) (ok \d+ \d+)|step (\w+)|stopped)/g)) {
    if (m[2] !== undefined) out.ready = Number(m[2]);
    else if (m[3] !== undefined) out.done.set(Number(m[3]), m[4]);
    else if (m[5] !== undefined) out.steps.push(m[5]);
  }
  return out;
}

export async function buildPushDriver({ udid, dir, team = keychainTeam(), log = () => {}, timeoutMs = 600000 }) {
  mkdirSync(dir, { recursive: true });
  cpSync(DRIVER_SRC, dir, { recursive: true });
  writeFileSync(join(dir, 'UITests', 'PushServer.swift'), PUSH_SWIFT);
  const gen = spawnSync('xcodegen', ['generate'], { cwd: dir, encoding: 'utf8' });
  if (gen.status !== 0) throw new Error(`xcodegen failed: ${(gen.stderr || gen.stdout || '').slice(-400)}`);
  const logFile = join(dir, 'build.log');
  const t0 = Date.now();
  const r = await runGroup('xcodebuild', deviceBuildArgs({ udid, team, derived: join(dir, 'dd') }), { cwd: dir, timeoutMs, logFile });
  if (r.code !== 0) throw new Error(`xcodebuild build-for-testing failed (code ${r.code}${r.timedOut ? ', timed out' : ''}); log tail in ${logFile}`);
  log(`phone push driver built in ${Math.round((Date.now() - t0) / 1000)} s`);
  return findDriver(dir);
}

const copyToPhone = (udid, src, name) => spawnSync('xcrun', ['devicectl', 'device', 'copy', 'to', '--device', udid, '--source', src,
  '--destination', `Documents/${name}`, '--domain-type', 'appDataContainer', '--domain-identifier', RUNNER_ID], { encoding: 'utf8', timeout: 30000 });

export async function startPhoneServer(driver, { udid, log = () => {}, push = TOUCH_PUSH, maxS = 2400, readyMs = 120000, tag = 'push', pollMs = 100 }) {
  const dir = mkdtempSync(join(tmpdir(), 'fw-push-'));
  rmSync(join(driver.dir, `${tag}.log`), { force: true });
  const run = serve(driver, { udid, dir, push, maxS, tag, suite: 'PushServer' });
  const sent = new Set();
  let live = true;
  const bridge = (async () => {
    while (live) {
      let text = '';
      try { text = readFileSync(run.logFile, 'utf8'); } catch {}
      const m = parseMarkers(text);
      if (m.ready !== null && !existsSync(join(dir, 'ready'))) writeFileSync(join(dir, 'ready'), String(m.ready));
      for (const [n, v] of m.done) if (!existsSync(join(dir, `done-${n}`))) writeFileSync(join(dir, `done-${n}`), v);
      for (const f of readdirSync(dir)) {
        if (sent.has(f) || !(/^go-\d+$/.test(f) || f === 'stop')) continue;
        sent.add(f);
        const r = copyToPhone(udid, join(dir, f), f);
        if (r.status !== 0) log(`copy of ${f} to the phone failed: ${(r.stderr || r.stdout || '').slice(-200)}`);
      }
      await sleep(pollMs);
    }
  })();
  const server = { dir, run, next: 0, bridge, stopBridge: () => { live = false; } };
  const t0 = Date.now();
  while (!existsSync(join(dir, 'ready'))) {
    if (run.state.ended || Date.now() - t0 > readyMs) {
      const why = run.state.ended ? `the driver ended (code ${run.state.code})` : `no ready marker after ${Math.round((Date.now() - t0) / 1000)} s`;
      const steps = parseMarkers(readFileSync(run.logFile, 'utf8')).steps.join(',');
      const tail = logTail(run.logFile);
      await stopPhoneServer(server);
      throw new Error(`push server: ${why} (steps: ${steps || 'none'})${tail ? `; log tail: ${tail}` : ''}`);
    }
    await sleep(250);
  }
  log(`push server ready after ${Math.round((Date.now() - t0) / 1000)} s`);
  return server;
}

export async function stopPhoneServer(server) {
  try { writeFileSync(join(server.dir, 'stop'), ''); } catch {}
  await Promise.race([server.run.exited, sleep(20000)]);
  server.stopBridge();
  await server.bridge;
  rmSync(server.dir, { recursive: true, force: true });
}
