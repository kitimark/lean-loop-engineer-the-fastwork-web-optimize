// The end-of-page push through real touches (I/O glue): the XCUITest driver of the toolbar-throttle probe swipes Mobile Safari while
// the page records. morph.tween reacts to touchmove as well as wheel (apps/site/src/parts/morph.tween/driver.ts onTouchMove), so a
// finger swipe up at the end of the page opens the morph and a swipe down closes it. One xcodebuild start costs about 60 s on the CI
// runner, so one long run (PushServer.swift) serves every push of a job. The deadlines and verdicts below are TS stand-ins of
// Lean `Fw.Measure.TouchPush`, replayed against its golden in test/touch-push.test.mjs.
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { findDriver, serve } from './throttle/driver.mjs';
import { sleep } from './sim.mjs';

/** One swipe up (opens), hold, one swipe down (closes), hold: 300 pt at 600 pt/s, each hold 1 s. */
export const TOUCH_PUSH = Object.freeze({ dragPt: 300, velocity: 600, holdMs: 1000 });

/**
 * Millisecond deadlines of one touch window (Lean `Fw.Measure.TouchPush.budget`, golden `contracts/golden/measure/touch-push.jsonl`).
 * `beginMs`: go file to first touchstart. `swipeMs`: first touchstart to last touchend. `tailMs`: the page keeps recording after it.
 * `answerMs`: wait for the page value once it was told to stop. `doneMs`: wait for the driver's done file after the swipe deadline.
 */
export const TOUCH_BUDGET = Object.freeze({ readyMs: 240000, beginMs: 45000, swipeMs: 20000, tailMs: 600, answerMs: 20000, doneMs: 60000 });

/** Lean `windowCap`: the longest the harness waits for the page of one window. */
export const windowCap = (b) => b.beginMs + b.swipeMs + b.tailMs + b.answerMs;

const within = (x, cap) => x != null && x <= cap;

/** Lean `classify`: the first failing check of what the harness saw, in this order. `o` = {beginAt, swipeAt, moves, answered, doneAt}. */
export function classifyWindow(b, o) {
  if (!o.answered) return 'pageLost';
  if (!within(o.beginAt, b.beginMs)) return 'beginLate';
  if (!within(o.swipeAt, b.swipeMs)) return 'swipeLate';
  if (o.moves === 0) return 'noMove';
  return 'ok';
}

/** Lean `doneInTime`. */
export const doneInTime = (b, o) => within(o.doneAt, b.beginMs + b.swipeMs + b.doneMs);

/** Lean `laneAfter`: the touch lane stays on only after an ok window whose driver finished in time. */
export const laneAfter = (b, on, o) => on && classifyWindow(b, o) === 'ok' && doneInTime(b, o);

/** Lean `spent`: the time the harness waits for the page of one window. */
export const spent = (b, o) => (o.beginAt == null ? b.beginMs : Math.min(o.beginAt, b.beginMs))
  + (o.swipeAt == null ? b.swipeMs : Math.min(o.swipeAt, b.swipeMs)) + b.tailMs + (o.answered ? 0 : b.answerMs);

/** Lean `timelinePlan`: a touch window records no Timeline; any other window stops it within `stopMs`. */
export const timelinePlan = (touch, stopMs) => (touch ? { kind: 'off' } : { kind: 'stopWithin', ms: stopMs });

/** Where the finger lands: `springboard` makes XCUITest wait for idle SpringBoard instead of busy Safari (PushServer.swift). */
export const TOUCH_VARIANTS = Object.freeze(['safari', 'springboard']);

/** The variant of push `i` from a comma list (default `springboard`); a name outside TOUCH_VARIANTS is an error. */
export function variantFor(i, list = process.env.FW_TOUCH_VARIANTS) {
  const names = (list ?? 'springboard').split(',').map((x) => x.trim()).filter(Boolean);
  const v = names[i % names.length];
  if (!TOUCH_VARIANTS.includes(v)) throw new Error(`unknown touch variant ${JSON.stringify(v)}; one of ${TOUCH_VARIANTS.join(', ')}`);
  return v;
}

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

