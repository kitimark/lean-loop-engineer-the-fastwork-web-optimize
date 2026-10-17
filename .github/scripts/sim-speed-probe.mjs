// sim-speed probe: boot + connect + one page load of the iOS Simulator on a GitHub macOS runner, with a mark per phase.
// Measurement glue for the research note research/notes/2026/10-17-sim-speed.md; it imports packages/measure-webkit
// read-only (sim.mjs, wip.mjs, serve.mjs, session.mjs) and holds no measurement decision. Counts are not taken here.
//
// Env: ARM (base | pre | fast | quiet | bg | combo), CONNECT (legacy = the harness's own withSession path | fast),
//      EXTRA=1 (after the first page: a warm second session, then shutdown + boot + a third session),
//      FW_SNAPSHOT_SITE, RUNNER_TEMP. Marks go to stdout and to $RUNNER_TEMP/result/marks.txt as "<epoch ms> <label>".
import { spawn, spawnSync } from 'node:child_process';
import { appendFileSync, mkdirSync, readFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = fileURLToPath(new URL('.', import.meta.url));
const SRC = resolve(HERE, '..', '..', 'packages', 'measure-webkit', 'src');
const RESULT = join(process.env.RUNNER_TEMP || '/tmp', 'result');
mkdirSync(RESULT, { recursive: true });
const ARM = process.env.ARM || 'base';
const CONNECT = process.env.CONNECT || 'legacy';
const EXTRA = process.env.EXTRA === '1';
const QUIET = ARM === 'quiet' || ARM === 'combo';
const BG = ARM === 'bg' || ARM === 'combo'; // the boot was started by an earlier workflow step
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const mark = (label) => {
  const t = Date.now();
  appendFileSync(join(RESULT, 'marks.txt'), `${t} ${label}\n`);
  console.log(`MARK ${t} ${label}`);
};
const tail = (r) => ((r.stderr || '') + (r.stdout || '')).trim().split('\n').slice(-2).join(' | ');
function sh(cmd, args, { timeoutMs = 300000 } = {}) {
  const t0 = Date.now();
  const r = spawnSync(cmd, args, { encoding: 'utf8', timeout: timeoutMs, maxBuffer: 64 * 1024 * 1024 });
  return { status: r.status, stdout: r.stdout || '', stderr: r.stderr || '', ms: Date.now() - t0, error: r.error };
}
const shAsync = (cmd, args, { timeoutMs = 300000 } = {}) => new Promise((res) => {
  const t0 = Date.now();
  const c = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'] });
  let out = '';
  for (const s of [c.stdout, c.stderr]) s.on('data', (d) => { out = (out + d).slice(-2000); });
  const timer = setTimeout(() => c.kill('SIGKILL'), timeoutMs);
  c.on('exit', (status) => { clearTimeout(timer); res({ status, ms: Date.now() - t0, out }); });
});
const simctl = (args, o) => sh('xcrun', ['simctl', ...args], o);

// ---- device choice (before sim.mjs is imported: it reads FW_SIM_NAME at import time)
let udid, name;
const list = JSON.parse(simctl(['list', '-j', 'devices']).stdout).devices;
const iosKey = Object.keys(list).find((k) => /SimRuntime\.iOS-27-0$/.test(k));
const iosDevices = (list[iosKey] || []).filter((d) => d.isAvailable !== false);
mark(`devices on the image (iOS 27.0): ${iosDevices.map((d) => `${d.name}=${d.state}`).join(', ') || 'none'}`);
const PRE = ARM === 'pre' || ARM === 'combo';
if (PRE) {
  const pick = iosDevices.find((d) => d.name === 'iPhone 15 Pro Max') || iosDevices.find((d) => /iPhone.*Pro Max/.test(d.name)) || iosDevices.find((d) => /iPhone/.test(d.name));
  if (!pick) throw new Error('no preinstalled iPhone device');
  udid = pick.udid; name = pick.name;
  mark(`pre: using the preinstalled device "${name}" (state ${pick.state})`);
} else {
  udid = readFileSync(join(process.env.RUNNER_TEMP || '/tmp', 'fw-sim-udid.txt'), 'utf8').trim();
  name = process.env.FW_SIM_NAME || 'fw-iphone-27';
}
process.env.FW_SIM_NAME = name;
const du = () => sh('du', ['-sk', join(homedir(), 'Library', 'Developer', 'CoreSimulator', 'Devices', udid)]).stdout.trim().split(/\s+/)[0];
mark(`device data dir before boot: ${du()} KB`);

const sim = await import(pathToFileURL(join(SRC, 'sim.mjs')));
const wip = await import(pathToFileURL(join(SRC, 'wip.mjs')));
const serve = await import(pathToFileURL(join(SRC, 'serve.mjs')));
const session = await import(pathToFileURL(join(SRC, 'session.mjs')));

// ---- Simulator quieting (arms quiet, combo); the host side (Spotlight, unified logging) is a workflow step
function quietSim() {
  // `log config` is refused inside the Simulator ("unable to set system mode", status 64: CONFIRMED locally), so the
  // background daemons that are not needed to load a page are booted out instead (not persistent: gone at next boot)
  for (const label of ['chronod', 'searchd', 'photoanalysisd', 'suggestd', 'biomesyncd', 'biomed', 'cloudphotod', 'spotlightknowledged', 'hybridsearchd']) {
    const r = simctl(['spawn', udid, 'launchctl', 'bootout', `system/com.apple.${label}`], { timeoutMs: 60000 });
    mark(`quiet sim: bootout ${label} -> status ${r.status} in ${r.ms} ms ${r.status ? tail(r).slice(0, 80) : ''}`);
  }
}

// ---- boot
async function boot(label) {
  mark(`${label}: boot begin`);
  if (!BG || label !== 'boot') {
    const r = simctl(['boot', udid], { timeoutMs: 600000 });
    mark(`${label}: simctl boot returned status ${r.status} in ${r.ms} ms ${r.status ? tail(r) : ''}`);
  } else mark('boot: started by an earlier step (background), waiting with bootstatus');
  const b = simctl(['bootstatus', udid, '-b'], { timeoutMs: 600000 });
  mark(`${label}: bootstatus -b returned status ${b.status} in ${b.ms} ms`);
  if (b.status !== 0) throw new Error(`bootstatus failed: ${tail(b)}`);
}

// ---- connect, fast: no terminate/launch, no fixed sleep, openurl launches Safari, poll and re-send
async function fastConnect(tag) {
  const root = session.snapshotRoot();
  const server = await serve.serveTree(root, { vendors: 'off', mounts: {}, rewrite: null });
  const url = server.url;
  mark(`${tag}: serving at ${url}`);
  let opens = 0, inflight = null;
  const open = () => {
    const n = ++opens;
    mark(`${tag}: openurl #${n} sent`);
    inflight = shAsync('xcrun', ['simctl', 'openurl', udid, url], { timeoutMs: 120000 }).then((r) => { inflight = null; mark(`${tag}: openurl #${n} returned status ${r.status} in ${r.ms} ms`); });
  };
  open();
  const t0 = Date.now();
  while (inflight && Date.now() - t0 < 90000) await sleep(250);
  let proxy = null, client = null, lastWin = Date.now(), lastErr = '';
  const deadline = Date.now() + 240000;
  const startProxy = async () => {
    for (let i = 0; i < 60 && !sim.findSockets().length; i++) await sleep(500);
    proxy = await sim.startProxy({ log: (s) => mark(`${tag}: ${s}`), timeoutMs: 60000 });
  };
  await startProxy();
  let proxyStarts = 1;
  while (Date.now() < deadline && !client) {
    try {
      const tabs = (await sim.listTabs(proxy.ports)).filter((x) => x.webSocketDebuggerUrl && String(x.url).startsWith(url));
      if (tabs.length === 1) {
        mark(`${tag}: tab listed`);
        const c = await wip.connect(tabs[0].webSocketDebuggerUrl);
        try { await c.evaluate('1', { timeoutMs: 8000 }); client = c; } catch (e) { c.close(); lastErr = e.message; }
      } else lastErr = `${tabs.length} tabs`;
    } catch (e) { lastErr = e.message; }
    if (client) break;
    if (Date.now() - lastWin > 15000 && !inflight) {
      mark(`${tag}: no tab after 15 s (${lastErr}); resend (proxy output: ${proxy.output().trim().split('\n').slice(-2).join(' | ').slice(0, 160)})`);
      open(); lastWin = Date.now();
      if (opens >= 3 && proxyStarts < 2) { await proxy.stop(); await startProxy(); proxyStarts++; mark(`${tag}: proxy restarted`); }
    }
    await sleep(500);
  }
  if (!client) throw new Error(`${tag}: no tab (${lastErr})`);
  mark(`${tag}: attached (openurl sends ${opens}, proxy starts ${proxyStarts})`);
  return { c: client, proxy, server, url };
}

async function pageChecks(tag, c) {
  const t0 = Date.now();
  let rs = '';
  while (Date.now() - t0 < 90000) { rs = await c.evaluate('document.readyState'); if (rs === 'complete') break; await sleep(200); }
  const info = await c.evaluate('JSON.stringify({rs: document.readyState, title: document.title.slice(0, 40), nodes: document.querySelectorAll("*").length})');
  mark(`${tag}: page ${rs} ${info}`);
}

async function finish(s) { try { s.c.close(); } catch { /* closed */ } await s.proxy.stop(); await s.server.close(); }

try {
  await boot('boot');
  mark(`device data dir after boot: ${du()} KB`);
  if (QUIET) quietSim();

  if (CONNECT === 'legacy') {
    // the harness's own path (terminate + launch Safari, fixed sleep, openurl, proxy, tab wait): marks from its log lines
    await session.withSession(async (ctx) => {
      mark('legacy: attached');
      await pageChecks('legacy', ctx.c);
    }, { keep: true, log: (s) => mark(`legacy: ${s}`) });
  } else {
    const s = await fastConnect('fast1');
    await pageChecks('fast1', s.c);
    await finish(s);
  }
  mark('first session done');

  if (EXTRA) {
    const s2 = await fastConnect('warm2');
    await pageChecks('warm2', s2.c);
    await finish(s2);
    const sd = simctl(['shutdown', udid], { timeoutMs: 300000 });
    mark(`reboot: shutdown returned status ${sd.status} in ${sd.ms} ms`);
    await boot('reboot');
    const s3 = await fastConnect('reboot3');
    await pageChecks('reboot3', s3.c);
    await finish(s3);
  }
  mark('probe ok');
} catch (e) {
  mark(`FAIL: ${String(e.message).slice(0, 300)}`);
  process.exitCode = 1;
}
process.exit(process.exitCode || 0);
