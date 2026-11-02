import { execFile, execFileSync } from 'node:child_process';
import { closeSync, copyFileSync, existsSync, fstatSync, mkdtempSync, openSync, readFileSync, readSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { findDriver, serve } from './throttle/driver.mjs';
import { sleep } from './sim.mjs';
import { LAUNCH_FAULTS, READY_CFG, GATE, launchUntilReady, stopStep, gateStep, bodyEndedIn } from './touch-ready.mjs';

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
    return execFileSync('ps', ['-Ao', 'pcpu,etime,comm', '-r'], { encoding: 'utf8', timeout: 15000 }).split('\n').slice(0, 7)
      .map((l) => l.trim().replace(/\/Users\/[^/\s]+/g, '<home>').slice(0, 100));
  } catch (e) { return [`ps failed: ${e.code ?? e.signal ?? 'error'}`]; }
};

export const hostHealth = () => {
  const out = { memFreePct: null, simctlMs: null };
  try { out.memFreePct = Number(/free percentage: (\d+)%/.exec(execFileSync('memory_pressure', ['-Q'], { encoding: 'utf8', timeout: 10000 }))?.[1] ?? NaN) || null; } catch {}
  const t = Date.now();
  try { execFileSync('xcrun', ['simctl', 'list', 'devices', 'booted'], { encoding: 'utf8', timeout: 10000, stdio: ['ignore', 'pipe', 'ignore'] }); out.simctlMs = Date.now() - t; } catch {}
  return out;
};

const execAsync = (cmd, args, timeout) => new Promise((resolve, reject) => {
  execFile(cmd, args, { encoding: 'utf8', timeout }, (e, out) => (e ? reject(e) : resolve(out)));
});
const probeCode = (e) => (e.killed || e.signal ? 'ETIMEDOUT' : (e.code ?? 'error'));

/** The probes of `hostTop` and `hostHealth` without blocking the event loop, so they can run while a launch is under way. */
export async function hostProbes() {
  const top = execAsync('ps', ['-Ao', 'pcpu,etime,comm', '-r'], 15000).then(
    (o) => o.split('\n').slice(0, 7).map((l) => l.trim().replace(/\/Users\/[^/\s]+/g, '<home>').slice(0, 100)),
    (e) => [`ps failed: ${probeCode(e)}`]);
  const mem = execAsync('memory_pressure', ['-Q'], 10000).then((o) => Number(/free percentage: (\d+)%/.exec(o)?.[1] ?? NaN) || null, () => null);
  const t = Date.now();
  const simctlMs = execAsync('xcrun', ['simctl', 'list', 'devices', 'booted'], 10000).then(() => Date.now() - t, () => null);
  return { top: await top, health: { memFreePct: await mem, simctlMs: await simctlMs } };
}

/**
 * Resolves {dir, run, next, launches}; throws after the last launch with `.launches` and `.fault` set.
 * `onLaunched` is called once, right after the first launch is spawned (a restart starts its host probes there).
 */