/**
 * In-page: counts the touches the page receives and ends the window itself: `window.__fwTouchStop` is set `tailMs` after the second
 * touchend (the swipe up and the swipe down), so the recorded window holds the fingers' time and not the driver's idle waits.
 * Install once per load, before the touches. Times are `Date.now()`, the clock the Simulator shares with the harness.
 */
export const touchCountJs = (tailMs) => `(() => {
  const w = window.__fwTouch = { starts: 0, moves: 0, ends: 0, firstAt: null, lastEndAt: null };
  addEventListener('touchstart', () => { if (w.starts++ === 0) w.firstAt = Date.now(); }, { capture: true, passive: true });
  addEventListener('touchmove', () => { w.moves++; }, { capture: true, passive: true });
  addEventListener('touchend', () => { w.lastEndAt = Date.now(); if (++w.ends === 2) setTimeout(() => { window.__fwTouchStop = true; }, ${tailMs}); }, { capture: true, passive: true });
  return true;
})()`;
export const TOUCH_COUNT_JS = touchCountJs(TOUCH_BUDGET.tailMs);

/** Start the push server and wait until Safari is in front. Returns {dir, run, next}; throws with the log tail when it never gets ready. */
export async function startServer(driver, { udid, log = () => {}, push = TOUCH_PUSH, maxS = 2400, readyMs = TOUCH_BUDGET.readyMs }) {
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
 * Run `pageJs` (a promise that ends when `window.__fwTouchStop` is set, see `touchCountJs`) while the server swipes once with
 * `variant`. Waits for the page at most `windowCap(budget)` and for the driver's done file at most until `beginMs + swipeMs + doneMs`
 * after the go file. Resolves {pushed, result, error, obs, variant, outcome, presses}: `obs` is the Lean observation (ms from the go
 * file; null when never reached), `outcome` its verdict (`classifyWindow`), `presses` the driver's per-press times in ms.
 */
export async function touchWindow(c, { server, pageJs, variant = 'springboard', budget = TOUCH_BUDGET, pollMs = 500 }) {
  await c.evaluate('window.__fwTouchStop = false; true');
  const page = c.runAsync(pageJs, { pollMs, timeoutMs: windowCap(budget) + 10000 }).then((result) => ({ result }), (e) => ({ error: e.message }));
  const n = server.next++;
  const goAt = Date.now();
  writeFileSync(join(server.dir, `go-${n}`), variant);
  const timers = [];
  const after = (ms, value) => new Promise((resolve) => { timers.push(setTimeout(() => resolve(value), ms)); });
  let got = await Promise.race([page, after(budget.beginMs + budget.swipeMs + budget.tailMs, 'deadline')]);
  if (got === 'deadline') {
    await c.evaluate('window.__fwTouchStop = true; true').catch(() => {});
    got = await Promise.race([page, after(budget.answerMs, { error: 'the page did not answer after the touches (reloaded?)' })]);
  }
  for (const t of timers) clearTimeout(t);
  const doneFile = join(server.dir, `done-${n}`);
  const doneBy = goAt + budget.beginMs + budget.swipeMs + budget.doneMs;
  while (!existsSync(doneFile) && !server.run.state.ended && Date.now() < doneBy) await sleep(100);
  const pushed = existsSync(doneFile);
  const doneAt = pushed ? Date.now() - goAt : null;
  let presses = null;
  if (pushed) { try { presses = readFileSync(doneFile, 'utf8').trim().split(/\s+/).slice(1).map(Number); } catch { /* unreadable */ } }
  const t = got.result?.touch ?? null;
  const obs = {
    beginAt: t?.firstAt == null ? null : Math.max(0, t.firstAt - goAt),
    swipeAt: t?.firstAt == null || t.ends < 2 ? null : Math.max(0, t.lastEndAt - t.firstAt),
    moves: t?.moves ?? 0, answered: !!got.result, doneAt,
  };
  return { pushed, ...got, obs, variant, outcome: classifyWindow(budget, obs), presses };
}
