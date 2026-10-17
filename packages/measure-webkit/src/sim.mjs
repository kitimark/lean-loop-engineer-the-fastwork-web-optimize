// Simulator device control and the Inspector proxy (ios_webkit_debug_proxy) for the iOS Simulator.
//
// Facts used (CONFIRMED by running them, iOS 27.0 Simulator, 2026-10; and by ios-webkit-debug-proxy's README):
//  - `simctl boot` + `simctl bootstatus -b` boot headless (no Simulator.app window is needed).
//  - Mobile Safari opens nothing useful on about:blank; `simctl openurl` with a real http URL opens a tab.
//  - The Simulator's web inspector socket is a unix socket of `launchd_sim`
//    (`lsof -aUc launchd_sim -Fn`, name ends in com.apple.webinspectord_sim.socket); the proxy takes it with
//    `-s unix:<socket>` and lists the Simulator under the fixed device id SIMULATOR.
//  - The proxy "fakes the attach once at start", so Safari must be running before the proxy starts.
// A real iPhone must never be attached by this proxy: every phone that `idevice_id -l/-n` lists is written into the
// proxy's config with port -1 (= ignored). The config lives in a private temp dir and is removed at the end; ids are
// never printed.
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { T } from './timeouts.mjs';
import { retryWhile } from './poll.mjs';

export const DEVICE_NAME = process.env.FW_SIM_NAME || 'fw-iphone-27';
export const SAFARI = 'com.apple.mobilesafari';
export const SIM_ID = 'SIMULATOR';
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const PHONE_PORTS = [9221, 9222];

/** Ports of this package's proxy. Never the phone's 9221/9222, never equal. */
export function ports(env = process.env) {
  const p = { list: Number(env.FW_WK_LIST_PORT || 9341), tabs: Number(env.FW_WK_TABS_PORT || 9342) };
  for (const [k, v] of Object.entries(p)) {
    if (!Number.isInteger(v) || v <= 0 || v > 65535) throw new Error(`bad ${k} port ${v}`);
    if (PHONE_PORTS.includes(v)) throw new Error(`refusing ${k} port ${v}: that is the phone proxy's port`);
  }
  if (p.list === p.tabs) throw new Error('list and tabs ports must differ');
  return p;
}

function run(cmd, args, { timeoutMs = 120000 } = {}) {
  const r = spawnSync(cmd, args, { encoding: 'utf8', timeout: timeoutMs, maxBuffer: 64 * 1024 * 1024 });
  return { status: r.status, stdout: r.stdout || '', stderr: r.stderr || '', error: r.error };
}
export const simctl = (args, opts) => run('xcrun', ['simctl', ...args], opts);
const tail = (r) => (r.error ? r.error.code || r.error.message : (r.stderr || r.stdout).trim().split('\n').slice(-2).join(' | '));

/** [{udid, name, state, runtime}] for every available simulator device. */
export function listDevices() {
  const r = simctl(['list', '-j', 'devices']);
  if (r.status !== 0) throw new Error(`simctl list devices failed: ${tail(r)}`);
  return Object.entries(JSON.parse(r.stdout).devices).flatMap(([runtime, ds]) =>
    ds.filter((d) => d.isAvailable !== false).map((d) => ({ udid: d.udid, name: d.name, state: d.state, runtime })));
}

/** The one device named DEVICE_NAME. Refuses zero or several. */
export function findDevice(name = DEVICE_NAME) {
  const m = listDevices().filter((d) => d.name === name);
  if (m.length !== 1) throw new Error(`expected exactly one Simulator device named "${name}", found ${m.length}`);
  return m[0];
}

export const bootedDevices = () => listDevices().filter((d) => d.state === 'Booted');

/** Webinspectord socket paths of the booted Simulators. */
export function findSockets() {
  const r = run('lsof', ['-aUc', 'launchd_sim', '-Fn'], { timeoutMs: 30000 });
  if (r.error) throw new Error(`lsof: ${r.error.code || r.error.message}`);
  return [...new Set(r.stdout.split('\n').filter((l) => l.startsWith('n') && l.endsWith('com.apple.webinspectord_sim.socket')).map((l) => l.slice(1)))];
}

/**
 * Boot headless and launch Safari. Throws if another Simulator is booted (the inspector socket would be ambiguous).
 * Returns { udid, name, wasBooted }.
 */
export async function bootDevice({ log = () => {} } = {}) {
  const d = findDevice();
  const others = bootedDevices().filter((x) => x.udid !== d.udid);
  if (others.length) throw new Error(`another Simulator is booted (${others.map((o) => o.name).join(', ')}); shut it down first`);
  const wasBooted = d.state === 'Booted';
  if (!wasBooted) {
    const t0 = Date.now();
    const r = simctl(['boot', d.udid], { timeoutMs: T(120000) });
    if (r.status !== 0 && findDevice().state !== 'Booted') throw new Error(`simctl boot failed: ${tail(r)}`);
    const b = simctl(['bootstatus', d.udid, '-b'], { timeoutMs: T(300000) });
    if (b.status !== 0) throw new Error(`simctl bootstatus failed: ${tail(b)}`);
    log(`booted ${d.name} (${d.runtime.split('.').pop()}) in ${Math.round((Date.now() - t0) / 1000)} s`);
  }
  // Safari restores the last session's tabs; terminate first so the run starts from the same state.
  simctl(['terminate', d.udid, SAFARI]);
  let l;
  for (let i = 0; i < 3; i++) { // under heavy host load a launch can time out; the device stays booted, so ask again
    l = simctl(['launch', d.udid, SAFARI], { timeoutMs: T(90000) });
    if (l.status === 0) break;
    log(`simctl launch Safari failed (${tail(l)}); attempt ${i + 1} of 3`);
  }
  if (l.status !== 0) throw new Error(`simctl launch Safari failed: ${tail(l)}`);
  for (let i = 0; i < T(60); i++) {
    if (findSockets().length) return { udid: d.udid, name: d.name, wasBooted };
    await sleep(500);
  }
  throw new Error(`Safari runs, but no web inspector socket appeared in ${Math.round(T(60) / 2)} s`);
}

