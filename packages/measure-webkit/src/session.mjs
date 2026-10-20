// One measurement session: serve the original read-only snapshot on 127.0.0.1, boot the Simulator headless, open the
// page in Mobile Safari, start the Inspector proxy, connect, run `fn`, and shut everything down in `finally`
// (also on SIGINT/SIGTERM). The snapshot is read from disk per request and never copied.
import { existsSync, readFileSync } from 'node:fs';
import { resolve, dirname, join, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { serveTree } from './serve.mjs';
import { bootDevice, launchSafari, openUrl, shutdownDevice, startProxy, proxyCheck, findDevice, findSockets, listTabs, sleep } from './sim.mjs';
import { inspectorAction, InspectorDeadError } from './inspector.mjs';
import { openTab } from './wip.mjs';
import { T, attempts } from './timeouts.mjs';
import { ensureTab } from './poll.mjs';

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
export async function withSession(fn, { keep = false, vendors = 'off', site = null, log = (s) => console.error(s) } = {}) {
  // site: { dir, search } serves a prerendered build of apps/site (dist/aot): "/" + search is answered with the HTML of
  // that search's config hash (configs.json), as a CDN rewrite would. Without it: the read-only snapshot.
  let root, rewrite = null, startPath = '/';
  if (site) {
    root = resolve(site.dir);
    const cfg = JSON.parse(readFileSync(join(root, 'configs.json'), 'utf8'));
    const hash = cfg.bySearch[site.search ?? ''];
    if (!hash) throw new Error(`search "${site.search}" is not prerendered; known: ${Object.keys(cfg.bySearch).join(' | ')}`);
    const file = cfg.byHash[hash];
    rewrite = (p) => (p === '/' || p === '/index.html' ? '/' + file : null);
    startPath = '/' + (site.search ?? '');
    site.configHash = hash;
  } else root = snapshotRoot();
  const server = await serveTree(root, { vendors, mounts: { '/__fixtures': FIXTURES }, rewrite });
  log(`serving ${site ? 'the prerendered build ' + site.dir : 'the snapshot'} read-only at ${server.url}`);
  let device = null, proxy = null, client = null, cleaned = false, relaunched = false, refusals = 0;
  const cleanup = async () => {
    if (cleaned) return; cleaned = true;
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
      // The proxy can die under host load (seen on a runner: ECONNREFUSED after a 1006 close): start it again, Safari still runs.
      // When the inspector socket is gone or the proxy was refused twice in a row (Lean: Fw.Measure.SimBound), Safari is
      // relaunched once; a second death ends the run with exit code 4 instead of waiting out every attempt.
      ensureProxy: async () => {
        let socket = true;
        try { socket = findSockets().length > 0; } catch { /* lsof failed: not evidence of a dead inspector */ }
        if (socket && proxy?.alive()) {
          try { await proxyCheck(); refusals = 0; return; } catch (e) { if (/ECONNREFUSED/.test(e.message)) refusals++; }
        } else if (socket) refusals++;
        const action = inspectorAction(relaunched, socket, refusals);
        if (action === 'giveUp') throw new InspectorDeadError(`the inspector is dead again after Safari was relaunched (${socket ? `proxy refused ${refusals} times` : 'no inspector socket'}); giving up`);
        try { await proxy?.stop(); } catch { /* already gone */ }
        proxy = null;
        if (action === 'relaunch') {
          log(`the inspector is dead (${socket ? `proxy refused ${refusals} times` : 'no inspector socket'}); relaunching Safari once`);
          relaunched = true; refusals = 0;
          try {
            await launchSafari(device.udid, { log });
            openUrl(device.udid, tabUrl);
            proxy = await startProxy({ log });
            await ensureTab({ list: listPageTabs, ask: () => openUrl(device.udid, tabUrl), timeoutMs: T(30000), log });
          } catch (e) { throw new InspectorDeadError(`the inspector is dead and relaunching Safari failed: ${e.message}`); }
          return;
        }
        log('the inspector proxy is gone or not answering; starting it again');
        proxy = await startProxy({ log });
      },
    };
    return await fn(ctx);
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
