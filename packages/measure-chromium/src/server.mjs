// Tiny static server for the read-only snapshot (counts lane). Serves exactly the bytes under the root, no
// rewriting, no caching headers that depend on time. Every served path is recorded with the sha256 of its bytes so a
// run can prove which bytes it measured.
import http from 'node:http';
import { createHash } from 'node:crypto';
import { readFile, stat } from 'node:fs/promises';
import { join, normalize, extname, sep } from 'node:path';
import { canonSearch } from '../../contracts/src/flag-key.mjs';

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.avif': 'image/avif', '.gif': 'image/gif',
  '.ico': 'image/x-icon', '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf', '.otf': 'font/otf',
  '.webmanifest': 'application/manifest+json', '.txt': 'text/plain; charset=utf-8', '.map': 'application/json',
  '.mp4': 'video/mp4', '.webm': 'video/webm',
};

export async function startServer(root, port = 0) {
  const served = new Map(); // url path -> sha256 of the bytes sent
  const missing = new Set();
  let inflight = 0, requests = 0;
  const pages = await readFile(join(root, 'configs.json'), 'utf8').then(JSON.parse, () => null);
  const server = http.createServer(async (req, res) => {
    requests++; inflight++; res.on('close', () => { inflight--; });
    try {
      const url = new URL(req.url, 'http://x');
      let p = normalize(decodeURIComponent(url.pathname));
      if (p.includes('..')) { res.writeHead(400).end(); return; }
      let file = join(root, p);
      // Prerendered site build (apps/site): "/" + search is answered by the page prerendered for that exact search
      // (dist/configs.json: bySearch -> hash -> byHash). An unknown search gets index.html, as apps/site's own server
      // does; the page then reports mode "client-render" and the driver refuses to measure it.
      if (p === '/' && pages) {
        const hash = pages.bySearch[canonSearch(url.search)];
        file = join(root, hash ? pages.byHash[hash] : 'index.html');
      }
      let st = await stat(file).catch(() => null);
      if (st && st.isDirectory()) { file = join(file, 'index.html'); st = await stat(file).catch(() => null); }
      if (!st) { missing.add(url.pathname); res.writeHead(404, { 'content-type': 'text/plain' }).end('not found'); return; }
      const buf = await readFile(file);
      served.set(url.pathname, createHash('sha256').update(buf).digest('hex'));
      res.writeHead(200, { 'content-type': TYPES[extname(file)] ?? 'application/octet-stream', 'content-length': buf.length, 'cache-control': 'no-store' });
      res.end(req.method === 'HEAD' ? undefined : buf);
    } catch (e) {
      res.writeHead(500).end(String(e));
    }
  });
  await new Promise((r) => server.listen(port, '127.0.0.1', r));
  return {
    port: server.address().port,
    served: () => Object.fromEntries([...served.entries()].sort(([a], [b]) => (a < b ? -1 : 1))),
    inflight: () => inflight,
    requests: () => requests,
    missing: () => [...missing].sort(),
    close: () => new Promise((r) => server.close(r)),
  };
}
if (process.argv[1] && process.argv[1].endsWith('server.mjs')) {
  const s = await startServer(process.argv[2], +(process.argv[3] ?? 0));
  console.log(`serving ${process.argv[2]} on http://127.0.0.1:${s.port}/`);
}
export { sep };