export const openUrl = (udid, url) => {
  const r = simctl(['openurl', udid, url], { timeoutMs: T(120000) }); // blocked 77 s once on a loaded runner
  if (r.status !== 0) throw new Error(`simctl openurl failed: ${tail(r)}`);
};

export function shutdownDevice(udid, { log = () => {} } = {}) {
  simctl(['terminate', udid, SAFARI]);
  const r = simctl(['shutdown', udid], { timeoutMs: 120000 });
  const state = listDevices().find((d) => d.udid === udid)?.state;
  if (state !== 'Shutdown') log(`warning: shutdown left the device in state ${state} (${tail(r)})`);
  else log('simulator shut down');
  return state === 'Shutdown';
}

const IWDP_ID = /^[A-Fa-f0-9-]{25,}$/;
/** Ids of attached iPhones (USB and network); [] when idevice_id is not installed. Fails closed on odd output. */
export function phoneIds({ exec = run, tries = 3 } = {}) {
  const ids = new Set();
  for (const flag of ['-l', '-n']) {
    // idevice_id can take longer than a fixed 15 s on a loaded runner: scaled timeout, and a timeout or a failed spawn is
    // asked again (a non-zero exit is a real failure, and so is the last timeout: the proxy then does not start)
    const r = retryWhile(() => exec('idevice_id', [flag], { timeoutMs: T(15000) }), { tries, retryable: (x) => x.error && x.error.code !== 'ENOENT' });
    if (r.error?.code === 'ENOENT') return [];
    if (r.error || r.status !== 0) throw new Error(`idevice_id ${flag} failed; not starting the proxy (it could attach a phone)`);
    for (const s of r.stdout.split('\n').map((x) => x.trim()).filter(Boolean)) {
      if (!IWDP_ID.test(s)) throw new Error('idevice_id printed a line the proxy config cannot name; not starting the proxy');
      ids.add(s);
    }
  }
  return [...ids];
}

/** Text of the proxy config: list port, every phone ignored, then the Simulator on the tabs port. */
export const iwdpConfigText = (ids, { list, tabs }) => [`null:${list}`, ...[...new Set(ids)].map((u) => `${u}:-1`), `:${tabs}`].join('\n') + '\n';

const getJson = async (port, path = '/json') => (await fetch(`http://127.0.0.1:${port}${path}`, { signal: AbortSignal.timeout(T(4000)) })).json();

/** The proxy lists exactly the device SIMULATOR on the list port. */
export async function proxyCheck(p = ports()) {
  let j;
  try { j = await getJson(p.list); } catch (e) { throw new Error(`proxy not reachable on :${p.list} (${e.cause?.code || e.message})`); }
  const ids = Array.isArray(j) ? j.map((d) => d?.deviceId) : [];
  if (ids.length !== 1 || ids[0] !== SIM_ID) throw new Error(`proxy lists ${ids.length} device(s), not exactly the Simulator`);
}

/** Start ios_webkit_debug_proxy against the Simulator. Returns { stop, ports, log }. */
export async function startProxy({ log = () => {}, timeoutMs = T(20000) } = {}) {
  const p = ports();
  const sockets = findSockets();
  if (sockets.length !== 1) throw new Error(`expected one Simulator inspector socket, found ${sockets.length}`);
  const dir = mkdtempSync(join(tmpdir(), 'fw-wk-iwdp-'));
  const cfg = join(dir, 'iwdp.cfg');
  writeFileSync(cfg, iwdpConfigText(phoneIds(), p), { mode: 0o600 });
  const child = spawn('ios_webkit_debug_proxy', ['-c', cfg, '-s', `unix:${sockets[0]}`, '-F'], { stdio: ['ignore', 'pipe', 'pipe'] });
  let out = '';
  for (const s of [child.stdout, child.stderr]) s.on('data', (d) => { out = (out + d).slice(-4000); });
  let exited = false;
  child.on('exit', () => { exited = true; });
  const stop = async () => {
    if (!exited) { child.kill('SIGTERM'); for (let i = 0; i < 20 && !exited; i++) await sleep(100); if (!exited) child.kill('SIGKILL'); }
    rmSync(dir, { recursive: true, force: true });
  };
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await sleep(400);
    if (exited) { rmSync(dir, { recursive: true, force: true }); throw new Error(`proxy exited at start: ${out.trim().split('\n').slice(-3).join(' | ')}`); }
    try {
      await proxyCheck(p);
      await getJson(p.tabs);
      log(`proxy up: ${SIM_ID} on :${p.list}, tabs on :${p.tabs}`);
      return { stop, ports: p, output: () => out, alive: () => !exited };
    } catch (e) { if (/non-simulator|not exactly/.test(e.message)) { await stop(); throw e; } }
  }
  await stop();
  throw new Error(`proxy did not list the Simulator in ${timeoutMs / 1000} s`);
}

/** Tab list from the proxy (webSocketDebuggerUrl, url, title, appId). */
export const listTabs = (p = ports()) => getJson(p.tabs);
