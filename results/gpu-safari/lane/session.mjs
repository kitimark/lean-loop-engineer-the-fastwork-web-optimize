// One macOS Safari session (safaridriver) over one origin that serves every arm's prerendered tree.
// Glue only: it holds no decision. The driver, the Safari windows it opened and the server are stopped by `close`.
import { spawn, spawnSync } from 'node:child_process';
import { armServer, freePort, webdriver } from '../../../packages/measure-webkit/src/safari-local.mjs';

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const pids = (name) => spawnSync('pgrep', ['-x', name], { encoding: 'utf8' }).stdout.split('\n').filter(Boolean).map(Number);

/** The WebDriver calls the existing client lacks: a raw call, a viewport screenshot (base64 PNG). */
export function extra(base, getSid) {
  const call = async (method, path, body, timeoutMs = 120000) => {
    const r = await fetch(base + path, { method, headers: { 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(timeoutMs) });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(`${method} ${path}: ${r.status} ${j.value?.error ?? ''} ${String(j.value?.message ?? '').slice(0, 160)}`);
    return j.value;
  };
  return {
    call,
    screenshot: async () => Buffer.from(await call('GET', `/session/${getSid()}/screenshot`), 'base64'),
  };
}

/**
 * Open the lane. `arms` = [{ id, site, tree: { dir, search } | { dir: null }, search }] as `armServer` takes them.
 * Returns the client, the server and `close`, which stops only the driver pid this call started and the Safari pids that did not exist before.
 */
export async function openLane({ arms, width = 430, height = 932, log = (s) => console.error(s) }) {
  const server = await armServer(arms);
  const port = await freePort();
  const safariBefore = new Set(pids('Safari'));
  const driver = spawn('safaridriver', ['-p', String(port)], { detached: true, stdio: 'ignore' });
  driver.unref();
  log(`safaridriver pid ${driver.pid} on port ${port}; serving at ${server.url}`);
  const base = `http://127.0.0.1:${port}`;
  const wd = webdriver(base);
  let sid = null;
  await sleep(1500);
  const v = await wd.newSession();
  sid = v.sessionId;
  await wd.timeouts(90000);
  const rect = await wd.setRect({ x: 0, y: 0, width, height }).catch((e) => ({ error: e.message }));
  const x = extra(base, () => sid);
  const close = async () => {
    await wd.close();
    try { process.kill(driver.pid); } catch {}
    for (const p of pids('Safari')) if (!safariBefore.has(p)) { try { process.kill(p); } catch {} }
    await server.close();
  };
  return { wd, x, server, rect, close, driverPid: driver.pid };
}

/** Navigate to an arm and wait until the page reports the arm's config hash (a wrong page throws). */
export async function loadArm(lane, arm, { settleMs = 2500 } = {}) {
  lane.server.setArm(arm.id);
  await lane.wd.navigate(`${lane.server.url}${arm.search}`);
  const INFO = `return JSON.stringify({ vw: innerWidth, vh: innerHeight, dpr: devicePixelRatio, vis: document.visibilityState, ua: navigator.userAgent, ready: document.readyState, fw: window.__fw ? { configHash: window.__fw.configHash, mode: window.__fw.mode, hydrated: window.__fw.hydrated } : null })`;
  for (let i = 0; i < 100 && JSON.parse(await lane.wd.sync(INFO)).ready !== 'complete'; i++) await sleep(100);
  for (let i = 0; i < 100 && !JSON.parse(await lane.wd.sync(INFO)).fw?.hydrated; i++) await sleep(100);
  await sleep(settleMs);
  const info = JSON.parse(await lane.wd.sync(INFO));
  if (arm.tree.dir && info.fw?.configHash !== lane.server.armHash(arm.id)) throw new Error(`arm ${arm.id}: wrong page (${JSON.stringify(info.fw)})`);
  if (info.vis !== 'visible' && !process.env.FW_GPU_DEBUG_HIDDEN) throw new Error(`the Safari window is ${info.vis}: rAF would be throttled`);
  return info;
}
