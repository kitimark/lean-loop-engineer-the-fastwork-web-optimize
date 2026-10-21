// Static server for the probe: two synthetic pages (/blank.html, /paint.html) and a read-only view of snapshot/site (the original
// page, served byte for byte, no-store). Binds 127.0.0.1 on a free port.
import http from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { dirname, extname, join, normalize, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
/** Repository root of this checkout (src/linux -> measure-webkit -> packages -> root). */
export const ROOT = resolve(HERE, '../../../..');

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.avif': 'image/avif', '.gif': 'image/gif',
  '.ico': 'image/x-icon', '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf', '.otf': 'font/otf',
  '.webmanifest': 'application/manifest+json', '.txt': 'text/plain; charset=utf-8',
};

/** A tall empty page: the scroll has room for 10 steps at any width. */
const TALL = '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
  + '<style>html,body{margin:0;background:#fff}body{height:30000px}</style><body>';

export const SYNTHETIC = { '/blank.html': TALL, '/paint.html': TALL };

/** Snapshot root: $FW_SNAPSHOT_SITE, else snapshot/site of this checkout (a linked worktree falls back to the main checkout's copy). */
export function snapshotRoot(env = process.env) {
  if (env.FW_SNAPSHOT_SITE) return resolve(env.FW_SNAPSHOT_SITE);
  return join(ROOT, 'snapshot', 'site');
}

/** Start the server; resolves {origin, close}. */
export async function startServer(root = snapshotRoot()) {
  const server = http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, 'http://x');
      const p = normalize(decodeURIComponent(url.pathname));
      if (p.includes('..')) { res.writeHead(400).end(); return; }
      if (SYNTHETIC[p]) { res.writeHead(200, { 'content-type': TYPES['.html'], 'cache-control': 'no-store' }).end(SYNTHETIC[p]); return; }
      let file = join(root, p);
      let st = await stat(file).catch(() => null);
      if (st && st.isDirectory()) { file = join(file, 'index.html'); st = await stat(file).catch(() => null); }
      if (!st) { res.writeHead(404).end('not found'); return; }
      const body = await readFile(file);
      res.writeHead(200, { 'content-type': TYPES[extname(file)] ?? 'application/octet-stream', 'cache-control': 'no-store' }).end(body);
    } catch (e) {
      res.writeHead(500).end(String(e));
    }
  });
  await new Promise((ok) => server.listen(0, '127.0.0.1', ok));
  const { port } = server.address();
  return { origin: `http://127.0.0.1:${port}`, close: () => new Promise((ok) => server.close(ok)) };
}

/** URL path of a page kind. */
export function pagePath(page) {
  return page === 'orig' ? '/' : `/${page}.html`;
}
