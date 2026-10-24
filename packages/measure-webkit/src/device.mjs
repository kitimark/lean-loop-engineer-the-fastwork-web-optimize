// The real measurement iPhone (PLAN Q1: iPhone 15 Pro Max, iOS 27.0.1) behind its own ios_webkit_debug_proxy.
// I/O glue only; it holds no decision logic and no counts. Nothing here ever touches the Simulator.
//
// Rules this file enforces:
//  - The phone is selected by model and OS version from `xcrun devicectl list devices` (exactly one match) and must be
//    on USB (`idevice_id -l`). Every other phone `idevice_id` lists is written into the proxy config with port -1, so
//    the proxy can never attach it. Its id is used only as a command argument: never printed, logged or stored.
//  - Ports 9460/9461 (never 9221/9222, never the Simulator lane's 9341/9342).
//  - The phone must reach this Mac on the LAN: the page server binds to this Mac's LAN address (or $FW_PHONE_HOST).
//    The address is used in memory only; `redact()` strips it from every logged line.
//  - The proxy and server started here are stopped in `finally`; no process is killed by name.
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir, networkInterfaces } from 'node:os';
import { join, resolve } from 'node:path';
import { serveTree } from './serve.mjs';
import { snapshotRoot, FIXTURES } from './session.mjs';
import { phoneIds, sleep } from './sim.mjs';
import { navigateTab, openTab, connect } from './wip.mjs';
import { T } from './timeouts.mjs';
import { canonSearch } from '../../contracts/src/flag-key.mjs';

export const MEASUREMENT_DEVICE = Object.freeze({ model: 'iPhone 15 Pro Max', os: '27.0.1' });
export const PHONE_PORTS = Object.freeze({ list: 9460, tabs: 9461 });
const FORBIDDEN = [9221, 9222, 9341, 9342];

const run = (cmd, args, timeoutMs = 20000) => {
  const r = spawnSync(cmd, args, { encoding: 'utf8', timeout: timeoutMs, maxBuffer: 16 * 1024 * 1024 });
  return { status: r.status, stdout: r.stdout || '', stderr: r.stderr || '', error: r.error };
};

/** The one physical phone with the measurement model and OS, on USB. Returns { udid, model, os, build } (udid private). */
export function selectPhone({ model = MEASUREMENT_DEVICE.model, os = MEASUREMENT_DEVICE.os } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'fw-dev-'));
  try {
    const file = join(dir, 'devices.json');
    const r = run('xcrun', ['devicectl', 'list', 'devices', '--json-output', file], 60000);
    if (r.status !== 0) throw new Error('xcrun devicectl list devices failed');
    const all = JSON.parse(readFileSync(file, 'utf8')).result.devices;
    const m = all.filter((d) => d.hardwareProperties?.reality === 'physical' && d.hardwareProperties?.marketingName === model && d.deviceProperties?.osVersionNumber === os);
    if (m.length !== 1) throw new Error(`expected exactly one physical ${model} on iOS ${os}, found ${m.length}`);
    const udid = m[0].hardwareProperties.udid;
    const usb = run('idevice_id', ['-l']).stdout.split('\n').map((s) => s.trim()).filter(Boolean);
    if (!usb.includes(udid)) throw new Error(`the ${model} (iOS ${os}) is paired but not on USB`);
    return { udid, model, os, build: m[0].deviceProperties.osBuildUpdate ?? null };
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

/** Battery readout over lockdown/diagnostics (no thermal state is exposed there; the battery's own temperature is). */
export function readout(udid) {
  const batt = run('ideviceinfo', ['-u', udid, '-q', 'com.apple.mobile.battery']).stdout;
  const num = (re, s) => { const m = re.exec(s); return m ? Number(m[1]) : null; };
  const io = run('idevicediagnostics', ['-u', udid, 'ioregentry', 'AppleSmartBattery'], 30000).stdout;
  return {
    at: new Date().toISOString(),
    batteryPct: num(/BatteryCurrentCapacity:\s*(\d+)/, batt),
    charging: /BatteryIsCharging:\s*true/.test(batt),
    // AverageBattVirtualTemp / AverageBattSkinTemp from IORegistry AppleSmartBattery (unit not documented: read as degrees C, INFERRED)
    batteryVirtualTemp: num(/<key>AverageBattVirtualTemp<\/key>\s*<integer>(-?\d+)/, io),
    batterySkinTemp: num(/<key>AverageBattSkinTemp<\/key>\s*<integer>(-?\d+)/, io),
    thermalState: 'not exposed over USB lockdown or the inspector (no API); battery temperature is the proxy',
  };
}

/** This Mac's LAN IPv4 address (en0 first), or $FW_PHONE_HOST. Memory only. */
export function lanAddress(env = process.env) {
  if (env.FW_PHONE_HOST) return env.FW_PHONE_HOST;
  const ifs = networkInterfaces();
  const cand = [...(ifs.en0 ?? []), ...Object.values(ifs).flat()].filter((i) => i && i.family === 'IPv4' && !i.internal);
  if (!cand.length) throw new Error('no LAN IPv4 address found; set FW_PHONE_HOST');
  return cand[0].address;
}

/** Strip the LAN address and any device id from a log line. */
export const redact = (s, ...secrets) => secrets.filter(Boolean).reduce((t, x) => t.split(x).join('<redacted>'), String(s))
  .replace(/\b\d{1,3}(?:\.\d{1,3}){3}\b/g, (ip) => (ip === '127.0.0.1' ? ip : '<ip>')).replace(/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}/g, '<id>');

