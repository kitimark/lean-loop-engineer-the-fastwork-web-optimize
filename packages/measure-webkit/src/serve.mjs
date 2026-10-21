// Static server for a read-only tree (plus optional read-only mounts) (the original snapshot or a fixture directory).
// Nothing is copied: files are read from disk per request. Every response is `Cache-Control: no-store`, so Safari's
// cache (which persists across Simulator sessions) can never change what a run loads.
// `/analytics.js` is answered with an empty script unless `vendors: 'live'`: the original's first-party loader pulls
// Google Tag Manager from the network, which would make a run depend on the outside world.
import http from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8', '.svg': 'image/svg+xml',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.avif': 'image/avif',
  '.gif': 'image/gif', '.ico': 'image/x-icon', '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf',
  '.txt': 'text/plain; charset=utf-8', '.webmanifest': 'application/manifest+json', '.mp4': 'video/mp4',
  '.webm': 'video/webm', '.xml': 'application/xml',
};

/** Resolve a request path under `root`, or null when it escapes the root or contains NUL. */
export function safeJoin(root, urlPath) {
  let p;
  try { p = decodeURIComponent(urlPath.split('?')[0].split('#')[0]); } catch { return null; }
  if (p.includes('\0')) return null;
  const abs = resolve(root, '.' + (p.startsWith('/') ? p : '/' + p));
  const r = resolve(root);
  return abs === r || abs.startsWith(r + sep) ? abs : null;
}

/**
 * Start a server on 127.0.0.1. `port: 0` picks a free port.
 * @returns {Promise<{port:number, url:string, requests:string[], close:()=>Promise<void>}>}
 */
export async function serveTree(root0, { port = 0, host = '127.0.0.1', vendors = 'off', mounts = {}, rewrite: rewrite0 = null, select = null } = {}) {
  const requests = [];
  const server = http.createServer(async (req, res) => {
    // `select()` -> { root, rewrite } read on every request: one origin that serves a different tree per arm (the Simulator keeps one tab origin)
    const { root, rewrite } = select ? select() : { root: root0, rewrite: rewrite0 };
    const fail = (code, msg) => { res.writeHead(code, { 'content-type': 'text/plain', 'cache-control': 'no-store' }); res.end(msg); };
    try {
      if (req.method !== 'GET' && req.method !== 'HEAD') return fail(405, 'method not allowed');
      let urlPath = req.url || '/';
      // `rewrite(pathOnly, search)` -> a path under root, or null: lets a prerendered build serve one HTML per config hash
      if (rewrite) { const [pth, ...q] = urlPath.split('?'); const to = rewrite(pth, q.length ? '?' + q.join('?') : ''); if (to) urlPath = to; }
      requests.push(urlPath.split('?')[0]);
      if (vendors === 'off' && urlPath.split('?')[0] === '/analytics.js') {
        res.writeHead(200, { 'content-type': MIME['.js'], 'cache-control': 'no-store' });
        return res.end('/* analytics loader replaced by an empty script (vendors: off) */\n');
      }
      // `mounts`: { '/__fixtures': '/abs/dir' } serves that directory under that URL prefix, read-only.
      let file = null;
      const pathOnly = urlPath.split('?')[0];
      for (const [prefix, dir] of Object.entries(mounts)) {
        if (pathOnly === prefix || pathOnly.startsWith(prefix + '/')) { file = safeJoin(dir, urlPath.slice(prefix.length) || '/'); break; }
      }
      if (!file) file = safeJoin(root, urlPath);
      if (!file) return fail(400, 'bad path');
      let st = await stat(file).catch(() => null);
      if (st?.isDirectory()) { file = resolve(file, 'index.html'); st = await stat(file).catch(() => null); }
      if (!st?.isFile()) return fail(404, 'not found');
      const body = await readFile(file);
      const headers = { 'content-type': MIME[extname(file).toLowerCase()] || 'application/octet-stream', 'content-length': body.length, 'cache-control': 'no-store', 'accept-ranges': 'bytes' };
      const range = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range || '');
      if (range && (range[1] || range[2])) {
        const a = range[1] === '' ? Math.max(0, body.length - Number(range[2])) : Number(range[1]);
        const b = range[1] === '' || range[2] === '' ? body.length - 1 : Math.min(Number(range[2]), body.length - 1);
        if (a > b || a >= body.length) { res.writeHead(416, { 'content-range': `bytes */${body.length}` }); return res.end(); }
        res.writeHead(206, { ...headers, 'content-length': b - a + 1, 'content-range': `bytes ${a}-${b}/${body.length}` });
        return res.end(req.method === 'HEAD' ? undefined : body.subarray(a, b + 1));
      }
      res.writeHead(200, headers);
      res.end(req.method === 'HEAD' ? undefined : body);
    } catch (e) { fail(500, String(e?.message || e)); }
  });
  await new Promise((ok, bad) => { server.once('error', bad); server.listen(port, host, ok); });
  const p = server.address().port;
  return {
    port: p, url: `http://${host}:${p}/`, requests,
    close: () => new Promise((ok) => { server.closeAllConnections?.(); server.close(() => ok()); }),
  };
}
