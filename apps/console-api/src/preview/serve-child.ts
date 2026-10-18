// The preview server process (one per preview, started by PreviewManager in its own process group).
// Two read-only static servers on 127.0.0.1: the rewrite (`--rewrite <dist>` on --rp) and the original snapshot
// (`--original <dir>` on --op). Only I/O: no decisions (ports, lifetime and who may start come from Lean
// `Fw.Console.Preview`). GET/HEAD only, no-store, path containment, analytics stubbed.
//   node serve-child.ts --fw-preview=<id> --rewrite <dist> --original <dir> --media <dir> --rp N --op N
// `--fw-preview=<id>` is only a marker: the manager checks it in `ps` before it signals a recorded pid after a restart.
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { existsSync, readFileSync, statSync } from "node:fs";
import { extname, join, normalize, resolve, sep } from "node:path";

const MIME: Record<string, string> = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css",
  ".json": "application/json", ".svg": "image/svg+xml", ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
  ".webp": "image/webp", ".avif": "image/avif", ".gif": "image/gif", ".ico": "image/x-icon", ".woff": "font/woff",
  ".woff2": "font/woff2", ".ttf": "font/ttf", ".otf": "font/otf", ".mp4": "video/mp4", ".webm": "video/webm", ".txt": "text/plain",
};
/** Extensions the rewrite may take from the snapshot when its own build lacks them (never HTML, JS or CSS). */
const MEDIA = new Set([".png", ".jpg", ".jpeg", ".webp", ".avif", ".gif", ".svg", ".ico", ".woff", ".woff2", ".ttf", ".otf", ".mp4", ".webm"]);

function arg(name: string): string | undefined {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

/** `root` joined with the request path, or null when the path leaves `root` (or is not a file). */
export function safeFile(root: string, urlPath: string): string | null {
  let p: string;
  try { p = decodeURIComponent(urlPath); } catch { return null; }
  if (p.includes("\0")) return null;
  const base = resolve(root);
  const f = resolve(join(base, normalize(p)));
  if (f !== base && !f.startsWith(base + sep)) return null;
  try { return statSync(f).isFile() ? f : null; } catch { return null; }
}

function send(res: ServerResponse, req: IncomingMessage, status: number, type: string, body: Buffer | string) {
  res.writeHead(status, { "content-type": type, "cache-control": "no-store" });
  res.end(req.method === "HEAD" ? undefined : body);
}

function serveFile(req: IncomingMessage, res: ServerResponse, file: string) {
  send(res, req, 200, MIME[extname(file).toLowerCase()] ?? "application/octet-stream", readFileSync(file));
}

type Opts = { root: string; mediaRoot?: string; prerendered?: boolean; compare?: { rp: number; op: number } };

export function handler(o: Opts) {
  const configs = o.prerendered && existsSync(join(o.root, "configs.json"))
    ? JSON.parse(readFileSync(join(o.root, "configs.json"), "utf8")) as { bySearch: Record<string, string>; byHash: Record<string, string> }
    : null;
  return (req: IncomingMessage, res: ServerResponse) => {
    if (req.method !== "GET" && req.method !== "HEAD") return send(res, req, 405, "text/plain", "read-only");
    const u = new URL(req.url ?? "/", "http://127.0.0.1");
    if (u.pathname === "/analytics.js") return send(res, req, 200, "text/javascript", ""); // the GTM loader never reaches the network
    if (o.compare && u.pathname === "/__fw/compare") return send(res, req, 200, "text/html; charset=utf-8", comparePage(o.compare.op, o.compare.rp));
    // "/" with a search: the prerendered page of that search (as the gate does), else index.html (the page client-renders)
    let path = u.pathname;
    if (configs && (path === "/" || path === "/index.html")) {
      const hash = configs.bySearch[u.search];
      const rel = hash ? configs.byHash[hash] : undefined;
      if (rel) path = "/" + rel;
    }
    if (path.endsWith("/")) path += "index.html";
    let f = safeFile(o.root, path);
    if (!f && o.mediaRoot && MEDIA.has(extname(path).toLowerCase())) f = safeFile(o.mediaRoot, path);
    if (!f) return send(res, req, 404, "text/plain", "not found");
    serveFile(req, res, f);
  };
}

/** Side by side: original left, task version right, two iframes of the same width (an iframe's width is its viewport
 *  for `(width)` media queries). Hover, pointer, reduced-motion and dpr cannot be set from an iframe. */
export function comparePage(op: number, rp: number): string {
  return `<!doctype html><meta charset="utf-8"><title>original | task version</title>
<style>body{margin:0;font:13px system-ui;background:#eee}header{padding:6px 10px;display:flex;gap:10px;align-items:center}
.row{display:flex;gap:8px;padding:0 8px 8px}.col{flex:1;min-width:0}.col h2{font-size:12px;margin:2px 0}
iframe{border:1px solid #888;background:#fff;height:calc(100vh - 80px);width:100%}</style>
<header><b>Side by side</b> width <select id=w><option value="">fit</option><option>320</option><option>390</option><option>600</option>
<option>861</option><option>1024</option><option>1280</option><option>1512</option></select>
<span>Scroll each side yourself. Emulate hover, reduced motion and dpr in DevTools per window.</span></header>
<div class=row><div class=col><h2>original (snapshot) :${op}</h2><iframe id=a src="http://127.0.0.1:${op}/"></iframe></div>
<div class=col><h2>task version :${rp}</h2><iframe id=b src="http://127.0.0.1:${rp}/"></iframe></div></div>
<script>const w=document.getElementById('w');w.onchange=()=>{for(const id of ['a','b']){const f=document.getElementById(id);f.style.width=w.value?w.value+'px':'100%';f.parentElement.style.flex=w.value?'none':'1'}}</script>`;
}

if (process.argv.includes("--serve")) {
  const rewrite = arg("--rewrite")!, original = arg("--original")!, media = arg("--media");
  const rp = Number(arg("--rp")), op = Number(arg("--op"));
  const a = createServer(handler({ root: rewrite, mediaRoot: media, prerendered: true, compare: { rp, op } }));
  const b = createServer(handler({ root: original }));
  let up = 0;
  const ready = () => { if (++up === 2) console.log(JSON.stringify({ ready: true, rp, op })); };
  a.listen(rp, "127.0.0.1", ready);
  b.listen(op, "127.0.0.1", ready);
  const bye = () => { a.close(); b.close(); process.exit(0); };
  process.on("SIGTERM", bye);
  process.on("SIGINT", bye);
}
