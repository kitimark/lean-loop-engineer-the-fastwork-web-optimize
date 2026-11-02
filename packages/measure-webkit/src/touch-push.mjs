import { execFileSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { findDriver, serve } from './throttle/driver.mjs';
import { sleep } from './sim.mjs';
import { LAUNCH_FAULTS, READY_CFG, launchUntilReady, stopStep } from './touch-ready.mjs';

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

const hostTop = () => {
  try {
    return execFileSync('ps', ['-Ao', 'pcpu,etime,comm', '-r'], { encoding: 'utf8', timeout: 5000 }).split('\n').slice(0, 7)
      .map((l) => l.trim().replace(/\/Users\/[^/\s]+/g, '<home>').slice(0, 100));
  } catch { return null; }
};

/**
 * Start the push server: up to READY_CFG.launches xcodebuild launches, each cut by `verdict` (Lean TouchReady) after launchMs without `ready`,
 * when it ends, or at once on `ready`. A cut launch is killed and named (driver-launch-stuck | driver-body-stuck | driver-ended) in `launches`.
 * Resolves {dir, run, next, launches}; throws after the last launch with `.launches` and `.fault` set.
 */
export async function startServer(driver, { udid, log = () => {}, push = TOUCH_PUSH, maxS = 2400, tag = 'serve', suite = 'PushServer', cfg = READY_CFG }) {
  const t0 = Date.now();
  const dirs = [];
  const start = (n) => {
    const dir = mkdtempSync(join(tmpdir(), 'fw-push-'));
    dirs.push(dir);
    const run = serve(driver, { udid, dir, push, maxS, tag: n === 1 ? tag : `${tag}-l${n}`, suite, graceMs: Math.max(1000, cfg.killMs - 2000) });
    return { dir, run, state: run.state, exited: run.exited, kill: () => run.kill('launch cut') };
  };
  const look = (h) => ({ alive: existsSync(join(h.dir, 'alive')), ready: existsSync(join(h.dir, 'ready')) });
  const onCut = (rec, h) => { rec.top = hostTop(); rec.tail = logTail(h.run.logFile)?.slice(-600) ?? null; };
  const got = await launchUntilReady({ start, look, now: Date.now, sleep, cfg, log, onCut });
  if (got.handle) {
    for (const d of dirs) if (d !== got.handle.dir) rmSync(d, { recursive: true, force: true });
    const rec = got.launches[got.launches.length - 1];
    log(`push server ready after ${Math.round((Date.now() - t0) / 1000)} s (launch ${rec.n}, alive ${rec.aliveAt == null ? 'never' : `${Math.round(rec.aliveAt / 1000)} s`}, ready ${Math.round(rec.readyAt / 1000)} s)`);
    return { dir: got.handle.dir, run: got.handle.run, next: 0, launches: got.launches };
  }
  const last = got.launches[got.launches.length - 1];
  const lastTag = got.launches.length === 1 ? tag : `${tag}-l${got.launches.length}`;
  const tail = logTail(join(driver.dir, `${lastTag}.log`));
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
  const total = Math.round((Date.now() - t0) / 1000);
  const why = last.fault === LAUNCH_FAULTS.ended ? 'the driver ended' : `no ready file after ${total} s`;
  const e = new Error(`push server: ${why}; launches: ${got.launches.map((r) => `${r.n}:${r.fault}@${Math.round(r.ms / 1000)}s`).join(' ')}${tail ? `; log tail: ${tail}` : ''}`);
  e.launches = got.launches;
  e.fault = last.fault;
  throw e;
}

/** Stop the server: a `stop` file, then `stopStep` (Lean TouchReady): after stopWaitMs without exit the group is killed and `server.stopFault` is set. */
export async function stopServer(server, { cfg = READY_CFG } = {}) {
  try { writeFileSync(join(server.dir, 'stop'), ''); } catch {}
  const w0 = Date.now();
  let exited = false;
  server.run.exited.then(() => { exited = true; }, () => { exited = true; });
  for (;;) {
    const step = stopStep(cfg, exited || server.run.state.ended, Date.now() - w0);
    if (step === 'clean') break;
    if (step !== 'wait') { server.stopFault = step; server.run.kill('stop timeout'); await Promise.race([server.run.exited, sleep(cfg.killMs)]); break; }
    await Promise.race([server.run.exited, sleep(100)]);
  }
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
