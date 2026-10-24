// The preview server process (one per preview, started by PreviewManager in its own process group).
// Two read-only static servers on 127.0.0.1: the rewrite (`--rewrite <dist>` on --rp) and the original snapshot
// (`--original <dir>` on --op). Only I/O: no decisions (ports, lifetime and who may start come from Lean
// `Fw.Console.Preview`). GET/HEAD only, path containment, analytics stubbed. Files carry the cache policy of Lean
// `Fw.Console.PreviewCache` (cache-policy.ts): files under /_app/immutable/, listed in the build's .vite/manifest.json or named mui.<sha8>.css immutable, the rest no-cache with a strong ETag (304 on a match);
// text types are compressed once per file and kept in memory, keyed by the file's mtime, ctime, size and inode.
//   node serve-child.ts --fw-preview=<id> --rewrite <dist> --original <dir> --media <dir> --rp N --op N [--arm-rp N --arm-op N]
// `--rp`/`--op`: the private ports it listens on. `--arm-rp`/`--arm-op`: the arms' public ports (their gated origins on the
// console host), which the side-by-side page frames by the host of its own address.
// `--fw-preview=<id>` is only a marker: the manager checks it in `ps` before it signals a recorded pid after a restart.
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { existsSync, readFileSync, statSync } from "node:fs";
import { extname, join, normalize, relative, resolve, sep } from "node:path";
import { choose, picker } from "./picker.ts";
import { cachePolicy, etagMatches, etagOf, manifestNames, pickEncoding, Variants } from "./cache-policy.ts";
import { canonSearch } from "../../../../packages/contracts/src/flag-key.mjs";

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

/** Files up to this size keep their bytes in memory; larger ones are read per request and their ETag hashes the bytes sent. */
const KEEP_BYTES = 4 * 1024 * 1024;
const MAX_FILES = 2000;
type Cached = { key: string; variants?: Variants };
const files = new Map<string, Cached>();

function cached(file: string, size: number, key: string): Cached {
  if (size > KEEP_BYTES) throw new Error("too large to keep");
  let c = files.get(file);
  if (!c || c.key !== key) {
    c = { key };
    const bytes = readFileSync(file);
    c.variants = new Variants(bytes);
    files.set(file, c);
    if (files.size > MAX_FILES) files.delete(files.keys().next().value!);
  }
  return c;
}

/** `rel`: the file's path below the root it was found in (the policy reads this, never the requested path). */
function serveFile(req: IncomingMessage, res: ServerResponse, file: string, rel: string, names: ReadonlySet<string>) {
  const st = statSync(file);
  const c = st.size <= KEEP_BYTES ? cached(file, st.size, `${st.mtimeMs}:${st.ctimeMs}:${st.size}:${st.ino}`) : null;
  const ct = MIME[extname(file).toLowerCase()] ?? "application/octet-stream";
  const pol = cachePolicy(rel, names);
  const enc = pol.compress && c?.variants ? pickEncoding(req.headers["accept-encoding"]) : "identity";
  const headers: Record<string, string> = { "content-type": ct, "cache-control": pol.cacheControl };
  if (pol.compress) headers.vary = "accept-encoding";
  let body: Buffer;
  if (c?.variants) {
    const v = c.variants.get(enc);
    headers.etag = v.etag; body = v.body;
    if (enc !== "identity") headers["content-encoding"] = enc;
  } else {
    body = readFileSync(file); headers.etag = etagOf(body);
  }
  if (etagMatches(req.headers["if-none-match"], headers.etag)) {
    res.writeHead(304, headers);
    return res.end();
  }
  headers["content-length"] = String(body.length);
  res.writeHead(200, headers);
  res.end(req.method === "HEAD" ? undefined : body);
}

/** The rewrite build's manifest names, re-read when `.vite/manifest.json` changes (a rebuild). */
function manifestReader(root: string): () => ReadonlySet<string> {
  const file = join(root, ".vite", "manifest.json");
  let key = "", names: ReadonlySet<string> = new Set();
  return () => {
    let k = "";
    try { const st = statSync(file); k = `${st.mtimeMs}:${st.ctimeMs}:${st.size}:${st.ino}`; } catch { /* no manifest: nothing is listed */ }
    if (k !== key) {
      key = k;
      try { names = k ? manifestNames(JSON.parse(readFileSync(file, "utf8"))) : new Set(); } catch { names = new Set(); }
    }
    return names;
  };
}

/** `compare`: the PUBLIC ports of the two arms (their gated origins), which the side-by-side page frames. */
type Opts = { root: string; mediaRoot?: string; prerendered?: boolean; compare?: { rp: number; op: number } };

