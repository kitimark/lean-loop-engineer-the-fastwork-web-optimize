import http from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.webp': 'image/webp', '.avif': 'image/avif', '.ico': 'image/x-icon', '.woff2': 'font/woff2',
  '.woff': 'font/woff', '.txt': 'text/plain; charset=utf-8', '.map': 'application/json',
};

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
  return { origin: `http://127.0.0.1:${server.address().port}`, close: () => new Promise((r) => server.close(r)) };
}
