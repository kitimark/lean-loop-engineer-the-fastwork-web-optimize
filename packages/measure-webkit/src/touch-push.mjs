import { copyFileSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { findDriver, serve } from './throttle/driver.mjs';
import { sleep } from './sim.mjs';

export const TOUCH_PUSH = Object.freeze({ dragPt: 300, velocity: 600, holdMs: 1000 });

export const TOUCH_BUDGET = Object.freeze({ readyMs: 240000, beginMs: 45000, swipeMs: 20000, tailMs: 600, answerMs: 20000, doneMs: 60000 });

export const windowCap = (b) => b.beginMs + b.swipeMs + b.tailMs + b.answerMs;

const within = (x, cap) => x != null && x <= cap;

export function classifyWindow(b, o) {
  if (!o.answered) return 'pageLost';
  if (!within(o.beginAt, b.beginMs)) return 'beginLate';
  if (!within(o.swipeAt, b.swipeMs)) return 'swipeLate';
  if (o.moves === 0) return 'noMove';
  return 'ok';
}

export const doneInTime = (b, o) => within(o.doneAt, b.beginMs + b.swipeMs + b.doneMs);

export const laneAfter = (b, on, o) => on && classifyWindow(b, o) === 'ok' && doneInTime(b, o);

export const spent = (b, o) => (o.beginAt == null ? b.beginMs : Math.min(o.beginAt, b.beginMs))
  + (o.swipeAt == null ? b.swipeMs : Math.min(o.swipeAt, b.swipeMs)) + b.tailMs + (o.answered ? 0 : b.answerMs);

export const timelinePlan = (touch, stopMs) => (touch ? { kind: 'off' } : { kind: 'stopWithin', ms: stopMs });

export const TOUCH_VARIANTS = Object.freeze(['safari', 'springboard']);

export function variantFor(i, list = process.env.FW_TOUCH_VARIANTS) {
  const names = (list ?? 'springboard').split(',').map((x) => x.trim()).filter(Boolean);
  const v = names[i % names.length];
  if (!TOUCH_VARIANTS.includes(v)) throw new Error(`unknown touch variant ${JSON.stringify(v)}; one of ${TOUCH_VARIANTS.join(', ')}`);
  return v;
}

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

export const touchCountJs = (tailMs) => `(() => {
  const w = window.__fwTouch = { starts: 0, moves: 0, ends: 0, firstAt: null, lastEndAt: null };
  addEventListener('touchstart', () => { if (w.starts++ === 0) w.firstAt = performance.timeOrigin + performance.now(); }, { capture: true, passive: true });
  addEventListener('touchmove', () => { w.moves++; }, { capture: true, passive: true });
  addEventListener('touchend', () => { w.lastEndAt = performance.timeOrigin + performance.now(); if (++w.ends === 2) setTimeout(() => { window.__fwTouchStop = true; }, ${tailMs}); }, { capture: true, passive: true });
  return true;
})()`;
export const TOUCH_COUNT_JS = touchCountJs(TOUCH_BUDGET.tailMs);

export async function startServer(driver, { udid, log = () => {}, push = TOUCH_PUSH, maxS = 2400, readyMs = TOUCH_BUDGET.readyMs, tag = 'serve', suite = 'PushServer' }) {
  const dir = mkdtempSync(join(tmpdir(), 'fw-push-'));
  const run = serve(driver, { udid, dir, push, maxS, tag, suite });
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

export async function stopServer(server) {
  try { writeFileSync(join(server.dir, 'stop'), ''); } catch {}
  await Promise.race([server.run.exited, sleep(20000)]);
  if (process.env.FW_TOUCH_KEEP_LOG) { try { copyFileSync(server.run.logFile, process.env.FW_TOUCH_KEEP_LOG); } catch {} }
  rmSync(server.dir, { recursive: true, force: true });
}

export async function touchWindow(c, { server, pageJs, variant = 'springboard', budget = TOUCH_BUDGET, pollMs = 500 }) {
  const timers = [];
  const after = (ms, value) => new Promise((resolve) => { timers.push(setTimeout(() => resolve(value), ms)); });
  const armed = await Promise.race([
    Promise.resolve(c.evaluate('window.__fwTouchStop = false; true', { timeoutMs: budget.answerMs })).then(() => true, (e) => e),
    after(budget.answerMs, false),
  ]);
  if (armed !== true) {
    for (const t of timers) clearTimeout(t);
    throw armed === false ? new Error(`the page did not take the touch window start within ${budget.answerMs} ms`) : armed;
  }
  const page = c.runAsync(pageJs, { pollMs, timeoutMs: windowCap(budget) + 10000 }).then((result) => ({ result }), (e) => ({ error: e.message }));
  const n = server.next++;
  const goAt = Date.now();
  writeFileSync(join(server.dir, `go-${n}`), variant);
  let got = await Promise.race([page, after(budget.beginMs + budget.swipeMs + budget.tailMs, 'deadline')]);
  if (got === 'deadline') {
    Promise.resolve(c.evaluate('window.__fwTouchStop = true; true', { timeoutMs: budget.answerMs })).catch(() => {});
    got = await Promise.race([page, after(budget.answerMs, { error: 'the page did not answer after the touches (reloaded?)' })]);
  }
  for (const t of timers) clearTimeout(t);
  const doneFile = join(server.dir, `done-${n}`);
  const doneBy = goAt + budget.beginMs + budget.swipeMs + budget.doneMs;
  while (!existsSync(doneFile) && !server.run.state.ended && Date.now() < doneBy) await sleep(100);
  const pushed = existsSync(doneFile);
  const doneAt = pushed ? Date.now() - goAt : null;
  let presses = null;
  if (pushed) { try { presses = readFileSync(doneFile, 'utf8').trim().split(/\s+/).slice(1).map(Number); } catch {} }
  const t = got.result?.touch ?? null;
  const obs = {
    beginAt: t?.firstAt == null ? null : Math.max(0, t.firstAt - goAt),
    swipeAt: t?.firstAt == null || t.ends < 2 ? null : Math.max(0, t.lastEndAt - t.firstAt),
    moves: t?.moves ?? 0, answered: !!got.result, doneAt,
  };
  return { pushed, ...got, obs, variant, outcome: classifyWindow(budget, obs), presses };
}
