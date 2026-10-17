// One measurement session: serve the original read-only snapshot on 127.0.0.1, boot the Simulator headless, open the
// page in Mobile Safari, start the Inspector proxy, connect, run `fn`, and shut everything down in `finally`
// (also on SIGINT/SIGTERM). The snapshot is read from disk per request and never copied.
import { existsSync, readFileSync } from 'node:fs';
import { resolve, dirname, join, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { serveTree } from './serve.mjs';
import { bootDevice, openUrl, shutdownDevice, startProxy, proxyCheck, findDevice, sleep } from './sim.mjs';
import { openTab } from './wip.mjs';
import { T, attempts } from './timeouts.mjs';

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
  let device = null, proxy = null, client = null, cleaned = false;
  const cleanup = async () => {
    if (cleaned) return; cleaned = true;
    try { client?.close(); } catch { /* ignore */ }
    try { await proxy?.stop(); } catch (e) { log(`proxy stop: ${e.message}`); }
    if (device && !keep) { try { shutdownDevice(device.udid, { log }); } catch (e) { log(`shutdown: ${e.message}`); } }
    await server.close();
  };
  const onSignal = (sig) => { log(`${sig}: cleaning up`); cleanup().finally(() => process.exit(130)); };
  process.once('SIGINT', () => onSignal('SIGINT'));
  process.once('SIGTERM', () => onSignal('SIGTERM'));
  try {
    device = await bootDevice({ log });
    await sleep(T(3000)); // an openurl right after the launch is sometimes dropped
    openUrl(device.udid, server.url + startPath.slice(1));
    proxy = await startProxy({ log });
    // the proxy sometimes lists the tab late or Safari dropped the openurl: ask again, bounded (FW_WK_ATTEMPTS asks in all)
    for (let ask = 1; !client; ask++) {
      try { client = await openTab(server.url, { waitMs: T(ask === 1 ? 10000 : 40000), log }); } catch (e) {
        if (ask >= Math.max(2, attempts())) throw e;
        log(`${e.message}; opening the URL again (ask ${ask + 1})`);
        openUrl(device.udid, server.url + startPath.slice(1));
      }
    }
    await proxyCheck();
    const ctx = {
      c: client, url: server.url + startPath.slice(1), base: server.url.replace(/\/$/, ''), root, device: { name: device.name }, log,
      setClient: (c2) => { client = c2; ctx.c = c2; },
      // the proxy can die under host load (seen on a runner: ECONNREFUSED after a 1006 close); start it again, Safari still runs
      ensureProxy: async () => {
        if (proxy?.alive()) { try { await proxyCheck(); return; } catch { /* answers no more */ } }
        log('the inspector proxy is gone or not answering; starting it again');
        try { await proxy?.stop(); } catch { /* already gone */ }
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
