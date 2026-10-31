import { existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, dirname, join, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { serveTree } from './serve.mjs';
import { relaunchPlan } from './sim-host.mjs';
import { bootDevice, terminateSafariAsync, startSafariAsync, waitSocket, openUrlAsync, shutdownDeviceAsync, startProxy, proxyCheck, probeInspector, findDevice, shutdownDevice, listTabs, sleep } from './sim.mjs';
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

/** The file of pass `n` next to the result file `out`: `x.json` becomes `x.pass-2.part` (never `*.json`: the workflow merges every `v*-session-*.json`). */
export const passFile = (out, n) => out.replace(/(\.json)?$/, `.pass-${n}.part`);

/**
 * Write one finished pass beside the result file, whole or not at all (a temp file, then a rename), so a job that is lost mid-run
 * leaves every pass that ended. Returns the path, or null when there is no result file. The result file itself is unchanged.
 */
export function writePassFile(out, n, of, data, { now = Date.now } = {}) {
  if (!out) return null;
  const file = passFile(resolve(out), n);
  mkdirSync(dirname(file), { recursive: true });
  const tmp = `${file}.tmp`;
  writeFileSync(tmp, JSON.stringify({ schema: 'fw.webkit.pass/1', pass: n, of, wroteAt: new Date(now()).toISOString(), data }));
  renameSync(tmp, file);
  return file;
}

/**
 * `ensureTab` calls `ask()` without waiting for it: an openurl that is still running is not sent again (a second one could open a second
 * tab), and a failure is logged, as ensureTab did when the call was synchronous.
 */
export const askOnce = (send, log) => {
  let busy = false;
  return () => {
    if (busy) return;
    busy = true;
    send().catch((e) => log(`  openurl failed: ${e.message}`)).finally(() => { busy = false; });
  };
};

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
  let select = null, armTable = null, armNow = null;
  const blankDirs = [];
  if (arms) {
    armTable = Object.fromEntries(Object.entries(arms).map(([name, a]) => {
      if (a.blank) {
        const d = mkdtempSync(join(tmpdir(), 'fw-blank-'));
        blankDirs.push(d);
        writeFileSync(join(d, 'index.html'), '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>blank</title></head><body></body></html>\n');
        return [name, { root: d, rewrite: null, hash: null }];
      }
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
    if (device && !keep) { try { await shutdownDeviceAsync(device.udid, { log }); } catch (e) { log(`shutdown: ${e.message}`); } }
    await server.close();
    for (const d of blankDirs) rmSync(d, { recursive: true, force: true });
  };
  const onSignal = (sig) => { log(`${sig}: cleaning up`); cleanup().finally(() => process.exit(130)); };
  process.once('SIGINT', () => onSignal('SIGINT'));
  process.once('SIGTERM', () => onSignal('SIGTERM'));
  try {
    device = await bootDevice({ log });
    // The first openurl is dropped in 10 of 10 first sessions on the CI runner, and a fixed sleep before it did not help.
    // Ask now, then poll the tab list: while no tab is listed, ask again every 6 s up to the (scaled) deadline.
    const tabUrl = server.url + startPath.slice(1);
    await openUrlAsync(device.udid, tabUrl);
    proxy = await startProxy({ log });
    const listPageTabs = async () => (await listTabs()).filter((x) => x.webSocketDebuggerUrl && String(x.url).startsWith(server.url));
    for (let ask = 1; !client; ask++) {
      try {
        await ensureTab({ list: listPageTabs, ask: askOnce(() => openUrlAsync(device.udid, tabUrl), log), timeoutMs: T(30000), log });
        client = await openTab(server.url, { waitMs: T(30000), log });
      } catch (e) {
        if (ask >= Math.max(2, attempts())) throw e;
        log(`${e.message}; opening the URL again (ask ${ask + 1})`);
        await openUrlAsync(device.udid, tabUrl);
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
    // The steps and their bounds are Lean's (SimHost.Freeze.relaunchPlan): right after a reboot there is no Safari to terminate.
    const relaunch = async ({ fresh = false } = {}) => {
      try { client?.close().catch(() => {}); } catch { /* the page is gone with Safari */ } // not awaited: its close waits for a dead socket
      const doStep = {
        'terminate Safari': () => terminateSafariAsync(device.udid, { timeoutMs: BOUNDS.terminateMs }),
        'launch Safari': () => startSafariAsync(device.udid, { log, timeoutMs: BOUNDS.launchMs, max: 1 }),
        'wait for the inspector socket': () => waitSocket({ timeoutMs: BOUNDS.socketMs }),
        'start the proxy': async () => {
          try { await proxy?.stop(); } catch { /* already gone */ }
          proxy = null;
          proxy = await startProxy({ log, timeoutMs: BOUNDS.proxyMs - 5000, phones, lsofMs: 5000 });
        },
        // no openurl first: Safari restores its tab, and a second one would make `openTab` see two; one ask if none is listed
        'wait for the Safari tab': () => ensureTab({
          list: listPageTabs, ask: askOnce(() => openUrlAsync(device.udid, tabUrl, { timeoutMs: BOUNDS.askMs, max: 1 }), log), maxAsks: 1, timeoutMs: BOUNDS.tabMs, log }),
        // the page answers: connect once and let go again; the run's own retry connects its client (one owner of ctx.c)
        'connect to the tab': async () => { await (await openTab(server.url, { waitMs: BOUNDS.connectMs, log })).close(); },
      };
      await runSteps(relaunchPlan(fresh).map(({ name, ms }) => ({ name, ms, run: doStep[name] })), { log });
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
        kill: plan.kind === 'kill-safari' ? () => terminateSafariAsync(device.udid, { timeoutMs: 20000 }) : () => proxy?.kill(),
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