export async function startServer(driver, { udid, log = () => {}, push = TOUCH_PUSH, maxS = 2400, tag = 'serve', suite = 'PushServer', cfg = READY_CFG, onLaunched = null }) {
  const t0 = Date.now();
  const dirs = [];
  const start = (n) => {
    const dir = mkdtempSync(join(tmpdir(), 'fw-push-'));
    dirs.push(dir);
    const run = serve(driver, { udid, dir, push, maxS, tag: n === 1 ? tag : `${tag}-l${n}`, suite, graceMs: Math.max(1000, cfg.killMs - 2000) });
    if (n === 1) { try { onLaunched?.(); } catch {} }
    return { dir, run, state: run.state, exited: run.exited, kill: () => run.kill('launch cut') };
  };
  const logged = (h) => { try { return statSync(h.run.logFile).size > 0; } catch { return false; } };
  const look = (h) => ({ alive: existsSync(join(h.dir, 'alive')), ready: existsSync(join(h.dir, 'ready')), logged: logged(h) });
  const onCut = (rec, h) => { rec.top = hostTop(); rec.health = hostHealth(); rec.tail = logTail(h.run.logFile)?.slice(-600) ?? null; };
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

export function fileTail(file, bytes) {
  const fd = openSync(file, 'r');
  try {
    const size = fstatSync(fd).size;
    const buf = Buffer.alloc(Math.min(size, bytes));
    readSync(fd, buf, 0, buf.length, size - buf.length);
    return buf.toString('utf8');
  } finally { closeSync(fd); }
}

/**
 * Write the stop file and wait up to the stop wait for the driver to exit; a late stop is named and nothing is killed.
 * The log is read again at the decision, so a body that returned in the last poll gap is not named a hung press.
 * The host probes of a late stop run in `probeStop`, not here: they must not stand between the stop and the next launch.
 */
export async function stopServer(server, { cfg = READY_CFG } = {}) {
  try { writeFileSync(join(server.dir, 'stop'), ''); } catch {}
  const w0 = Date.now();
  server.stopAt = w0;
  const trace = { waitedMs: 0, bodyEndedMs: null, exitedMs: null, top: null, health: null, tail: null };
  server.stopTrace = trace;
  let exited = false;
  const gone = () => { exited = true; trace.exitedMs ??= Date.now() - w0; };
  server.run.exited.then(gone, gone);
  const looksEnded = () => { try { return bodyEndedIn(fileTail(server.run.logFile, 65536)); } catch { return false; } };
  for (let i = 0; ; i++) {
    let waited = Date.now() - w0;
    if (trace.bodyEndedMs == null && (i % 5 === 0 || waited >= cfg.stopWaitMs) && looksEnded()) trace.bodyEndedMs = waited;
    waited = Date.now() - w0;
    const step = stopStep(cfg, exited || server.run.state.ended, trace.bodyEndedMs != null, waited);
    trace.waitedMs = waited;
    if (step === 'clean') { trace.exitedMs ??= waited; break; }
    if (step !== 'wait') { server.stopFault = step; trace.tail =logTail(server.run.logFile)?.slice(-600) ?? null; break; }
    await Promise.race([server.run.exited, sleep(100)]);
  }
  if (process.env.FW_TOUCH_KEEP_LOG) { try { copyFileSync(server.run.logFile, process.env.FW_TOUCH_KEEP_LOG); } catch {} }
  rmSync(server.dir, { recursive: true, force: true });
}

/** The host probes of a late stop, filled into the stop trace when they answer (never throws). */
export async function probeStop(server, probes = hostProbes) {
  const trace = server?.stopTrace;
  if (!trace || !server.stopFault) return;
  try { const got = await probes(); trace.top = got.top; trace.health = got.health; } catch { /* the trace keeps its nulls */ }
}

/**
 * Between the stop and the next launch (Lean `gateStep`): wait for the old xcodebuild to exit, then for the inspector to answer.
 * `check()` is the session guard's probe (it also waits for a recovery in flight and throws when the inspector is dead);
 * `probe()` returns {socket, proxy, page}. Resolves the act, `launch` or `launch:<fault names>`, also written to the stop trace.
 */
export async function restartGate(server, { gate = GATE, check = null, probe = null, now = Date.now, nap = sleep } = {}) {
  const w0 = server.stopAt ?? now();
  const once = server.run.exited.then(() => {}, () => {});
  let ok = false;
  let checked = 0;
  let err = null;
  for (;;) {
    const waited = now() - w0;
    const act = gateStep(gate, !!server.run.state.ended, waited, ok, checked);
    if (act === 'wait-exit') { await Promise.race([once, nap(100)]); continue; }
    if (act === 'recheck') {
      if (checked > 0) await nap(gate.gapMs);
      try {
        await check?.();
        const p = probe ? await probe() : { socket: true, proxy: true, page: true };
        ok = !!(p.socket && p.proxy && p.page);
      } catch (e) { ok = false; err = String(e?.message ?? e).slice(0, 120); }
      checked++;
      continue;
    }
    if (server.stopTrace) server.stopTrace.gate = { act, waitedMs: waited, checked, ...(err ? { err } : {}) };
    return act;
  }
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