export function handler(o: Opts) {
  const configs = o.prerendered && existsSync(join(o.root, "configs.json"))
    ? JSON.parse(readFileSync(join(o.root, "configs.json"), "utf8")) as { bySearch: Record<string, string>; byHash: Record<string, string> }
    : null;
  const names = manifestReader(o.root);
  return (req: IncomingMessage, res: ServerResponse) => {
    if (req.method !== "GET" && req.method !== "HEAD") return send(res, req, 405, "text/plain", "read-only");
    const u = new URL(req.url ?? "/", "http://127.0.0.1");
    if (u.pathname === "/analytics.js") return send(res, req, 200, "text/javascript", ""); // the GTM loader never reaches the network
    if (o.compare && u.pathname === "/__fw/compare") {
      const keys = configs ? Object.keys(configs.bySearch) : [];
      return send(res, req, 200, "text/html; charset=utf-8", comparePage(o.compare.op, o.compare.rp, picker(keys), choose(keys, canonSearch(u.search))));
    }
    // "/" with a search: the prerendered page of that search (as the gate does), else index.html (the page client-renders)
    let path = u.pathname;
    if (configs && (path === "/" || path === "/index.html")) {
      const hash = configs.bySearch[canonSearch(u.search)];
      const rel = hash ? configs.byHash[hash] : undefined;
      if (rel) path = "/" + rel;
    }
    if (path.endsWith("/")) path += "index.html";
    let f = safeFile(o.root, path), base = o.root;
    if (!f && o.mediaRoot && MEDIA.has(extname(path).toLowerCase())) { f = safeFile(o.mediaRoot, path); base = o.mediaRoot; }
    if (!f) return send(res, req, 404, "text/plain", "not found");
    const rel = "/" + relative(resolve(base), f).split(sep).join("/");
    serveFile(req, res, f, rel, base === o.root ? names() : new Set());
  };
}

/** Side by side: original left, task version right, two iframes of the same width (an iframe's width is its viewport
 *  for `(width)` media queries). Hover, pointer, reduced-motion and dpr cannot be set from an iframe. */
export function comparePage(op: number, rp: number, searches: string[] = [""], current = ""): string {
  const q = JSON.stringify(current).replace(/</g, "\\u003c"); // the search of the task version's address, as a script string
  const esc = (t: string) => t.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
  const label = (k: string) => (k === "" ? "default" : k.startsWith("?preset=") ? `preset ${k.slice(8)}` : `flags ${k.slice(4)}`);
  const picked = searches.length > 1
    ? `<label>build <select id=s>${searches.map((k) => `<option value="${esc(k)}"${k === current ? " selected" : ""}>${esc(label(k))}</option>`).join("")}</select></label>`
    : "";
  return `<!doctype html><meta charset="utf-8"><title>original | task version</title>
<style>body{margin:0;font:13px system-ui;background:#eee}header{padding:6px 10px;display:flex;gap:10px;align-items:center}
.row{display:flex;gap:8px;padding:0 8px 8px}.col{flex:1;min-width:0}.col h2{font-size:12px;margin:2px 0}
iframe{border:1px solid #888;background:#fff;height:calc(100vh - 80px);width:100%}</style>
<header><b>Side by side</b> ${picked} width <select id=w><option value="">fit</option><option>320</option><option>390</option><option>600</option>
<option>861</option><option>1024</option><option>1280</option><option>1512</option></select>
<span>Scroll each side yourself. Emulate hover, reduced motion and dpr in DevTools per window.</span></header>
<div class=row><div class=col><h2>original (snapshot) :${op}</h2><iframe id=a></iframe></div>
<div class=col><h2>task version :${rp}</h2><iframe id=b></iframe></div></div>
<script>const at=(p,q)=>location.protocol+'//'+location.hostname+':'+p+'/'+q;/* each arm is its own origin (its port), on the host of this page */
document.getElementById('a').src=at(${op},'');document.getElementById('b').src=at(${rp},${q});
const s=document.getElementById('s');if(s)s.onchange=()=>{location.search=s.value};const w=document.getElementById('w');w.onchange=()=>{for(const id of ['a','b']){const f=document.getElementById(id);f.style.width=w.value?w.value+'px':'100%';f.parentElement.style.flex=w.value?'none':'1'}}</script>`;
}

if (process.argv.includes("--serve")) {
  const rewrite = arg("--rewrite")!, original = arg("--original")!, media = arg("--media");
  // `--rp`/`--op`: the private ports this process listens on; `--arm-rp`/`--arm-op`: the arms' public ports (default: the same)
  const rp = Number(arg("--rp")), op = Number(arg("--op"));
  const a = createServer(handler({ root: rewrite, mediaRoot: media, prerendered: true, compare: { rp: Number(arg("--arm-rp") ?? rp), op: Number(arg("--arm-op") ?? op) } }));
  const b = createServer(handler({ root: original }));
  for (const srv of [a, b]) srv.keepAliveTimeout = 65_000;
  let up = 0;
  const ready = () => { if (++up === 2) console.log(JSON.stringify({ ready: true, rp, op })); };
  a.listen(rp, "127.0.0.1", ready);
  b.listen(op, "127.0.0.1", ready);
  const bye = () => { a.close(); b.close(); process.exit(0); };
  process.on("SIGTERM", bye);
  process.on("SIGINT", bye);
}
