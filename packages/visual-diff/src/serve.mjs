// The rewrite arm's server and the fonts it is given. The rewrite build ships none of the original's images or fonts (its theme
// keeps a system font stack as a placeholder, and its image URLs point at /selling/... files that only the snapshot has), so
// without help it draws serif fallback glyphs and grey placeholder boxes, and a pixel diff of that measures the missing files,
// not the port. The harness therefore serves, for the rewrite arm only, the snapshot's own static files at the same URL for every
// request the rewrite build does not answer itself, and declares the original's font faces in the rewrite page. Nothing is copied
// into git; both are read from snapshot/site at run time and held in memory.
import http from 'node:http';
import { readFile, readdir, stat } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';

const TYPES = {
  '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp',
  '.avif': 'image/avif', '.gif': 'image/gif', '.ico': 'image/x-icon', '.woff2': 'font/woff2', '.woff': 'font/woff',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.mp4': 'video/mp4', '.webm': 'video/webm',
};
/** Only static media falls back to the snapshot: never HTML, JS or CSS, so the rewrite's own code is what runs. */
export const FALLBACK_EXTS = Object.freeze(Object.keys(TYPES));

const statFile = async (p) => { const s = await stat(p).catch(() => null); return s && s.isFile() ? p : null; };

/** Serve `root` (the rewrite build); a media file it lacks comes from `fallbackRoot` (the snapshot). Counts what fell back. */
export async function startOverlayServer(root, fallbackRoot) {
  const fellBack = new Map();
  const missed = new Set();
  const server = http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, 'http://x');
      const p = normalize(decodeURIComponent(url.pathname));
      if (p.includes('..')) { res.writeHead(400).end(); return; }
      let file = await statFile(join(root, p));
      if (!file) {
        const d = await stat(join(root, p)).catch(() => null);
        if (d && d.isDirectory()) file = await statFile(join(root, p, 'index.html'));
      }
      let fb = false;
      if (!file && FALLBACK_EXTS.includes(extname(p).toLowerCase())) { file = await statFile(join(fallbackRoot, p)); fb = file !== null; }
      if (!file) { missed.add(p); res.writeHead(404, { 'content-type': 'text/plain' }).end('not found'); return; }
      if (fb) fellBack.set(p, (fellBack.get(p) ?? 0) + 1);
      const buf = await readFile(file);
      const type = extname(file) === '.html' ? 'text/html; charset=utf-8' : (TYPES[extname(file).toLowerCase()] ?? 'application/octet-stream');
      res.writeHead(200, { 'content-type': type, 'content-length': buf.length, 'cache-control': 'no-store' });
      res.end(req.method === 'HEAD' ? undefined : buf);
    } catch (e) {
      res.writeHead(500).end(String(e));
    }
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  return {
    port: server.address().port,
    origin: `http://127.0.0.1:${server.address().port}`,
    close: () => new Promise((r) => server.close(r)),
    /** Media served from the snapshot, and paths neither root had (a 404 the page would draw as a broken asset). */
    report: () => ({ fellBack: Object.fromEntries(fellBack), missed: [...missed].filter((m) => FALLBACK_EXTS.includes(extname(m).toLowerCase())) }),
  };
}

/** The original's @font-face rules (the families named in `families`), read from the snapshot's CSS files, as one CSS text. */
export async function originalFontFaces(snapshotRoot, families) {
  const dir = join(snapshotRoot, '_app', 'immutable', 'assets');
  const names = (await readdir(dir).catch(() => [])).filter((n) => n.endsWith('.css')).sort();
  const out = [];
  for (const n of names) {
    const css = await readFile(join(dir, n), 'utf8');
    for (const m of css.matchAll(/@font-face\s*\{[^}]*\}/g)) {
      const fam = /font-family:\s*["']?([^;"'}]+)["']?/.exec(m[0]);
      if (fam && families.includes(fam[1].trim())) out.push(m[0]);
    }
  }
  return out.join('\n');
}
