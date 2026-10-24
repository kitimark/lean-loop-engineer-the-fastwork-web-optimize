// One measurement session: serve the original read-only snapshot on 127.0.0.1, boot the Simulator headless, open the
// page in Mobile Safari, start the Inspector proxy, connect, run `fn`, and shut everything down in `finally`
// (also on SIGINT/SIGTERM). The snapshot is read from disk per request and never copied.
import { existsSync, readFileSync } from 'node:fs';
import { resolve, dirname, join, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { serveTree } from './serve.mjs';
import { bootDevice, terminateSafari, startSafari, waitSocket, openUrl, shutdownDevice, startProxy, proxyCheck, probeInspector, findDevice, listTabs, sleep } from './sim.mjs';
import { BOUNDS, InspectorDeadError, TargetLostError } from './inspector.mjs';
import { createGuard, runSteps } from './guard.mjs';
import { armFault, faultPlan } from './fault.mjs';
import { openTab } from './wip.mjs';
import { T, attempts } from './timeouts.mjs';
import { ensureTab } from './poll.mjs';
import { canonSearch } from '../../contracts/src/flag-key.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
export const FIXTURES = resolve(HERE, '..', 'fixtures');

/** The snapshot tree: $FW_SNAPSHOT_SITE, else `snapshot/site` of the main checkout (a worktree has none of its own). */
export function snapshotRoot(env = process.env) {
  if (env.FW_SNAPSHOT_SITE) return resolve(env.FW_SNAPSHOT_SITE);
  const candidates = [];
  let dir = HERE;
  for (let i = 0; i < 8; i++) { candidates.push(join(dir, 'snapshot', 'site')); dir = dirname(dir); }
  // a linked worktree lives at <main>/.claude/worktrees/<name>: the main checkout holds the (gitignored) snapshot
  const marker = `${sep}.claude${sep}worktrees${sep}`;
  const at = HERE.indexOf(marker);
  if (at > 0) candidates.push(join(HERE.slice(0, at), 'snapshot', 'site'));
  const found = candidates.find((p) => existsSync(join(p, 'index.html')));
  if (!found) throw new Error('snapshot/site not found: set FW_SNAPSHOT_SITE');
  return found;
}

/**
 * @param {(ctx:{c:object, url:string, base:string, root:string, device:object, log:Function})=>Promise<any>} fn
 * @param {{keep?:boolean, vendors?:'off'|'live', log?:Function}} opts keep: leave the Simulator booted
 */
export async function withSession(fn, { keep = false, vendors = 'off', site = null, arms = null, log = (s) => console.error(s) } = {}) {
  // site: { dir, search } serves a prerendered build of apps/site (dist/aot): "/" + search is answered with the HTML of
  // that search's config hash (configs.json), as a CDN rewrite would. Without it: the read-only snapshot.
  let root, rewrite = null, startPath = '/';
  if (site) {
    root = resolve(site.dir);
    const cfg = JSON.parse(readFileSync(join(root, 'configs.json'), 'utf8'));
    const hash = cfg.bySearch[canonSearch(site.search ?? '')];
    if (!hash) throw new Error(`search "${site.search}" is not prerendered; known: ${Object.keys(cfg.bySearch).join(' | ')}`);
    const file = cfg.byHash[hash];
    rewrite = (p) => (p === '/' || p === '/index.html' ? '/' + file : null);
    startPath = '/' + (site.search ?? '');
    site.configHash = hash;
  } else root = snapshotRoot();
  // arms: { name: { dir, search } } serves one tree per arm on ONE origin (dir null = the snapshot); `ctx.setArm(name)` picks the tree
  // the next request is answered from. The tab keeps its origin, so the inspector guard and the tab lookup stay valid.
  let select = null, armTable = null, armNow = null;
  if (arms) {
    armTable = Object.fromEntries(Object.entries(arms).map(([name, a]) => {
      if (!a.dir) return [name, { root: snapshotRoot(), rewrite: null, hash: null }];
      const r = resolve(a.dir);
      const cfg = JSON.parse(readFileSync(join(r, 'configs.json'), 'utf8'));
      const hash = cfg.bySearch[canonSearch(a.search ?? '')];
      if (!hash) throw new Error(`arm ${name}: search "${a.search}" is not prerendered; known: ${Object.keys(cfg.bySearch).join(' | ')}`);
      const file = cfg.byHash[hash];
      return [name, { root: r, rewrite: (p) => (p === '/' || p === '/index.html' ? '/' + file : null), hash }];
    }));
    armNow = Object.keys(armTable)[0];
    root = armTable[armNow].root;
    select = () => armTable[armNow];
  }
  const server = await serveTree(root, { vendors, mounts: { '/__fixtures': FIXTURES }, rewrite, select });
  log(`serving ${site ? 'the prerendered build ' + site.dir : 'the snapshot'} read-only at ${server.url}`);
  let device = null, proxy = null, client = null, cleaned = false, guard = null, fault = null;
  const cleanup = async () => {
    if (cleaned) return; cleaned = true;
    guard?.stop();
    fault?.stop();
    try { await client?.close(); } catch { /* ignore */ }
    try { await proxy?.stop(); } catch (e) { log(`proxy stop: ${e.message}`); }
    if (device && !keep) { try { shutdownDevice(device.udid, { log }); } catch (e) { log(`shutdown: ${e.message}`); } }
    await server.close();
  };
  const onSignal = (sig) => { log(`${sig}: cleaning up`); cleanup().finally(() => process.exit(130)); };
  process.once('SIGINT', () => onSignal('SIGINT'));
  process.once('SIGTERM', () => onSignal('SIGTERM'));
  try {
    device = await bootDevice({ log });
    // The first openurl is dropped in 10 of 10 first sessions on the CI runner, and a fixed sleep before it did not help.
    // Ask now, then poll the tab list: while no tab is listed, ask again every 6 s up to the (scaled) deadline.
    const tabUrl = server.url + startPath.slice(1);
    openUrl(device.udid, tabUrl);
    proxy = await startProxy({ log });
    const listPageTabs = async () => (await listTabs()).filter((x) => x.webSocketDebuggerUrl && String(x.url).startsWith(server.url));
    for (let ask = 1; !client; ask++) {
      try {
        await ensureTab({ list: listPageTabs, ask: () => openUrl(device.udid, tabUrl), timeoutMs: T(30000), log });
        client = await openTab(server.url, { waitMs: T(30000), log });
      } catch (e) {
        if (ask >= Math.max(2, attempts())) throw e;
        log(`${e.message}; opening the URL again (ask ${ask + 1})`);
        openUrl(device.udid, tabUrl);
      }
    }
    await proxyCheck();
    const ctx = {
      c: client, url: server.url + startPath.slice(1), base: server.url.replace(/\/$/, ''), root, device: { name: device.name }, log,
      setClient: (c2) => { client = c2; ctx.c = c2; },
      setArm: (name) => { if (!armTable?.[name]) throw new Error(`no arm ${name}`); armNow = name; },
      armHash: (name) => armTable?.[name]?.hash ?? null,
    };
    // A dead inspector (Lean: Fw.Measure.SimBound): probed at the start of every attempt (ctx.check) and on every tick of the
    // stall watchdog. Two failed probes in a row, or a gone socket: Safari is relaunched once; a second death ends the run
    // with exit code 4. The relaunch steps run within the Lean bounds (BOUNDS), unscaled.
    let deadReject = null;
    const deadP = new Promise((_, rej) => { deadReject = rej; });
    deadP.catch(() => {});
    const phones = proxy.phones;
    const restartProxy = async () => {
      log('the inspector proxy is gone or not answering; starting it again');
      try { await proxy?.stop(); } catch { /* already gone */ }
      proxy = null;
      proxy = await startProxy({ log, timeoutMs: BOUNDS.proxyMs - 5000, phones: phones, lsofMs: 5000 });
    };
    const relaunch = async () => {
      try { client?.close().catch(() => {}); } catch { /* the page is gone with Safari */ } // not awaited: its close waits for a dead socket
      await runSteps([
        { name: 'terminate Safari', ms: BOUNDS.terminateMs, run: () => terminateSafari(device.udid, { timeoutMs: BOUNDS.terminateMs }) },
        { name: 'launch Safari', ms: BOUNDS.launchMs, run: () => startSafari(device.udid, { log, timeoutMs: BOUNDS.launchMs, max: 1 }) },
        { name: 'wait for the inspector socket', ms: BOUNDS.socketMs, run: () => waitSocket({ timeoutMs: BOUNDS.socketMs }) },
        { name: 'start the proxy', ms: BOUNDS.proxyMs, run: async () => {
          try { await proxy?.stop(); } catch { /* already gone */ }
          proxy = null;
          proxy = await startProxy({ log, timeoutMs: BOUNDS.proxyMs - 5000, phones, lsofMs: 5000 });
        } },
        // no openurl first: Safari restores its tab, and a second one would make `openTab` see two; one ask if none is listed
        { name: 'wait for the Safari tab', ms: BOUNDS.tabMs + BOUNDS.askMs, run: () => ensureTab({
          list: listPageTabs, ask: () => openUrl(device.udid, tabUrl, { timeoutMs: BOUNDS.askMs, max: 1 }), maxAsks: 1, timeoutMs: BOUNDS.tabMs, log }) },
        // the page answers: connect once and let go again; the run's own retry connects its client (one owner of ctx.c)
        { name: 'connect to the tab', ms: BOUNDS.connectMs, run: async () => { await (await openTab(server.url, { waitMs: BOUNDS.connectMs, log })).close(); } },
      ], { log });
    };
    guard = createGuard({
      probe: () => probeInspector({ urlPrefix: server.url }), relaunch, repair: restartProxy, log, onDead: (e) => deadReject(e),
    });
    // The proxy can die under host load (seen on a runner: ECONNREFUSED after a 1006 close): a single failed probe starts it again.
    ctx.check = () => guard.check('attempt').then(() => {});
    ctx.ensureProxy = () => guard.check('reconnect', { repair: true }).then(() => {});
    // the wait for the page target (wip.mjs reconnect, Lean targetAction) relaunches Safari through the guard's one relaunch
    ctx.relaunchTab = () => guard.relaunchTab();
    guard.start();
    const plan = faultPlan();
    if (plan) {
      fault = armFault(plan, {
        log,
        kill: plan.kind === 'kill-safari' ? () => terminateSafari(device.udid, { timeoutMs: 20000 }) : () => proxy?.kill(),
      });
      log(`fault ${plan.kind} armed: the first kill comes ${plan.afterMs / 1000} s from now`);
    }
    try {
      return await Promise.race([fn(ctx), deadP]);
    } catch (e) {
      if (e instanceof InspectorDeadError || e instanceof TargetLostError) throw e;
      // the run failed for another reason: one more probe; a dead inspector is found by the same rule (a relaunch, or exit 4 when it gives up), and a probe that does not give up lets this error stand (exit 1)
      log(`the run failed (${e.message}); probing the inspector once more`);
      await guard.check('end of run');
      throw e;
    }
  } finally {
    await cleanup();
  }
}

/** Shut the device down (the `sim down` command). */
export function simDown(log = console.error) {
  const d = findDevice();
  return shutdownDevice(d.udid, { log });
}
export { sleep };
