// The end-of-page push through real touches (I/O glue): the XCUITest driver of the toolbar-throttle probe swipes Mobile Safari while
// the page records. morph.tween reacts to touchmove as well as wheel (apps/site/src/parts/morph.tween/driver.ts onTouchMove), so a
// finger swipe up at the end of the page opens the morph and a swipe down closes it. One xcodebuild start costs about 60 s on the CI
// runner, so one long run (PushServer.swift) serves every push of a job. Nothing is decided here.
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { findDriver, serve } from './throttle/driver.mjs';
import { sleep } from './sim.mjs';

/** One swipe up (opens), hold, one swipe down (closes), hold: 300 pt at 600 pt/s, each hold 1 s. */
export const TOUCH_PUSH = Object.freeze({ dragPt: 300, velocity: 600, holdMs: 1000 });

/** The prebuilt driver in `dir`, or null with the reason. */
export function openDriver(dir) {
  if (!dir) return { driver: null, why: 'no driver directory given' };
  try { return { driver: findDriver(dir), why: null }; } catch (e) { return { driver: null, why: `driver not built (${e.message.replace(/\/Users\/[^/\s]+/g, '<home>')})` }; }
}

/** The last 1500 characters of a driver log with device ids and home paths removed. */
export function logTail(file) {
  try {
    return readFileSync(file, 'utf8').slice(-1500)
      .replace(/[0-9A-F]{8}-(?:[0-9A-F]{4}-){3}[0-9A-F]{12}/gi, '<id>').replace(/\/Users\/[^/\s]+/g, '<home>');
  } catch { return null; }
}

/** In-page: counts the touches the page receives. Install once per load, before the touches. */
export const TOUCH_COUNT_JS = `(() => {
  const w = window.__fwTouch = { starts: 0, moves: 0 };
  addEventListener('touchstart', () => { w.starts++; }, { capture: true, passive: true });
  addEventListener('touchmove', () => { w.moves++; }, { capture: true, passive: true });
  return true;
})()`;

/** Start the push server and wait until Safari is in front. Returns {dir, run, next}; throws with the log tail when it never gets ready. */
export async function startServer(driver, { udid, log = () => {}, push = TOUCH_PUSH, maxS = 2400, readyMs = 240000 }) {
  const dir = mkdtempSync(join(tmpdir(), 'fw-push-'));
  const run = serve(driver, { udid, dir, push, maxS });
  const t0 = Date.now();
  while (!existsSync(join(dir, 'ready'))) {
    if (run.state.ended || Date.now() - t0 > readyMs) {
      const why = run.state.ended ? `the driver ended (code ${run.state.code})` : `no ready file after ${Math.round((Date.now() - t0) / 1000)} s`;
      const tail = logTail(run.logFile);
      await stopServer({ dir, run });
      throw new Error(`push server: ${why}${tail ? `; log tail: ${tail}` : ''}`);
    }
    await sleep(250);
  }
  log(`push server ready after ${Math.round((Date.now() - t0) / 1000)} s`);
  return { dir, run, next: 0 };
}

/** Ask the server to end and clean up. */
export async function stopServer(server) {
  try { writeFileSync(join(server.dir, 'stop'), ''); } catch { /* directory gone */ }
  await Promise.race([server.run.exited, sleep(20000)]);
  rmSync(server.dir, { recursive: true, force: true });
}

/**
 * Run `pageJs` (a promise that ends when `window.__fwTouchStop` is set) while the server swipes once. Resolves {pushed, result, error}:
 * `pushed` says the swipe pair finished, `result` is the page value, `error` why it is missing.
 */
export async function touchWindow(c, { server, pageJs, pollMs = 500, tailMs = 600, pushMs = 60000, lostMs = 20000 }) {
  await c.evaluate('window.__fwTouchStop = false; true');
  const page = c.runAsync(pageJs, { pollMs, timeoutMs: 150000 }).then((result) => ({ result }), (e) => ({ error: e.message }));
  const n = server.next++;
  writeFileSync(join(server.dir, `go-${n}`), '');
  const t0 = Date.now();
  while (!existsSync(join(server.dir, `done-${n}`)) && !server.run.state.ended && Date.now() - t0 < pushMs) await sleep(100);
  const pushed = existsSync(join(server.dir, `done-${n}`));
  await sleep(tailMs);
  await c.evaluate('window.__fwTouchStop = true; true').catch(() => {});
  const got = await Promise.race([page, sleep(lostMs).then(() => ({ error: 'the page did not answer after the touches (reloaded?)' }))]);
  return { pushed, ...got };
}
