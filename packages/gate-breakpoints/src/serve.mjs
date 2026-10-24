// Read-only static servers for the two arms. Serves exactly the bytes under a root (no rewriting), `no-store`.
// Nothing of the snapshot is copied.
import http from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, extname, join, normalize, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { canonSearch } from '../../contracts/src/flag-key.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
export const PKG = resolve(HERE, '..');

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.avif': 'image/avif', '.gif': 'image/gif',
  '.ico': 'image/x-icon', '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf', '.otf': 'font/otf',
  '.webmanifest': 'application/manifest+json', '.txt': 'text/plain; charset=utf-8', '.map': 'application/json',
};

/** snapshot/site of the main checkout ($FW_SNAPSHOT_SITE overrides; a linked worktree has none of its own). */
export function snapshotRoot(env = process.env) {
  if (env.FW_SNAPSHOT_SITE) return resolve(env.FW_SNAPSHOT_SITE);
  const candidates = [];
  let dir = HERE;
  for (let i = 0; i < 8; i++) { candidates.push(join(dir, 'snapshot', 'site')); dir = dirname(dir); }
  const marker = `${sep}.claude${sep}worktrees${sep}`;
  const at = HERE.indexOf(marker);
  if (at > 0) candidates.push(join(HERE.slice(0, at), 'snapshot', 'site'));
  const found = candidates.find((p) => existsSync(join(p, 'index.html')));
  if (!found) throw new Error('snapshot/site not found: set FW_SNAPSHOT_SITE');
  return found;
}

/** The rewrite's prerendered default config: apps/site/dist/aot ($FW_SITE_DIST overrides). */
export function siteDist(env = process.env) {
  const p = env.FW_SITE_DIST ? resolve(env.FW_SITE_DIST) : resolve(PKG, '../../apps/site/dist/aot');
  if (!existsSync(join(p, 'index.html'))) throw new Error(`rewrite build not found at ${p}: run \`pnpm --filter @fw/site build\``);
  return p;
}

/** `FW_SEARCH` (e.g. `?fw=morph.tween:waapi`): the rewrite arm loads that prerendered config (configs.json bySearch); empty = the default page. */
export function rewriteFor(root, env = process.env) {
  const search = env.FW_SEARCH ?? "";
  if (!search) return { search: "", hash: null, rewrite: null };
  const cfg = JSON.parse(readFileSync(join(root, "configs.json"), "utf8"));
  const hash = cfg.bySearch[canonSearch(search)];
  if (!hash) throw new Error(`FW_SEARCH "${search}" is not prerendered; known: ${Object.keys(cfg.bySearch).join(" | ")}`);
  const file = "/" + cfg.byHash[hash];
  return { search, hash, rewrite: (p) => (p === "/" || p === "/index.html" ? file : null) };
}

export async function startServer(root, rewrite = null) {
  const server = http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, 'http://x');
      const p = (rewrite && rewrite(normalize(decodeURIComponent(url.pathname)))) || normalize(decodeURIComponent(url.pathname));
      if (p.includes('..')) { res.writeHead(400).end(); return; }
      let file = join(root, p);
      let st = await stat(file).catch(() => null);
      if (st && st.isDirectory()) { file = join(file, 'index.html'); st = await stat(file).catch(() => null); }
      if (!st) { res.writeHead(404, { 'content-type': 'text/plain' }).end('not found'); return; }
      const buf = await readFile(file);
      res.writeHead(200, { 'content-type': TYPES[extname(file)] ?? 'application/octet-stream', 'content-length': buf.length, 'cache-control': 'no-store' });
      res.end(req.method === 'HEAD' ? undefined : buf);
    } catch (e) {
      res.writeHead(500).end(String(e));
    }
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  return { port: server.address().port, origin: `http://127.0.0.1:${server.address().port}`, close: () => new Promise((r) => server.close(r)) };
}