/** Proxy config text: list port, the phone on the tabs port, every other phone ignored (port -1). */
export const phoneConfigText = (udid, others, { list, tabs }) => [`null:${list}`, `${udid}:${tabs}`, ...others.filter((x) => x !== udid).map((u) => `${u}:-1`)].join('\n') + '\n';

export async function startPhoneProxy(udid, { log = () => {}, timeoutMs = 20000 } = {}) {
  const p = { ...PHONE_PORTS };
  for (const v of Object.values(p)) if (FORBIDDEN.includes(v)) throw new Error(`refusing port ${v}`);
  const dir = mkdtempSync(join(tmpdir(), 'fw-ph-iwdp-'));
  const cfg = join(dir, 'iwdp.cfg');
  writeFileSync(cfg, phoneConfigText(udid, phoneIds(), p), { mode: 0o600 });
  const child = spawn('ios_webkit_debug_proxy', ['-c', cfg, '-F'], { stdio: ['ignore', 'pipe', 'pipe'] });
  let out = '', exited = false;
  for (const s of [child.stdout, child.stderr]) s.on('data', (d) => { out = (out + d).slice(-4000); });
  child.on('exit', () => { exited = true; });
  const stop = async () => {
    if (!exited) { child.kill('SIGTERM'); for (let i = 0; i < 20 && !exited; i++) await sleep(100); if (!exited) child.kill('SIGKILL'); }
    rmSync(dir, { recursive: true, force: true });
  };
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await sleep(500);
    if (exited) { rmSync(dir, { recursive: true, force: true }); throw new Error(`phone proxy exited at start: ${redact(out.trim().split('\n').slice(-2).join(' | '), udid)}`); }
    try {
      const r = await fetch(`http://127.0.0.1:${p.tabs}/json`, { signal: AbortSignal.timeout(3000) });
      if (r.ok) { log(`phone proxy up, tabs on :${p.tabs}`); return { stop, ports: p, alive: () => !exited, output: () => redact(out, udid) }; }
    } catch { /* not yet */ }
  }
  await stop();
  throw new Error(`phone proxy listed no tabs in ${timeoutMs / 1000} s (is Web Inspector on, the phone unlocked, Safari open?)`);
}

const tabsOf = async (p) => (await fetch(`http://127.0.0.1:${p.tabs}/json`, { signal: AbortSignal.timeout(4000) })).json();

/**
 * Serve `site` (a prerendered dist/aot) or the read-only snapshot on the LAN, drive the phone's single about:blank Safari tab
 * to it through the inspector, call fn(ctx), and put the tab back to about:blank. ctx matches withSession's:
 * { c, url, base, root, device, log, setClient, ensureProxy, udid, readout }.
 * Reconnect/navigate helpers read the tabs port from FW_WK_*_PORT, which is set here to the phone's ports.
 */
export async function withPhone(fn, { site = null, mounts = {}, log = (s) => console.error(s), vendors = 'off', port = 0, serve = null, startPath: customStart = null } = {}) {
  const phone = selectPhone();
  const host = lanAddress();
  const say = (s) => log(redact(s, phone.udid, host));
  process.env.FW_WK_LIST_PORT = String(PHONE_PORTS.list);
  process.env.FW_WK_TABS_PORT = String(PHONE_PORTS.tabs);
  let root = null, rewrite = null, startPath = customStart ?? '/';
  if (serve) { /* a caller's own server (the gaps probe page): serve(host) -> { port, close } */ } else if (site) {
    root = resolve(site.dir);
    const cfg = JSON.parse(readFileSync(join(root, 'configs.json'), 'utf8'));
    const hash = cfg.bySearch[canonSearch(site.search ?? '')];
    if (!hash) throw new Error(`search "${site.search}" is not prerendered; known: ${Object.keys(cfg.bySearch).join(' | ')}`);
    const file = cfg.byHash[hash];
    rewrite = (p) => (p === '/' || p === '/index.html' ? '/' + file : null);
    startPath = '/' + (site.search ?? '');
    site.configHash = hash;
  } else root = snapshotRoot();
  const server = serve ? await serve(host) : await serveTree(root, { host, port, vendors, mounts: { '/__fixtures': FIXTURES, ...mounts }, rewrite });
  if (!server.url) server.url = `http://${host}:${server.port}/`;
  say(`serving ${serve ? 'a page server' : site ? 'the prerendered build' : 'the snapshot'} on the LAN, port ${server.port}`);
  let proxy = null, client = null, cleaned = false;
  const cleanup = async () => {
    if (cleaned) return; cleaned = true;
    try {
      if (client && !client.closed) { await client.evaluate("setTimeout(() => { location.href = 'about:blank'; }, 30); 1").catch(() => {}); await client.close(); }
    } catch { /* ignore */ }
    try { await proxy?.stop(); } catch (e) { say(`proxy stop: ${e.message}`); }
    await server.close();
  };
  const onSignal = (sig) => { say(`${sig}: cleaning up`); cleanup().finally(() => process.exit(130)); };
  process.once('SIGINT', () => onSignal('SIGINT'));
  process.once('SIGTERM', () => onSignal('SIGTERM'));
  try {
    proxy = await startPhoneProxy(phone.udid, { log: say });
    const tabs = await tabsOf(proxy.ports);
    const mine = tabs.filter((t) => t.url === 'about:blank');
    if (mine.length !== 1) throw new Error(`expected exactly one about:blank Safari tab (the tab this tool may drive), found ${mine.length} of ${tabs.length} tabs; open one blank tab on the phone`);
    const first = await connect(mine[0].webSocketDebuggerUrl);
    const url = server.url + startPath.slice(1);
    client = await navigateTab(first, url, { p: { ...proxy.ports }, log: say });
    const ctx = {
      c: client, url, server, base: server.url.replace(/\/$/, ''), root, log: say, udid: phone.udid,
      device: { model: phone.model, os: phone.os, build: phone.build },
      readout: () => readout(phone.udid),
      /** Navigate the driven tab to url (location.href through the inspector) and reconnect. */
      go: async (to) => { ctx.setClient(await navigateTab(ctx.c, to, { p: { ...proxy.ports }, log: say })); return ctx.c; },
      setClient: (c2) => { client = c2; ctx.c = c2; },
      ensureProxy: async () => {
        if (proxy?.alive()) { try { await tabsOf(proxy.ports); return; } catch { /* no answer */ } }
        say('the phone proxy is gone or not answering; starting it again');
        try { await proxy?.stop(); } catch { /* gone */ }
        proxy = await startPhoneProxy(phone.udid, { log: say });
      },
      lan: { host, port: server.port },
    };
    return await fn(ctx);
  } finally {
    await cleanup();
  }
}
export { openTab };
